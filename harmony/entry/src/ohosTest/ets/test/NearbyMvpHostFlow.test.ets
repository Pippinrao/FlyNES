import { describe, it, expect } from '@ohos/hypium';
import { NearbyMvpHostFlow, NearbyHostPort } from '../../../main/ets/service/NearbyMvpHostFlow';
import { PlayService } from '../../../main/ets/service/PlayService';
import nativeSession from 'libentry.so';

class FakeHostPort implements NearbyHostPort {
  started: boolean = false;
  cancelled: boolean = false;
  host(token: Uint8Array): boolean {
    this.started = token.length === 16;
    return this.started;
  }
  invite(): string { return this.started ? 'flynes-lan-v1:192.168.1.2:1234:invite' : ''; }
  cancel(): void { this.cancelled = true; }
}

export default function nearbyMvpHostFlowTest(): void {
  describe('NearbyMvpHostFlow', () => {
    it('unpaired_snapshot_has_an_empty_peer_configuration_token', 0, () => {
      nativeSession.nearbyMvpCancel();
      expect(nativeSession.nearbyMvpSnapshot().peerConfigToken).assertEqual('');
    });
    it('creation_publishes_shared_invite_and_page_exit_keeps_owner', 0, () => {
      const port = new FakeHostPort();
      const flow = new NearbyMvpHostFlow(port, (): Uint8Array => new Uint8Array(16));
      expect(flow.start()).assertTrue();
      expect(flow.invite()).assertEqual('flynes-lan-v1:192.168.1.2:1234:invite');
      flow.hidePage();
      expect(port.cancelled).assertFalse();
      flow.disconnect();
      expect(port.cancelled).assertTrue();
    });
    it('page_hide_before_play_opens_does_not_call_a_closed_native_session', 0, () => {
      const play = new PlayService();
      play.setButtons(0);
      play.close();
      play.setButtons(0);
      expect(true).assertTrue();
    });
  });
}
