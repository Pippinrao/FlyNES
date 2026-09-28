import { PlayService } from '../../../main/ets/service/PlayService';
import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import nativePlay, { HistoryInput } from 'libentry.so';
import { BuiltinGames } from '../../../main/ets/service/BuiltinGames';
import { SaveHistoryService } from '../../../main/ets/service/SaveHistoryService';

async function delay(ms: number): Promise<void> {
  await new Promise<void>((resolve) => { setTimeout(resolve, ms); });
}
class UnwritableHistory extends SaveHistoryService {
  calls: number = 0;
  advance(sourceFrames: number, sourceFps: number, running: boolean): void { this.calls++; throw new Error('storage full'); }
}
export default function saveHistoryPlayTest() {
  describe('SaveHistoryPlay', () => {
    it('blocks_automatic_writes_until_startup_failure_is_resolved', 0, () => {
      const play = new PlayService();
      const history = new UnwritableHistory('unused', 'unused');
      play.history = history;
      play.historyWarning = true;
      play.advanceHistory(3600, 60, true);
      expect(history.calls).assertEqual(0);
    });
    it('reports_autosave_failure_without_interrupting_game_tick', 0, () => {
      const play = new PlayService();
      play.history = new UnwritableHistory('unused', 'unused');
      expect(play.advanceHistory(3600, 60, true)).assertFalse();
    });
    it('restore_started_while_running_waits_for_explicit_resume', 0, () => {
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext()
        .createModuleContext('entry');
      const game = BuiltinGames.loadSync(context).all()[0];
      const rom = context.resourceManager.getRawFileContentSync(game.assetPath());
      const path = `${context.filesDir}/history-restore-paused-${Date.now()}.db`;
      const key = nativePlay.historyContentKey(rom);
      nativePlay.playOpen(rom); nativePlay.playSetPaused(true);
      try {
        const history = new SaveHistoryService(path, key);
        history.initialize(false);
        const target = history.save(1, 'target');
        nativePlay.playSetPaused(false);
        history.restore(target);
        expect(nativePlay.playRuntimeStatus().paused).assertTrue();
        expect(nativePlay.historyHead(path, key)).assertEqual(target);
      } finally { nativePlay.playClose(); }
    });
    it('failed_restore_started_while_running_preserves_head_and_stays_paused', 0, () => {
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext()
        .createModuleContext('entry');
      const game = BuiltinGames.loadSync(context).all()[0];
      const rom = context.resourceManager.getRawFileContentSync(game.assetPath());
      const path = `${context.filesDir}/history-restore-failed-${Date.now()}.db`;
      const key = nativePlay.historyContentKey(rom);
      nativePlay.playOpen(rom); nativePlay.playSetPaused(true);
      try {
        const history = new SaveHistoryService(path, key);
        history.initialize(false);
        const original = history.save(1, 'current');
        const invalid: HistoryInput = { playedMs: 0, kind: 1, label: 'invalid runtime state',
          session: 'invalid-state', parent: 0, state: new Uint8Array([1, 2, 3]).buffer as ArrayBuffer,
          thumbnail: new ArrayBuffer(0), makeHead: false };
        const target = nativePlay.historySave(path, key, invalid);
        nativePlay.playSetPaused(false);
        let rejected = false;
        try { history.restore(target); } catch (error) { rejected = true; }
        expect(rejected).assertTrue();
        expect(nativePlay.playRuntimeStatus().paused).assertTrue();
        expect(nativePlay.historyHead(path, key)).assertEqual(original);
        expect(history.list().some((row) => row.kind === 2)).assertTrue();
        // Cancellation has released the pending operation, allowing a durable manual save.
        expect(history.save(1, 'after rollback') > target).assertTrue();
      } finally { nativePlay.playClose(); }
    });
    it('counts_last_running_frames_at_pause_boundary_once', 0, () => {
      // No native runtime is needed when automatic writes are disabled.
      const history = new SaveHistoryService('', 'clock-only');
      history.intervalMs = 0;
      history.advance(0, 60, false);
      history.advance(0, 60, true);
      history.advance(120, 60, false);
      expect(history.playedMs).assertEqual(2000);
      history.advance(120, 60, false);
      expect(history.playedMs).assertEqual(2000);
    });
    it('rewinds_restarts_and_reopens_real_core_without_losing_history', 0, async () => {
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext()
        .createModuleContext('entry');
      const game = BuiltinGames.loadSync(context).all()[0];
      const rom = context.resourceManager.getRawFileContentSync(game.assetPath());
      const path = `${context.filesDir}/history-play-${Date.now()}.db`;
      const key = nativePlay.historyContentKey(rom);
      nativePlay.playOpen(rom);
      nativePlay.playSetPaused(true);
      try {
        const history = new SaveHistoryService(path, key);
        history.initialize(false);
        const initial = nativePlay.playStep().frameIndex;
        const first = history.save(1, 'start');
        expect(first > 0).assertTrue();
        nativePlay.playSetPaused(false);
        await delay(300);
        nativePlay.playSetPaused(true);
        expect(nativePlay.playStep().frameIndex > initial).assertTrue();
        const second = history.save(1, 'later');
        history.restore(first);
        expect(nativePlay.playStep().frameIndex).assertEqual(initial);
        expect(nativePlay.historyHead(path, key)).assertEqual(first);
        history.restore(second);
        expect(nativePlay.playStep().frameIndex > initial).assertTrue();
        history.restart();
        expect(nativePlay.playStep().frameIndex).assertEqual(initial);
        expect(history.list().some((row) => row.id === first)).assertTrue();
        expect(history.list().some((row) => row.kind === 2)).assertTrue();
        nativePlay.playClose();
        nativePlay.playOpen(rom);
        nativePlay.playSetPaused(true);
        const reopened = new SaveHistoryService(path, key);
        let legacyRead = false;
        reopened.initialize(true, () => { legacyRead = true; return undefined; });
        expect(legacyRead).assertFalse();
        expect(nativePlay.playStep().frameIndex).assertEqual(initial);
      } finally { nativePlay.playClose(); }
    });
    it('autosaves_only_emulated_play_time_and_honors_disabled_interval', 0, async () => {
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext()
        .createModuleContext('entry');
      const game = BuiltinGames.loadSync(context).all()[0];
      const rom = context.resourceManager.getRawFileContentSync(game.assetPath());
      nativePlay.playOpen(rom); nativePlay.playSetPaused(true);
      try {
        const history = new SaveHistoryService(`${context.filesDir}/history-clock-${Date.now()}.db`, nativePlay.historyContentKey(rom));
        history.initialize(false);
        history.advance(0, 60, false);
        history.advance(0, 60, false);
        expect(history.list().length).assertEqual(0);
        history.advance(0, 60, true);
        history.advance(3600, 60, true);
        expect(history.list().length).assertEqual(1);
        expect(history.playedMs).assertEqual(60000);
        history.intervalMs = 0;
        history.advance(10800, 60, true);
        expect(history.list().length).assertEqual(1);
      } finally { nativePlay.playClose(); }
    });
  });
}
