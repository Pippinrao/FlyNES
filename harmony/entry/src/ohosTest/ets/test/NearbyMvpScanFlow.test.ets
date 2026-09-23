import { describe, it, expect } from '@ohos/hypium';
import { NearbyMvpPort, NearbyMvpScanFlow, NearbyMvpSnapshot, NearbyWifiPort } from
  '../../../main/ets/service/NearbyMvpScanFlow';

const LAN_INVITE: string = 'flynes-lan-v1:192.168.43.1:4242:' + 'a'.repeat(64) + ':' + 'b'.repeat(32);

class FakeWifiPort implements NearbyWifiPort {
  calls: number = 0;
  releaseCalls: number = 0;
  connected: boolean = true;
  async connect(_: string, __: string): Promise<boolean> {
    this.calls++;
    return this.connected;
  }
  release(): void { this.releaseCalls++; }
}

class FakeMvpPort implements NearbyMvpPort {
  joinCalls: number = 0;
  wifiOnly: boolean = false;
  cancelCalls: number = 0;
  joinResult: boolean = true;
  value: NearbyMvpSnapshot = { state: 0, reason: 0, transportResult: 0, transportOperation: 0 };

  join(_: string, wifiOnly: boolean = false): boolean {
    this.joinCalls++;
    this.wifiOnly = wifiOnly;
    if (this.joinResult) this.value = { state: 2, reason: 0, transportResult: 0, transportOperation: 4 };
    return this.joinResult;
  }

  snapshot(): NearbyMvpSnapshot { return this.value; }

  cancel(): boolean {
    this.cancelCalls++;
    this.value = { state: 4, reason: 5, transportResult: 0, transportOperation: 0 };
    return true;
  }
}

interface PendingScan {
  promise: Promise<string>;
  resolve: (value: string) => void;
}

function pendingScan(): PendingScan {
  let complete: (value: string) => void = (_: string): void => {};
  const promise = new Promise<string>((resolve: (value: string) => void): void => { complete = resolve; });
  return { promise: promise, resolve: complete };
}

export default function nearbyMvpScanFlowTest(): void {
  describe('NearbyMvpScanFlow', () => {
    it('valid_result_uses_real_port_and_publishes_joining', 0, async () => {
      const port = new FakeMvpPort();
      const flow = new NearbyMvpScanFlow(port);
      expect(await flow.scan(async (): Promise<string> => LAN_INVITE)).assertTrue();
      expect(port.joinCalls).assertEqual(1);
      expect(flow.snapshot().state).assertEqual(2);
    });

    it('invalid_result_does_not_create_connection_and_can_retry', 0, async () => {
      const port = new FakeMvpPort();
      const flow = new NearbyMvpScanFlow(port);
      expect(await flow.scan(async (): Promise<string> => 'invalid')).assertFalse();
      expect(flow.snapshot().state).assertEqual(4);
      expect(port.joinCalls).assertEqual(0);
      expect(await flow.scan(async (): Promise<string> => LAN_INVITE)).assertTrue();
      expect(port.joinCalls).assertEqual(1);
      expect(port.wifiOnly).assertFalse();
    });

    it('hidden_page_resumes_polling_the_same_owner', 0, () => {
      const port = new FakeMvpPort();
      const flow = new NearbyMvpScanFlow(port);
      flow.hideForScanner();
      port.value = { state: 3, reason: 0, transportResult: 0, transportOperation: 7 };
      flow.poll();
      expect(flow.snapshot().state).assertEqual(0);
      flow.appear();
      flow.poll();
      expect(flow.snapshot().state).assertEqual(3);
      expect(port.cancelCalls).assertEqual(0);
    });

    it('explicit_leave_discards_late_scan_result', 0, async () => {
      const port = new FakeMvpPort();
      const flow = new NearbyMvpScanFlow(port);
      const pending = pendingScan();
      const result = flow.scan(async (): Promise<string> => pending.promise);
      flow.leave();
      pending.resolve('flynes-lan-v1:late');
      expect(await result).assertFalse();
      expect(port.joinCalls).assertEqual(0);
      expect(port.cancelCalls).assertEqual(1);
    });

    it('ordinary_page_exit_discards_late_scan_without_disconnecting', 0, async () => {
      const port = new FakeMvpPort();
      const flow = new NearbyMvpScanFlow(port);
      const pending = pendingScan();
      const result = flow.scan(async (): Promise<string> => pending.promise);
      flow.dismissPage();
      pending.resolve('flynes-lan-v1:late');
      expect(await result).assertFalse();
      expect(port.joinCalls).assertEqual(0);
      expect(port.cancelCalls).assertEqual(0);
    });

    it('double_tap_starts_only_one_scanner', 0, async () => {
      const port = new FakeMvpPort();
      const flow = new NearbyMvpScanFlow(port);
      const pending = pendingScan();
      let scannerCalls = 0;
      const first = flow.scan(async (): Promise<string> => { scannerCalls++; return pending.promise; });
      expect(await flow.scan(async (): Promise<string> => { scannerCalls++; return 'duplicate'; })).assertFalse();
      pending.resolve(LAN_INVITE);
      expect(await first).assertTrue();
      expect(scannerCalls).assertEqual(1);
      expect(port.joinCalls).assertEqual(1);
    });

    it('wifi_envelope_waits_for_network_then_joins_inner_invite', 0, async () => {
      const port = new FakeMvpPort();
      const wifi = new FakeWifiPort();
      const flow = new NearbyMvpScanFlow(port, wifi);
      const qr = 'flynes-wifi-v1:Test%20NES:password8:' + encodeURIComponent(LAN_INVITE);
      expect(await flow.scan(async (): Promise<string> => qr)).assertTrue();
      expect(wifi.calls).assertEqual(1);
      expect(port.joinCalls).assertEqual(1);
      expect(port.wifiOnly).assertTrue();
    });

    it('rejected_wifi_prompt_does_not_consume_invite', 0, async () => {
      const port = new FakeMvpPort();
      const wifi = new FakeWifiPort();
      wifi.connected = false;
      const flow = new NearbyMvpScanFlow(port, wifi);
      const qr = 'flynes-wifi-v1:Test:password8:' + encodeURIComponent(LAN_INVITE);
      expect(await flow.scan(async (): Promise<string> => qr)).assertFalse();
      expect(port.joinCalls).assertEqual(0);
      expect(await flow.scan(async (): Promise<string> => LAN_INVITE)).assertTrue();
    });

    it('leaving_releases_guest_wifi_candidate', 0, async () => {
      const port = new FakeMvpPort();
      const wifi = new FakeWifiPort();
      const flow = new NearbyMvpScanFlow(port, wifi);
      const qr = 'flynes-wifi-v1:Test:password8:' + encodeURIComponent(LAN_INVITE);
      expect(await flow.scan(async (): Promise<string> => qr)).assertTrue();
      flow.leave();
      expect(wifi.releaseCalls).assertEqual(1);
    });

    it('failed_lan_join_releases_guest_wifi_candidate', 0, async () => {
      const port = new FakeMvpPort();
      port.joinResult = false;
      const wifi = new FakeWifiPort();
      const flow = new NearbyMvpScanFlow(port, wifi);
      const qr = 'flynes-wifi-v1:Test:password8:' + encodeURIComponent(LAN_INVITE);
      expect(await flow.scan(async (): Promise<string> => qr)).assertFalse();
      expect(wifi.releaseCalls).assertEqual(1);
    });
  });
}
