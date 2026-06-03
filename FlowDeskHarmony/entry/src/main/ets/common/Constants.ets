// 协议常量
export const DISCOVERY_PORT: number = 47800;
export const DATA_PORT: number = 47801;
export const PROTOCOL_VERSION: string = 'flowdesk-v1';
export const PIN_REFRESH_SECONDS: number = 30;
export const PAIRING_TIMEOUT_MS: number = 60000;
export const HEARTBEAT_INTERVAL_MS: number = 3000;
export const HEARTBEAT_TIMEOUT_MS: number = 10000;

// 设备ID 格式校验
export function isValidDeviceId(id: string): boolean {
  return /^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$/.test(id);
}

// 生成 9 位易记设备ID (例: 8K7M-3XQ2-NP5R)
export function generateDeviceId(): string {
  // 字符集：去掉易混淆的 0/O/1/I
  const charset: string = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const group1: string = pickChars(charset, 4);
  const group2: string = pickChars(charset, 4);
  const group3: string = pickChars(charset, 4);
  return group1 + '-' + group2 + '-' + group3;
}

function pickChars(charset: string, count: number): string {
  let result: string = '';
  for (let i = 0; i < count; i++) {
    const idx: number = Math.floor(Math.random() * charset.length);
    result += charset.charAt(idx);
  }
  return result;
}

// 生成 6 位动态 PIN
export function generatePin(): string {
  const n: number = Math.floor(Math.random() * 1000000);
  return n.toString().padStart(6, '0');
}
