import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import UIAbility from '@ohos.app.ability.UIAbility';
import { preferences } from '@kit.ArkData';
import { FlutterEngineCache } from '@ohos/flutter_ohos';
import { fileIo } from '@kit.CoreFileKit';
import { i18n } from '@kit.LocalizationKit';
import { Driver, MatchPattern, ON } from '@ohos.UiTest';
import hidebug from '@ohos.hidebug';
import process from '@ohos.process';
import systemDateTime from '@ohos.systemDateTime';
import socket from '@ohos.net.socket';
import nativeProduct from 'libentry.so';
import { builtinGamesSync } from '../../../main/ets/service/PlayService';
import { localizedGameTitle } from '../../../main/ets/service/CatalogProductService';
import { performanceBuildMode } from './G1PerformanceObservations';
import { DartHeapAck, DartAckFrame, dartHeapWaitEnabled, gcCountEvidence, gcCountFromStat, gcStatsForJson, measuredPositive, memoryRoundTripsEnabled,
  validateDartHeapAck } from './G1MemoryObservations';

function now(): number { return systemDateTime.getUptime(systemDateTime.TimeType.STARTUP, false); }

class MemoryPreferences {
  store: preferences.Preferences | undefined = undefined;
  hadCategory: boolean = false;
  hadFilter: boolean = false;
  category: preferences.ValueType = 'all';
  filter: preferences.ValueType = false;
}

class MemoryPoint {
  round: number = 0;
  phase: string = '';
  beginUptimeMs: number = 0;
  endUptimeMs: number = 0;
  pid: number = process.pid;
  tid: number = process.tid;
  pssKb: number = -1;
  rssKb: number = -1;
  privateDirtyKb: number = -1;
  arkHeapUsedKb: number = -1;
  arkHeapCapacityKb: number = -1;
  arkArraySizeKb: number = -1;
  nativeAllocatorRawBytes: number = -1;
  nativeAllocatorBytes: number = -1;
  arkGcCount: number = -1;
  arkGcStats: Record<string, string> = {};
  errors: string[] = [];
}

class RoundTrip {
  round: number = 0;
  sourceFramesBefore: number = 0;
  sourceFramesAfter: number = 0;
  runtimePausedBeforeReturn: boolean = false;
  audioStoppedBeforeReturn: boolean = false;
  coreClosedAfterReturn: boolean = false;
  rendererStoppedAfterReturn: boolean = false;
  rendererPresentedBeforeSettle: number = -1;
  rendererPresentedAfterSettle: number = -1;
  memory: MemoryPoint | undefined = undefined;
}

class ArkGcCheckpoint {
  round: number = 0;
  request: string = 'hidebug.dumpJsRawHeapData(true)';
  externalReadyPath: string = '';
  before: MemoryPoint | undefined = undefined;
  after: MemoryPoint | undefined = undefined;
  requestBeginUptimeMs: number = 0;
  requestEndUptimeMs: number = 0;
  rawHeapPath: string = '';
  rawHeapBytes: number = -1;
  commandExitCode: number = -1;
  commandOutput: string = '';
  requestError: string = '';
  arkGcEvidence: string = 'unavailable';
}

class DartHeapReady {
  schemaVersion: number = 1;
  state: string = 'waiting-for-dart';
  runToken: string = '';
  round: number = 0;
  pid: number = process.pid;
  readyEpochMs: number = 0;
  expiresEpochMs: number = 0;
  ackTransport: string = 'loopback-tcp-newline-json';
  ackPort: number = 0;
}

class DartHeapHandshake {
  ready: DartHeapReady = new DartHeapReady();
  readyPath: string = '';
  ackPath: string = '';
  acknowledged: boolean = false;
  rejectedAckReads: number = 0;
  timedOut: boolean = false;
  ack: DartHeapAck | undefined = undefined;
  afterDart: MemoryPoint | undefined = undefined;
  transportErrors: string[] = [];
}

class MemoryReport {
  schemaVersion: number = 1;
  route: string = 'flutter';
  pid: number = process.pid;
  tid: number = process.tid;
  debug: boolean = false;
  buildMode: string = '';
  canonicalId: string = '';
  settingsJson: string = '';
  epochStartMs: number = Date.now();
  startUptimeMs: number = now();
  endUptimeMs: number = 0;
  returnSettleMs: number = 500;
  requestedRounds: number = 20;
  arkPostGcComparisonRounds: number[] = [5, 20];
  initial: MemoryPoint | undefined = undefined;
  rounds: RoundTrip[] = [];
  arkGcCheckpoints: ArkGcCheckpoint[] = [];
  roundTripsComplete: boolean = false;
  memoryCaptureComplete: boolean = false;
  arkGcObservedAtBothCheckpoints: boolean = false;
  dartVmServiceMeasured: boolean = false;
  waitForDartHeap: boolean = false;
  externalArkGc: boolean = false;
  dartHandshakes: DartHeapHandshake[] = [];
  nativeAllAllocationsMeasured: boolean = false;
  failure: string = '';
  outputPath: string = '';
  limitations: string[] = [
    'Ark values describe only the calling Ark VM/thread, not Dart, GPU, or all native allocations.',
    'Dart GC/heap values live in external VM Service evidence; matched acknowledgements are references only.',
    'A raw heap request is not GC evidence unless the calling Ark VM GC count actually increases.',
    'PSS/RSS include allocators, mapped resources, graphics and caches; they are not equivalent to live heap.',
    'Zero/invalid native allocator and heap metrics are marked unavailable (-1), never zero retained memory.',
    'Round 5 and 20 dumps are resource-intensive. This run must not measure frame time or input latency.',
    'Report objects and UiTest have observer overhead; twenty rounds and closed cores alone do not prove no leak.',
    'Licensed ROM progress may be saved through the real product return path; existing saves are not reset.',
    'Raw heap files remain in the application sandbox for explicit evidence collection; quota errors are recorded.'
  ];
}

function writeNewJson(path: string, text: string): void {
  if (fileIo.accessSync(path)) throw new Error('Refuse to overwrite memory evidence');
  const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
  try { fileIo.writeSync(file.fd, text); fileIo.fsyncSync(file.fd); }
  finally { fileIo.closeSync(file); }
}

async function waitForDartHeap(report: MemoryReport, round: number, context: common.UIAbilityContext,
  driver: Driver): Promise<void> {
  const gate = new DartHeapHandshake();
  gate.ready.runToken = `${report.epochStartMs}-${report.pid}`;
  gate.ready.round = round;
  gate.ready.readyEpochMs = Date.now();
  gate.ready.expiresEpochMs = gate.ready.readyEpochMs + 180000;
  const base = `${context.filesDir}/g1-dart-heap-${gate.ready.runToken}-${round}`;
  gate.readyPath = `${base}.ready.json`;
  gate.ackPath = `${base}.ack.json`;
  report.dartHandshakes.push(gate);
  if (fileIo.accessSync(gate.ackPath)) throw new Error('Stale Dart heap acknowledgement exists');
  const deadline = now() + 180000;
  const server = socket.constructTCPSocketServerInstance();
  const connections: socket.TCPSocketConnection[] = [];
  server.on('error', (error) => { gate.transportErrors.push(`server: ${error.code}`); });
  server.on('connect', (connection) => {
    if (connections.length >= 4 || gate.acknowledged || now() >= deadline) {
      connection.close().catch(() => {}); return;
    }
    connections.push(connection);
    const frame = new DartAckFrame();
    connection.on('error', (error) => { gate.transportErrors.push(`connection: ${error.code}`); });
    connection.on('message', (message: socket.SocketMessageInfo) => {
      try {
        if (gate.acknowledged || now() >= deadline) throw new Error('Expired ACK');
        const bytes = new Uint8Array(message.message);
        if (bytes.length > 16384) throw new Error('ACK too large');
        let chunk = '';
        for (let index = 0; index < bytes.length; index++) {
          if (bytes[index] > 127) throw new Error('ACK must be ASCII JSON');
          chunk += String.fromCharCode(bytes[index]);
        }
        const text = frame.push(chunk);
        if (text.length === 0) return;
        const ack = validateDartHeapAck(text, gate.ready.runToken, round, report.pid);
        writeNewJson(gate.ackPath, text);
        gate.ack = ack;
        gate.acknowledged = true;
      } catch (_) { gate.rejectedAckReads++; connection.close().catch(() => {}); }
    });
  });
  try {
    await server.listen({ address: '127.0.0.1', port: 0, family: 1 });
    gate.ready.ackPort = (await server.getLocalAddress()).port ?? 0;
    if (gate.ready.ackPort <= 0) throw new Error('ACK listener has no assigned port');
    writeNewJson(gate.readyPath, JSON.stringify(gate.ready));
    console.info(`FlyNES Dart heap checkpoint ready=${gate.readyPath} ack=${gate.ackPath}`);
    while (!gate.acknowledged && now() < deadline) await driver.delayMs(200);
  } finally {
    gate.timedOut = !gate.acknowledged && now() >= deadline;
    for (const connection of connections) {
      try { await connection.close(); } catch (_) { /* May already be closed by the peer. */ }
    }
    try { await server.close(); }
    catch (error) { gate.transportErrors.push(`server-close: ${error}`); }
  }
  if (!gate.acknowledged) {
    gate.timedOut = true;
    throw new Error('Dart heap checkpoint timed out; no same-point sample may be claimed');
  }
  expect(await driver.waitForComponent(ON.id('flutter_foundation_host'), 1000) !== null).assertTrue();
  let closed = false;
  try { nativeProduct.playRuntimeStatus(); } catch (_) { closed = true; }
  expect(closed).assertTrue();
  gate.afterDart = await memoryPoint(round, 'after-dart-handshake');
}

async function memoryPoint(round: number, phase: string): Promise<MemoryPoint> {
  const point = new MemoryPoint();
  point.round = round;
  point.phase = phase;
  point.beginUptimeMs = now();
  try {
    const memory = await hidebug.getAppNativeMemInfoAsync();
    point.pssKb = measuredPositive(Number(memory.pss));
    point.rssKb = measuredPositive(Number(memory.rss));
    point.privateDirtyKb = measuredPositive(Number(memory.privateDirty));
  } catch (error) { point.errors.push(`process-memory: ${error}`); }
  try {
    const memory = hidebug.getAppVMMemoryInfo();
    point.arkHeapUsedKb = measuredPositive(Number(memory.heapUsed));
    point.arkHeapCapacityKb = measuredPositive(Number(memory.totalHeap));
    point.arkArraySizeKb = Number(memory.allArraySize);
  } catch (error) { point.errors.push(`ark-memory: ${error}`); }
  try {
    point.arkGcStats = gcStatsForJson(hidebug.getVMRuntimeStats());
    point.arkGcCount = gcCountFromStat(point.arkGcStats['ark.gc.gc-count']);
  } catch (error) { point.errors.push(`ark-gc: ${error}`); }
  try {
    point.nativeAllocatorRawBytes = Number(hidebug.getNativeHeapAllocatedSize());
    point.nativeAllocatorBytes = measuredPositive(point.nativeAllocatorRawBytes);
  } catch (error) { point.errors.push(`native-allocator: ${error}`); }
  point.endUptimeMs = now();
  return point;
}

async function arkGcCheckpoint(round: number, driver: Driver, report: MemoryReport,
  context: common.UIAbilityContext): Promise<ArkGcCheckpoint> {
  const point = new ArkGcCheckpoint();
  point.round = round;
  point.before = await memoryPoint(round, 'before-ark-gc-request');
  point.requestBeginUptimeMs = now();
  try {
    if (report.externalArkGc) {
      // Release test-process shell delegation returns 11 on this API20 HVD;
      // the host's public hdc shell can issue the same targeted command.
      point.request = `external hidumper --mem-jsheap ${report.pid} -T ${report.tid} --gc`;
      point.externalReadyPath = `${context.filesDir}/g2-ark-gc-${report.epochStartMs}-${report.pid}-${round}.ready.json`;
      writeNewJson(point.externalReadyPath, JSON.stringify({ pid: report.pid, tid: report.tid,
        round: round, epochStartMs: report.epochStartMs, beforeCount: point.before.arkGcCount }));
      console.info(`FlyNES external Ark GC ready=${point.externalReadyPath}`);
      const deadline = now() + 30000;
      while (now() < deadline) {
        const stats = gcStatsForJson(hidebug.getVMRuntimeStats());
        if (gcCountFromStat(stats['ark.gc.gc-count']) > point.before.arkGcCount) break;
        await driver.delayMs(200);
      }
    } else if (report.buildMode === 'release') {
      point.request = `hidumper --mem-jsheap ${process.pid} -T ${process.tid} --gc`;
      const result = await abilityDelegatorRegistry.getAbilityDelegator().executeShellCommand(point.request, 30);
      point.commandExitCode = result.exitCode;
      point.commandOutput = result.stdResult;
      if (result.exitCode !== 0) throw new Error(`GC command exit=${result.exitCode}`);
    } else {
      point.rawHeapPath = await hidebug.dumpJsRawHeapData(true);
      point.rawHeapBytes = Number(fileIo.statSync(point.rawHeapPath).size);
    }
  } catch (error) { point.requestError = `${error}`; }
  point.requestEndUptimeMs = now();
  await driver.delayMs(500);
  point.after = await memoryPoint(round, 'after-ark-gc-request');
  point.arkGcEvidence = gcCountEvidence(point.before.arkGcCount, point.after.arkGcCount);
  if (report.externalArkGc && point.arkGcEvidence !== 'observed')
    point.requestError = 'External targeted Ark GC was not observed before the deadline';
  return point;
}

async function launch(driver: Driver): Promise<void> {
  const chinese = i18n.System.getSystemLanguage().startsWith('zh');
  for (let attempt = 0; attempt < 100; attempt++) {
    try {
      // The outgoing native pause drawer can remain in UiTest's tree while
      // the cached Flutter hall attaches. Its Continue must never count as
      // the next product launch.
      if (await driver.findComponent(ON.id('product_presentation_gate')) !== null ||
          await driver.findComponent(ON.id('history-manual-save')) !== null) {
        await driver.delayMs(100); continue;
      }
      const resume = await driver.findComponent(ON.text(chinese ? '继续' : 'Continue').type('Button'));
      const button = resume ?? await driver.findComponent(ON.text(chinese ? '开始' : 'Start').type('Button'));
      if (button !== null && await button.isEnabled()) { await button.click(); return; }
    } catch (error) {
      const message = (error as Error).message;
      if (message.indexOf('NoCandidates') < 0) throw new Error(message);
    }
    await driver.delayMs(100);
  }
  throw new Error('Shared library launch button unavailable');
}

export default function g1MemoryRoundTripsTest() {
  const args = abilityDelegatorRegistry.getArguments().parameters;
  if (!memoryRoundTripsEnabled(args['-s memoryRoundTripsOnly'], args['-s g1CandidateApproved'])) return;
  const waitForDart = dartHeapWaitEnabled(args['-s g1WaitForDartHeap']);
  const externalArkGc = args['-s g2ExternalArkGc'] === 'true';
  describe('G1MemoryRoundTrips', () => {
    it('records_ark_and_process_memory_across_twenty_real_native_returns', 0, async () => {
      const report = new MemoryReport();
      report.waitForDartHeap = waitForDart;
      report.externalArkGc = externalArkGc;
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      const saved = new MemoryPreferences();
      const monitor: abilityDelegatorRegistry.AbilityMonitor = {
        abilityName: 'EntryAbility',
        onAbilityCreate: (ability: UIAbility): void => {
          const store = preferences.getPreferencesSync(ability.context, { name: 'game_center_ui' });
          saved.store = store;
          saved.hadCategory = store.hasSync('category'); saved.category = store.getSync('category', 'all');
          saved.hadFilter = store.hasSync('multiplayerOnly'); saved.filter = store.getSync('multiplayerOnly', false);
          store.putSync('category', 'all'); store.putSync('multiplayerOnly', false); store.flushSync();
        }
      };
      let monitoring = false;
      report.outputPath = `${delegator.getAppContext().filesDir}/g1-memory-roundtrips-${report.epochStartMs}-${report.pid}.json`;
      try {
        expect(FlutterEngineCache.getInstance().contains('flynes-product')).assertFalse();
        await delegator.addAbilityMonitor(monitor);
        monitoring = true;
        await delegator.startAbility({ bundleName: 'com.flynes.emu', abilityName: 'EntryAbility' });
        const driver = Driver.create();
        // startAbility returns before this cold ability becomes the current top.
        // Wait for its actual host before obtaining the module-scoped context.
        expect(await driver.waitForComponent(ON.id('flutter_foundation_host'), 15000) !== null).assertTrue();
        const context = (await delegator.getCurrentTopAbility()).context as common.UIAbilityContext;
        report.debug = context.applicationInfo.debug;
        report.buildMode = performanceBuildMode(args['-s g1BuildMode'], report.debug);
        if (report.externalArkGc && report.buildMode !== 'release') throw new Error('External Ark GC is Release-only');
        report.outputPath = `${context.filesDir}/g1-memory-roundtrips-${report.epochStartMs}-${report.pid}.json`;
        // Do not silently sample another Ark VM/worker as the ability's main thread.
        expect(report.tid === report.pid).assertTrue();
        if (report.buildMode === 'release' && waitForDart) throw new Error('Release has no Dart VM service');
        const engine = FlutterEngineCache.getInstance().get('flynes-product');
        expect(engine !== undefined && engine !== null).assertTrue();
        expect(await driver.waitForComponent(ON.id('flutter_foundation_host'), 15000) !== null).assertTrue();
        const game = builtinGamesSync(context).all()[0];
        report.canonicalId = game.canonicalId;
        const title = localizedGameTitle(game.titleEn, game.titleZhHans, game.canonicalId,
          'system', i18n.System.getSystemLanguage());
        await (await driver.waitForComponent(ON.type('Button').text(title, MatchPattern.STARTS_WITH), 10000)).click();
        // A visible real card proves the asynchronous native catalog owner has
        // opened; the host surface alone does not establish product readiness.
        report.settingsJson = JSON.stringify(nativeProduct.settingsGet());
        await driver.delayMs(report.returnSettleMs);
        report.initial = await memoryPoint(0, 'initial-no-gc');
        for (let round = 1; round <= report.requestedRounds; round++) {
          const entry = new RoundTrip();
          entry.round = round;
          report.rounds.push(entry);
          await launch(driver);
          await driver.waitForComponent(ON.text('II'), 10000);
          entry.sourceFramesBefore = nativeProduct.playRuntimeStatus().sourceFrames;
          await driver.delayMs(250);
          entry.sourceFramesAfter = nativeProduct.playRuntimeStatus().sourceFrames;
          expect(entry.sourceFramesAfter > entry.sourceFramesBefore).assertTrue();
          await (await driver.waitForComponent(ON.text('II'), 5000)).click();
          for (let wait = 0; wait < 40; wait++) {
            const status = nativeProduct.playRuntimeStatus();
            entry.runtimePausedBeforeReturn = status.paused;
            entry.audioStoppedBeforeReturn = !status.audioStarted;
            if (entry.runtimePausedBeforeReturn && entry.audioStoppedBeforeReturn) break;
            await driver.delayMs(50);
          }
          expect(entry.runtimePausedBeforeReturn).assertTrue();
          expect(entry.audioStoppedBeforeReturn).assertTrue();
          const label = context.resourceManager.getStringByNameSync('pause_game_center');
          await driver.waitForComponent(ON.id('history-manual-save'), 5000);
          await driver.delayMs(300); // Native drawer bounds settle after its 220ms entrance.
          const drawer = await driver.waitForComponent(ON.type('Scroll'), 5000);
          const back = await drawer.scrollSearch(ON.text(label), true, 200);
          expect(back !== null).assertTrue();
          await back.click();
          expect(await driver.waitForComponent(ON.id('flutter_foundation_host'), 10000) !== null).assertTrue();
          await driver.delayMs(report.returnSettleMs);
          try { nativeProduct.playRuntimeStatus(); } catch (_) { entry.coreClosedAfterReturn = true; }
          entry.rendererPresentedBeforeSettle = nativeProduct.renderStatus().presentedFrames;
          await driver.delayMs(100);
          entry.rendererPresentedAfterSettle = nativeProduct.renderStatus().presentedFrames;
          entry.rendererStoppedAfterReturn = entry.rendererPresentedAfterSettle === entry.rendererPresentedBeforeSettle;
          expect(entry.coreClosedAfterReturn).assertTrue();
          expect(entry.rendererStoppedAfterReturn).assertTrue();
          expect(FlutterEngineCache.getInstance().get('flynes-product') === engine).assertTrue();
          expect(process.pid === report.pid && process.tid === report.tid).assertTrue();
          entry.memory = await memoryPoint(round, 'returned-no-gc');
          if (round === 5 || round === 20) {
            report.arkGcCheckpoints.push(await arkGcCheckpoint(round, driver, report, context));
            if (report.waitForDartHeap) await waitForDartHeap(report, round, context, driver);
          }
          console.info(`FlyNES memory roundtrip=${round} coreClosed=true runtimePaused=true arkHeapKb=${entry.memory.arkHeapUsedKb} pssKb=${entry.memory.pssKb}`);
        }
        report.roundTripsComplete = true;
        report.dartVmServiceMeasured = report.waitForDartHeap && report.dartHandshakes.length === 2 &&
          report.dartHandshakes.every((gate) => gate.acknowledged);
        report.memoryCaptureComplete = report.rounds.every((entry) => entry.memory !== undefined &&
          entry.memory.pssKb > 0 && entry.memory.arkHeapUsedKb > 0) &&
          report.arkGcCheckpoints.length === 2 && report.arkGcCheckpoints.every((point) =>
            point.before !== undefined && point.after !== undefined && point.after.arkHeapUsedKb > 0 &&
            point.after.pssKb > 0 && point.requestError.length === 0 &&
            (report.externalArkGc ? point.arkGcEvidence === 'observed' :
              report.buildMode === 'release' ? point.commandExitCode === 0 : point.rawHeapBytes > 0));
        report.arkGcObservedAtBothCheckpoints = report.arkGcCheckpoints.length === 2 &&
          report.arkGcCheckpoints.every((point) => point.arkGcEvidence === 'observed');
        expect(report.memoryCaptureComplete).assertTrue();
        expect(report.arkGcObservedAtBothCheckpoints).assertTrue();
      } catch (error) { report.failure = `${error}`; throw new Error(report.failure); }
      finally {
        try {
          if (saved.store !== undefined) {
            if (saved.hadCategory) saved.store.putSync('category', saved.category); else saved.store.deleteSync('category');
            if (saved.hadFilter) saved.store.putSync('multiplayerOnly', saved.filter); else saved.store.deleteSync('multiplayerOnly');
            saved.store.flushSync();
          }
        } catch (error) { report.failure += ` preferences cleanup: ${error}`; }
        try { if (monitoring) await delegator.removeAbilityMonitor(monitor); }
        catch (error) { report.failure += ` monitor cleanup: ${error}`; }
        report.endUptimeMs = now();
        writeNewJson(report.outputPath, JSON.stringify(report));
        console.info(`FlyNES memory report=${report.outputPath} roundsComplete=${report.roundTripsComplete} memoryComplete=${report.memoryCaptureComplete} arkGcObserved=${report.arkGcObservedAtBothCheckpoints} dartEvidenceAcknowledged=${report.dartVmServiceMeasured}`);
        if (report.failure.length > 0) throw new Error(report.failure);
      }
    });
  });
}
