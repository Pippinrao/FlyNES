import nativeSession from 'libentry.so';
import { NearbyMvpPort, NearbyMvpScanFlow, NearbyMvpSnapshot, NearbyWifiPort } from './NearbyMvpScanFlow';
import { nearbyWifiConnector } from './NearbyWifiConnector';
import { parseLanInvite, parseWifiEnvelope } from './NearbyLanNetwork';

export interface NearbyScanClock {
  start(callback: () => void): number;
  stop(id: number): void;
}

class SystemNearbyScanClock implements NearbyScanClock {
  start(callback: () => void): number { return setInterval(callback, 500); }
  stop(id: number): void { clearInterval(id); }
}

class NativeNearbyMvpPort implements NearbyMvpPort {
  join(qrText: string, wifiOnly: boolean = false): boolean {
    return nativeSession.nearbyMvpJoin(qrText, wifiOnly);
  }
  snapshot(): NearbyMvpSnapshot { return nativeSession.nearbyMvpSnapshot(); }
  cancel(): boolean { return nativeSession.nearbyMvpCancel(); }
}

// Backend entry point for a future scanner UI. It owns the Wi-Fi candidate
// until cancel (or a failed session), so leaving the scanner does not drop it.
export class NearbyScanJoinService {
  private flow: NearbyMvpScanFlow;
  private readonly port: NearbyMvpPort;
  private readonly clock: NearbyScanClock;
  private readonly wifiPort: NearbyWifiPort;
  private timerId: number = -1;
  private monitorGeneration: number = 0;
  private ownsWifi: boolean = false;

  constructor(port: NearbyMvpPort = new NativeNearbyMvpPort(),
    wifiPort: NearbyWifiPort = nearbyWifiConnector,
    clock: NearbyScanClock = new SystemNearbyScanClock()) {
    this.flow = new NearbyMvpScanFlow(port, wifiPort);
    this.port = port;
    this.wifiPort = wifiPort;
    this.clock = clock;
  }

  async joinScannedText(qrText: string): Promise<boolean> {
    const wifi = parseWifiEnvelope(qrText);
    if (parseLanInvite(qrText) === 0 && wifi === null) return false;
    this.stopMonitor();
    if (this.ownsWifi && wifi === null) this.wifiPort.release();
    this.ownsWifi = false;
    const flow = this.flow;
    const joined = await flow.scan(async (): Promise<string> => qrText);
    if (joined && flow === this.flow && this.timerId < 0) {
      this.ownsWifi = wifi !== null;
      const generation = this.monitorGeneration;
      this.timerId = this.clock.start((): void => {
        if (generation === this.monitorGeneration) this.poll();
      });
    }
    return joined;
  }

  snapshot(): NearbyMvpSnapshot { return this.flow.snapshot(); }
  poll(): void {
    this.flow.poll();
    const state = this.flow.snapshot().state;
    if (state === 0 || state === 4) {
      if (state === 0) this.wifiPort.release();
      this.ownsWifi = false;
      this.stopMonitor();
    }
  }
  cancel(): void {
    this.stopMonitor();
    this.flow.leave();
    this.ownsWifi = false;
    this.flow = new NearbyMvpScanFlow(this.port, this.wifiPort);
  }

  private stopMonitor(): void {
    this.monitorGeneration++;
    if (this.timerId >= 0) this.clock.stop(this.timerId);
    this.timerId = -1;
  }
}

export const nearbyScanJoinService: NearbyScanJoinService = new NearbyScanJoinService();
