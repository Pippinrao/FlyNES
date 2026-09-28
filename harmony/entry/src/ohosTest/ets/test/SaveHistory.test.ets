import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import nativePlay, { HistoryInput } from 'libentry.so';

export default function saveHistoryTest() {
  describe('SaveHistory', () => {
    it('rejects_out_of_range_kind_before_mutating_history', 0, () => {
      const root = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().filesDir;
      const path = `${root}/history-kind-${Date.now()}.db`;
      const input: HistoryInput = { playedMs: 0, kind: 4294967296, label: '',
        session: 'invalid-kind', parent: 0, state: new Uint8Array([1, 2, 3]).buffer as ArrayBuffer,
        thumbnail: new ArrayBuffer(0), makeHead: true };
      let rejected = false;
      try { nativePlay.historySave(path, 'test-rom', input); } catch (error) { rejected = true; }
      expect(rejected).assertTrue();
      expect(nativePlay.historyHead(path, 'test-rom')).assertEqual(0);
      expect(nativePlay.historyList(path, 'test-rom').length).assertEqual(0);
    });
    it('persists_independent_history_and_resumes_selected_record', 0, () => {
      const root = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().filesDir;
      const path = `${root}/history-test-${Date.now()}.db`;
      const input: HistoryInput = { playedMs: 60000, kind: 1, label: 'checkpoint',
        session: 'test-round', parent: 0, state: new Uint8Array([1, 2, 3]).buffer as ArrayBuffer,
        thumbnail: new ArrayBuffer(0), makeHead: true };
      const first = nativePlay.historySave(path, 'test-rom', input);
      expect(first > 0).assertTrue();
      expect(nativePlay.historyHead(path, 'test-rom')).assertEqual(first);
      input.state = new Uint8Array([4, 5, 6]).buffer as ArrayBuffer;
      input.playedMs = 120000;
      const second = nativePlay.historySave(path, 'test-rom', input);
      expect(second > first).assertTrue();
      expect(nativePlay.historyList(path, 'test-rom').length).assertEqual(2);
      const operation = nativePlay.historyPrepare(path, 'test-rom', first, input);
      expect(nativePlay.historyHead(path, 'test-rom')).assertEqual(second);
      nativePlay.historyFinish(path, operation.operation, true);
      expect(nativePlay.historyHead(path, 'test-rom')).assertEqual(first);
      const bytes = new Uint8Array(nativePlay.historyRead(path, 'test-rom', first, false));
      expect(bytes[0]).assertEqual(1);
      expect(nativePlay.historyList(path, 'different-rom').length).assertEqual(0);
      const interrupted = nativePlay.historyPrepare(path, 'test-rom', second, input);
      expect(nativePlay.historyRecover(path, 'test-rom')).assertEqual(interrupted.backup);
      expect(nativePlay.historyHead(path, 'test-rom')).assertEqual(interrupted.backup);
    });
  });
}
