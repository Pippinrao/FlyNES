import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { Driver, ON, MatchPattern } from '@ohos.UiTest';
import nativeApp from 'libentry.so';
import { ProductCatalog } from '../../../main/ets/flutter/ProductCatalog';
import { PlayService, RomLaunchLocator } from '../../../main/ets/service/PlayService';
import { productBuildRevision } from '../../../main/ets/flutter/ProductBuildInfo';
import { patchProductSetting, ProductHostLease } from '../../../main/ets/flutter/ProductPolicy';
import { FlutterEngine, FlutterEngineCache } from '@ohos/flutter_ohos';
import { FoundationFlutterEntry } from '../../../main/ets/flutter/FoundationFlutterEntry';

export default function productG2Test() {
  describe('ProductG2', () => {
    it('native_product_projection_returns_real_canonical_rows_and_favorite', 0, async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      await delegator.startAbility({ bundleName: 'com.flynes.emu', abilityName: 'EntryAbility' });
      // startAbility resolves before the cold ability is necessarily foreground.
      await Driver.create().waitForComponent(ON.id('flutter_foundation_host'), 20000);
      const context = (await delegator.getCurrentTopAbility()).context;
      expect(/^[a-f0-9]{40}(-dirty\.[a-f0-9]{12})?$/.test(await productBuildRevision(context))).assertTrue();
      const catalog = new ProductCatalog(context);
      const projected = await catalog.query('all', '', false, '');
      const items = projected['items'] as Record<string, Object>[];
      expect(items.length > 0).assertTrue();
      const id = items[0]['canonicalId'] as string;
      expect(id.length > 0 && !id.startsWith('builtin:')).assertTrue();
      const row = await catalog.row(id);
      const before = row.favorite;
      try {
        nativeApp.catalogFavoriteSet(id, !before);
        const updated = await catalog.item(id);
        expect(updated['favorite'] === !before).assertTrue();
      } finally { nativeApp.catalogFavoriteSet(id, before); }
    });
    it('latest_settings_patch_preserves_layout_and_host_lease_rejects_old_cleanup', 0, () => {
      const before = nativeApp.settingsGet();
      const next = patchProductSetting(before, 'audioEnabled', before.audioEnabled !== 1);
      expect(next.buttonScale).assertEqual(before.buttonScale);
      expect(next.deadZone).assertEqual(before.deadZone);
      expect(next.audioEnabled !== before.audioEnabled).assertTrue();
      try {
        nativeApp.settingsApply(patchProductSetting(before, 'audioFocusPolicy', 3));
        expect(nativeApp.settingsGet().audioFocusPolicy).assertEqual(3);
        expect(nativeApp.settingsGet().buttonScale).assertEqual(before.buttonScale);
      } finally { nativeApp.settingsApply(before); }
      const lease = new ProductHostLease();
      const first = lease.acquire('hall'); lease.release(first);
      const second = lease.acquire('settings');
      expect(lease.release(first)).assertFalse();
      expect(lease.accepts(second)).assertTrue();
    });
    it('normal_ability_starts_product_hall_and_native_pause_settings_returns_same_game', 0, async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      await delegator.startAbility({ bundleName: 'com.flynes.emu', abilityName: 'EntryAbility' });
      const driver = Driver.create();
      expect(await driver.waitForComponent(ON.id('flutter_foundation_host'), 20000) !== null).assertTrue();
      const context = (await delegator.getCurrentTopAbility()).context;
      // Recovery capability may change Reading -> Continue after the host
      // appears. Reacquire either enabled product action, never wait only for
      // Start after a one-time Continue lookup.
      await launchNormalHall(driver);
      expect(await driver.waitForComponent(ON.text('II'), 15000) !== null).assertTrue();
      try {
        await pauseCommand(driver, context, 'pause_settings');
        expect(await driver.waitForComponent(ON.id('flutter_foundation_host'), 15000) !== null).assertTrue();
        // Sample after the actual pause transition has completed. A frame that
        // was already in flight at the touch is not a frame run while settings
        // owns the UI; the interval below must remain exactly frozen.
        expect(nativeApp.playRuntimeStatus().paused).assertTrue();
        const frames = nativeApp.playRuntimeStatus().sourceFrames;
        const clock = PlayService.lifecycleSnapshot();
        await driver.delayMs(400);
        expect(nativeApp.playRuntimeStatus().sourceFrames).assertEqual(frames);
        expect(PlayService.lifecycleSnapshot().playedMs).assertEqual(clock.playedMs);
        await driver.pressBack();
        expect(await driver.waitForComponent(ON.text('II'), 10000) !== null).assertTrue();
        await driver.delayMs(300);
        expect(nativeApp.playRuntimeStatus().running).assertTrue();
        expect(nativeApp.playRuntimeStatus().sourceFrames > frames).assertTrue();
      } finally {
        if (PlayService.lifecycleSnapshot().activeOwners > 0) {
          if (await driver.findComponent(ON.text('II')) === null) await driver.pressBack();
          await pauseCommand(driver, context, 'pause_game_center');
          await driver.waitForComponent(ON.id('flutter_foundation_host'), 15000);
        }
      }
      await driver.screenCap(`${context.filesDir}/product-g2-return.png`);
    });
    it('normal_entry_twenty_hall_game_and_twenty_pause_settings_layout_cycles', 0, async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      // No diagnostic Want, direct router call, or launch bridge bypass.
      await delegator.startAbility({ bundleName: 'com.flynes.emu', abilityName: 'EntryAbility' });
      const context = (await delegator.getCurrentTopAbility()).context;
      const driver = Driver.create();
      await driver.waitForComponent(ON.id('flutter_foundation_host'), 20000);
      const engine = FlutterEngineCache.getInstance().get('flynes-product')!;
      expect(engine !== undefined && engine !== null).assertTrue();
      const layout = nativeApp.controlLayoutGet();
      let previousGeneration = PlayService.lifecycleSnapshot().generation;
      for (let cycle = 1; cycle <= 20; cycle++) {
        assertProductOwners(engine, 1, 0);
        await launchNormalHall(driver);
        await driver.waitForComponent(ON.text('II'), 15000);
        assertProductOwners(engine, 0, 1);
        const opened = PlayService.lifecycleSnapshot();
        expect(opened.generation > previousGeneration).assertTrue();
        previousGeneration = opened.generation;
        const frames = nativeApp.playRuntimeStatus().sourceFrames;
        await driver.delayMs(250);
        expect(nativeApp.playRuntimeStatus().sourceFrames > frames).assertTrue();
        await pauseCommand(driver, context, 'pause_game_center');
        await driver.waitForComponent(ON.id('flutter_foundation_host'), 15000);
        assertProductOwners(engine, 1, 0);
        assertNativeClosed();
        console.info(`FlyNES G2 normal hall cycle=${cycle} engineSame=true hosts=1 owners=0 coreProgress=true coreClosed=true`);
      }
      await driver.screenCap(`${context.filesDir}/product-g2-hall-20.png`);
      await launchNormalHall(driver);
      await driver.waitForComponent(ON.text('II'), 15000);
      for (let attempt = 0; attempt < 100 && nativeApp.playRuntimeStatus().paused; attempt++) {
        await driver.delayMs(100);
      }
      expect(nativeApp.playRuntimeStatus().paused).assertFalse();
      const generation = PlayService.lifecycleSnapshot().generation;
      try {
        for (let cycle = 1; cycle <= 20; cycle++) {
          await pauseCommand(driver, context, 'pause_settings');
          await driver.waitForComponent(ON.id('flutter_foundation_host'), 15000);
          assertProductOwners(engine, 1, 1);
          const frames = nativeApp.playRuntimeStatus().sourceFrames;
          const clock = PlayService.lifecycleSnapshot();
          expect(nativeApp.playRuntimeStatus().paused).assertTrue();
          await clickProductText(driver, ['Controls', '操作', '[Cóntróls']);
          await clickProductText(driver, ['Edit layout', '编辑布局', '[Édít láyóút']);
          await driver.waitForComponent(ON.id('control-layout-save'), 10000);
          assertProductOwners(engine, 0, 1);
          await driver.delayMs(250);
          expect(nativeApp.playRuntimeStatus().sourceFrames).assertEqual(frames);
          expect(PlayService.lifecycleSnapshot().playedMs).assertEqual(clock.playedMs);
          expect(PlayService.lifecycleSnapshot().sinceSaveMs).assertEqual(clock.sinceSaveMs);
          if (cycle === 1) await driver.screenCap(`${context.filesDir}/product-g2-native-layout.png`);
          const save = cycle % 2 === 1;
          await (await driver.waitForComponent(ON.id(save ? 'control-layout-save' : 'control-layout-discard'), 5000)).click();
          if (save) {
            const warning = await driver.findComponent(ON.text(context.resourceManager.getStringByNameSync('control_layout_warning_save')));
            if (warning !== null) {
              const confirms = await driver.findComponents(ON.text(context.resourceManager.getStringByNameSync('control_layout_save')));
              await confirms[confirms.length - 1].click();
            }
          }
          await driver.waitForComponent(ON.id('flutter_foundation_host'), 15000);
          assertProductOwners(engine, 1, 1);
          // The same Flutter settings section survives its native layout child.
          await findProductText(driver, ['Edit layout', '编辑布局', '[Édít láyóút']);
          await driver.delayMs(250);
          expect(nativeApp.playRuntimeStatus().paused).assertTrue();
          expect(nativeApp.playRuntimeStatus().sourceFrames).assertEqual(frames);
          expect(PlayService.lifecycleSnapshot().playedMs).assertEqual(clock.playedMs);
          expect(PlayService.lifecycleSnapshot().sinceSaveMs).assertEqual(clock.sinceSaveMs);
          expect(PlayService.lifecycleSnapshot().generation).assertEqual(generation);
          if (cycle === 20) await driver.screenCap(`${context.filesDir}/product-g2-settings-20.png`);
          await driver.pressBack();
          // Compact settings first returns from its detail panel to its sections.
          if (await driver.findComponent(ON.text('II')) === null) await driver.pressBack();
          await driver.waitForComponent(ON.text('II'), 10000);
          assertProductOwners(engine, 0, 1);
          expect(PlayService.lifecycleSnapshot().generation).assertEqual(generation);
          await driver.delayMs(250);
          expect(nativeApp.playRuntimeStatus().running).assertTrue();
          expect(nativeApp.playRuntimeStatus().sourceFrames > frames).assertTrue();
          console.info(`FlyNES G2 normal settings cycle=${cycle} layout=${save ? 'save' : 'discard'} engineSame=true ownerSame=true pausedFrames=${frames} pausedClock=${clock.playedMs} autosaveClock=${clock.sinceSaveMs} resumed=true hosts=0 owners=1`);
        }
      } finally {
        nativeApp.controlLayoutApply(layout);
      }
      await pauseCommand(driver, context, 'pause_game_center');
      await driver.waitForComponent(ON.id('flutter_foundation_host'), 15000);
      assertProductOwners(engine, 1, 0);
      assertNativeClosed();
      await driver.screenCap(`${context.filesDir}/product-g2-cycles-complete.png`);
    });
  });
}

function assertProductOwners(engine: FlutterEngine, hosts: number, owners: number): void {
  expect(FlutterEngineCache.getInstance().get('flynes-product') === engine).assertTrue();
  expect(FoundationFlutterEntry.activeHostCount()).assertEqual(hosts);
  expect(PlayService.lifecycleSnapshot().activeOwners).assertEqual(owners);
}

function assertNativeClosed(): void {
  let closed = false;
  try { nativeApp.playRuntimeStatus(); } catch (_) { closed = true; }
  expect(closed).assertTrue();
}

async function findProductText(driver: Driver, labels: string[]): Promise<void> {
  for (let attempt = 0; attempt < 100; attempt++) {
    for (const label of labels) {
      if (await driver.findComponent(ON.text(label, MatchPattern.STARTS_WITH)) !== null) return;
    }
    await driver.delayMs(100);
  }
  throw new Error(`Product control missing: ${labels[0]}`);
}

async function clickProductText(driver: Driver, labels: string[]): Promise<void> {
  await findProductText(driver, labels);
  for (const label of labels) {
    const control = await driver.findComponent(ON.text(label, MatchPattern.STARTS_WITH));
    if (control !== null) { await control.click(); return; }
  }
  throw new Error(`Product control disappeared: ${labels[0]}`);
}

export async function launchNormalHall(driver: Driver): Promise<void> {
  for (let attempt = 0; attempt < 100; attempt++) {
    try {
      // A cached hall and the outgoing pause drawer coexist during the system
      // transition. A label match alone may click the old native Continue.
      if (await driver.findComponent(ON.id('product_presentation_gate')) !== null ||
          await driver.findComponent(ON.id('history-manual-save')) !== null) {
        await driver.delayMs(100); continue;
      }
      for (const label of ['Continue', '继续', 'Start', '开始', '[Cóntínúé', '[Stárt']) {
        const control = await driver.findComponent(ON.text(label, MatchPattern.STARTS_WITH).type('Button'));
        if (control !== null && await control.isEnabled()) { await control.click(); return; }
      }
    } catch (error) {
      if (!(error as Error).message.includes('NoCandidates')) throw new Error((error as Error).message);
    }
    await driver.delayMs(100);
  }
  throw new Error('Normal product hall has no enabled launch action');
}

export async function pauseCommand(driver: Driver, context: common.Context, resource: string): Promise<void> {
  console.info(`FlyNES G2 pause request=${resource} paused=${nativeApp.playRuntimeStatus().paused}`);
  if (!nativeApp.playRuntimeStatus().paused) await (await driver.waitForComponent(ON.text('II'), 10000)).click();
  const manual = await driver.waitForComponent(ON.id('history-manual-save'), 5000);
  // UiTest publishes accessibility bounds before the native 220ms drawer
  // entrance completes. Scrolling those off-screen bounds hits the OS gesture.
  await driver.delayMs(300);
  if (resource === 'pause_settings') await driver.screenCap(`${context.filesDir}/product-g2-settings-before-scroll.png`);
  console.info(`FlyNES G2 drawer ready=${manual !== null} paused=${nativeApp.playRuntimeStatus().paused}`);
  const label = context.resourceManager.getStringByNameSync(resource);
  for (let attempt = 0; attempt < 5; attempt++) {
    const drawer = await driver.waitForComponent(ON.type('Scroll'), 5000);
    if (drawer === null) break;
    // API18's explicit inset keeps the synthetic swipe clear of the HVD's
    // system gesture band even when the full-height drawer reaches the edge.
    const command = await drawer.scrollSearch(ON.text(label), true, 200);
    if (command !== null) { await command.click(); return; }
    await driver.delayMs(200);
  }
  await driver.screenCap(`${context.filesDir}/product-g2-pause-command-failure.png`);
  throw new Error(`Pause command unavailable: ${label}`);
}

// Deliberate native fault injection is compiled out of Release, not a product API.
export function productG2FaultTest() {
  describe('ProductG2NativeFaults', () => {
    it('native_nearby_selection_worker_keeps_arkui_responsive_and_rejects_replaced_room', 0, async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      expect(delegator.getAppContext().applicationInfo.debug).assertTrue();
      await delegator.startAbility({ bundleName: 'com.flynes.emu', abilityName: 'EntryAbility' });
      await Driver.create().waitForComponent(ON.id('flutter_foundation_host'), 20000);
      const context = (await delegator.getCurrentTopAbility()).context;
      const catalog = new ProductCatalog(context);
      const projection = await catalog.query('all', '', false, '');
      const items = projection['items'] as Record<string, Object>[];
      const row = await catalog.row(items[0]['canonicalId'] as string);
      const locator = new RomLaunchLocator();
      locator.canonicalId = row.canonicalId; locator.sourceUuidHex = row.sourceUuidHex;
      locator.sourceRelativePath = row.sourceRelativePath; locator.packageFormat = row.packageFormat;
      locator.zipEntryName = row.originalFilename;
      const bytes = await new PlayService().readRom(context, locator);
      const generation = nativeApp.nearbyMvpTestSelectionRoom(350);
      let completed = false;
      try {
        const selection = nativeApp.nearbyMvpSelectGameAsync(bytes, row.canonicalId, generation);
        void selection.then(() => { completed = true; });
        await new Promise<void>((resolve) => { setTimeout(resolve, 30); });
        // A real ArkUI timer callback and native snapshot/settings calls execute
        // while the N-API worker is deliberately blocked before timing/decode.
        expect(completed).assertFalse();
        expect(nativeApp.nearbyMvpSnapshot().selectionPending).assertTrue();
        expect(nativeApp.nearbyMvpSnapshot().localReady).assertEqual(0);
        expect(nativeApp.settingsGet().localeTag.length > 0).assertTrue();
        expect(nativeApp.nearbyMvpConfirm()).assertFalse();
        expect(nativeApp.nearbyMvpSelectGame(bytes, row.canonicalId)).assertFalse();
        const busy = await nativeApp.nearbyMvpSelectGameAsync(bytes, row.canonicalId, generation);
        expect(busy.status).assertEqual('nearby_busy');
        const replacement = nativeApp.nearbyMvpTestSelectionRoom(0);
        expect(replacement !== generation).assertTrue();
        expect(nativeApp.nearbyMvpSnapshot().roomGeneration).assertEqual(replacement);
        expect(nativeApp.nearbyMvpSnapshot().selectionPending).assertFalse();
        const result = await selection;
        expect(result.selected).assertFalse();
        expect(result.status).assertEqual('stale_room');
        expect(result.roomGeneration).assertEqual(generation);
        expect(nativeApp.nearbyMvpSnapshot().roomGeneration).assertEqual(replacement);
        expect(nativeApp.nearbyMvpTestSelectionFailure(0)).assertEqual(0);
        for (const mode of [1, 2, 3, 4, 5]) {
          const faultGeneration = nativeApp.nearbyMvpTestSelectionRoom(0);
          nativeApp.nearbyMvpTestSelectionFailure(mode);
          let rejected = false;
          try {
            const failed = await nativeApp.nearbyMvpSelectGameAsync(bytes, row.canonicalId, faultGeneration);
            expect(mode).assertEqual(3);
            expect(failed.selected).assertFalse();
            expect(failed.status).assertEqual('stale_room');
          } catch (error) {
            rejected = true;
            expect((error as Error).message).assertEqual('selection_failed');
          }
          expect(rejected).assertEqual(mode !== 3);
          expect(nativeApp.nearbyMvpSnapshot().selectionPending).assertFalse();
          expect(nativeApp.nearbyMvpTestSelectionFailure(0)).assertEqual(0);
        }
      } finally { nativeApp.nearbyMvpTestSelectionFailure(0); nativeApp.nearbyMvpCancel(); }
    });
  });
}
