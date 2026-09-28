import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { window } from '@kit.ArkUI';
import { Driver, ON } from '@ohos.UiTest';
import nativePlay from 'libentry.so';
import { BuiltinGames } from '../../../main/ets/service/BuiltinGames';
async function wait(ms: number): Promise<void> { await new Promise<void>((resolve) => setTimeout(resolve, ms)); }
export default function saveHistoryUiTest() {
  describe('SaveHistoryUi', () => {
    it('pause_exposes_manual_history_and_safe_restart', 0, async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      await delegator.startAbility({ bundleName: 'com.flynes.emu', abilityName: 'EntryAbility' });
      await wait(400);
      const context = (await delegator.getCurrentTopAbility()).context;
      const game = BuiltinGames.loadSync(context).all()[0];
      const win = await window.getLastWindow(context);
      const nav = win.getUIContext().getRouter();
      await nav.replaceUrl({ url: 'pages/RunGame', params: { canonicalId: game.canonicalId } });
      const driver = Driver.create();
      try {
        await wait(1200);
        await (await driver.findComponent(ON.text('II'))).click();
        expect(await driver.findComponent(ON.id('history-manual-save')) !== null).assertTrue();
        expect(await driver.screenCap(`${context.filesDir}/history-menu.png`)).assertTrue();
        await (await driver.findComponent(ON.id('history-manual-save'))).click();
        await driver.delayMs(300);
        await (await driver.findComponent(ON.id('history-open'))).click();
        expect(await driver.waitForComponent(ON.id('history-list'), 5000) !== null).assertTrue();
        expect(await driver.findComponent(ON.id('history-restore')) !== null).assertTrue();
        expect(await driver.waitForComponent(ON.id('history-preview'), 3000) !== null).assertTrue();
        await driver.delayMs(300);
        expect(await driver.screenCap(`${context.filesDir}/history-panel.png`)).assertTrue();
        await (await driver.findComponent(ON.id('history-close'))).click();
        // Wait for ArkUI to remove the full-screen panel before targeting the drawer.
        for (let attempt = 0; attempt < 40; attempt++) {
          if (await driver.findComponent(ON.id('history-close')) === null) break;
          await driver.delayMs(50);
        }
        await (await driver.waitForComponent(ON.id('history-restart'), 3000)).click();
        expect(await driver.waitForComponent(ON.id('history-confirm'), 5000) !== null).assertTrue();
        await (await driver.waitForComponent(ON.id('history-confirm'), 5000)).click();
        await wait(300);
        expect(nativePlay.playRuntimeStatus().running).assertTrue();
        expect(nativePlay.playRuntimeStatus().paused).assertFalse();
      } finally { await nav.replaceUrl({ url: 'pages/GameCenter' }); await wait(300); }
      expect(await driver.findComponent(ON.id('home-history')) === null).assertTrue();
      expect(await driver.findComponent(ON.id('home-restart')) === null).assertTrue();
      expect(await driver.screenCap(`${context.filesDir}/history-home.png`)).assertTrue();
    });
  });
}
