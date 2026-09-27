import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo } from '@kit.CoreFileKit';
import nativeSession, { NearbyMvpStepResult } from 'libentry.so';
import { BuiltinGame, BuiltinGames } from '../../../main/ets/service/BuiltinGames';

function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => { setTimeout(resolve, ms); });
}

function writeEvidence(path: string, content: string | ArrayBuffer): void {
  if (fileIo.accessSync(path)) fileIo.unlinkSync(path);
  const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);
  try { fileIo.writeSync(file.fd, content); fileIo.fsyncSync(file.fd); }
  finally { fileIo.closeSync(file.fd); }
}

export default function nearbyMvpExternalHostTest(): void {
  describe('NearbyMvpExternalHost', () => {
    it('real_napi_host_serves_external_product_guest', 0, async () => {
      nativeSession.nearbyMvpCancel();
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext()
        .createModuleContext('entry');
      const invitePath = `${context.filesDir}/nearby-cross-host-invite.txt`;
      if (fileIo.accessSync(invitePath)) fileIo.unlinkSync(invitePath);
      try {
        expect(nativeSession.nearbyMvpHost(new Uint8Array(16))).assertTrue();
        let invite = '';
        const inviteDeadline = Date.now() + 10_000;
        while (invite.length === 0 && Date.now() < inviteDeadline) {
          invite = nativeSession.nearbyMvpInvite();
          if (invite.length === 0) await delay(20);
        }
        expect(invite.startsWith('flynes-lan-v1:')).assertTrue();
        writeEvidence(invitePath, invite);

        const joinDeadline = Date.now() + 60_000;
        let snapshot = nativeSession.nearbyMvpSnapshot();
        while (snapshot.state !== 3 && Date.now() < joinDeadline) {
          await delay(20);
          snapshot = nativeSession.nearbyMvpSnapshot();
        }
        expect(snapshot.state).assertEqual(3);
        expect(snapshot.role).assertEqual(1);

        const games = BuiltinGames.loadSync(context).all();
        let selected: BuiltinGame | undefined = undefined;
        for (let index = 0; index < games.length; index++) {
          if (games[index].multiplayerEligibility === 'SUPPORTED' &&
            games[index].multiplayerMaxPlayers === 2) { selected = games[index]; break; }
        }
        expect(selected !== undefined).assertTrue();
        const game = selected as BuiltinGame;
        const rom = context.resourceManager.getRawFileContentSync(game.assetPath());
        expect(nativeSession.nearbyMvpSelectGame(rom, game.canonicalId)).assertTrue();
        const readyDeadline = Date.now() + 20_000;
        snapshot = nativeSession.nearbyMvpSnapshot();
        while (snapshot.state !== 5 && Date.now() < readyDeadline) {
          await delay(20);
          snapshot = nativeSession.nearbyMvpSnapshot();
        }
        expect(snapshot.state).assertEqual(5);
        expect(nativeSession.nearbyMvpConfirm()).assertTrue();
        const runDeadline = Date.now() + 35_000;
        snapshot = nativeSession.nearbyMvpSnapshot();
        while (snapshot.state !== 6 && Date.now() < runDeadline) {
          await delay(10);
          snapshot = nativeSession.nearbyMvpSnapshot();
        }
        expect(snapshot.state).assertEqual(6);
        let step: NearbyMvpStepResult = nativeSession.nearbyMvpStep(0x01);
        let pcmSamples = 0;
        let frame: Uint8Array | undefined = undefined;
        while (step.completedFrames < 600 && Date.now() < runDeadline) {
          step = nativeSession.nearbyMvpStep(Math.floor(step.completedFrames / 30) % 2 === 0 ? 0x01 : 0);
          pcmSamples += step.pcmSampleCount;
          if (frame === undefined && step.completedFrames >= 600) frame = new Uint8Array(step.rgb565);
          await delay(step.submitted ? 8 : 1);
        }
        const finalSnapshot = nativeSession.nearbyMvpSnapshot();
        writeEvidence(`${context.filesDir}/nearby-cross-host-debug.txt`,
          `${step.completedFrames},${finalSnapshot.state},${finalSnapshot.reason},${finalSnapshot.localReady},${finalSnapshot.peerReady}`);
        expect(step.completedFrames >= 600).assertTrue();
        expect(frame !== undefined).assertTrue();
        expect((frame as Uint8Array).byteLength).assertEqual(256 * 240 * 2);
        expect(pcmSamples > 0).assertTrue();
        writeEvidence(`${context.filesDir}/nearby-cross-host-play.txt`,
          `${step.completedFrames},${step.frameIndex},${pcmSamples}`);
        writeEvidence(`${context.filesDir}/nearby-cross-host-frame.rgb565`,
          (frame as Uint8Array).buffer as ArrayBuffer);
        await delay(3_000);
      } finally {
        nativeSession.nearbyMvpCancel();
        if (fileIo.accessSync(invitePath)) fileIo.unlinkSync(invitePath);
      }
    });
  });
}
