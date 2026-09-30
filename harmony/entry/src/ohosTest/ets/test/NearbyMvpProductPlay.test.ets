import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { display, window } from '@kit.ArkUI';
import { Driver, ON } from '@ohos.UiTest';
import { fileIo } from '@kit.CoreFileKit';
import nativePlay from 'libentry.so';
import { BuiltinGames } from '../../../main/ets/service/BuiltinGames';
import { PlayService, RomLaunchLocator } from '../../../main/ets/service/PlayService';

async function delay(ms: number): Promise<void> {
  await new Promise<void>((resolve) => { setTimeout(resolve, ms); });
}

export default function nearbyMvpProductPlayTest(): void {
  describe('NearbyMvpProductPlay', () => {
    it('guest_reuses_RunGame_controls_renderer_and_audio', 0, async () => {
      const args = abilityDelegatorRegistry.getArguments().parameters;
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      await delegator.startAbility({ bundleName: 'com.flynes.emu', abilityName: 'EntryAbility' });
      await delay(800);
      const context = (await delegator.getCurrentTopAbility()).context;
      const win = await window.getLastWindow(context);
      nativePlay.appOpen(context.filesDir, context.cacheDir);
      const query = args['-s localGameQuery'];
      const invite = args['-s crossAppInvite'];
      expect(typeof invite === 'string').assertTrue();
      nativePlay.nearbyMvpCancel();
      expect(nativePlay.nearbyMvpJoin(invite)).assertTrue();
      const deadline = Date.now() + 20000;
      while (nativePlay.nearbyMvpSnapshot().state !== 3 && Date.now() < deadline) await delay(20);
      expect(nativePlay.nearbyMvpSnapshot().state).assertEqual(3);
      const connectedId = nativePlay.nearbyMvpSnapshot().sessionId;
      await win.getUIContext().getRouter().replaceUrl({ url: 'pages/NearbyLobby' });
      while (nativePlay.nearbyMvpSnapshot().state !== 6 && Date.now() < deadline) await delay(20);
      expect(nativePlay.nearbyMvpSnapshot().state).assertEqual(6);
      const firstKey = nativePlay.nearbyMvpSnapshot().peerGameKey;
      expect(firstKey.length > 0).assertTrue();
      const driver = Driver.create();
      await delay(1200);
      expect(await driver.findComponent(ON.type('Canvas')) !== null).assertTrue();
      const rect = win.getWindowProperties().windowRect;
      const avoid = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const settings = nativePlay.settingsGet();
      const hit = nativePlay.hitMapFromLayout(rect.width, rect.height,
        display.getDefaultDisplaySync().densityDPI / 160,
        avoid.leftRect.width, avoid.rightRect.width, avoid.topRect.height, avoid.bottomRect.height,
        nativePlay.controlLayoutGet(), Math.max(0, Math.min(2, settings.directionMode - 1)), settings.deadZone);
      const names = ['START', 'SELECT', 'A', 'B'];
      const bits = [8, 4, 1, 2];
      for (let index = 0; index < names.length; index++) {
        const target = hit.controls.find((item) => item.control === names[index]);
        expect(target !== undefined).assertTrue();
        let observed = false;
        const timer = setInterval(() => {
          observed = observed || (nativePlay.playStep().appliedButtons & bits[index]) !== 0;
        }, 10);
        try { await driver.longClick(Math.round(rect.left + target!.centerX), Math.round(rect.top + target!.centerY)); }
        finally { clearInterval(timer); }
        expect(observed).assertTrue();
        const releaseDeadline = Date.now() + 600;
        while (nativePlay.playStep().appliedButtons !== 0 && Date.now() < releaseDeadline)
          await delay(10);
        expect(nativePlay.playStep().appliedButtons).assertEqual(0);
      }
      const status = nativePlay.playRuntimeStatus();
      expect(status.running).assertTrue();
      expect(status.error).assertEqual('');
      expect(status.audioStarted).assertTrue();
      expect(status.audioConsumedSamples > 0).assertTrue();
      const render = nativePlay.renderStatus();
      expect(render.uploadedFrames > 30 && render.presentedFrames > 30).assertTrue();
      const frame = nativePlay.playStep();
      const evidence = fileIo.openSync(`${context.filesDir}/nearby-g2-guest-frame.rgb565`,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      try { fileIo.writeSync(evidence.fd, frame.rgb565); } finally { fileIo.closeSync(evidence.fd); }
      expect(await driver.screenCap(`${context.filesDir}/nearby-g2-guest-uitest.png`)).assertTrue();
      console.info(`FlyNesNearby product_audio consumed=${status.audioConsumedSamples} callbacks=${status.audioCallbackCount}`);
      // Exercise P2 movement after the host has passed the game's opening screens.
      await delay(8000);
      const right = hit.controls.find((item) => item.control === 'RIGHT');
      expect(right !== undefined).assertTrue();
      let moved = false;
      const movementTimer = setInterval(() => {
        moved = moved || (nativePlay.playStep().appliedButtons & 128) !== 0;
      }, 10);
      try { await driver.longClick(Math.round(rect.left + right!.centerX), Math.round(rect.top + right!.centerY)); }
      finally { clearInterval(movementTimer); }
      expect(moved).assertTrue();
      const hold = args['-s playHoldMs'];
      await delay(typeof hold === 'string' ? Number.parseInt(hold, 10) : 1000);
      let sawPause = false;
      const lobbyDeadline = Date.now() + 45000;
      while (nativePlay.nearbyMvpSnapshot().state === 6 && Date.now() < lobbyDeadline) {
        sawPause = sawPause || nativePlay.nearbyMvpSnapshot().paused;
        await delay(20);
      }
      expect(sawPause).assertTrue();
      // RunGame itself navigates back; the guest lobby loads the host's new catalog identity.
      const nextDeadline = Date.now() + 30000;
      while (nativePlay.nearbyMvpSnapshot().localConfigured === 0 && Date.now() < nextDeadline)
        await delay(50);
      expect(nativePlay.nearbyMvpSnapshot().localConfigured).assertEqual(1);
      expect(nativePlay.nearbyMvpSnapshot().peerGameKey !== firstKey).assertTrue();
      expect(nativePlay.nearbyMvpSnapshot().sessionId).assertEqual(connectedId);
      while (nativePlay.nearbyMvpSnapshot().state !== 6 && Date.now() < nextDeadline) await delay(50);
      expect(nativePlay.nearbyMvpSnapshot().state).assertEqual(6);
      await delay(3000);
      expect(nativePlay.nearbyMvpSnapshot().completedFrames > 30).assertTrue();
      expect(nativePlay.playRuntimeStatus().audioConsumedSamples > 0).assertTrue();
      console.info('FlyNesNearby product_lobby_switch second_game=PASS');
      if (typeof query === 'string' && query.length > 0) {
        const thirdDeadline = Date.now() + 30000;
        while (nativePlay.nearbyMvpSnapshot().state === 6 && Date.now() < thirdDeadline) await delay(20);
        while (nativePlay.nearbyMvpSnapshot().localConfigured === 0 && Date.now() < thirdDeadline)
          await delay(50);
        expect(nativePlay.nearbyMvpSnapshot().localConfigured).assertEqual(1);
        expect(nativePlay.nearbyMvpSnapshot().peerGameKey).assertEqual(firstKey);
        while (nativePlay.nearbyMvpSnapshot().state !== 6 && Date.now() < thirdDeadline) await delay(50);
        expect(nativePlay.nearbyMvpSnapshot().state).assertEqual(6);
        await delay(3000);
        expect(nativePlay.nearbyMvpSnapshot().completedFrames > 30).assertTrue();
        console.info('FlyNesNearby product_lobby_switch third_game=PASS');
      }
    });
  });
}
