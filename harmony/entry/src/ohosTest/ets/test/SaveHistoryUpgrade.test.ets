import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import zlib from '@ohos.zlib';
import nativePlay, { HistoryInput } from 'libentry.so';
import { BuiltinGames } from '../../../main/ets/service/BuiltinGames';
import { CheckpointStore } from '../../../main/ets/service/CheckpointStore';
import { SaveHistoryService } from '../../../main/ets/service/SaveHistoryService';
import { PlayService, RomLaunchLocator } from '../../../main/ets/service/PlayService';

interface ProductEvidence {
  settings: string;
  layout: string;
  sourceMap: string;
  canonicalId: string;
  sourceUuidHex: string;
  sourceRelativePath: string;
  packageFormat: number;
  contentKey: string;
  lastPlayedSequence: number;
}

async function productStorage(context: common.UIAbilityContext, phase: string, fixture: string): Promise<void> {
  const evidencePath = `${context.filesDir}/g1-product-${fixture}.json`;
  nativePlay.appOpen(context.filesDir, context.cacheDir);
  const interval = preferences.getPreferencesSync(context, { name: 'save_history' });
  const sources = preferences.getPreferencesSync(context, { name: 'flynes_source_uuids' });
  if (phase === 'seed') {
    expect(fileIo.accessSync(evidencePath)).assertFalse();
    // This row must already exist through the real Sources FILE picker flow.
    // The fixture never inserts a source, grants a URI or copies a managed ROM.
    const row = nativePlay.catalogSnapshot().find((candidate) => candidate.sourceRelativePath === 'upgrade212.nes');
    expect(row !== undefined).assertTrue();
    if (row === undefined) throw new Error('Import upgrade212.nes with the system FILE picker first');
    nativePlay.catalogFavoriteSet(row.canonicalId, true);
    nativePlay.catalogMarkPlayed(row.canonicalId);
    const settings = nativePlay.settingsGet();
    settings.aspectMode = 2;
    settings.audioEnabled = 0;
    settings.hapticLevel = 1;
    settings.localeTag = 'en';
    nativePlay.settingsApply(settings);
    const recommended = nativePlay.controlLayoutRecommended().split('|');
    recommended[1] = '0.7300';
    nativePlay.controlLayoutApply(recommended.join('|'));
    interval.putSync('intervalMs', 30000);
    await interval.flush();
    const locator = new RomLaunchLocator();
    locator.canonicalId = row.canonicalId; locator.sourceUuidHex = row.sourceUuidHex;
    locator.sourceRelativePath = row.sourceRelativePath; locator.packageFormat = row.packageFormat;
    const play = new PlayService();
    const rom = await play.readRom(context, locator);
    const evidence: ProductEvidence = { settings: JSON.stringify(nativePlay.settingsGet()),
      layout: nativePlay.controlLayoutGet(), sourceMap: sources.getSync('source_map_v1', '') as string,
      canonicalId: row.canonicalId, sourceUuidHex: row.sourceUuidHex,
      sourceRelativePath: row.sourceRelativePath, packageFormat: row.packageFormat,
      contentKey: nativePlay.historyContentKey(rom),
      lastPlayedSequence: nativePlay.catalogUserStateGet(row.canonicalId).lastPlayedSequence };
    expect(evidence.sourceMap.length > 0).assertTrue();
    const file = fileIo.openSync(evidencePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
    try { fileIo.writeSync(file.fd, JSON.stringify(evidence)); fileIo.fsyncSync(file.fd); }
    finally { fileIo.closeSync(file.fd); }
  }
  const evidence = JSON.parse(fileIo.readTextSync(evidencePath)) as ProductEvidence;
  expect(JSON.stringify(nativePlay.settingsGet())).assertEqual(evidence.settings);
  expect(nativePlay.controlLayoutGet()).assertEqual(evidence.layout);
  expect(sources.getSync('source_map_v1', '') as string).assertEqual(evidence.sourceMap);
  expect(interval.getSync('intervalMs', 60000) as number).assertEqual(30000);
  expect(nativePlay.catalogUserStateGet(evidence.canonicalId).favorite).assertTrue();
  expect(nativePlay.catalogUserStateGet(evidence.canonicalId).lastPlayedSequence).assertEqual(evidence.lastPlayedSequence);
  const row = nativePlay.catalogSnapshot().find((candidate) => candidate.canonicalId === evidence.canonicalId &&
    candidate.sourceUuidHex === evidence.sourceUuidHex && candidate.sourceRelativePath === evidence.sourceRelativePath);
  expect(row !== undefined).assertTrue();
  const locator = new RomLaunchLocator();
  locator.canonicalId = evidence.canonicalId; locator.sourceUuidHex = evidence.sourceUuidHex;
  locator.sourceRelativePath = evidence.sourceRelativePath; locator.packageFormat = evidence.packageFormat;
  const play = new PlayService();
  expect(nativePlay.historyContentKey(await play.readRom(context, locator))).assertEqual(evidence.contentKey);
  try {
    await play.open(context, locator, false);
    expect(play.history?.intervalMs).assertEqual(30000);
    await new Promise<void>((resolve) => setTimeout(resolve, 150));
    expect(nativePlay.playRuntimeStatus().sourceFrames > 0).assertTrue();
  } finally { play.close(); }
  console.info(`FlyNES upgrade product ${phase}: interval=30000 favorite/settings/layout/source/ROM/open PASS`);
}

interface UpgradeEvidence {
  key: string;
  pendingKey: string;
  head: number;
  frame: number;
  backup: number;
  rows: string;
}

function sameBytes(first: ArrayBuffer, second: ArrayBuffer): boolean {
  const a = new Uint8Array(first);
  const b = new Uint8Array(second);
  if (a.length !== b.length) return false;
  for (let index = 0; index < a.length; index++) if (a[index] !== b[index]) return false;
  return true;
}

// A trailing test marker gives the licensed ROM its own real content identity.
// The emulator must accept it; no production game's existing saves are changed.
function isolatedRom(bytes: Uint8Array, marker: string): Uint8Array {
  const rom = new Uint8Array(bytes.length + marker.length);
  rom.set(bytes);
  for (let index = 0; index < marker.length; index++) rom[bytes.length + index] = marker.charCodeAt(index);
  return rom;
}

export default function saveHistoryUpgradeTest() {
  const parameters = abilityDelegatorRegistry.getArguments().parameters;
  const phase = parameters['-s saveHistoryUpgradePhase'];
  const fixture = parameters['-s saveHistoryUpgradeFixture'];
  describe('SaveHistoryUpgrade', () => {
    it(`preserves_real_storage_${phase}`, 0, async () => {
      if (phase === 'prepare') {
        const delegator = abilityDelegatorRegistry.getAbilityDelegator();
        await delegator.startAbility({ bundleName: 'com.flynes.emu', abilityName: 'EntryAbility' });
        await new Promise<void>((resolve) => setTimeout(resolve, 1500));
        const ability = await delegator.getCurrentTopAbility();
        const options = new picker.DocumentSaveOptions();
        const kind = parameters['-s sourceFixtureKind'];
        const g2 = kind === 'rom' || kind === 'zip';
        options.newFileNames = [g2 ? `g2-source-20260930.${kind === 'zip' ? 'zip' : 'nes'}` : 'upgrade212.nes'];
        const uris = await new picker.DocumentViewPicker(ability.context).save(options);
        expect(uris.length).assertEqual(1);
        const game = BuiltinGames.loadSync(ability.context).all()[0];
        const rom = isolatedRom(ability.context.resourceManager.getRawFileContentSync(game.assetPath()), 'upgrade212-import');
        let exported = rom.buffer as ArrayBuffer;
        if (kind === 'zip') {
          const directory = `${ability.context.cacheDir}/g2-export-${Date.now()}`;
          fileIo.mkdirSync(directory);
          const source = `${directory}/fixture.nes`;
          const input = fileIo.openSync(source, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
          try { fileIo.writeSync(input.fd, exported); } finally { fileIo.closeSync(input.fd); }
          const archive = `${directory}/fixture.zip`;
          await zlib.compressFile(source, archive, { level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION });
          const packed = fileIo.openSync(archive, fileIo.OpenMode.READ_ONLY);
          try { exported = new ArrayBuffer(Number(fileIo.statSync(packed.fd).size)); fileIo.readSync(packed.fd, exported); }
          finally { fileIo.closeSync(packed.fd); }
        }
        const file = fileIo.openSync(uris[0], fileIo.OpenMode.WRITE_ONLY);
        try { fileIo.writeSync(file.fd, exported); fileIo.fsyncSync(file.fd); }
        finally { fileIo.closeSync(file.fd); }
        console.info('FlyNES upgrade preparation: licensed ROM exported with system DocumentSavePicker');
        return;
      }
      expect(phase === 'seed' || phase === 'verify').assertTrue();
      expect(typeof fixture === 'string' && /^[a-z0-9-]{1,40}$/.test(fixture)).assertTrue();
      let context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().createModuleContext('entry');
      if (parameters['-s saveHistoryUpgradeProduct'] === 'true') {
        const delegator = abilityDelegatorRegistry.getAbilityDelegator();
        await delegator.startAbility({ bundleName: 'com.flynes.emu', abilityName: 'EntryAbility' });
        await new Promise<void>((resolve) => setTimeout(resolve, 1500));
        context = (await delegator.getCurrentTopAbility()).context;
      }
      const game = BuiltinGames.loadSync(context).all()[0];
      const bytes = context.resourceManager.getRawFileContentSync(game.assetPath());
      const rom = isolatedRom(bytes, `g1-upgrade-${fixture}`);
      const pendingRom = isolatedRom(bytes, `g1-pending-${fixture}`);
      const key = nativePlay.historyContentKey(rom);
      const pendingKey = nativePlay.historyContentKey(pendingRom);
      const path = `${context.filesDir}/save-history.db`;
      const canonical = `g1-upgrade-${fixture}`;
      const legacyOnly = `${canonical}-legacy`;
      const evidencePath = `${context.filesDir}/${canonical}.json`;
      const oldFiles = new CheckpointStore(context.filesDir);
      if (parameters['-s saveHistoryUpgradeProduct'] === 'true') {
        await productStorage(context as common.UIAbilityContext, phase as string, fixture as string);
      }
      if (phase === 'seed') {
        // Never overwrite another fixture, including a prior interrupted run.
        expect(fileIo.accessSync(evidencePath)).assertFalse();
        expect(nativePlay.historyHead(path, key)).assertEqual(0);
        expect(nativePlay.historyHead(path, pendingKey)).assertEqual(0);
        nativePlay.playOpen(rom); nativePlay.playSetPaused(true);
        try {
          const history = new SaveHistoryService(path, key);
          history.initialize(false);
          const initial = nativePlay.playSaveCheckpoint();
          oldFiles.write(canonical, initial);
          oldFiles.write(legacyOnly, initial);
          oldFiles.write(`${canonical}-expected`, initial);
          history.playedMs = 1234;
          const first = history.save(1, 'upgrade retained');
          oldFiles.write(`${canonical}-thumbnail`, nativePlay.historyRead(path, key, first, true));
          history.edit(first, 'upgrade retained', true, false);
          nativePlay.playSetPaused(false);
          await new Promise<void>((resolve) => setTimeout(resolve, 300));
          nativePlay.playSetPaused(true);
          expect(nativePlay.playStep().frameIndex > 0).assertTrue();
          history.playedMs = 5678;
          const latest = history.save(0, 'later automatic');
          history.restore(first);
          expect(nativePlay.historyHead(path, key)).assertEqual(first);
          expect(latest > first).assertTrue();
          // A bad old slot must not mask an already valid new head after install.
          oldFiles.write(canonical, new Uint8Array([1, 2, 3]).buffer as ArrayBuffer);
          const frame = nativePlay.playStep().frameIndex;
          nativePlay.playClose();
          nativePlay.playOpen(pendingRom); nativePlay.playSetPaused(true);
          const pendingHistory = new SaveHistoryService(path, pendingKey);
          pendingHistory.initialize(false);
          const target = pendingHistory.save(1, 'pending target');
          const input: HistoryInput = { playedMs: 9876, kind: 2, label: '', session: 'upgrade-pending',
            parent: target, state: nativePlay.playSaveCheckpoint(), thumbnail: new ArrayBuffer(0), makeHead: false };
          const operation = nativePlay.historyPrepare(path, pendingKey, target, input);
          const evidence: UpgradeEvidence = { key: key, pendingKey: pendingKey, head: first, frame: frame,
            backup: operation.backup, rows: JSON.stringify(nativePlay.historyList(path, key)) };
          const file = fileIo.openSync(evidencePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
          try { fileIo.writeSync(file.fd, JSON.stringify(evidence)); fileIo.fsyncSync(file.fd); }
          finally { fileIo.closeSync(file.fd); }
        } finally { nativePlay.playClose(); }
      } else {
        const evidence = JSON.parse(fileIo.readTextSync(evidencePath)) as UpgradeEvidence;
        expect(key).assertEqual(evidence.key);
        expect(pendingKey).assertEqual(evidence.pendingKey);
        expect(nativePlay.historyHead(path, key)).assertEqual(evidence.head);
        expect(JSON.stringify(nativePlay.historyList(path, key))).assertEqual(evidence.rows);
        const expected = oldFiles.read(`${canonical}-expected`)!;
        expect(sameBytes(oldFiles.read(legacyOnly)!, expected)).assertTrue();
        expect(sameBytes(oldFiles.read(canonical)!, new Uint8Array([1, 2, 3]).buffer as ArrayBuffer)).assertTrue();
        expect(sameBytes(nativePlay.historyRead(path, key, evidence.head, false), expected)).assertTrue();
        expect(sameBytes(nativePlay.historyRead(path, key, evidence.head, true),
          oldFiles.read(`${canonical}-thumbnail`)!)).assertTrue();
        nativePlay.playOpen(rom); nativePlay.playSetPaused(true);
        try {
          const reopened = new SaveHistoryService(path, key);
          reopened.initialize(true, () => { throw new Error('new head must bypass damaged old slot'); });
          expect(nativePlay.playStep().frameIndex).assertEqual(evidence.frame);
          expect(reopened.playedMs).assertEqual(1234);
          nativePlay.playClose();
          nativePlay.playOpen(pendingRom); nativePlay.playSetPaused(true);
          const pendingHistory = new SaveHistoryService(path, pendingKey);
          pendingHistory.initialize(true);
          expect(nativePlay.historyHead(path, pendingKey)).assertEqual(evidence.backup);
          expect(pendingHistory.playedMs).assertEqual(9876);
          expect(nativePlay.historyRecover(path, pendingKey)).assertEqual(0);
          // Import a preserved old slot only when this isolated new key has no head.
          nativePlay.playClose();
          const legacyRom = isolatedRom(bytes, `g1-legacy-${fixture}`);
          const legacyKey = nativePlay.historyContentKey(legacyRom);
          nativePlay.playOpen(legacyRom); nativePlay.playSetPaused(true);
          const legacyHistory = new SaveHistoryService(path, legacyKey);
          const existingLegacyHead = nativePlay.historyHead(path, legacyKey);
          let legacyReads = 0;
          legacyHistory.initialize(true, () => { legacyReads++; return oldFiles.read(legacyOnly); });
          expect(legacyReads).assertEqual(existingLegacyHead === 0 ? 1 : 0);
          expect(legacyHistory.list().some((row) => row.kind === 3 && row.isHead)).assertTrue();
          expect(sameBytes(oldFiles.read(legacyOnly)!, expected)).assertTrue();
        } finally { nativePlay.playClose(); }
      }
    });
  });
}
