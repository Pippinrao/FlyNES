import { wifiManager } from '@kit.ConnectivityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { NearbyWifiPort } from './NearbyMvpScanFlow';

export interface WifiCandidateApi {
  add(ssid: string, passphrase: string): Promise<number>;
  request(networkId: number): Promise<void>;
  ready(ssid: string): Promise<boolean>;
  remove(networkId: number): Promise<void>;
}

class HarmonyWifiCandidateApi implements WifiCandidateApi {
  add(ssid: string, passphrase: string): Promise<number> {
    return wifiManager.addCandidateConfig({
        ssid: ssid,
        preSharedKey: passphrase,
        securityType: wifiManager.WifiSecurityType.WIFI_SEC_TYPE_PSK
      });
  }

  request(networkId: number): Promise<void> {
    return wifiManager.connectToCandidateConfigWithUserAction(networkId);
  }

  async ready(ssid: string): Promise<boolean> {
    return wifiManager.isConnected() && wifiManager.getIpInfo().ipAddress !== 0 &&
      (await wifiManager.getLinkedInfo()).ssid === ssid;
  }

  remove(networkId: number): Promise<void> {
    return wifiManager.removeCandidateConfig(networkId);
  }
}

export class NearbyWifiConnector implements NearbyWifiPort {
  private readonly api: WifiCandidateApi;
  private generation: number = 0;
  private candidateId: number = -1;

  constructor(api: WifiCandidateApi = new HarmonyWifiCandidateApi()) { this.api = api; }

  release(): void {
    this.generation++;
    const id = this.candidateId;
    this.candidateId = -1;
    if (id >= 0) {
      try { void this.api.remove(id).catch((): void => {}); }
      catch { /* Best effort credential cleanup. */ }
    }
  }

  async connect(ssid: string, passphrase: string): Promise<boolean> {
    this.release();
    const generation = this.generation;
    let networkId = -1;
    let connected = false;
    let stage: string = 'add';
    try {
      networkId = await this.api.add(ssid, passphrase);
      if (generation !== this.generation) {
        await this.api.remove(networkId);
        return false;
      }
      this.candidateId = networkId;
      stage = 'request';
      hilog.info(0, 'FlyNesWifi', 'candidate ready; requesting system approval');
      await this.api.request(networkId);
      stage = 'address';
      const deadline = Date.now() + 15000;
      while (generation === this.generation && Date.now() < deadline) {
        try {
          if (await this.api.ready(ssid)) {
            connected = generation === this.generation;
            hilog.info(0, 'FlyNesWifi', 'hotspot address ready');
            return connected;
          }
        } catch { /* The Wi-Fi link may still be acquiring an address. */ }
        await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 250); });
      }
      hilog.info(0, 'FlyNesWifi', 'join stopped stage=%{public}s superseded=%{public}s',
        stage, String(generation !== this.generation));
    } catch (error) {
      // Never include system error messages: they may contain SSIDs or credentials.
      hilog.info(0, 'FlyNesWifi', 'join failed stage=%{public}s code=%{public}d',
        stage, (error as BusinessError).code ?? -1);
    }
    finally {
      if (!connected && networkId >= 0 && this.candidateId === networkId) {
        this.candidateId = -1;
        try { await this.api.remove(networkId); } catch { /* Best effort credential cleanup. */ }
      }
    }
    return false;
  }
}

// The numeric ID follows the guest through Pairing, Lobby, and RunGame.
export const nearbyWifiConnector: NearbyWifiConnector = new NearbyWifiConnector();
