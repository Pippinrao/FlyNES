import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import { display, window } from '@kit.ArkUI';
import { Component, Driver, MatchPattern, ON } from '@ohos.UiTest';
import process from '@ohos.process';
import nativeApp, { HistoryInput, HistoryRow } from 'libentry.so';
import { ProductCatalog } from '../../../main/ets/flutter/ProductCatalog';
import { PlayService } from '../../../main/ets/service/PlayService';
import { CoverStore } from '../../../main/ets/service/CoverStore';
import { retentionCleanup } from './ProductRetentionCleanup';
import { NavigationEntry, saveNavigation, restoreNavigation, writeEvidence, readBytes, writeBytes,
  sameBytes, normalHall, hallReady, textControl, assertNoGameOrRoom, romFor } from './ProductRetentionFixture';
import { launchNormalHall, pauseCommand } from './ProductG2.test';

class CoverBackup {
  path: string = '';
  backup: string = '';
  mtime: number = 0;
}
class HistoryProof {
  schemaVersion: number = 1;
  pid: number = process.pid;
  canonicalId: string = '';
  contentKey: string = '';
  originalHead: number = 0;
  saveA: number = 0;
  saveB: number = 0;
  restart: number = 0;
  navigation: NavigationEntry[] = [];
  originalNavigation: NavigationEntry[] = [];
  originalAutosave: number = 0;
  originalHistoryRow: HistoryRow | undefined = undefined;
  coverBackups: CoverBackup[] = [];
  anchorTitle: string = '';
  anchorBounds: string = '';
  query: string = 'nes';
  coverBefore: Record<string, Object> = {};
  coverRestored: Record<string, Object> = {};
  coverRestarted: Record<string, Object> = {};
  coverMode: string = 'production-RunGame-sampling-only';
  coverBytesChanged: boolean = false;
  exactRestoredState: boolean = false;
  restoredHall: boolean = false;
  restartedHall: boolean = false;
  originalHeadRestored: boolean = false;
  coversRestored: boolean = false;
  preferencesRestored: boolean = false;
  failure: string = '';
  stage: string = 'prepare';
  cleanupErrors: string[] = [];
}

export default function productHistoryReturnTest(): void {
  describe('ProductHistoryReturn', () => {
    it('real_restore_restart_return_preserves_hall_and_projects_authoritative_cover', 0, async () => {
      const run = abilityDelegatorRegistry.getArguments().parameters['-s productHistoryRun'] ?? '';
      expect(/^[a-z0-9-]{1,40}$/.test(run)).assertTrue();
      const driver = Driver.create(); const context = await normalHall(driver);
      const prefix = `${context.filesDir}/g2-history-${run}`;
      expect(fileIo.accessSync(`${prefix}.json`)).assertFalse();
      const proof = new HistoryProof(); const catalog = new ProductCatalog(context);
      const originalNavigation = saveNavigation(context);
      const originalSettings = nativeApp.settingsGet();
      const backups: CoverBackup[] = []; let originalRow: HistoryRow | undefined = undefined;
      let coversBackedUp = false;
      const database = `${context.filesDir}/save-history.db`;
      let stateA = new ArrayBuffer(0); let thumbnailA = new ArrayBuffer(0);
      try {
        assertNoGameOrRoom();
        const projection = await catalog.query('builtin', proof.query, false, '');
        const rows = projection['items'] as Record<string, Object>[];
        expect(rows.length > 2).assertTrue();
        // Only a game with a pre-existing real head is eligible: its exact head can
        // be restored through the public history transaction without editing SQL.
        let selected: Record<string, Object> | undefined = undefined;
        for (let i = rows.length - 1; i >= 0; i--) {
          const id = rows[i]['canonicalId'] as string;
          const key = nativeApp.historyContentKey(await romFor(context, catalog, id));
          const head = nativeApp.historyHead(database, key);
          if (head > 0) { selected = rows[i]; proof.canonicalId = id; proof.contentKey = key;
            proof.originalHead = head; break; }
        }
        if (selected === undefined) throw new Error('An existing played builtin head is required; no user library is replaced');
        originalRow = nativeApp.historyList(database, proof.contentKey).find((row) => row.id === proof.originalHead);
        expect(originalRow !== undefined).assertTrue();
        proof.originalNavigation = originalNavigation; proof.originalAutosave = originalSettings.autosaveEnabled;
        proof.originalHistoryRow = originalRow;
        writeEvidence(`${prefix}.json`, proof);
        // Pin before creating new history entries so retention cannot collect the original.
        nativeApp.historyEdit(database, proof.originalHead, originalRow!.label, true, false);
        for (const id of [proof.canonicalId, catalog.legacy(proof.canonicalId)]) {
          const path = new CoverStore(context.filesDir).localPath(id);
          if (path.length > 0 && !backups.some((row) => row.path === path)) {
            const backup = new CoverBackup(); backup.path = path;
            backup.backup = `${prefix}-original-cover-${backups.length}.png`;
            backup.mtime = fileIo.statSync(path).mtime;
            writeBytes(backup.backup, readBytes(path)); backups.push(backup);
          }
        }
        proof.coverBackups = backups; coversBackedUp = true; writeEvidence(`${prefix}.json`, proof);
        const settings = nativeApp.settingsGet(); settings.autosaveEnabled = 0; nativeApp.settingsApply(settings);
        await (await textControl(driver, ['Built-in', '内置'])).click();
        const toggle = await textControl(driver, ['Two-player', '双人支持'], 'Toggle');
        if (await toggle.isChecked()) await toggle.click();
        await (await textControl(driver, ['Search', '搜索'])).click();
        const input = await driver.waitForComponent(ON.type('TextInput'), 5000);
        expect(input !== null).assertTrue(); await input.inputText(proof.query);
        await driver.pressBack(); // Dismiss the actual keyboard; keep the search field.
        await hallReady(driver);
        const titles = [selected['titleEn'] as string, selected['titleZhHans'] as string];
        proof.stage = 'select-card';
        const card = await findCard(driver, titles, true); await card.click();
        const last = rows[rows.length - 1];
        const lastTitles = [last['titleEn'] as string, last['titleZhHans'] as string];
        const beforeAnchor = await maybeCard(driver, lastTitles);
        const initialBounds = beforeAnchor === null ? '' : JSON.stringify(await beforeAnchor.getBounds());
        proof.stage = 'scroll-catalog';
        const anchor = await findCard(driver, lastTitles, true);
        proof.anchorTitle = await anchor.getText(); proof.anchorBounds = await stableCardBounds(driver, proof.anchorTitle);
        expect(proof.anchorBounds !== initialBounds).assertTrue(); // Observed nonzero scroll, not just a scroll call.
        for (let i = 0; i < 100; i++) {
          proof.navigation = saveNavigation(context);
          if (proof.navigation.find((row) => row.key === 'selected.builtin')?.value === proof.canonicalId) break;
          await driver.delayMs(50);
        }
        expect(proof.navigation.find((row) => row.key === 'selected.builtin')?.value).assertEqual(proof.canonicalId);
        expect(await (await driver.findComponent(ON.type('TextInput'))).getText()).assertEqual(proof.query);
        proof.coverBefore = await catalog.item(proof.canonicalId);
        expect(await driver.screenCap(`${prefix}-before.png`)).assertTrue();
        writeEvidence(`${prefix}.json`, proof);

        proof.stage = 'play-save';
        await launchNormalHall(driver); await waitGame(driver);
        proof.stage = 'native-input';
        await actualButtons(driver, context);
        proof.stage = 'play-save';
        await frames(driver, 500); // Real emulation passes all 2/4/6/8s cover sample thresholds.
        await pause(driver);
        const beforeManual = nativeApp.historyHead(database, proof.contentKey);
        await (await driver.waitForComponent(ON.id('history-manual-save'), 5000)).click();
        proof.saveA = await changedHead(driver, database, proof.contentKey, beforeManual);
        stateA = nativeApp.historyRead(database, proof.contentKey, proof.saveA, false);
        thumbnailA = nativeApp.historyRead(database, proof.contentKey, proof.saveA, true);
        expect(sameBytes(nativeApp.playSaveCheckpoint(), stateA)).assertTrue();
        await pauseCommand(driver, context, 'pause_resume'); await frames(driver, 90); await pause(driver);
        await (await driver.waitForComponent(ON.id('history-manual-save'), 5000)).click();
        proof.saveB = await changedHead(driver, database, proof.contentKey, proof.saveA);
        expect(sameBytes(nativeApp.historyRead(database, proof.contentKey, proof.saveB, false), stateA)).assertFalse();
        proof.stage = 'restore-history';
        await (await driver.waitForComponent(ON.id('history-open'), 5000)).click();
        const list = await driver.waitForComponent(ON.id('history-list'), 5000);
        const rowA = await list.scrollSearch(ON.id(`history-row-${proof.saveA}`));
        expect(rowA !== null).assertTrue(); await rowA.click();
        await (await driver.waitForComponent(ON.id('history-restore'), 5000)).click();
        await (await driver.waitForComponent(ON.id('history-confirm'), 5000)).click();
        for (let i = 0; i < 100 && nativeApp.historyHead(database, proof.contentKey) !== proof.saveA; i++) await driver.delayMs(50);
        expect(nativeApp.historyHead(database, proof.contentKey)).assertEqual(proof.saveA);
        expect(nativeApp.playRuntimeStatus().paused).assertTrue();
        expect(sameBytes(nativeApp.playSaveCheckpoint(), stateA)).assertTrue(); proof.exactRestoredState = true;
        expect(await driver.screenCap(`${prefix}-restored-native.png`)).assertTrue();
        proof.stage = 'restore-return';
        await pauseCommand(driver, context, 'pause_game_center');
        await returnedHall(driver, context, proof);
        expect(nativeApp.historyHead(database, proof.contentKey)).assertEqual(proof.saveA);
        expect(sameBytes(nativeApp.historyRead(database, proof.contentKey, proof.saveA, true), thumbnailA)).assertTrue();
        proof.coverRestored = await catalog.item(proof.canonicalId);
        const coverPath = proof.coverRestored['coverPath'] as string;
        expect(coverPath.length > 0).assertTrue();
        writeBytes(`${prefix}-restored-cover.png`, readBytes(coverPath));
        const previous = backups.find((row) => row.path === coverPath);
        proof.coverBytesChanged = previous === undefined || !sameBytes(readBytes(previous.backup), readBytes(coverPath));
        expect(proof.coverRestored['coverRevision']).assertEqual(fileIo.statSync(coverPath).mtime);
        // Same natural frame is valid; record it, never force mtime or replace the cover.
        expect(await driver.screenCap(`${prefix}-restored-hall.png`)).assertTrue(); proof.restoredHall = true;

        proof.stage = 'restart';
        await launchNormalHall(driver); await waitGame(driver); await pause(driver);
        const beforeRestart = nativeApp.historyHead(database, proof.contentKey);
        await (await driver.waitForComponent(ON.id('history-restart'), 5000)).click();
        await (await driver.waitForComponent(ON.id('history-confirm'), 5000)).click();
        proof.restart = await changedHead(driver, database, proof.contentKey, beforeRestart);
        const restart = nativeApp.historyList(database, proof.contentKey).find((row) => row.id === proof.restart);
        expect(restart !== undefined).assertTrue(); expect(restart!.playedMs).assertEqual(0);
        expect(restart!.kind).assertEqual(0); expect(restart!.parent > 0).assertTrue();
        expect(sameBytes(nativeApp.historyRead(database, proof.contentKey, proof.saveA, false), stateA)).assertTrue();
        await pause(driver); expect(await driver.screenCap(`${prefix}-restarted-native.png`)).assertTrue();
        await pauseCommand(driver, context, 'pause_game_center');
        await returnedHall(driver, context, proof);
        const head = nativeApp.historyHead(database, proof.contentKey);
        expect(head === proof.restart || nativeApp.historyList(database, proof.contentKey).find((row) => row.id === head)?.parent === proof.restart).assertTrue();
        proof.coverRestarted = await catalog.item(proof.canonicalId);
        expect(await driver.screenCap(`${prefix}-restarted-hall.png`)).assertTrue(); proof.restartedHall = true;
      } catch (error) {
        proof.failure = String(error);
        try { await driver.screenCap(`${prefix}-failure.png`); } catch (_) {}
        throw new Error(proof.failure);
      }
      finally {
        proof.cleanupErrors = await retentionCleanup([
          async () => {
            if (PlayService.lifecycleSnapshot().activeOwners > 0) {
              try {
                if (await driver.findComponent(ON.id('history-confirm')) !== null) {
                  const cancel = context.resourceManager.getStringByNameSync('history_cancel');
                  await (await driver.findComponent(ON.text(cancel))).click();
                }
                if (await driver.findComponent(ON.id('history-close')) !== null) await (await driver.findComponent(ON.id('history-close'))).click();
                await pauseCommand(driver, context, 'pause_game_center'); await hallReady(driver);
              } catch (_) {
                // Cleanup only: page teardown closes the actual RunGame owner even
                // if a failed assertion left a dialog blocking the normal command.
                const win = await window.getLastWindow(context);
                await win.getUIContext().getRouter().replaceUrl({ url: 'pages/FlutterFoundation' });
                await hallReady(driver);
              }
            }
            assertNoGameOrRoom();
          },
          async () => {
            if (proof.originalHead <= 0 || originalRow === undefined) return;
            if (PlayService.lifecycleSnapshot().activeOwners !== 0) throw new Error('Refusing head cleanup while a real game owner is live');
            const current = nativeApp.historyHead(database, proof.contentKey);
            if (current !== proof.originalHead) {
              const input: HistoryInput = { playedMs: originalRow.playedMs, kind: 2, label: '', session: `g2-cleanup-${run}`,
                parent: current, state: nativeApp.historyRead(database, proof.contentKey, current, false),
                thumbnail: nativeApp.historyRead(database, proof.contentKey, current, true), makeHead: false };
              const operation = nativeApp.historyPrepare(database, proof.contentKey, proof.originalHead, input);
              nativeApp.historyFinish(database, operation.operation, true);
            }
            nativeApp.historyEdit(database, proof.originalHead, originalRow.label, originalRow.pinned, false);
            expect(nativeApp.historyHead(database, proof.contentKey)).assertEqual(proof.originalHead); proof.originalHeadRestored = true;
          },
          async () => {
            if (!coversBackedUp) return;
            if (PlayService.lifecycleSnapshot().activeOwners !== 0) throw new Error('Refusing cover cleanup while a real game owner is live');
            for (const id of [proof.canonicalId, catalog.legacy(proof.canonicalId)]) {
              const path = new CoverStore(context.filesDir).localPath(id);
              const backup = backups.find((row) => row.path === path);
              if (path.length > 0 && backup === undefined) fileIo.unlinkSync(path);
            }
            for (const backup of backups) {
              writeBytes(backup.path, readBytes(backup.backup)); fileIo.utimes(backup.path, backup.mtime * 1000);
              expect(sameBytes(readBytes(backup.path), readBytes(backup.backup))).assertTrue();
              expect(fileIo.statSync(backup.path).mtime).assertEqual(backup.mtime);
            }
            proof.coversRestored = true;
          },
          async () => { const settings = nativeApp.settingsGet(); settings.autosaveEnabled = originalSettings.autosaveEnabled;
            nativeApp.settingsApply(settings); expect(nativeApp.settingsGet().autosaveEnabled).assertEqual(originalSettings.autosaveEnabled); },
          async () => { await restoreNavigation(context, originalNavigation); proof.preferencesRestored = true; }
        ]);
        writeEvidence(`${prefix}.json`, proof);
        expect(proof.cleanupErrors.length).assertEqual(0);
      }
    });
  });
}

async function maybeCard(driver: Driver, labels: string[]): Promise<Component | null> {
  for (const title of labels) { const item = await driver.findComponent(ON.text(title, MatchPattern.STARTS_WITH).type('Button'));
    if (item !== null) return item; }
  return null;
}
async function findCard(driver: Driver, labels: string[], scroll: boolean): Promise<Component> {
  let item = await maybeCard(driver, labels);
  if (item === null && scroll) {
    const grid = await catalogScroll(driver);
    const bounds = await grid.getBounds();
    console.info(`FlyNES G2 catalog swipe bounds=${JSON.stringify(bounds)} target=${labels[0]}`);
    // Use the observed catalog container, not the separate detail-panel Scroll.
    // Touch remains within those bounds and away from OS gesture edges.
    for (let attempt = 0; attempt < 5 && item === null; attempt++) {
      const y = Math.round((bounds.top + bounds.bottom) / 2);
      await driver.swipe(Math.round(bounds.right - 100), y, Math.round(bounds.left + 100), y, 600);
      item = await maybeCard(driver, labels);
    }
  }
  if (item === null) throw new Error(`Real catalog card unavailable: ${labels[0]}`);
  return item;
}
async function catalogScroll(driver: Driver): Promise<Component> {
  const toggle = await textControl(driver, ['Two-player', '双人支持'], 'Toggle');
  const control = await toggle.getBounds();
  for (const scroll of await driver.findComponents(ON.scrollable(true))) {
    const bounds = await scroll.getBounds();
    if (bounds.top >= control.top && bounds.bottom > control.bottom && bounds.right >= control.right) return scroll;
  }
  throw new Error('No observed catalog scroll below the Two-player header');
}
async function returnedHall(driver: Driver, context: common.UIAbilityContext, proof: HistoryProof): Promise<void> {
  await hallReady(driver); assertNoGameOrRoom();
  expect(JSON.stringify(saveNavigation(context))).assertEqual(JSON.stringify(proof.navigation));
  expect(await (await driver.findComponent(ON.type('TextInput'))).getText()).assertEqual(proof.query);
  expect(await stableCardBounds(driver, proof.anchorTitle)).assertEqual(proof.anchorBounds);
  await textControl(driver, ['Continue', '继续']);
}
async function stableCardBounds(driver: Driver, title: string): Promise<string> {
  let previous = ''; let stable = 0;
  for (let attempt = 0; attempt < 30; attempt++) {
    const current = JSON.stringify(await (await textControl(driver, [title])).getBounds());
    stable = current === previous ? stable + 1 : 0; previous = current;
    if (stable >= 3) return current;
    await driver.delayMs(100);
  }
  throw new Error('Catalog anchor still moving after touch/route transition');
}
async function waitGame(driver: Driver): Promise<void> {
  expect(await driver.waitForComponent(ON.text('II'), 15000) !== null).assertTrue();
  for (let i = 0; i < 100 && (PlayService.lifecycleSnapshot().activeOwners !== 1 || nativeApp.playRuntimeStatus().paused); i++) await driver.delayMs(50);
  expect(PlayService.lifecycleSnapshot().activeOwners).assertEqual(1); expect(nativeApp.playRuntimeStatus().paused).assertFalse();
}
async function frames(driver: Driver, count: number): Promise<void> {
  const start = nativeApp.playRuntimeStatus().sourceFrames;
  for (let i = 0; i < 300 && nativeApp.playRuntimeStatus().sourceFrames < start + count; i++) await driver.delayMs(50);
  expect(nativeApp.playRuntimeStatus().sourceFrames >= start + count).assertTrue();
}
async function pause(driver: Driver): Promise<void> {
  if (!nativeApp.playRuntimeStatus().paused) await (await driver.waitForComponent(ON.text('II'), 10000)).click();
  expect(await driver.waitForComponent(ON.id('history-manual-save'), 5000) !== null).assertTrue();
  expect(nativeApp.playRuntimeStatus().paused).assertTrue();
}
async function changedHead(driver: Driver, path: string, key: string, previous: number): Promise<number> {
  for (let i = 0; i < 100; i++) { const head = nativeApp.historyHead(path, key);
    if (head > 0 && head !== previous) return head; await driver.delayMs(50); }
  throw new Error('Real history action did not publish a new head');
}
async function actualButtons(driver: Driver, context: common.UIAbilityContext): Promise<void> {
  const win = await window.getLastWindow(context); const rect = win.getWindowProperties().windowRect;
  expect(await driver.waitForComponent(ON.type('Canvas'), 5000) !== null).assertTrue();
  const avoid = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM); const settings = nativeApp.settingsGet();
  const hit = nativeApp.hitMapFromLayout(rect.width, rect.height, display.getDefaultDisplaySync().densityDPI / 160,
    avoid.leftRect.width, avoid.rightRect.width, avoid.topRect.height, avoid.bottomRect.height,
    nativeApp.controlLayoutGet(), Math.max(0, Math.min(2, settings.directionMode - 1)), settings.deadZone);
  for (const name of ['START', 'A', 'A']) {
    const control = hit.controls.find((row) => row.control === name); expect(control !== undefined).assertTrue();
    let observed = 0;
    const timer = setInterval(() => { observed |= nativeApp.playStep().appliedButtons; }, 10);
    const x = Math.round(rect.left + control!.centerX); const y = Math.round(rect.top + control!.centerY);
    console.info(`FlyNES G2 history input=${name} x=${x} y=${y} window=${JSON.stringify(rect)}`);
    try { await driver.swipe(x - 40, y, x + 40, y, 200); }
    finally { clearInterval(timer); }
    if ((observed & (name === 'START' ? 8 : 1)) === 0) throw new Error(`Real ${name} touch not observed: mask=${observed} x=${x} y=${y}`);
    await frames(driver, 12);
  }
}
