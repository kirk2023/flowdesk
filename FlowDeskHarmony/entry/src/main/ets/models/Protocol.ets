// 设备配对信息（持久化在 Preferences 中）
export interface PairedDevice {
  deviceId: string;
  alias: string;
  pairedAt: number;
  lastConnectedAt: number;
  lastSeenIp: string;
  online: boolean;
  trustPublicKey: string;
}

// 设备发现广播包
export class DiscoveryBeacon {
  type: string = 'whoami'; // 'whoami' | 'iam' | 'bye'
  id: string = '';
  alias: string = '';
  port: number = 0;
  proto: string = 'flowdesk-v1';
  ts: number = 0;
}

// 配对握手
export class PairingHello {
  type: string = 'pair-hello';
  id: string = '';
  pubKey: string = '';
  pin: string = '';
  ts: number = 0;
  nonce: string = '';
}

export class PairingAccept {
  type: string = 'pair-accept';
  id: string = '';
  pubKey: string = '';
  ts: number = 0;
  nonce: string = '';
  screenW: number = 1920;
  screenH: number = 1080;
}

export class PairingReject {
  type: string = 'pair-reject';
  id: string = '';
  reason: string = '';
  ts: number = 0;
}

// 屏幕帧
export class ScreenFrame {
  type: string = 'frame';
  seq: number = 0;
  data: string = ''; // base64 编码的 JPEG
  ts: number = 0;
}

// 输入事件
export class InputEventMessage {
  type: string = 'input';
  event: string = ''; // mouse-down, mouse-up, mouse-move, mouse-wheel, key-down, key-up, paste-text
  x: number = 0;
  y: number = 0;
  button: string = ''; // left, right, middle
  dx: number = 0;
  dy: number = 0;
  code: number = 0; // virtual key code
  modifiers: number = 0;
  text: string = ''; // for paste-text event
  ts: number = 0;
}

// 修饰键位掩码
export const MOD_SHIFT: number = 1 << 0;
export const MOD_CTRL: number = 1 << 1;
export const MOD_ALT: number = 1 << 2;
export const MOD_META: number = 1 << 3;
