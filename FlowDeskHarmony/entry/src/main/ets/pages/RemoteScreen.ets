import { hilog } from '@kit.PerformanceAnalysisKit';
import { router } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo } from '@kit.CoreFileKit';
import { ConnectionService, ConnectionState, ConnectionEvents } from '../services/ConnectionService';
import { InputService } from '../services/InputService';
import { CryptoService } from '../services/CryptoService';

const TAG = 'FlowDesk';
const DOMAIN = 0x0001;

class RemoteParams {
  deviceId: string = '';
  alias: string = '';
  pcIp: string = '';
  pcPort: number = 0;
  pin: string = '';
}

class PcPoint {
  x: number = 0;
  y: number = 0;
}

class VkMod {
  vk: number = 0;
  mod: number = 0;
}

class VkMap {
  entries: string[] = [];
  codes: number[] = [];
  shiftEntries: string[] = [];
  shiftCodes: number[] = [];
}

@Entry
@Component
struct RemoteScreen {
  @State deviceId: string = '';
  @State alias: string = '';
  @State pcIp: string = '';
  @State pcPort: number = 47801;
  @State pin: string = '';
  @State connectionState: ConnectionState = 'idle';
  @State statusText: string = '正在连接...';
  @State lastError: string = '';
  @State fps: number = 0;
  @State latencyMs: number = 0;
  @State showToolbar: boolean = true;
  @State showKeyboard: boolean = false;
  @State rightClickArmed: boolean = false;
  @State inputText: string = '';
  @State screenPixelMap: image.PixelMap | null = null;
  // 旧的 PixelMap 字段已废弃,改用 frameBase64 字符串直接喂给 Image
  @State lastFrameSeq: number = 0;
  @State frameCounter: number = 0;
  @State fpsTimer: number = 0;
  @State imgDisplayW: number = 0;
  @State imgDisplayH: number = 0;
  @State imgOffsetX: number = 0;
  @State imgOffsetY: number = 0;
  @State jpegW: number = 1280;
  @State jpegH: number = 720;
  @State frameBase64: string = '';

  private connection: ConnectionService = new ConnectionService();
  private inputService: InputService = new InputService(this.connection);
  private lastLocalX: number = 0;
  private lastLocalY: number = 0;
  private pcWidth: number = 1920;
  private pcHeight: number = 1080;
  private movedSinceDown: boolean = false;

  async aboutToAppear(): Promise<void> {
    hilog.info(DOMAIN, TAG, 'RemoteScreen aboutToAppear');
    const raw: Object | undefined = router.getParams();
    if (raw) {
      const params: RemoteParams = raw as RemoteParams;
      this.deviceId = params.deviceId ?? '';
      this.alias = params.alias ?? '';
      this.pcIp = params.pcIp ?? '';
      this.pcPort = params.pcPort ?? 47801;
      this.pin = params.pin ?? '';
    }

    if (this.pcIp.length === 0 || this.pin.length === 0) {
      hilog.error(DOMAIN, TAG, 'missing pcIp or pin');
      this.statusText = '参数错误';
      return;
    }

    this.setupConnection();
    await this.startPairing();
  }

  aboutToDisappear(): void {
    hilog.info(DOMAIN, TAG, 'RemoteScreen aboutToDisappear');
    if (this.fpsTimer !== 0) {
      clearInterval(this.fpsTimer);
      this.fpsTimer = 0;
    }
    this.connection.close();
  }

  private setupConnection(): void {
    const events: ConnectionEvents = {
      onStateChange: (state: ConnectionState, msg?: string) => {
        this.connectionState = state;
        if (state === 'connecting') {
          this.statusText = msg ?? '正在连接...';
        } else if (state === 'paired') {
          const sz = this.connection.getScreenSize();
          this.pcWidth = sz.w;
          this.pcHeight = sz.h;
          this.statusText = '已连接 · 等待画面';
        } else if (state === 'error') {
          this.statusText = msg ?? '连接错误';
        } else if (state === 'idle') {
          this.statusText = '已断开';
        }
      },
      onScreenFrame: (jpegData: Uint8Array, seq: number) => {
        this.renderJpegFrame(jpegData, seq);
      },
      onError: (err: string) => {
        hilog.error(DOMAIN, TAG, 'connection error: %{public}s', err);
        this.lastError = err;
        this.statusText = '画面错误';
      }
    };
    this.connection.setEvents(events);

    this.fpsTimer = setInterval(() => {
      this.fps = this.frameCounter;
      this.frameCounter = 0;
    }, 1000);
  }

  private async startPairing(): Promise<void> {
    try {
      await this.connection.startPairing(this.pcIp, this.pcPort, this.deviceId, this.pin);
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'startPairing failed: %{public}s', e.message);
      this.statusText = '配对失败: ' + e.message;
    }
  }

  private async renderJpegFrame(jpegData: Uint8Array, seq: number): Promise<void> {
    this.frameCounter++;
    this.lastFrameSeq = seq;
    try {
      this.frameBase64 = CryptoService.bufToBase64(jpegData);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'base64 failed: %{public}s', JSON.stringify(err));
    }
  }

  build() {
    Stack() {
      Column() {
        if (this.connectionState === 'paired' && this.frameBase64.length > 0) {
          this.buildScreenArea()
        } else {
          this.buildConnectingState()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#000000')

      if (this.showToolbar && this.connectionState === 'paired' && !this.showKeyboard) {
        this.buildBottomBar()
      }

      if (this.showKeyboard && this.connectionState === 'paired') {
        this.buildKeyboard()
      }

      if (this.rightClickArmed && this.connectionState === 'paired') {
        this.buildRightClickBanner()
      }

      if (this.connectionState === 'paired' && this.frameBase64.length > 0) {
        this.buildToolbarToggle()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
  }

  @Builder
  buildToolbarToggle() {
    Button() {
      Text('≡')
        .fontSize(20)
        .fontColor(Color.White)
    }
    .width(36)
    .height(36)
    .backgroundColor('rgba(0,0,0,0.4)')
    .position({ x: '100%', y: 56 })
    .translate({ x: -44, y: 0 })
    .onClick(() => {
      this.showToolbar = !this.showToolbar;
    })
  }

  @Builder
  buildConnectingState() {
    Column() {
      if (this.connectionState === 'error' || this.connectionState === 'idle') {
        SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
          .fontSize(56)
          .fontColor([$r('app.color.status_offline')])
        Text(this.statusText)
          .fontSize(15)
          .fontColor(Color.White)
          .margin({ top: 16 })
          .textAlign(TextAlign.Center)
        Button('返回')
          .fontSize(14)
          .fontColor(Color.White)
          .backgroundColor('#33FFFFFF')
          .height(40)
          .margin({ top: 24 })
          .onClick(() => {
            router.back();
          })
      } else {
        LoadingProgress()
          .width(56)
          .height(56)
          .color($r('app.color.primary'))

        Text(this.alias || this.deviceId)
          .fontSize(17)
          .fontColor(Color.White)
          .margin({ top: 16 })
          .fontWeight(FontWeight.Medium)

        Text(this.statusText)
          .fontSize(14)
          .fontColor('#A0FFFFFF')
          .margin({ top: 8 })
          .textAlign(TextAlign.Center)

        Text(this.pcIp + ':' + this.pcPort)
          .fontSize(11)
          .fontColor('#80FFFFFF')
          .margin({ top: 4 })
          .fontFamily('monospace')

        if (this.lastError.length > 0) {
          Text(this.lastError)
            .fontSize(11)
            .fontColor('#FF6B6B')
            .margin({ top: 12, left: 24, right: 24 })
            .textAlign(TextAlign.Center)
            .maxLines(4)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }

        Button('取消')
          .fontSize(14)
          .fontColor(Color.White)
          .backgroundColor('#33FFFFFF')
          .height(40)
          .margin({ top: 32 })
          .onClick(() => {
            router.back();
          })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  buildScreenArea() {
    Stack() {
      if (this.frameBase64.length > 0) {
        Image('data:image/jpeg;base64,' + this.frameBase64)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
          .onAreaChange((_oldArea: Area, newArea: Area) => {
            const containerW: number = this.parseLength(newArea.width);
            const containerH: number = this.parseLength(newArea.height);
            if (containerW <= 0 || containerH <= 0 || this.jpegW <= 0 || this.jpegH <= 0) return;
            const imgAspect: number = this.jpegW / this.jpegH;
            const containerAspect: number = containerW / containerH;
            if (imgAspect > containerAspect) {
              this.imgDisplayW = containerW;
              this.imgDisplayH = containerW / imgAspect;
              this.imgOffsetX = 0;
              this.imgOffsetY = (containerH - this.imgDisplayH) / 2;
            } else {
              this.imgDisplayW = containerH * imgAspect;
              this.imgDisplayH = containerH;
              this.imgOffsetX = (containerW - this.imgDisplayW) / 2;
              this.imgOffsetY = 0;
            }
          })
      }
      // 透明全屏覆盖层，专门接收手势（不受 Image 重建影响）
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .hitTestBehavior(HitTestMode.Default)
        .gesture(
          GestureGroup(GestureMode.Parallel,
            TapGesture({ count: 1 })
              .onAction((event: GestureEvent) => this.onSingleTap(event)),
            PanGesture({ direction: PanDirection.All, fingers: 1, distance: 5 })
              .onActionStart((event: GestureEvent) => this.onTouchStart(event))
              .onActionUpdate((event: GestureEvent) => this.onTouchMove(event))
              .onActionEnd(() => this.onTouchEndDrag())
          )
        )
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildTopBar() {
    Row() {
      Button() {
        SymbolGlyph($r('sys.symbol.chevron_backward'))
          .fontSize(22)
          .fontColor([Color.White])
      }
      .width(40)
      .height(40)
      .backgroundColor('rgba(0,0,0,0.4)')
      .onClick(() => {
        router.back();
      })

      Column() {
        Text(this.alias || this.deviceId)
          .fontSize(13)
          .fontColor(Color.White)
        Row({ space: 8 }) {
          Text(this.fps + 'fps')
            .fontSize(11)
            .fontColor('#A0FFFFFF')
          Text('#' + this.lastFrameSeq)
            .fontSize(11)
            .fontColor('#A0FFFFFF')
        }
        .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)

      Button() {
        SymbolGlyph($r('sys.symbol.camera_fill'))
          .fontSize(20)
          .fontColor([Color.White])
      }
      .width(40)
      .height(40)
      .backgroundColor('rgba(0,0,0,0.4)')
      .onClick(() => {
        // TODO
      })
    }
    .width('100%')
    .height(56)
    .padding({ left: 12, right: 12 })
    .backgroundColor('rgba(0,0,0,0.5)')
    .alignItems(VerticalAlign.Center)
    .position({ x: 0, y: 0 })
  }

  @Builder
  buildBottomBar() {
    Column() {
      Text('点击=左键  拖动=按住移动  长按右键=武装右键后点击')
        .fontSize(10)
        .fontColor('#A0FFFFFF')
        .margin({ bottom: 4 })
      Row({ space: 0 }) {
        this.buildToolButton('右键', () => {
          this.rightClickArmed = !this.rightClickArmed;
        }, this.rightClickArmed ? '#FF9500' : 'rgba(0,0,0,0.4)')

        this.buildToolButton('键盘', () => {
          this.showKeyboard = !this.showKeyboard;
          if (this.showKeyboard) {
            this.lastSentText = this.inputText;
          }
        }, 'rgba(0,0,0,0.4)')

        this.buildToolButton('截图', () => {
          this.saveScreenshot();
        }, 'rgba(0,0,0,0.4)')

        this.buildToolButton('结束', () => {
          router.back();
        }, '#FF3B30')
      }
      .width('100%')
      .height(56)
      .backgroundColor('rgba(0,0,0,0.5)')
      .justifyContent(FlexAlign.SpaceEvenly)
    }
    .width('100%')
    .backgroundColor('rgba(0,0,0,0.3)')
    .position({ x: 0, y: '100%' })
    .translate({ y: -88 })
  }

  @Builder
  buildRightClickBanner() {
    Row() {
      Text('👉 下次点击 = 右键(点此取消)')
        .fontSize(13)
        .fontColor(Color.White)
        .fontWeight(FontWeight.Bold)
    }
    .width('80%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .backgroundColor('#FF9500')
    .borderRadius(20)
    .justifyContent(FlexAlign.Center)
    .position({ x: '10%', y: 130 })
    .onClick(() => {
      this.rightClickArmed = false;
    })
  }

  // 系统键盘输入栏:TextInput + onChange → onPasteText(支持中文等任意语言)
  @Builder
  buildKeyboard() {
    Row({ space: 0 }) {
      TextInput({ placeholder: '在此输入,远程同步显示…', text: this.inputText })
        .id('remoteKbInput')
        .layoutWeight(1)
        .height(40)
        .fontSize(15)
        .placeholderColor('#888888')
        .backgroundColor('#FFFFFF')
        .padding({ left: 10 })
        .onChange((value: string) => {
          this.handleTextChange(value);
        })
        .onAppear(() => {
          setTimeout(() => {
            try { focusControl.requestFocus('remoteKbInput'); } catch (e) {}
          }, 200);
        })
        .defaultFocus(true)
        .onSubmit(() => {
          this.pressVk(0x0D, 0);
          this.inputText = '';
          this.lastSentText = '';
        })

      Button('⏎')
        .fontSize(14).fontColor(Color.White)
        .backgroundColor('#1E90FF')
        .height(40).width(40)
        .onClick(() => {
          this.pressVk(0x0D, 0);
          this.inputText = '';
          this.lastSentText = '';
        })

      Button('⌫')
        .fontSize(14).fontColor(Color.White)
        .backgroundColor('#666666')
        .height(40).width(40)
        .onClick(() => {
          this.pressVk(0x08, 0);
          if (this.inputText.length > 0) {
            this.inputText = this.inputText.substring(0, this.inputText.length - 1);
            this.lastSentText = this.inputText;
          }
        })

      Button('×')
        .fontSize(20).fontColor(Color.White).fontWeight(FontWeight.Bold)
        .backgroundColor('#FF3B30')
        .height(40).width(46)
        .onClick(() => { this.showKeyboard = false })
    }
    .width('100%')
    .height(40)
    .backgroundColor('#F0F0F0')
    .position({ x: 0, y: '100%' })
    .translate({ y: this.showKeyboard ? -40 : 0 })
  }

  private lastSentText: string = '';
  private textBusy: boolean = false;
  private pendingText: string = '';
  private hasPending: boolean = false;

  private async handleTextChange(value: string): Promise<void> {
    this.inputText = value;
    if (this.textBusy) {
      this.pendingText = value;
      this.hasPending = true;
      return;
    }
    this.textBusy = true;
    try {
      await this.doSendText(value);
      while (this.hasPending) {
        const next: string = this.pendingText;
        this.hasPending = false;
        await this.doSendText(next);
      }
    } finally {
      this.textBusy = false;
    }
  }

  private async doSendText(value: string): Promise<void> {
    const prev: string = this.lastSentText;
    let common: number = 0;
    const minLen: number = Math.min(prev.length, value.length);
    for (let i = 0; i < minLen; i++) {
      if (prev.charAt(i) === value.charAt(i)) {
        common++;
      } else {
        break;
      }
    }
    const toDel: number = prev.length - common;
    for (let i = 0; i < toDel; i++) {
      await this.pressVk(0x08, 0);
    }
    const toAdd: string = value.substring(common);
    if (toAdd.length > 0) {
      await this.inputService.onPasteText(toAdd);
    }
    this.lastSentText = value;
  }

  private async typeChar(c: string): Promise<void> {
    const r: VkMod = this.charToVkAndMod(c);
    if (r.vk <= 0) {
      hilog.warn(DOMAIN, TAG, 'unsupported char: %{public}s', c);
      return;
    }
    await this.pressVk(r.vk, r.mod);
  }

  private charToVkAndMod(c: string): VkMod {
    const r: VkMod = new VkMod();
    const code: number = c.charCodeAt(0);
    // 大写字母
    if (code >= 0x41 && code <= 0x5A) {
      r.vk = code;
      r.mod = 0x01;
      return r;
    }
    // 小写字母
    if (code >= 0x61 && code <= 0x7A) {
      r.vk = code - 0x20;
      r.mod = 0;
      return r;
    }
    // 数字（带 shift 表示符号）
    if (code >= 0x30 && code <= 0x39) {
      const shifted: string = ')!@#$%^&*(';
      const idx: number = code - 0x30;
      const isShifted: boolean = c !== String(idx);
      r.vk = code;
      r.mod = isShifted ? 0x01 : 0;
      return r;
    }
    // 常用符号（带 shift）
    const shiftedMap: VkMap = this.getShiftedMap();
    const idx1: number = shiftedMap.shiftEntries.indexOf(c);
    if (idx1 >= 0) {
      r.vk = shiftedMap.shiftCodes[idx1];
      r.mod = 0x01;
      return r;
    }
    // 不带 shift 的符号
    const unshiftedMap: VkMap = this.getUnshiftedMap();
    const idx2: number = unshiftedMap.entries.indexOf(c);
    if (idx2 >= 0) {
      r.vk = unshiftedMap.codes[idx2];
      r.mod = 0;
      return r;
    }
    return r;
  }

  private getShiftedMap(): VkMap {
    const m: VkMap = new VkMap();
    m.shiftEntries = ['!', '@', '#', '$', '%', '^', '&', '*', '(', ')',
      '_', '+', '{', '}', ':', '"', '|', '<', '>', '?', '~'];
    m.shiftCodes = [0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30,
      0xBD, 0xBB, 0xDB, 0xDD, 0xBA, 0xDE, 0xDC, 0xBC, 0xBE, 0xBF, 0xC0];
    return m;
  }

  private getUnshiftedMap(): VkMap {
    const m: VkMap = new VkMap();
    m.entries = [' ', '-', '=', '[', ']', ';', "'", '\\', ',', '.', '/', '`', '\n', '\t'];
    m.codes = [0x20, 0xBD, 0xBB, 0xDB, 0xDD, 0xBA, 0xDE, 0xDC, 0xBC, 0xBE, 0xBF, 0xC0, 0x0D, 0x09];
    return m;
  }

  private async pressVk(vk: number, mod: number): Promise<void> {
    await this.inputService.onKeyDown(vk, mod);
    await this.inputService.onKeyUp(vk, mod);
  }

  private async saveScreenshot(): Promise<void> {
    try {
      if (this.frameBase64.length === 0) {
        this.lastError = '当前无画面';
        return;
      }
      const jpegBytes: Uint8Array = CryptoService.base64ToBuf(this.frameBase64);
      const ts: number = Date.now();
      const ctx = getContext(this);
      const cachePath = ctx.cacheDir;
      const tmpFile = `${cachePath}/flowdesk_${ts}.jpg`;
      const file = fileIo.openSync(tmpFile, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      fileIo.writeSync(file.fd, jpegBytes.buffer);
      fileIo.closeSync(file);

      try {
        const helper = photoAccessHelper.getPhotoAccessHelper(ctx);
        const asset = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, 'jpg', { title: `FlowDesk_${ts}` });
        this.lastError = '已保存到相册: ' + asset;
        hilog.info(DOMAIN, TAG, 'screenshot saved to gallery: %{public}s', String(asset));
      } catch (gErr) {
        const ge: BusinessError = gErr as BusinessError;
        hilog.warn(DOMAIN, TAG, 'gallery save failed: %{public}s, cache file: %{public}s', ge.message, tmpFile);
        this.lastError = '已保存到缓存(相册权限不足): ' + tmpFile;
      }
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      this.lastError = '截图失败[' + e.code + ']: ' + e.message;
      hilog.error(DOMAIN, TAG, 'screenshot failed: %{public}s', e.message);
    }
  }

  @Builder
  buildToolButton(label: string, onTap: () => void, bgColor: string) {
    Column() {
      Text(label)
        .fontSize(16)
        .fontColor(Color.White)
        .fontWeight(FontWeight.Medium)
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(bgColor)
    .onClick(onTap)
  }

  private toPcCoords(localX: number, localY: number): PcPoint {
    const p: PcPoint = new PcPoint();
    if (this.imgDisplayW <= 0 || this.imgDisplayH <= 0) {
      p.x = localX;
      p.y = localY;
      return p;
    }
    const ix: number = localX - this.imgOffsetX;
    const iy: number = localY - this.imgOffsetY;
    p.x = Math.max(0, Math.min(this.pcWidth, (ix * this.pcWidth) / this.imgDisplayW));
    p.y = Math.max(0, Math.min(this.pcHeight, (iy * this.pcHeight) / this.imgDisplayH));
    return p;
  }

  private parseLength(v: number | string | Resource): number {
    if (typeof v === 'number') return v;
    if (typeof v === 'string') {
      const n: number = parseFloat(v);
      return isNaN(n) ? 0 : n;
    }
    return 0;
  }

  private async onTouchStart(event: GestureEvent): Promise<void> {
    if (event.fingerList.length === 0) return;
    const finger = event.fingerList[0];
    if (!finger) return;
    this.movedSinceDown = false;
    const p: PcPoint = this.toPcCoords(finger.localX, finger.localY);
    this.lastLocalX = p.x;
    this.lastLocalY = p.y;
    await this.inputService.onTouchStart(p.x, p.y, 'left');
  }

  private async onTouchMove(event: GestureEvent): Promise<void> {
    if (event.fingerList.length === 0) return;
    const finger = event.fingerList[0];
    if (!finger) return;
    this.movedSinceDown = true;
    const p: PcPoint = this.toPcCoords(finger.localX, finger.localY);
    this.lastLocalX = p.x;
    this.lastLocalY = p.y;
    await this.inputService.onTouchMove(p.x, p.y);
  }

  private async onTouchEnd(): Promise<void> {
    if (!this.movedSinceDown) {
      await this.inputService.onTouchEnd('left');
    } else {
      await this.inputService.onTouchEnd('left');
    }
  }

  private async onTouchEndDrag(): Promise<void> {
    await this.inputService.onTouchEnd('left');
  }

  private async onSingleTap(event: GestureEvent): Promise<void> {
    if (this.movedSinceDown) return;
    let lx: number = this.lastLocalX;
    let ly: number = this.lastLocalY;
    if (event.fingerList.length > 0) {
      const finger = event.fingerList[0];
      if (finger) {
        const p: PcPoint = this.toPcCoords(finger.localX, finger.localY);
        lx = p.x;
        ly = p.y;
        this.lastLocalX = lx;
        this.lastLocalY = ly;
      }
    }
    if (this.rightClickArmed) {
      this.rightClickArmed = false;
      await this.inputService.onRightClick(lx, ly);
      return;
    }
    await this.inputService.onLeftClick(lx, ly);
  }

  private async onDoubleTap(event: GestureEvent): Promise<void> {
    let lx: number = this.lastLocalX;
    let ly: number = this.lastLocalY;
    if (event.fingerList.length > 0) {
      const finger = event.fingerList[0];
      if (finger) {
        const p: PcPoint = this.toPcCoords(finger.localX, finger.localY);
        lx = p.x;
        ly = p.y;
        this.lastLocalX = lx;
        this.lastLocalY = ly;
      }
    }
    await this.inputService.onRightClick(lx, ly);
  }
}
