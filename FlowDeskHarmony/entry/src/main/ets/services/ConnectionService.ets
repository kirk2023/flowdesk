import { socket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CryptoService, EcdhKeyPair } from './CryptoService';
import { PairingHello, PairingAccept, PairingReject, ScreenFrame, InputEventMessage } from '../models/Protocol';

const TAG = 'FlowDesk.Connection';
const CHUNK_STALE_MS = 5000;

class ScreenSize {
  w: number = 0;
  h: number = 0;
}

class FrameChunkState {
  total: number = 0;
  parts: Uint8Array[] = [];
  receivedMask: number = 0;
  lastAccess: number = Date.now();
}

export type ConnectionState = string; // 'idle' | 'connecting' | 'paired' | 'error'

export interface ConnectionEvents {
  onStateChange?: (state: ConnectionState, message?: string) => void;
  onScreenFrame?: (jpegData: Uint8Array, seq: number) => void;
  onError?: (err: string) => void;
}

export class ConnectionService {
  private udpSocket: socket.UDPSocket | null = null;
  private state: ConnectionState = 'idle';
  private ecdh: EcdhKeyPair | null = null;
  private sessionKey: Uint8Array | null = null;
  private sendNonce: Uint8Array | null = null;
  private recvNonce: Uint8Array | null = null;
  private remoteAddress: socket.NetAddress | null = null;
  private events: ConnectionEvents = {};
  private frameChunks: Map<number, FrameChunkState> = new Map();
  private screenWidth: number = 1920;
  private screenHeight: number = 1080;

  getScreenSize(): ScreenSize {
    const sz: ScreenSize = new ScreenSize();
    sz.w = this.screenWidth;
    sz.h = this.screenHeight;
    return sz;
  }

  setEvents(events: ConnectionEvents): void {
    this.events = events;
  }

  getState(): ConnectionState {
    return this.state;
  }

  setState(s: ConnectionState, msg?: string): void {
    this.state = s;
    hilog.info(0x0001, TAG, 'state -> %{public}s', s);
    if (this.events.onStateChange) {
      this.events.onStateChange(s, msg);
    }
  }

  async startPairing(pcIp: string, pcPort: number, deviceId: string, pin: string): Promise<void> {
    this.setState('connecting', '正在发起配对...');
    try {
      this.udpSocket = socket.constructUDPSocketInstance();
      const bindAddr: socket.NetAddress = {
        address: '0.0.0.0',
        port: 0,
        family: 1
      };
      await this.udpSocket.bind(bindAddr);
      this.udpSocket.on('message', (data: socket.SocketMessageInfo) => {
        this.handleMessage(data);
      });
      this.setState('connecting', '已绑定本地 UDP，等待生成密钥...');

      this.ecdh = await CryptoService.generateEcdhKeyPair();
      this.setState('connecting', '已生成密钥，准备发送 PHEL...');

      const hello: PairingHello = new PairingHello();
      hello.id = deviceId;
      hello.pubKey = this.ecdh.publicKeyBase64;
      hello.pin = pin;
      hello.ts = Date.now();
      const nonceBytes: Uint8Array = new Uint8Array(8);
      for (let i = 0; i < 8; i++) nonceBytes[i] = Math.floor(Math.random() * 256);
      hello.nonce = CryptoService.bufToBase64(nonceBytes);

      const helloJson: string = JSON.stringify(hello);
      const helloBytes: Uint8Array = this.strToBytes(helloJson);
      const header: Uint8Array = this.strToBytes('PHEL');
      const packet: Uint8Array = this.concatBytes(header, helloBytes);

      const addr: socket.NetAddress = {
        address: pcIp,
        port: pcPort,
        family: 1
      };
      this.remoteAddress = addr;

      hilog.info(0x0001, TAG, 'sending PHEL to %{public}s:%{public}d, len=%{public}d', pcIp, pcPort, packet.length);
      await this.udpSocket.send({
        data: packet.buffer,
        address: this.remoteAddress
      });
      this.setState('connecting', 'PHEL 已发送，等待 POK!...');
      hilog.info(0x0001, TAG, 'pair-hello sent to %{public}s:%{public}d', pcIp, pcPort);
    } catch (err) {
      const e = err as BusinessError;
      const code: number = (e && typeof e.code === 'number') ? e.code : -1;
      const msg: string = (e && typeof e.message === 'string') ? e.message : String(err);
      hilog.error(0x0001, TAG, 'startPairing failed: code=%{public}d msg=%{public}s', code, msg);
      this.setState('error', '配对失败[' + code + ']: ' + msg);
      if (this.events.onError) this.events.onError('pair[' + code + ']: ' + msg);
    }
  }

  private async handleMessage(info: socket.SocketMessageInfo): Promise<void> {
    try {
      const raw: ArrayBuffer = info.message;
      if (raw.byteLength < 4) return;
      const bytes: Uint8Array = new Uint8Array(raw);
      const header: string = this.bytesToStr(bytes.slice(0, 4));

      if (header === 'POK!') {
        const payload: string = this.bytesToStr(bytes.slice(4));
        const accept: PairingAccept = JSON.parse(payload) as PairingAccept;
        hilog.info(0x0001, TAG, 'pair-accept from %{public}s', accept.id);
        await this.onPairingAccepted(accept);
      } else if (header === 'PREJ') {
        const payload: string = this.bytesToStr(bytes.slice(4));
        const reject: PairingReject = JSON.parse(payload) as PairingReject;
        hilog.warn(0x0001, TAG, 'pair-reject: %{public}s', reject.reason);
        this.setState('error', '对方拒绝: ' + reject.reason);
        await this.cleanup();
      } else if (header === 'PCRY') {
        if (!this.sessionKey) return;
        try {
          if (raw.byteLength < 16) return;
          const seq: number = this.readUint64LE(bytes, 4);
          const idx: number = this.readUint16LE(bytes, 12);
          const total: number = this.readUint16LE(bytes, 14);
          const chunkData: Uint8Array = bytes.slice(16);

          if (total < 1 || idx < 0 || idx >= total) {
            hilog.warn(0x0001, TAG, 'bad chunk header seq=%{public}d idx=%{public}d total=%{public}d', seq, idx, total);
            return;
          }

          let state: FrameChunkState | undefined = this.frameChunks.get(seq);
          if (!state) {
            state = new FrameChunkState();
            state.total = total;
            state.parts = [];
            for (let i = 0; i < total; i++) state.parts.push(new Uint8Array(0));
            this.frameChunks.set(seq, state);
          }
          if (state.total !== total) {
            this.frameChunks.delete(seq);
            return;
          }

          state.parts[idx] = chunkData;
          state.receivedMask = state.receivedMask | (1 << idx);
          state.lastAccess = Date.now();

              if (state.receivedMask === ((1 << total) - 1)) {
                this.frameChunks.delete(seq);
                let totalLen: number = 0;
                for (let i = 0; i < total; i++) totalLen += state.parts[i].length;
                const cipher: Uint8Array = new Uint8Array(totalLen);
                let off: number = 0;
                for (let i = 0; i < total; i++) {
                  cipher.set(state.parts[i], off);
                  off += state.parts[i].length;
                }
                try {
                  const plain: Uint8Array = await CryptoService.aesGcmDecrypt(this.sessionKey, cipher);
                  const text: string = this.bytesToStr(plain);
                  const frame: ScreenFrame = JSON.parse(text) as ScreenFrame;
                  if (frame.type === 'frame') {
                    const jpegBytes: Uint8Array = CryptoService.base64ToBuf(frame.data);
                    if (this.events.onScreenFrame) {
                      this.events.onScreenFrame(jpegBytes, frame.seq);
                    }
                  }
                } catch (decErr) {
                  const e: BusinessError = decErr as BusinessError;
                  const code: number = (e && typeof e.code === 'number') ? e.code : -1;
                  const msg: string = (e && typeof e.message === 'string') ? e.message : String(decErr);
                  const errMsg: string = 'seq=' + seq + ' decrypt[' + code + ']: ' + msg;
                  hilog.error(0x0001, TAG, '%{public}s', errMsg);
                  if (this.events.onError) this.events.onError(errMsg);
                }
              }

              this.cleanupStaleChunks();
            } catch (err) {
              const msg: string = 'PCRY chunk error: ' + JSON.stringify(err);
              hilog.warn(0x0001, TAG, '%{public}s', msg);
              if (this.events.onError) this.events.onError(msg);
            }
      }
    } catch (err) {
      hilog.warn(0x0001, TAG, 'handleMessage error: %{public}s', JSON.stringify(err));
    }
  }

  private async onPairingAccepted(accept: PairingAccept): Promise<void> {
    try {
      if (!this.ecdh) throw new Error('no local ecdh key');
      this.sessionKey = await CryptoService.deriveSharedKey(this.ecdh.privateKey, accept.pubKey);
      this.sendNonce = new Uint8Array(12);
      this.recvNonce = new Uint8Array(12);
      this.screenWidth = accept.screenW > 0 ? accept.screenW : 1920;
      this.screenHeight = accept.screenH > 0 ? accept.screenH : 1080;
      this.setState('paired', '已配对');
      hilog.info(0x0001, TAG, 'session key ready, 32 bytes, screen=%{public}dx%{public}d',
        this.screenWidth, this.screenHeight);
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(0x0001, TAG, 'onPairingAccepted failed: %{public}s', e.message);
      this.setState('error', '派生密钥失败: ' + e.message);
    }
  }

  async sendInputEvent(event: InputEventMessage): Promise<void> {
    if (!this.udpSocket || !this.sessionKey || !this.sendNonce || !this.remoteAddress) {
      hilog.warn(0x0001, TAG, 'sendInputEvent: not paired');
      return;
    }
    try {
      event.type = 'input';
      event.ts = Date.now();
      const plainText: string = JSON.stringify(event);
      const plainBytes: Uint8Array = this.strToBytes(plainText);

      const cipher: Uint8Array = await CryptoService.aesGcmEncrypt(this.sessionKey, this.sendNonce, plainBytes);
      CryptoService.incrementNonce(this.sendNonce);

      const header: Uint8Array = this.strToBytes('PCRY');
      const packet: Uint8Array = this.concatBytes(header, cipher);

      await this.udpSocket.send({
        data: packet.buffer,
        address: this.remoteAddress
      });
    } catch (err) {
      const e = err as BusinessError;
      hilog.warn(0x0001, TAG, 'sendInputEvent failed: %{public}s', e.message);
    }
  }

  async close(): Promise<void> {
    await this.cleanup();
  }

  private async cleanup(): Promise<void> {
    try {
      if (this.udpSocket) {
        await this.udpSocket.close();
        this.udpSocket = null;
      }
    } catch (err) { }
    this.ecdh = null;
    this.sessionKey = null;
    this.sendNonce = null;
    this.recvNonce = null;
    this.remoteAddress = null;
    this.frameChunks.clear();
    if (this.state !== 'error') {
      this.setState('idle');
    }
  }

  private cleanupStaleChunks(): void {
    if (this.frameChunks.size < 8) return;
    const now: number = Date.now();
    const toDelete: number[] = [];
    this.frameChunks.forEach((v, k) => {
      if (now - v.lastAccess > CHUNK_STALE_MS) toDelete.push(k);
    });
    for (let i = 0; i < toDelete.length; i++) this.frameChunks.delete(toDelete[i]);
  }

  private readUint16LE(bytes: Uint8Array, offset: number): number {
    return bytes[offset] | (bytes[offset + 1] << 8);
  }

  private readUint64LE(bytes: Uint8Array, offset: number): number {
    const lo: number = (bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24)) >>> 0;
    const hi: number = (bytes[offset + 4] |
      (bytes[offset + 5] << 8) |
      (bytes[offset + 6] << 16) |
      (bytes[offset + 7] << 24)) >>> 0;
    return hi * 4294967296 + lo;
  }

  private strToBytes(s: string): Uint8Array {
    const bytes: number[] = [];
    for (let i = 0; i < s.length; i++) {
      const code: number = s.charCodeAt(i);
      if (code < 0x80) {
        bytes.push(code);
      } else if (code < 0x800) {
        bytes.push(0xc0 | (code >> 6));
        bytes.push(0x80 | (code & 0x3f));
      } else if (code >= 0xd800 && code <= 0xdbff && i + 1 < s.length) {
        const hi: number = code;
        const lo: number = s.charCodeAt(i + 1);
        const cp: number = 0x10000 + (((hi & 0x3ff) << 10) | (lo & 0x3ff));
        i++;
        bytes.push(0xf0 | (cp >> 18));
        bytes.push(0x80 | ((cp >> 12) & 0x3f));
        bytes.push(0x80 | ((cp >> 6) & 0x3f));
        bytes.push(0x80 | (cp & 0x3f));
      } else {
        bytes.push(0xe0 | (code >> 12));
        bytes.push(0x80 | ((code >> 6) & 0x3f));
        bytes.push(0x80 | (code & 0x3f));
      }
    }
    const arr: Uint8Array = new Uint8Array(bytes.length);
    for (let i = 0; i < bytes.length; i++) arr[i] = bytes[i];
    return arr;
  }

  private bytesToStr(bytes: Uint8Array): string {
    let s: string = '';
    let i: number = 0;
    while (i < bytes.length) {
      const b0: number = bytes[i];
      if (b0 < 0x80) {
        s += String.fromCharCode(b0);
        i++;
      } else if ((b0 & 0xe0) === 0xc0 && i + 1 < bytes.length) {
        s += String.fromCharCode(((b0 & 0x1f) << 6) | (bytes[i + 1] & 0x3f));
        i += 2;
      } else if ((b0 & 0xf0) === 0xe0 && i + 2 < bytes.length) {
        s += String.fromCharCode(((b0 & 0x0f) << 12) | ((bytes[i + 1] & 0x3f) << 6) | (bytes[i + 2] & 0x3f));
        i += 3;
      } else if ((b0 & 0xf8) === 0xf0 && i + 3 < bytes.length) {
        const cp: number = ((b0 & 0x07) << 18) | ((bytes[i + 1] & 0x3f) << 12) | ((bytes[i + 2] & 0x3f) << 6) | (bytes[i + 3] & 0x3f);
        const hi: number = 0xd800 + ((cp - 0x10000) >> 10);
        const lo: number = 0xdc00 + ((cp - 0x10000) & 0x3ff);
        s += String.fromCharCode(hi, lo);
        i += 4;
      } else {
        s += String.fromCharCode(b0);
        i++;
      }
    }
    return s;
  }

  private concatBytes(...arrays: Uint8Array[]): Uint8Array {
    let total: number = 0;
    for (let i = 0; i < arrays.length; i++) total += arrays[i].length;
    const out: Uint8Array = new Uint8Array(total);
    let offset: number = 0;
    for (let i = 0; i < arrays.length; i++) {
      out.set(arrays[i], offset);
      offset += arrays[i].length;
    }
    return out;
  }
}
