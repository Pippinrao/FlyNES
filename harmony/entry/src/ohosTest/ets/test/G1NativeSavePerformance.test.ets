import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { display, window } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { fileIo } from '@kit.CoreFileKit';
import { Driver, MatchPattern, ON } from '@ohos.UiTest';
import { i18n } from '@kit.LocalizationKit';
import hidebug from '@ohos.hidebug';
import systemDateTime from '@ohos.systemDateTime';
import nativePlay, { HistoryRow, PlayRuntimeStatusDto, RenderStatusDto } from 'libentry.so';
import { BuiltinGames } from '../../../main/ets/service/BuiltinGames';
import { PlayService, RomLaunchLocator } from '../../../main/ets/service/PlayService';
import { localizedGameTitle } from '../../../main/ets/service/CatalogProductService';
import { EmulatedProgress, performanceRoute, performanceBuildMode } from './G1PerformanceObservations';

function now(): number { return systemDateTime.getUptime(systemDateTime.TimeType.STARTUP, false); }
async function wait(ms: number): Promise<void> { await new Promise<void>((resolve) => setTimeout(resolve, ms)); }

class CounterSample {
  beginMs: number = 0;
  endMs: number = 0;
  playedMs: number = 0;
  runtime: PlayRuntimeStatusDto | undefined = undefined;
  renderer: RenderStatusDto | undefined = undefined;
}
class MemorySample {
  beginMs: number = 0;
  endMs: number = 0;
  pssKb: number = -1;
  vssKb: number = -1;
  nativeAllocatedBytes: number = -1;
  vmHeapUsedKb: number = -1;
  vmTotalHeapKb: number = -1;
  head: number = 0;
  error: string = '';
}
class InputSample {
  beginMs: number = 0;
  firstAppliedMs: number = -1;
  injectionReturnedMs: number = 0;
  releasedObservedMs: number = -1;
  observedButtons: number = 0;
  error: string = '';
}
class PerformanceReport {
  schemaVersion: number = 1;
  entry: string = 'native';
  buildMode: string = '';
  actualApplicationDebug: boolean = false;
  canonicalId: string = '';
  contentKey: string = '';
  epochStartMs: number = 0;
  uptimeStartMs: number = 0;
  uptimeEndMs: number = 0;
  requiredEmulatedMs: number = 65000;
  emulatedMs: number = 0;
  autosaveIntervalMs: number = 60000;
  requestedCounterPollMs: number = 20;
  requestedMemoryPollMs: number = 1000;
  beforeHead: number = 0;
  afterHead: number = 0;
  beforeRows: HistoryRow[] = [];
  afterRows: HistoryRow[] = [];
  newAutoRows: HistoryRow[] = [];
  counters: CounterSample[] = [];
  memory: MemorySample[] = [];
  inputs: InputSample[] = [];
  failure: string = '';
  complete: boolean = false;
  limitations: string[] = [
    'Emulator software baseline only; no physical refresh, energy, temperature or touch-to-photon certification.',
    'Counter polling times are observations, not per-frame present timestamps or exact save begin/end.',
    'Input interval includes UiTest injection and 10 ms polling; playStep copies frame/audio buffers during sparse input probes.',
    'Memory and history reads have their own begin/end timestamps; observer cost is included in this instrumented baseline.',
    'History head transitions are bounded by one-second observations; existing history is preserved and real AUTO records remain.'
  ];
}

function memorySample(db: string, key: string, start: number): MemorySample {
  const sample = new MemorySample();
  sample.beginMs = now() - start;
  try {
    sample.pssKb = Number(hidebug.getPss());
    sample.vssKb = Number(hidebug.getVss());
    sample.nativeAllocatedBytes = Number(hidebug.getNativeHeapAllocatedSize());
    const vm = hidebug.getAppVMMemoryInfo();
    sample.vmHeapUsedKb = Number(vm.heapUsed);
    sample.vmTotalHeapKb = Number(vm.totalHeap);
  } catch (error) { sample.error = `${error}`; }
  sample.head = nativePlay.historyHead(db, key);
  sample.endMs = now() - start;
  return sample;
}

async function inputSample(driver: Driver, win: window.Window, start: number): Promise<InputSample> {
  const sample = new InputSample();
  const rect = win.getWindowProperties().windowRect;
  const avoid = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
  const settings = nativePlay.settingsGet();
  const hit = nativePlay.hitMapFromLayout(rect.width, rect.height,
    display.getDefaultDisplaySync().densityDPI / 160,
    avoid.leftRect.width, avoid.rightRect.width, avoid.topRect.height, avoid.bottomRect.height,
    nativePlay.controlLayoutGet(), Math.max(0, Math.min(2, settings.directionMode - 1)), settings.deadZone);
  const target = hit.controls.find((candidate) => candidate.control === 'A');
  if (target === undefined) throw new Error('Native A hit region unavailable');
  sample.beginMs = now() - start;
  const timer = setInterval(() => {
    try {
      const buttons = nativePlay.playStep().appliedButtons;
      sample.observedButtons |= buttons;
      if ((buttons & 1) !== 0 && sample.firstAppliedMs < 0) sample.firstAppliedMs = now() - start;
      if (buttons === 0 && sample.firstAppliedMs >= 0 && sample.releasedObservedMs < 0) {
        sample.releasedObservedMs = now() - start;
      }
    } catch (error) { sample.error = `${error}`; }
  }, 10);
  try {
    await driver.click(Math.round(rect.left + target.centerX), Math.round(rect.top + target.centerY));
    sample.injectionReturnedMs = now() - start;
    await wait(100);
  } catch (error) { sample.error = `${error}`; }
  finally { clearInterval(timer); }
  return sample;
}

export default function g1NativeSavePerformanceTest() {
  const args = abilityDelegatorRegistry.getArguments().parameters;
  if (args['-s g1NativePerformance'] !== 'true') return;
  const route = performanceRoute(args['-s g1Entry'], args['-s g1CandidateApproved']);
  describe('G1NativeSavePerformance', () => {
    it('native_autosave_65_seconds_records_real_progress_and_observations', 0, async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      await delegator.startAbility({ bundleName: 'com.flynes.emu', abilityName: 'EntryAbility' });
      await wait(700);
      const context = (await delegator.getCurrentTopAbility()).context as common.UIAbilityContext;
      const win = await window.getLastWindow(context);
      const nav = win.getUIContext().getRouter();
      await nav.replaceUrl({ url: 'pages/GameCenter' });
      await wait(300);
      const original = nativePlay.settingsGet();
      const options = preferences.getPreferencesSync(context, { name: 'save_history' });
      const hadInterval = options.hasSync('intervalMs');
      const oldInterval = options.getSync('intervalMs', 60000);
      const report = new PerformanceReport();
      report.entry = route;
      report.actualApplicationDebug = context.applicationInfo.debug;
      const progress = new EmulatedProgress();
      let observer = -1;
      try {
        report.buildMode = performanceBuildMode(args['-s g1BuildMode'], report.actualApplicationDebug);
        const settings = nativePlay.settingsGet();
        settings.audioEnabled = 1;
        settings.autosaveEnabled = 1;
        nativePlay.settingsApply(settings);
        options.putSync('intervalMs', 60000);
        await options.flush();
        const games = BuiltinGames.loadSync(context).all();
        const requested = args['-s g1CanonicalId'];
        const game = requested === undefined ? games[0] : games.find((item) => item.canonicalId === requested);
        if (game === undefined) throw new Error('Requested licensed baseline game absent from manifest');
        report.canonicalId = game.canonicalId;
        const locator = new RomLaunchLocator();
        locator.canonicalId = game.canonicalId;
        report.contentKey = nativePlay.historyContentKey(await new PlayService().readRom(context, locator));
        const db = `${context.filesDir}/save-history.db`;
        report.beforeHead = nativePlay.historyHead(db, report.contentKey);
        report.beforeRows = nativePlay.historyList(db, report.contentKey);
        const driver = Driver.create();
        if (route === 'native') {
          await nav.replaceUrl({ url: 'pages/RunGame', params: { canonicalId: game.canonicalId } });
        } else {
          // Candidate must traverse the real shared directory and existing bridge.
          // Directly opening RunGame here would omit the retained Flutter engine.
          if (report.buildMode === 'release') {
            // Only this opt-in test router enters the existing real page. The
            // production Release Want gate remains disabled and unchanged.
            await nav.replaceUrl({ url: 'pages/FlutterFoundation' });
          } else {
            await delegator.startAbility({ bundleName: 'com.flynes.emu', abilityName: 'EntryAbility',
              parameters: { 'flynes.test.page': 'flutter_foundation' } });
          }
          await driver.waitForComponent(ON.id('flutter_foundation_host'), 15000);
          const title = localizedGameTitle(game.titleEn, game.titleZhHans, game.canonicalId,
            'system', i18n.System.getSystemLanguage());
          await (await driver.waitForComponent(ON.type('Button').text(title, MatchPattern.STARTS_WITH), 15000)).click();
          let launched = false;
          const chinese = i18n.System.getSystemLanguage().startsWith('zh');
          for (let attempt = 0; attempt < 100 && !launched; attempt++) {
            try {
              const resume = await driver.findComponent(ON.text(chinese ? '继续' : 'Continue').type('Button'));
              const button = resume ?? await driver.findComponent(ON.text(chinese ? '开始' : 'Start').type('Button'));
              if (button !== null && await button.isEnabled()) { await button.click(); launched = true; }
            } catch (error) {
              const message = (error as Error).message;
              if (message.indexOf('NoCandidates') < 0) throw new Error(message);
            }
            if (!launched) await wait(100);
          }
          expect(launched).assertTrue();
        }
        expect(await driver.waitForComponent(ON.text('II'), 5000) !== null).assertTrue();
        report.epochStartMs = Date.now();
        report.uptimeStartMs = now();
        const start = report.uptimeStartMs;
        const capture = (): void => {
          const sample = new CounterSample();
          sample.beginMs = now() - start;
          sample.runtime = nativePlay.playRuntimeStatus();
          sample.renderer = nativePlay.renderStatus();
          progress.sample(sample.runtime.sourceFrames, sample.runtime.sourceFps,
            sample.runtime.running && !sample.runtime.paused);
          sample.playedMs = progress.playedMs;
          sample.endMs = now() - start;
          report.counters.push(sample);
        };
        capture();
        observer = setInterval(capture, 20);
        let nextMemory = 0;
        let nextInput = 5000;
        while (progress.playedMs < 65000 && now() - start < 150000) {
          if (now() - start >= nextMemory) {
            report.memory.push(memorySample(db, report.contentKey, start));
            nextMemory += 1000;
          }
          if (now() - start >= nextInput) {
            report.inputs.push(await inputSample(driver, win, start));
            nextInput += 5000;
          }
          await wait(20);
        }
        clearInterval(observer); observer = -1;
        capture();
        report.uptimeEndMs = now();
        report.emulatedMs = progress.playedMs;
        report.memory.push(memorySample(db, report.contentKey, start));
        report.afterHead = nativePlay.historyHead(db, report.contentKey);
        report.afterRows = nativePlay.historyList(db, report.contentKey);
        report.newAutoRows = report.afterRows.filter((row) => row.kind === 0 &&
          !report.beforeRows.some((old) => old.id === row.id));
        expect(report.emulatedMs >= 65000).assertTrue();
        expect(report.newAutoRows.length > 0).assertTrue();
        expect(report.afterHead !== report.beforeHead).assertTrue();
        const first = report.counters[0];
        const last = report.counters[report.counters.length - 1];
        expect(last.runtime!.audioConsumedSamples > first.runtime!.audioConsumedSamples).assertTrue();
        expect(last.renderer!.presentedFrames > first.renderer!.presentedFrames).assertTrue();
        expect(report.inputs.length > 0).assertTrue();
        expect(report.inputs.every((input) => input.firstAppliedMs >= 0 && input.releasedObservedMs >= 0 &&
          input.error.length === 0)).assertTrue();
        report.complete = true;
      } catch (error) { report.failure = `${error}`; throw new Error(report.failure); }
      finally {
        if (observer !== -1) clearInterval(observer);
        report.emulatedMs = progress.playedMs;
        if (report.uptimeEndMs === 0) report.uptimeEndMs = now();
        try {
          // A debug Want replaces WindowStage content for the Flutter route.
          // Its previous UIContext router is invalid after that replacement.
          const current = (await delegator.getCurrentTopAbility()).context;
          const currentNav = (await window.getLastWindow(current)).getUIContext().getRouter();
          await currentNav.replaceUrl({ url: 'pages/GameCenter' }); await wait(300);
        } catch (error) {
          report.complete = false;
          report.failure += ` cleanup: ${error}`;
          throw new Error(report.failure);
        }
        finally {
          nativePlay.settingsApply(original);
          if (hadInterval) options.putSync('intervalMs', oldInterval); else options.deleteSync('intervalMs');
          await options.flush();
          const path = `${context.filesDir}/g1-${route}-save-performance.json`;
          const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
          try { fileIo.writeSync(file.fd, JSON.stringify(report)); fileIo.fsyncSync(file.fd); }
          finally { fileIo.closeSync(file); }
          console.info(`FlyNES native performance report=${path} complete=${report.complete} emulatedMs=${report.emulatedMs}`);
        }
      }
    });
  });
}
