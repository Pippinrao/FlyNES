import { describe, it, expect } from '@ohos/hypium';
import { NearbyScanJoinService, NearbyScanClock } from '../../../main/ets/service/NearbyScanJoinService';
import { NearbyMvpPort, NearbyMvpSnapshot, NearbyWifiPort } from
  '../../../main/ets/service/NearbyMvpScanFlow';

const INVITE: string = 'flynes-lan-v1:192.168.43.1:4242:' + 'a'.repeat(64) + ':' + 'b'.repeat(32);

class FakeNative implements NearbyMvpPort {
  joined: string = '';
  state: number = 2;
  join(value: string): boolean { this.joined = value; return true; }
  snapshot(): NearbyMvpSnapshot { return { state: this.state, reason: 0, transportResult: 0, transportOperation: 4 }; }
  cancel(): boolean { return true; }
}

class FakeWifi implements NearbyWifiPort {
  requested: string = '';
  releases: number = 0;
  async connect(ssid: string, _: string): Promise<boolean> { this.requested = ssid; return true; }
  release(): void { this.releases++; }
}

class FakeClock implements NearbyScanClock {
  tick: () => void = (): void => {};
  stops: number = 0;
  start(callback: () => void): number { this.tick = callback; return 1; }
  stop(_: number): void { this.stops++; this.tick = (): void => {}; }
}

class PendingWifi extends FakeWifi {
  complete: (value: boolean) => void = (_: boolean): void => {};
  connect(ssid: string, _: string): Promise<boolean> {
    this.requested = ssid;
    return new Promise<boolean>((resolve: (value: boolean) => void): void => { this.complete = resolve; });
  }
}

export default function nearbyScanJoinServiceTest(): void {
  describe('NearbyScanJoinService', () => {
    it('cancelled_wifi_completion_cannot_release_replacement_attempt', 0, async () => {
      const wifi = new PendingWifi();
      const service = new NearbyScanJoinService(new FakeNative(), wifi, new FakeClock());
      const qr = 'flynes-wifi-v1:Host:password8:' + encodeURIComponent(INVITE);
      const first = service.joinScannedText(qr);
      await Promise.resolve();
      const finishFirst = wifi.complete;
      service.cancel();
      const second = service.joinScannedText(qr);
      await Promise.resolve();
      const finishSecond = wifi.complete;
      const before = wifi.releases;
      finishFirst(false);
      const firstResult = await first;
      const after = wifi.releases;
      finishSecond(true);
      const secondResult = await second;
      service.cancel();
      expect(firstResult).assertFalse();
      expect(after).assertEqual(before);
      expect(secondResult).assertTrue();
    });
    it('page_poll_preserves_pending_wifi_prompt_with_idle_or_old_ended_session', 0, async () => {
      for (const previousState of [0, 4]) {
        const native = new FakeNative();
        native.state = previousState;
        const wifi = new PendingWifi();
        const service = new NearbyScanJoinService(native, wifi, new FakeClock());
        const pending = service.joinScannedText('flynes-wifi-v1:Host:password8:' + encodeURIComponent(INVITE));
        await Promise.resolve();
        const before = wifi.releases;
        service.poll();
        const after = wifi.releases;
        wifi.complete(true);
        const joined = await pending;
        service.cancel();
        expect(wifi.requested).assertEqual('Host');
        expect(after).assertEqual(before);
        expect(joined).assertTrue();
      }
    });
    it('joins_inner_lan_invite_only_after_hotspot_join', 0, async () => {
      const native = new FakeNative();
      const wifi = new FakeWifi();
      const service = new NearbyScanJoinService(native, wifi);
      const qr = 'flynes-wifi-v1:Host%20NES:password8:' + encodeURIComponent(INVITE);
      expect(await service.joinScannedText(qr)).assertTrue();
      expect(wifi.requested).assertEqual('Host NES');
      expect(native.joined).assertEqual(INVITE);
      service.cancel();
    });

    it('releases_hotspot_candidate_when_session_ends_without_a_page_poll', 0, async () => {
      const native = new FakeNative();
      const wifi = new FakeWifi();
      const clock = new FakeClock();
      const service = new NearbyScanJoinService(native, wifi, clock);
      const qr = 'flynes-wifi-v1:Host:password8:' + encodeURIComponent(INVITE);
      expect(await service.joinScannedText(qr)).assertTrue();
      native.state = 4;
      clock.tick();
      expect(wifi.releases).assertEqual(1);
    });

    it('cancelled_service_can_join_again', 0, async () => {
      const native = new FakeNative();
      const service = new NearbyScanJoinService(native, new FakeWifi(), new FakeClock());
      expect(await service.joinScannedText(INVITE)).assertTrue();
      service.cancel();
      expect(await service.joinScannedText(INVITE)).assertTrue();
      service.cancel();
    });

    it('new_hotspot_join_fences_previous_terminal_monitor', 0, async () => {
      const native = new FakeNative();
      const wifi = new FakeWifi();
      const clock = new FakeClock();
      const service = new NearbyScanJoinService(native, wifi, clock);
      expect(await service.joinScannedText(INVITE)).assertTrue();
      const oldTick = clock.tick;
      native.state = 4;
      const qr = 'flynes-wifi-v1:Host:password8:' + encodeURIComponent(INVITE);
      expect(await service.joinScannedText(qr)).assertTrue();
      const before = wifi.releases;
      oldTick();
      expect(wifi.releases).assertEqual(before);
      service.cancel();
    });

    it('plain_lan_replacement_releases_previous_hotspot_candidate', 0, async () => {
      const native = new FakeNative();
      const wifi = new FakeWifi();
      const service = new NearbyScanJoinService(native, wifi, new FakeClock());
      const qr = 'flynes-wifi-v1:Host:password8:' + encodeURIComponent(INVITE);
      expect(await service.joinScannedText(qr)).assertTrue();
      const before = wifi.releases;
      expect(await service.joinScannedText(INVITE)).assertTrue();
      expect(wifi.releases).assertEqual(before + 1);
      service.cancel();
    });
  });
}
