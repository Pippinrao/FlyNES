import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common, UIAbility, Want } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { fileIo } from '@kit.CoreFileKit';
import { i18n } from '@kit.LocalizationKit';
import { Component, Driver, MatchPattern, ON } from '@ohos.UiTest';
import process from '@ohos.process';
import systemDateTime from '@ohos.systemDateTime';
import hidebug from '@ohos.hidebug';
import nativeProduct from 'libentry.so';
import { BuiltinGames } from '../../../main/ets/service/BuiltinGames';
import { CatalogProductService, localizedGameTitle } from '../../../main/ets/service/CatalogProductService';
import { performanceRoute, performanceBuildMode } from './G1PerformanceObservations';
import { FlutterEngineCache } from '@ohos/flutter_ohos';
import { ProductStartupObservation } from '../../../main/ets/service/ProductStartupObservation';

let sampled = false;
function now(): number { return systemDateTime.getUptime(systemDateTime.TimeType.STARTUP, false); }
class PreferenceOwner {
  store: preferences.Preferences | undefined = undefined;
}
class StartupReport {
  schemaVersion: number = 1;
  route: string = '';
  pid: number = process.pid;
  debug: boolean = false;
  buildMode: string = '';
  sample: string = '';
  testEntryUptimeMs: number = now();
  abilityRequestUptimeMs: number = 0;
  startAbilityReturnedUptimeMs: number = 0;
  primaryInteractiveMs: number = -1;
  firstVisibleCardMs: number = -1;
  nativeOwnerReadyMs: number = -1;
  catalogReadyMs: number = -1;
  engineCreated: boolean = false;
  nativeSnapshotCount: number = -1;
  projectedDirectoryCount: number = -1;
  pssKb: number = -1;
  polls: number = 0;
  requestedPollMs: number = 25;
  category: string = 'ALL';
  query: string = '';
  multiplayerOnly: boolean = false;
  complete: boolean = false;
  failure: string = '';
  failureStack: string = '';
  phase: string = 'prepare';
  testContextFilesDir: string = '';
  moduleContextFilesDir: string = '';
  actualAbilityFilesDir: string = '';
  modulePreferencesDir: string = '';
  actualAbilityPreferencesDir: string = '';
  preferencesRestored: boolean = false;
  preferencesNormalizedUptimeMs: number = 0;
  windowStageCreatedUptimeMs: number = 0;
  scope: string = 'Fresh process per external aa test invocation; measures delegator startAbility request to UiTest observations. Excludes test runner/process initialization before request; includes UiTest/polling overhead; no physical first-frame timestamp.';
}
async function visible(component: Component, enabled: boolean): Promise<boolean> {
  const rect = await component.getBounds();
  return rect.right > rect.left && rect.bottom > rect.top && (!enabled ||
    await component.isEnabled() && await component.isClickable());
}

export default function g1StartupObservationTest() {
  const args = abilityDelegatorRegistry.getArguments().parameters;
  if (args['-s g1StartupObservation'] !== 'true') return;
  const route = performanceRoute(args['-s g1Entry'], args['-s g1CandidateApproved']);
  describe('G1StartupObservation', () => {
    it('observes_one_fresh_ability_request_with_real_ui_markers', 0, async () => {
      expect(sampled).assertFalse(); sampled = true;
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      const testContext = delegator.getAppContext();
      // Hypium getAppContext is a delegated wrapper: the free application API
      // rejects it as non-stage. Its Context method resolves the real module.
      const context = testContext.createModuleContext('entry') as common.UIAbilityContext;
      const report = new StartupReport();
      report.route = route;
      report.debug = context.applicationInfo.debug;
      report.buildMode = performanceBuildMode(args['-s g1BuildMode'], report.debug);
      report.sample = args['-s g1Sample'] ?? 'unspecified';
      report.testContextFilesDir = testContext.filesDir;
      report.moduleContextFilesDir = context.filesDir;
      report.modulePreferencesDir = context.preferencesDir;
      // Normalize through the actual cold Ability's context. A module resource
      // context retains app-level directories on API20 and is not equivalent.
      const owner = new PreferenceOwner();
      let hadFilter = false;
      let oldFilter: preferences.ValueType = false;
      let hadCategory = false;
      let oldCategory: preferences.ValueType = 'all';
      const monitor: abilityDelegatorRegistry.AbilityMonitor = {
        abilityName: 'EntryAbility',
        onAbilityCreate: (ability: UIAbility): void => {
          const actual = ability.context;
          const store = preferences.getPreferencesSync(actual, { name: 'game_center_ui' });
          owner.store = store;
          hadFilter = store.hasSync('multiplayerOnly');
          oldFilter = store.getSync('multiplayerOnly', false);
          hadCategory = store.hasSync('category'); oldCategory = store.getSync('category', 'all');
          store.putSync('category', 'all');
          store.putSync('multiplayerOnly', false); store.flushSync();
          report.actualAbilityFilesDir = actual.filesDir;
          report.actualAbilityPreferencesDir = actual.preferencesDir;
          report.preferencesNormalizedUptimeMs = now();
        },
        onWindowStageCreate: (_ability: UIAbility): void => { report.windowStageCreatedUptimeMs = now(); }
      };
      const games = BuiltinGames.loadSync(context);
      const first = games.all()[0];
      const title = localizedGameTitle(first.titleEn, first.titleZhHans, first.canonicalId,
        'system', i18n.System.getSystemLanguage());
      const driver = Driver.create();
      try {
        expect(FlutterEngineCache.getInstance().contains('flynes-product')).assertFalse();
        AppStorage.setOrCreate('ProductNativeBaseline', route === 'native');
        await delegator.addAbilityMonitor(monitor);
        const want: Want = { bundleName: 'com.flynes.emu', abilityName: 'EntryAbility' };
        // Candidate uses the ordinary application entry; native is selected
        // in-process before the first WindowStage loadContent.
        report.abilityRequestUptimeMs = now();
        await delegator.startAbility(want);
        report.startAbilityReturnedUptimeMs = now();
        const prefixes = route === 'flutter' ? ['Continue', 'Start', '继续', '开始'] :
          ['Continue game', 'Start game', 'Continue', 'Start', '继续', '开始'];
        while (now() - report.abilityRequestUptimeMs < 30000 &&
          (report.primaryInteractiveMs < 0 || report.firstVisibleCardMs < 0)) {
          report.polls++;
          if (report.primaryInteractiveMs < 0) {
            for (const prefix of prefixes) {
              report.phase = `primary.find:${prefix}`;
              const found = await driver.findComponents(ON.type('Button').text(prefix, MatchPattern.STARTS_WITH));
              // API 20 UiTest returns null before the ability tree is available,
              // despite the declared Array return type.
              if (found === null || found === undefined) continue;
              for (const component of found) {
                report.phase = `primary.visible:${prefix}`;
                if (await visible(component, true)) {
                  report.primaryInteractiveMs = now() - report.abilityRequestUptimeMs;
                  break;
                }
              }
              if (report.primaryInteractiveMs >= 0) break;
            }
          }
          if (report.firstVisibleCardMs < 0) {
            report.phase = 'card.find';
            const cards = await driver.findComponents(route === 'native' ? ON.type('ListItem') :
              ON.type('Button').text(title, MatchPattern.STARTS_WITH));
            if (cards !== null && cards !== undefined) {
              for (const card of cards) {
                report.phase = 'card.visible';
                if (await visible(card, false)) {
                  report.firstVisibleCardMs = now() - report.abilityRequestUptimeMs;
                  break;
                }
              }
            }
          }
          if (report.primaryInteractiveMs < 0 || report.firstVisibleCardMs < 0) await driver.delayMs(25);
        }
        expect(report.primaryInteractiveMs >= 0).assertTrue();
        expect(report.firstVisibleCardMs >= 0).assertTrue();
        const actual = (await delegator.getCurrentTopAbility()).context;
        report.actualAbilityFilesDir = actual.filesDir;
        report.actualAbilityPreferencesDir = actual.preferencesDir;
        expect(report.preferencesNormalizedUptimeMs > 0).assertTrue();
        expect(report.windowStageCreatedUptimeMs >= report.preferencesNormalizedUptimeMs).assertTrue();
        expect(report.actualAbilityPreferencesDir).assertEqual(actual.preferencesDir);
        const actualStore = preferences.getPreferencesSync(actual, { name: 'game_center_ui' });
        expect(actualStore.getSync('multiplayerOnly', true)).assertFalse();
        const snapshot = nativeProduct.catalogSnapshot();
        report.nativeSnapshotCount = snapshot.length;
        report.projectedDirectoryCount = new CatalogProductService().loadRowsFromSnapshot(games, snapshot).length;
        report.nativeOwnerReadyMs = ProductStartupObservation.nativeOwnerReadyMs - report.abilityRequestUptimeMs;
        report.catalogReadyMs = ProductStartupObservation.catalogReadyMs - report.abilityRequestUptimeMs;
        expect(report.nativeOwnerReadyMs >= 0).assertTrue();
        expect(report.catalogReadyMs >= report.nativeOwnerReadyMs).assertTrue();
        report.engineCreated = FlutterEngineCache.getInstance().contains('flynes-product');
        expect(report.engineCreated).assertEqual(route === 'flutter');
        report.pssKb = Number(hidebug.getPss());
        report.complete = true;
      } catch (error) {
        report.failure = `${error}`; report.failureStack = (error as Error).stack ?? '';
        throw new Error(report.failure);
      }
      finally {
        await delegator.removeAbilityMonitor(monitor);
        const store = owner.store;
        if (store !== undefined) {
          if (hadFilter) store.putSync('multiplayerOnly', oldFilter); else store.deleteSync('multiplayerOnly');
          if (hadCategory) store.putSync('category', oldCategory); else store.deleteSync('category');
          await store.flush();
          report.preferencesRestored = store.hasSync('multiplayerOnly') === hadFilter &&
            (!hadFilter || store.getSync('multiplayerOnly', false) === oldFilter) &&
            store.hasSync('category') === hadCategory && (!hadCategory || store.getSync('category', 'all') === oldCategory);
        }
        if (!report.preferencesRestored) {
          report.complete = false; report.failure += ' multiplayerOnly restore failed';
        }
        const path = `${context.filesDir}/g1-startup-${route}.json`;
        const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
        try { fileIo.writeSync(file.fd, JSON.stringify(report)); fileIo.fsyncSync(file.fd); }
        finally { fileIo.closeSync(file); }
        console.info(`FlyNES startup report=${path} complete=${report.complete}`);
        expect(report.preferencesRestored).assertTrue();
      }
    });
  });
}
