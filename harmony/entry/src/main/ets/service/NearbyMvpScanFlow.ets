import { parseLanInvite, parseWifiEnvelope, WifiEnvelope } from './NearbyLanNetwork';

export interface NearbyWifiPort {
  connect(ssid: string, passphrase: string): Promise<boolean>;
  release(): void;
}

export interface NearbyMvpSnapshot {
  state: number;
  reason: number;
  transportResult: number;
  transportOperation: number;
}

export interface NearbyMvpPort {
  join(qrText: string, wifiOnly?: boolean): boolean;
  snapshot(): NearbyMvpSnapshot;
  cancel(): boolean;
}

export type NearbyScanResult = () => Promise<string>;

const IDLE: NearbyMvpSnapshot = {
  state: 0, reason: 0, transportResult: 0, transportOperation: 0
};

export class NearbyMvpScanFlow {
  private readonly port: NearbyMvpPort;
  private readonly wifiPort: NearbyWifiPort | null;
  private visible: boolean = true;
  private disposed: boolean = false;
  private scanning: boolean = false;
  private current: NearbyMvpSnapshot = IDLE;

  constructor(port: NearbyMvpPort, wifiPort: NearbyWifiPort | null = null) {
    this.port = port;
    this.wifiPort = wifiPort;
  }

  appear(): void {
    if (!this.disposed) this.visible = true;
  }

  hideForScanner(): void {
    this.visible = false;
  }

  /** Leave the UI without closing a connection already owned by the native session. */
  dismissPage(): void {
    this.disposed = true;
    this.visible = false;
  }

  leave(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.visible = false;
    this.port.cancel();
    this.wifiPort?.release();
    this.current = { state: 4, reason: 5, transportResult: 0, transportOperation: 0 };
  }

  isScanning(): boolean { return this.scanning; }

  snapshot(): NearbyMvpSnapshot { return this.current; }

  poll(): void {
    if (!this.visible || this.disposed) return;
    this.current = this.port.snapshot();
    if (this.current.state === 4) this.wifiPort?.release();
  }

  async scan(readResult: NearbyScanResult): Promise<boolean> {
    if (this.scanning || this.disposed) return false;
    this.scanning = true;
    try {
      let qrText = await readResult();
      let wifiOnly = false;
      if (this.disposed) return false;
      if (qrText.startsWith('flynes-wifi-v1:')) {
        const wifi: WifiEnvelope | null = parseWifiEnvelope(qrText);
        qrText = '';
        if (wifi === null || this.wifiPort === null ||
          !await this.wifiPort.connect(wifi.ssid, wifi.passphrase) || this.disposed) {
          if (this.disposed) this.wifiPort?.release();
          if (!this.disposed) this.current = { state: 4, reason: 1, transportResult: 0, transportOperation: 0 };
          return false;
        }
        qrText = wifi.invite;
        wifiOnly = true;
      }
      if (parseLanInvite(qrText) === 0) {
        this.current = { state: 4, reason: 1, transportResult: 0, transportOperation: 0 };
        return false;
      }
      if (!this.port.join(qrText, wifiOnly)) {
        this.wifiPort?.release();
        this.current = { state: 4, reason: 1, transportResult: 0, transportOperation: 0 };
        return false;
      }
      this.current = this.port.snapshot();
      if (this.current.state === 0) {
        this.current = { state: 2, reason: 0, transportResult: 0, transportOperation: 4 };
      }
      return true;
    } catch {
      this.wifiPort?.release();
      if (!this.disposed) {
        this.current = { state: 4, reason: 1, transportResult: 0, transportOperation: 0 };
      }
      return false;
    } finally {
      this.scanning = false;
    }
  }
}
