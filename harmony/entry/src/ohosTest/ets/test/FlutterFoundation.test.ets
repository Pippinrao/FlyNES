import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common, Want } from '@kit.AbilityKit';
import { i18n } from '@kit.LocalizationKit';
import { window } from '@kit.ArkUI';
import { Driver, MatchPattern, ON } from '@ohos.UiTest';
import nativeProduct from 'libentry.so';
import { CatalogProductService, localizedGameTitle } from '../../../main/ets/service/CatalogProductService';
import { builtinGamesSync } from '../../../main/ets/service/PlayService';
import { foundationSnapshot, isFlutterFoundationRoute } from '../../../main/ets/flutter/FoundationProjection';

export default function flutterFoundationTest() {
  describe('FlutterFoundation', () => {
    it('accepts_only_debug_foundation_route', 0, () => {
      expect(isFlutterFoundationRoute('flutter_foundation', true)).assertTrue();
      expect(isFlutterFoundationRoute('flutter_foundation', false)).assertFalse();
      expect(isFlutterFoundationRoute('nearby_lobby', true)).assertFalse();
    });
    it('queries_existing_native_owner_and_shared_manifest_projection', 0, () => {
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext() as common.UIAbilityContext;
      nativeProduct.appOpen(context.filesDir, context.cacheDir);
      const nativeRows = nativeProduct.catalogSnapshot();
      expect(nativeRows.length >= 0).assertTrue();
      const games = builtinGamesSync(context);
      const rows = new CatalogProductService().loadRows(games);
      const snapshot = foundationSnapshot(rows, 1);
      expect(snapshot.games.length >= games.all().length).assertTrue();
      expect(snapshot.games.length > 0).assertTrue();
      expect(snapshot.games[0].canonicalId.length > 0).assertTrue();
    });
    it('renders_real_flutter_catalog_in_existing_ability', 0, async () => {
      const want: Want = { bundleName: 'com.flynes.emu', abilityName: 'EntryAbility',
        parameters: { 'flynes.test.page': 'flutter_foundation' } };
      await abilityDelegatorRegistry.getAbilityDelegator().startAbility(want);
      const driver = Driver.create();
      const library = await driver.waitForComponent(ON.id('flutter_foundation_host'), 15000);
      expect(library !== null && library !== undefined).assertTrue();
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext() as common.UIAbilityContext;
      const games = builtinGamesSync(context).all();
      expect(games.length > 0).assertTrue();
      // This pinned OH embedding exposes Flutter text/role to UiTest, but not
      // Semantics.identifier as a resource id. Assert the rendered real card.
      const title = localizedGameTitle(games[0].titleEn, games[0].titleZhHans,
        games[0].canonicalId, 'system', i18n.System.getSystemLanguage());
      const card = await driver.waitForComponent(ON.type('Button').text(title, MatchPattern.STARTS_WITH), 15000);
      expect(card !== null && card !== undefined).assertTrue();
      const second = games[1];
      const secondTitle = localizedGameTitle(second.titleEn, second.titleZhHans,
        second.canonicalId, 'system', i18n.System.getSystemLanguage());
      const nextCard = await driver.waitForComponent(ON.type('Button').text(secondTitle, MatchPattern.STARTS_WITH), 5000);
      await nextCard.click();
      expect(await driver.waitForComponent(ON.text(second.titleEn).type('Text'), 5000) !== null).assertTrue();
      await driver.screenCap(`${context.filesDir}/flutter-foundation.png`);
    });
    it('launches_native_game_saves_restores_restarts_and_returns_to_flutter', 0, async () => {
      await openFoundation();
      const driver = Driver.create();
      await launchFromFoundation(driver);
      const pause = await driver.waitForComponent(ON.text('II'), 10000);
      expect(pause !== null).assertTrue();
      await driver.delayMs(300);
      expect(nativeProduct.playRuntimeStatus().running).assertTrue();
      await pause.click();
      await (await driver.waitForComponent(ON.id('history-manual-save'), 5000)).click();
      await (await driver.waitForComponent(ON.id('history-open'), 5000)).click();
      await (await driver.waitForComponent(ON.id('history-restore'), 5000)).click();
      await (await driver.waitForComponent(ON.id('history-confirm'), 5000)).click();
      expect(nativeProduct.playRuntimeStatus().paused).assertTrue();
      await (await driver.waitForComponent(ON.id('history-restart'), 5000)).click();
      await (await driver.waitForComponent(ON.id('history-confirm'), 5000)).click();
      await driver.delayMs(250);
      expect(nativeProduct.playRuntimeStatus().paused).assertFalse();
      await (await driver.waitForComponent(ON.text('II'), 5000)).click();
      const context = (await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()).context;
      const backLabel = context.resourceManager.getStringByNameSync('pause_game_center');
      await (await driver.waitForComponent(ON.text(backLabel).type('Button'), 5000)).click();
      expect(await driver.waitForComponent(ON.id('flutter_foundation_host'), 10000) !== null).assertTrue();
      const resumeLabel = i18n.System.getSystemLanguage().startsWith('zh') ? '继续' : 'Continue';
      expect(await driver.waitForComponent(ON.text(resumeLabel).type('Button'), 10000) !== null).assertTrue();
      assertPlayClosed();
    });
    it('reuses_one_flutter_page_for_twenty_native_roundtrips', 0, async () => {
      await openFoundation();
      const driver = Driver.create();
      for (let index = 0; index < 20; index++) {
        await launchFromFoundation(driver);
        await driver.waitForComponent(ON.text('II'), 10000);
        const before = nativeProduct.playRuntimeStatus().sourceFrames;
        await driver.delayMs(200);
        expect(nativeProduct.playRuntimeStatus().sourceFrames > before).assertTrue();
        await returnFromNative(driver);
        assertPlayClosed();
        console.info(`FlyNES Flutter roundtrip=${index + 1} returned=true coreClosed=true`);
      }
    });
    it('background_cancels_pending_launch_without_breaking_the_next_return', 0, async () => {
      await openFoundation();
      const driver = Driver.create();
      await launchFromFoundation(driver);
      await driver.waitForComponent(ON.text('II'), 10000);
      await driver.pressHome();
      await driver.delayMs(400);
      await abilityDelegatorRegistry.getAbilityDelegator().startAbility({ bundleName: 'com.flynes.emu', abilityName: 'EntryAbility' });
      await driver.waitForComponent(ON.id('history-manual-save'), 5000);
      expect(nativeProduct.playRuntimeStatus().paused).assertTrue();
      await returnFromNative(driver);
      await launchFromFoundation(driver);
      await driver.waitForComponent(ON.text('II'), 10000);
      await returnFromNative(driver);
      assertPlayClosed();
    });
    it('opens_existing_settings_sources_and_nearby_and_returns', 0, async () => {
      await openFoundation();
      const driver = Driver.create();
      const chinese = i18n.System.getSystemLanguage().startsWith('zh');
      const labels = chinese ? ['设置', '游戏来源', '附近联机'] : ['Settings', 'Game sources', 'Nearby play'];
      const names = ['Settings', 'Sources', 'NearbyFriends'];
      for (let index = 0; index < labels.length; index++) {
        await (await driver.waitForComponent(ON.text(labels[index]).type('Button'), 10000)).click();
        await driver.delayMs(300);
        const context = (await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()).context;
        const state = (await window.getLastWindow(context)).getUIContext().getRouter().getState();
        expect(state.name === names[index] || state.path.indexOf(names[index]) >= 0).assertTrue();
        await driver.pressBack();
        expect(await driver.waitForComponent(ON.id('flutter_foundation_host'), 10000) !== null).assertTrue();
      }
    });
    it('root_back_returns_to_native_library_and_can_reopen_flutter', 0, async () => {
      await openFoundation();
      const driver = Driver.create();
      expect(await driver.waitForComponent(ON.id('flutter_foundation_host'), 10000) !== null).assertTrue();
      await driver.pressBack();
      await driver.delayMs(500);
      const context = (await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()).context;
      const state = (await window.getLastWindow(context)).getUIContext().getRouter().getState();
      expect(state.name === 'GameCenter' || state.path.indexOf('GameCenter') >= 0).assertTrue();
      await openFoundation();
      expect(await driver.waitForComponent(ON.id('flutter_foundation_host'), 10000) !== null).assertTrue();
      await launchFromFoundation(driver);
      await driver.waitForComponent(ON.text('II'), 10000);
      await returnFromNative(driver);
      assertPlayClosed();
    });
    it('native_only_twenty_roundtrips_preserve_rendering', 0, async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      await delegator.startAbility({ bundleName: 'com.flynes.emu', abilityName: 'EntryAbility' });
      const driver = Driver.create();
      await driver.delayMs(700);
      const context = (await delegator.getCurrentTopAbility()).context;
      const nav = (await window.getLastWindow(context)).getUIContext().getRouter();
      const game = builtinGamesSync(context as common.UIAbilityContext).all()[0];
      await nav.replaceUrl({ url: 'pages/GameCenter' });
      for (let index = 0; index < 20; index++) {
        await nav.replaceUrl({ url: 'pages/RunGame', params: { canonicalId: game.canonicalId } });
        await driver.waitForComponent(ON.text('II'), 10000);
        const before = nativeProduct.playRuntimeStatus().sourceFrames;
        await driver.delayMs(200);
        expect(nativeProduct.playRuntimeStatus().sourceFrames > before).assertTrue();
        await (await driver.waitForComponent(ON.text('II'), 5000)).click();
        const label = context.resourceManager.getStringByNameSync('pause_game_center');
        await (await driver.waitForComponent(ON.text(label).type('Button'), 5000)).click();
        await driver.delayMs(300);
        expect(nav.getState().name === 'GameCenter').assertTrue();
        assertPlayClosed();
        console.info(`FlyNES native-only roundtrip=${index + 1} returned=true coreClosed=true`);
      }
    });
  });
}

function assertPlayClosed(): void {
  let closed = false;
  try { nativeProduct.playRuntimeStatus(); } catch (_) { closed = true; }
  expect(closed).assertTrue();
}

async function returnFromNative(driver: Driver): Promise<void> {
  if (!nativeProduct.playRuntimeStatus().paused) await (await driver.waitForComponent(ON.text('II'), 5000)).click();
  const context = (await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility()).context;
  const label = context.resourceManager.getStringByNameSync('pause_game_center');
  await (await driver.waitForComponent(ON.text(label).type('Button'), 5000)).click();
  expect(await driver.waitForComponent(ON.id('flutter_foundation_host'), 10000) !== null).assertTrue();
}



async function openFoundation(): Promise<void> {
  await abilityDelegatorRegistry.getAbilityDelegator().startAbility({ bundleName: 'com.flynes.emu',
    abilityName: 'EntryAbility', parameters: { 'flynes.test.page': 'flutter_foundation' } });
}

async function launchFromFoundation(driver: Driver): Promise<void> {
  const chinese = i18n.System.getSystemLanguage().startsWith('zh');
  for (let attempt = 0; attempt < 100; attempt++) {
    try {
      const resume = await driver.findComponent(ON.text(chinese ? '继续' : 'Continue').type('Button'));
      const launch = resume ?? await driver.findComponent(ON.text(chinese ? '开始' : 'Start').type('Button'));
      if (launch !== null && await launch.isEnabled()) { await launch.click(); return; }
    } catch (error) {
      // A refreshed real catalog can replace the UiTest widget between lookup
      // and click. Reacquire only this documented stale-object condition.
      const message = (error as Error).message;
      if (message.indexOf('NoCandidates') < 0) throw new Error(message);
    }
    await driver.delayMs(100);
  }
  expect(false).assertTrue();
}
