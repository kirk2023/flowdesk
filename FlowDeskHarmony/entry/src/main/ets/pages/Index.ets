import { hilog } from '@kit.PerformanceAnalysisKit';
import { common, abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { promptAction, router } from '@kit.ArkUI';
import { wifiManager } from '@kit.ConnectivityKit';
import { preferences } from '@kit.ArkData';
import { scanBarcode } from '@kit.ScanKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { DiscoveryService, DiscoveredDevice } from '../services/DiscoveryService';
import { DATA_PORT } from '../common/Constants';

const TAG = 'FlowDesk';
const DOMAIN = 0x0001;
const STORAGE_KEY_DEVICES = 'flowdesk_paired_devices';

class PairedDevice {
  deviceId: string = '';
  alias: string = '';
  pairedAt: number = 0;
  lastConnectedAt: number = 0;
  lastSeenIp: string = '';
  online: boolean = false;
}

class ScannedInfo {
  id: string = '';
  alias: string = '';
  ip: string = '';
}

class QrPayload {
  id: string = '';
  alias: string = '';
  ip: string = '';
  pin: string = '';
}

class NavParams {
  deviceId: string = '';
  alias: string = '';
  pcIp: string = '';
  pcPort: number = 0;
  pin: string = '';
}

@Entry
@Component
struct Index {
  @State deviceList: PairedDevice[] = [];
  @State showAddSheet: boolean = false;
  @State showAboutDialog: boolean = false;
  @State inputDeviceId: string = '';
  @State inputPin: string = '';
  @State addMode: string = 'id'; // 'scan' | 'id' | 'pin'
  @State connectingDeviceId: string = '';
  @State localIp: string = '获取中...';
  @State wifiSsid: string = '';

  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private preferencesStore: preferences.Preferences | null = null;
  private discovery: DiscoveryService = new DiscoveryService();

  async aboutToAppear(): Promise<void> {
    hilog.info(DOMAIN, TAG, 'Index aboutToAppear');
    await this.requestPermissions();
    await this.initPreferences();
    await this.loadPairedDevices();
    await this.refreshNetworkInfo();
    this.startDiscovery();
  }

  aboutToDisappear(): void {
    hilog.info(DOMAIN, TAG, 'Index aboutToDisappear');
    this.stopDiscovery();
  }

  private async onScannedDevice(scanned: ScannedInfo): Promise<void> {
    this.inputDeviceId = scanned.id.toUpperCase();
    const existingIdx: number = this.deviceList.findIndex(d => d.deviceId === this.inputDeviceId);
    if (existingIdx >= 0) {
      const old: PairedDevice = this.deviceList[existingIdx];
      const updated: PairedDevice = new PairedDevice();
      updated.deviceId = old.deviceId;
      updated.alias = old.alias.length > 0 ? old.alias : scanned.alias;
      updated.pairedAt = old.pairedAt;
      updated.lastConnectedAt = old.lastConnectedAt;
      if (scanned.ip.length > 0) {
        updated.lastSeenIp = scanned.ip;
        updated.online = true;
      } else {
        updated.lastSeenIp = old.lastSeenIp;
        updated.online = old.online;
      }
      const next: PairedDevice[] = [];
      for (let i = 0; i < this.deviceList.length; i++) {
        if (i === existingIdx) next.push(updated);
        else next.push(this.deviceList[i]);
      }
      this.deviceList = next;
    } else {
      const newDevice: PairedDevice = new PairedDevice();
      newDevice.deviceId = this.inputDeviceId;
      newDevice.alias = scanned.alias;
      newDevice.pairedAt = 0;
      newDevice.lastConnectedAt = 0;
      newDevice.lastSeenIp = scanned.ip;
      newDevice.online = scanned.ip.length > 0;
      this.deviceList = [newDevice].concat(this.deviceList);
    }
    await this.savePairedDevices();
    this.addMode = 'pin';
    this.showAddSheet = true;
    promptAction.showToast({ message: '已识别设备 ' + this.inputDeviceId });
  }

  async requestPermissions(): Promise<void> {
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    const perms: Permissions[] = [
      'ohos.permission.INTERNET',
      'ohos.permission.GET_WIFI_INFO',
      'ohos.permission.CAMERA'
    ];
    try {
      await atManager.requestPermissionsFromUser(this.context, perms);
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'request permissions failed: %{public}s', e.message);
    }
  }

  async initPreferences(): Promise<void> {
    try {
      const options: preferences.Options = {
        name: 'flowdesk_store'
      };
      this.preferencesStore = await preferences.getPreferences(this.context, options);
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'init preferences failed: %{public}s', e.message);
    }
  }

  async loadPairedDevices(): Promise<void> {
    if (!this.preferencesStore) {
      return;
    }
    try {
      const raw: string = await this.preferencesStore.get(STORAGE_KEY_DEVICES, '[]') as string;
      const parsed: PairedDevice[] = JSON.parse(raw) as PairedDevice[];
      this.deviceList = parsed;
      hilog.info(DOMAIN, TAG, 'loaded %{public}d paired devices', this.deviceList.length);
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'load devices failed: %{public}s', e.message);
      this.deviceList = [];
    }
  }

  async savePairedDevices(): Promise<void> {
    if (!this.preferencesStore) {
      return;
    }
    try {
      await this.preferencesStore.put(STORAGE_KEY_DEVICES, JSON.stringify(this.deviceList));
      await this.preferencesStore.flush();
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'save devices failed: %{public}s', e.message);
    }
  }

  async refreshNetworkInfo(): Promise<void> {
    try {
      const ipInfo: wifiManager.IpInfo = wifiManager.getIpInfo();
      const rawIp: number = ipInfo.ipAddress;
      this.localIp = `${(rawIp >> 0) & 0xFF}.${(rawIp >> 8) & 0xFF}.${(rawIp >> 16) & 0xFF}.${(rawIp >> 24) & 0xFF}`;
    } catch (err) {
      this.localIp = '未知';
    }
    try {
      const wifiInfo: wifiManager.WifiLinkedInfo = await wifiManager.getLinkedInfo();
      this.wifiSsid = wifiInfo.ssid ? String(wifiInfo.ssid).replace(/"/g, '') : '';
    } catch (err) {
      this.wifiSsid = '';
    }
  }

  startDiscovery(): void {
    hilog.info(DOMAIN, TAG, 'start LAN discovery');
    this.discovery.onDeviceDiscovered((device: DiscoveredDevice) => {
      this.onDeviceDiscovered(device);
    });
    this.discovery.start().catch((err: BusinessError) => {
      hilog.error(DOMAIN, TAG, 'discovery start failed: %{public}s', err.message);
    });
  }

  stopDiscovery(): void {
    this.discovery.stop().catch(() => { });
  }

  private onDeviceDiscovered(device: DiscoveredDevice): void {
    const idx = this.deviceList.findIndex(d => d.deviceId === device.deviceId);
    if (idx >= 0) {
      const updated: PairedDevice[] = [];
      for (let i = 0; i < this.deviceList.length; i++) {
        if (i === idx) {
          const old: PairedDevice = this.deviceList[i];
          const replaced: PairedDevice = new PairedDevice();
          replaced.deviceId = old.deviceId;
          replaced.alias = old.alias;
          replaced.pairedAt = old.pairedAt;
          replaced.online = true;
          replaced.lastSeenIp = device.ip;
          replaced.lastConnectedAt = old.lastConnectedAt > 0 ? old.lastConnectedAt : Date.now();
          updated.push(replaced);
        } else {
          updated.push(this.deviceList[i]);
        }
      }
      this.deviceList = updated;
      this.savePairedDevices();
    }
    hilog.info(DOMAIN, TAG, 'discovered: %{public}s @ %{public}s', device.deviceId, device.ip);
  }

  build() {
    Stack() {
      Column() {
        this.buildHeader()
        this.buildDeviceList()
        this.buildFooter()
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background'))

      if (this.showAddSheet) {
        this.buildAddSheet()
      }

      if (this.showAboutDialog) {
        this.buildAboutDialog()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildHeader() {
    Row() {
      Text($r('app.string.title_devices'))
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)

      Button() {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(20)
          .fontColor([$r('app.color.primary')])
      }
      .width(40)
      .height(40)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.addMode = 'id';
        this.inputDeviceId = '';
        this.inputPin = '';
        this.showAddSheet = true;
      })

      Button() {
        SymbolGlyph($r('sys.symbol.info_circle'))
          .fontSize(20)
          .fontColor([$r('app.color.text_secondary')])
      }
      .width(40)
      .height(40)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.showAboutDialog = true;
      })
    }
    .width('100%')
    .height(64)
    .padding({ left: 24, right: 16 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  buildDeviceList() {
    List({ space: 12 }) {
      if (this.deviceList.length === 0) {
        ListItem() {
          Column() {
            SymbolGlyph($r('sys.symbol.desktop'))
              .fontSize(72)
              .fontColor([$r('app.color.text_tertiary')])
              .margin({ top: 80, bottom: 16 })
            Text($r('app.string.empty_devices_hint'))
              .fontSize(15)
              .fontColor($r('app.color.text_secondary'))
              .textAlign(TextAlign.Center)
              .lineHeight(22)
          }
          .width('100%')
          .padding({ top: 40, bottom: 40 })
        }
      }

      ForEach(this.deviceList, (device: PairedDevice) => {
        ListItem() {
          this.buildDeviceCard(device)
        }
        .swipeAction({ end: this.buildSwipeAction(device) })
      }, (device: PairedDevice) => device.deviceId)
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .scrollBar(BarState.Off)
  }

  @Builder
  buildDeviceCard(device: PairedDevice) {
    Row() {
      Column() {
        SymbolGlyph($r('sys.symbol.desktop'))
          .fontSize(28)
          .fontColor([$r('app.color.primary')])
      }
      .width(48)
      .height(48)
      .borderRadius(12)
      .backgroundColor('#E8F0FF')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Column() {
        Row() {
          Text(device.alias || device.deviceId)
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (this.connectingDeviceId === device.deviceId) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color($r('app.color.primary'))
          } else {
            Circle({ width: 8, height: 8 })
              .fill(device.online ? $r('app.color.status_online') : $r('app.color.status_offline'))
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(device.deviceId)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .fontFamily('monospace')
          .margin({ top: 4 })

        if (device.lastSeenIp) {
          Text(device.online ? `在线 · ${device.lastSeenIp}` : '离线')
            .fontSize(12)
            .fontColor(device.online ? $r('app.color.status_online') : $r('app.color.text_tertiary'))
            .margin({ top: 2 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (!device.online) {
        promptAction.showToast({ message: '设备未上线' });
        return;
      }
      this.inputDeviceId = device.deviceId;
      this.inputPin = '';
      this.addMode = 'pin';
      this.showAddSheet = true;
    })
  }

  @Builder
  buildSwipeAction(device: PairedDevice) {
    Button($r('app.string.btn_remove'))
      .fontSize(14)
      .fontColor(Color.White)
      .backgroundColor('#FF3B30')
      .width(80)
      .height('100%')
      .onClick(() => {
        this.removeDevice(device);
      })
  }

  @Builder
  buildFooter() {
    Column() {
      Divider()
        .color($r('app.color.divider'))
        .height(1)

      Row() {
        Column() {
          Text('当前网络')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
          Text(this.wifiSsid || this.localIp)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Column() {
          Text('本机')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
          Text(this.localIp)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.End)
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 12, bottom: 12 })
    }
    .width('100%')
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  buildAddSheet() {
    Column() {
      Column() {
        Row() {
          Column()
            .width(40)
            .height(4)
            .borderRadius(2)
            .backgroundColor($r('app.color.text_tertiary'))
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: 12, bottom: 16 })

        Text($r('app.string.dialog_add_title'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .padding({ left: 24 })

        Row({ space: 8 }) {
          this.buildModeChip('id', '输入ID')
          this.buildModeChip('scan', '扫码')
          this.buildModeChip('pin', '动态PIN')
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 16, bottom: 16 })

        if (this.addMode === 'id') {
          this.buildIdInput()
        } else if (this.addMode === 'scan') {
          this.buildScanButton()
        } else {
          this.buildPinInput()
        }

        Row({ space: 12 }) {
          Button($r('app.string.btn_cancel'))
            .fontSize(15)
            .fontColor($r('app.color.text_secondary'))
            .backgroundColor('#F1F3F5')
            .height(44)
            .layoutWeight(1)
            .onClick(() => {
              this.showAddSheet = false;
            })

          Button($r('app.string.btn_connect'))
            .fontSize(15)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.primary'))
            .height(44)
            .layoutWeight(1)
            .enabled(this.canSubmit())
            .onClick(() => {
              this.submitAdd();
            })
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 8, bottom: 24 })
      }
      .width('100%')
      .backgroundColor(Color.White)
      .borderRadius({ topLeft: 20, topRight: 20 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
    .backgroundColor('rgba(0,0,0,0.5)')
    .onClick(() => {
      this.showAddSheet = false;
    })
  }

  @Builder
  buildModeChip(mode: string, label: string) {
    Text(label)
      .fontSize(14)
      .fontColor(this.addMode === mode ? Color.White : $r('app.color.text_secondary'))
      .backgroundColor(this.addMode === mode ? $r('app.color.primary') : '#F1F3F5')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .borderRadius(20)
      .onClick(() => {
        this.addMode = mode;
      })
  }

  @Builder
  buildIdInput() {
    Column() {
      Text($r('app.string.input_device_id_hint'))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .margin({ bottom: 8 })

      TextInput({ placeholder: '例如: 8K7M-3XQ2-NP5R', text: this.inputDeviceId })
        .fontSize(18)
        .fontFamily('monospace')
        .height(52)
        .backgroundColor('#F8F9FA')
        .borderRadius(12)
        .onChange((value: string) => {
          this.inputDeviceId = value.toUpperCase();
        })
    }
    .width('100%')
    .padding({ left: 24, right: 24, bottom: 16 })
  }

  @Builder
  buildPinInput() {
    Column() {
      Text($r('app.string.input_pin_hint'))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .margin({ bottom: 8 })

      TextInput({ placeholder: '6 位数字', text: this.inputPin })
        .fontSize(24)
        .fontFamily('monospace')
        .height(60)
        .backgroundColor('#F8F9FA')
        .borderRadius(12)
        .type(InputType.Number)
        .maxLength(6)
        .onChange((value: string) => {
          this.inputPin = value;
        })

      Text('电脑屏幕上每 30 秒刷新一次')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ top: 8 })
    }
    .width('100%')
    .padding({ left: 24, right: 24, bottom: 16 })
  }

  @Builder
  buildScanButton() {
    Column() {
      SymbolGlyph($r('sys.symbol.camera_fill'))
        .fontSize(72)
        .fontColor([$r('app.color.primary')])
        .margin({ top: 16, bottom: 16 })

      Button('打开相机扫码')
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.primary'))
        .height(48)
        .width('100%')
        .onClick(() => {
          this.openScanner();
        })
    }
    .width('100%')
    .padding({ left: 24, right: 24, bottom: 16 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  buildAboutDialog() {
    Column() {
      Column() {
        Image($r('app.media.app_icon'))
          .width(72)
          .height(72)
          .borderRadius(16)
          .margin({ top: 24, bottom: 12 })

        Text('FlowDesk')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))

        Text($r('app.string.version_label'))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 4 })

        Text($r('app.string.slogan'))
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ top: 16 })
          .textAlign(TextAlign.Center)

        Button('关闭')
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
          .backgroundColor('#F1F3F5')
          .height(44)
          .width('100%')
          .margin({ top: 24 })
          .onClick(() => {
            this.showAboutDialog = false;
          })
      }
      .width('80%')
      .padding({ left: 24, right: 24, bottom: 24 })
      .borderRadius(20)
      .backgroundColor(Color.White)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('rgba(0,0,0,0.5)')
    .onClick(() => {
      this.showAboutDialog = false;
    })
  }

  canSubmit(): boolean {
    if (this.addMode === 'id') {
      return /^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$/.test(this.inputDeviceId);
    } else if (this.addMode === 'pin') {
      return /^\d{6}$/.test(this.inputPin);
    } else {
      return false;
    }
  }

  async openScanner(): Promise<void> {
    try {
      const result: scanBarcode.ScanResult = await scanBarcode.startScanForResult(getContext());
      const value: string = result.originalValue ?? '';
      const parsed: QrPayload = this.parseQrPayload(value);
      if (parsed.id.length > 0) {
        const scanned: ScannedInfo = new ScannedInfo();
        scanned.id = parsed.id;
        scanned.alias = parsed.alias;
        scanned.ip = parsed.ip;
        await this.onScannedDevice(scanned);

        // 如果二维码包含 PIN，直接配对（跳过手动输入）
        if (parsed.pin.length > 0) {
          const target: PairedDevice | undefined = this.deviceList.find(d => d.deviceId === parsed.id);
          if (target && target.lastSeenIp.length > 0) {
            promptAction.showToast({ message: '二维码包含 PIN,自动配对…' });
            await this.connectToDevice(target, parsed.pin);
            return;
          }
        }
      } else {
        const cleaned: string = value.toUpperCase().trim();
        if (/^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$/.test(cleaned)) {
          this.inputDeviceId = cleaned;
          this.addMode = 'id';
          promptAction.showToast({ message: '已识别: ' + this.inputDeviceId });
        } else {
          promptAction.showToast({ message: '二维码格式无效' });
        }
      }
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'scan failed: %{public}s', e.message);
      promptAction.showToast({ message: '扫码取消' });
    }
  }

  private parseQrPayload(value: string): QrPayload {
    const out: QrPayload = new QrPayload();
    out.id = '';
    out.alias = '';
    out.ip = '';
    try {
      if (value.startsWith('flowdesk://pair')) {
        const qIdx: number = value.indexOf('?');
        if (qIdx < 0) return out;
        const qs: string = value.substring(qIdx + 1);
        const parts: string[] = qs.split('&');
        for (let i = 0; i < parts.length; i++) {
          const p: string = parts[i];
          const eqIdx: number = p.indexOf('=');
          if (eqIdx < 0) continue;
          const k: string = p.substring(0, eqIdx);
          const v: string = p.substring(eqIdx + 1);
          const decoded: string = decodeURIComponent(v);
          if (k === 'id') out.id = decoded;
          else if (k === 'alias') out.alias = decoded;
          else if (k === 'ip') out.ip = decoded;
          else if (k === 'pin') out.pin = decoded;
        }
      }
    } catch (err) { }
    return out;
  }

  async submitAdd(): Promise<void> {
    if (!this.canSubmit()) {
      return;
    }
    if (this.addMode === 'id') {
      const newDevice: PairedDevice = new PairedDevice();
      newDevice.deviceId = this.inputDeviceId;
      newDevice.alias = this.inputDeviceId;
      newDevice.pairedAt = Date.now();
      newDevice.lastConnectedAt = 0;
      newDevice.lastSeenIp = '';
      newDevice.online = false;
      const exists: PairedDevice | undefined = this.deviceList.find(d => d.deviceId === newDevice.deviceId);
      if (exists) {
        promptAction.showToast({ message: '该设备已存在' });
        this.showAddSheet = false;
        return;
      }
      this.deviceList = [newDevice].concat(this.deviceList);
      await this.savePairedDevices();
      this.showAddSheet = false;
      promptAction.showToast({ message: '已添加，等待局域网内发现' });
    } else if (this.addMode === 'pin') {
      const target = this.deviceList.find(d => d.deviceId === this.inputDeviceId);
      if (!target) {
        promptAction.showToast({ message: '设备不存在' });
        return;
      }
      if (target.lastSeenIp.length === 0) {
        promptAction.showToast({ message: '请先扫码获取设备 IP' });
        return;
      }
      this.showAddSheet = false;
      await this.connectToDevice(target, this.inputPin);
    } else if (this.addMode === 'scan') {
      promptAction.showToast({ message: '请先扫码' });
    }
  }

  async removeDevice(device: PairedDevice): Promise<void> {
    const next: PairedDevice[] = [];
    for (let i = 0; i < this.deviceList.length; i++) {
      if (this.deviceList[i].deviceId !== device.deviceId) {
        next.push(this.deviceList[i]);
      }
    }
    this.deviceList = next;
    await this.savePairedDevices();
    promptAction.showToast({ message: '已移除' });
  }

  async connectToDevice(device: PairedDevice, pin: string): Promise<void> {
    this.connectingDeviceId = device.deviceId;
    hilog.info(DOMAIN, TAG, 'connecting to %{public}s @ %{public}s', device.deviceId, device.lastSeenIp);

    if (!device.lastSeenIp) {
      promptAction.showToast({ message: '设备未上线' });
      this.connectingDeviceId = '';
      return;
    }

    if (pin.length === 0) {
      promptAction.showToast({ message: '需要 PIN 码' });
      this.connectingDeviceId = '';
      return;
    }

    const navParams: NavParams = new NavParams();
    navParams.deviceId = device.deviceId;
    navParams.alias = device.alias;
    navParams.pcIp = device.lastSeenIp;
    navParams.pcPort = DATA_PORT;
    navParams.pin = pin;
    router.pushUrl({
      url: 'pages/RemoteScreen',
      params: navParams
    }).catch((err: BusinessError) => {
      hilog.error(DOMAIN, TAG, 'navigate failed: %{public}s', err.message);
      promptAction.showToast({ message: '打开远程页面失败' });
      this.connectingDeviceId = '';
    });
  }

  onRemoteScreenClosed(deviceId: string): void {
    this.connectingDeviceId = '';
    this.loadPairedDevices();
  }
}
