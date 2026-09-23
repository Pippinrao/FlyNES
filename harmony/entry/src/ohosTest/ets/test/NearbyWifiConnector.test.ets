import { describe, it, expect } from '@ohos/hypium';
import { NearbyWifiConnector, WifiCandidateApi } from '../../../main/ets/service/NearbyWifiConnector';

class FakeWifiApi implements WifiCandidateApi {
  removed: Array<number> = [];
  denied: boolean = false;
  async add(_: string, __: string): Promise<number> { return 7; }
  async request(_: number): Promise<void> { if (this.denied) throw new Error('refused'); }
  async ready(_: string): Promise<boolean> { return true; }
  async remove(id: number): Promise<void> { this.removed.push(id); }
}

export default function nearbyWifiConnectorTest(): void {
  describe('NearbyWifiConnector', () => {
    it('keeps_candidate_while_guest_session_is_active', 0, async () => {
      const api = new FakeWifiApi();
      const wifi = new NearbyWifiConnector(api);
      expect(await wifi.connect('Test', 'password8')).assertTrue();
      expect(api.removed.length).assertEqual(0);
      wifi.release();
      await Promise.resolve();
      expect(api.removed.length).assertEqual(1);
      expect(api.removed[0]).assertEqual(7);
    });

    it('refused_system_prompt_removes_candidate', 0, async () => {
      const api = new FakeWifiApi();
      api.denied = true;
      const wifi = new NearbyWifiConnector(api);
      expect(await wifi.connect('Test', 'password8')).assertFalse();
      expect(api.removed.length).assertEqual(1);
    });
  });
}
