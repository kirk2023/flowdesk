import { socket } from '@kit.NetworkKit';
import { wifiManager } from '@kit.ConnectivityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DiscoveryBeacon } from '../models/Protocol';
import { DISCOVERY_PORT, PROTOCOL_VERSION } from '../common/Constants';

const TAG = 'FlowDesk.Discovery';

export interface DiscoveredDevice {
  deviceId: string;
  alias: string;
  ip: string;
  port: number;
  lastSeen: number;
}

export class DiscoveryService {
  private udpSocket: socket.UDPSocket | null = null;
  private running: boolean = false;
  private broadcastTimer: number = -1;
  private listeners: Array<(device: DiscoveredDevice) => void> = [];

  async start(): Promise<void> {
    if (this.running) return;
    try {
      this.udpSocket = socket.constructUDPSocketInstance();
      const bindAddr: socket.NetAddress = {
        address: '0.0.0.0',
        port: 0,
        family: 1
      };
      await this.udpSocket.bind(bindAddr);
      const opts: socket.UDPExtraOptions = {
        broadcast: true,
        reuseAddress: true
      };
      this.udpSocket.setExtraOptions(opts);
      this.udpSocket.on('message', (data: socket.SocketMessageInfo) => {
        this.handleMessage(data);
      });
      this.running = true;
      this.broadcastTimer = setInterval(() => this.broadcastWhoami(), 2000);
      this.broadcastWhoami();
      hilog.info(0x0001, TAG, 'discovery started');
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(0x0001, TAG, 'start failed: %{public}s', e.message);
      throw new Error('Discovery start failed: ' + e.message);
    }
  }

  async stop(): Promise<void> {
    this.running = false;
    if (this.broadcastTimer !== -1) {
      clearInterval(this.broadcastTimer);
      this.broadcastTimer = -1;
    }
    if (this.udpSocket) {
      try {
        await this.udpSocket.close();
      } catch (err) { }
      this.udpSocket = null;
    }
  }

  onDeviceDiscovered(callback: (device: DiscoveredDevice) => void): void {
    this.listeners.push(callback);
  }

  removeAllListeners(): void {
    this.listeners = [];
  }

  private notify(device: DiscoveredDevice): void {
    for (let i = 0; i < this.listeners.length; i++) {
      const cb = this.listeners[i];
      try { cb(device); } catch { }
    }
  }

  private async broadcastWhoami(): Promise<void> {
    if (!this.udpSocket || !this.running) return;
    const beacon: DiscoveryBeacon = new DiscoveryBeacon();
    beacon.type = 'whoami';
    beacon.id = 'phone-' + this.getLocalId();
    beacon.port = 0;
    beacon.proto = PROTOCOL_VERSION;
    beacon.ts = Date.now();
    const data: string = JSON.stringify(beacon);

    const targets: string[] = this.getBroadcastTargets();
    for (let i = 0; i < targets.length; i++) {
      const target: string = targets[i];
      try {
        await this.udpSocket.send({
          data: data,
          address: {
            address: target,
            port: DISCOVERY_PORT,
            family: 1
          }
        });
      } catch (err) { }
    }
  }

  private getBroadcastTargets(): string[] {
    const list: string[] = ['255.255.255.255'];
    try {
      const ipInfo: wifiManager.IpInfo = wifiManager.getIpInfo();
      const rawIp: number = ipInfo.ipAddress;
      const rawMask: number = ipInfo.netmask;
      if (rawIp !== 0 && rawMask !== 0) {
        const bcast: number = (rawIp & rawMask) | (~rawMask >>> 0);
        const parts: string[] = [
          String((bcast >>> 24) & 0xFF),
          String((bcast >>> 16) & 0xFF),
          String((bcast >>> 8) & 0xFF),
          String(bcast & 0xFF)
        ];
        list.push(parts.join('.'));
      }
    } catch (err) { }
    return list;
  }

  private getLocalId(): string {
    const n: number = Math.floor(Math.random() * 0xFFFF);
    return n.toString().padStart(4, '0');
  }

  private handleMessage(info: socket.SocketMessageInfo): void {
    try {
      const raw: ArrayBuffer = info.message;
      const bytes: Uint8Array = new Uint8Array(raw);
      const text: string = this.bytesToStr(bytes);
      const beacon: DiscoveryBeacon = JSON.parse(text) as DiscoveryBeacon;
      if (beacon.proto !== PROTOCOL_VERSION) return;
      if (beacon.type !== 'iam') return;
      const device: DiscoveredDevice = {
        deviceId: beacon.id,
        alias: beacon.alias,
        ip: info.remoteInfo.address,
        port: beacon.port,
        lastSeen: Date.now()
      };
      hilog.info(0x0001, TAG, 'discovered: %{public}s @ %{public}s', device.deviceId, device.ip);
      this.notify(device);
    } catch (err) { }
  }

  private bytesToStr(bytes: Uint8Array): string {
    let s: string = '';
    for (let i = 0; i < bytes.length; i++) {
      s += String.fromCharCode(bytes[i]);
    }
    return s;
  }
}
