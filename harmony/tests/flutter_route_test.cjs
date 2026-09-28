const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const ts = require(process.env.FLYNES_TYPESCRIPT || 'D:/soft/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
function load(file, imports = {}) {
  const context = { exports: {}, console, require: name => imports[name] || {} };
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.resolve(__dirname, file), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  return context.exports;
}

test('native route completes only after leaving and returning; cancellation rejects late completion', async () => {
  const { FoundationRouteOwner } = load('../entry/src/main/ets/flutter/FoundationRouteOwner.ts');
  const owner = new FoundationRouteOwner();
  const results = [];
  const first = owner.begin(value => results.push(value));
  assert.ok(first > 0);
  assert.equal(owner.begin(() => assert.fail('second route must not enter')), 0);
  owner.shown();
  assert.equal(results.length, 0, 'initial page show is not a native return');
  owner.hidden();
  owner.shown();
  assert.equal(results[0].status, 'returned');
  const cancelled = owner.begin(value => results.push(value));
  owner.hidden();
  owner.cancel();
  assert.equal(results[1].status, 'cancelled');
  const current = owner.begin(value => results.push(value));
  owner.failed(cancelled);
  assert.equal(results.length, 2, 'old push rejection must not consume current request');
  owner.hidden(); owner.shown();
  assert.equal(results[2].status, 'returned');
  owner.failed(current);
  assert.equal(results.length, 3, 'duplicate completion must be ignored');
});

test('resume capability reads real head bytes or legacy without opening or mutating the emulator', () => {
  let head = 0;
  let reads = 0;
  const api = { historyHead: () => head, historyRead: () => { reads++; return new ArrayBuffer(8); } };
  const { SaveHistoryService } = load('../entry/src/main/ets/service/SaveHistoryService.ets', { 'libentry.so': { default: api } });
  const service = new SaveHistoryService('db', 'key');
  assert.equal(service.hasResume(() => undefined), false);
  assert.equal(service.hasResume(() => new ArrayBuffer(8)), true);
  assert.equal(reads, 0);
  head = 4;
  assert.equal(service.hasResume(() => assert.fail('head takes precedence over legacy')), true);
  assert.equal(reads, 1);
  api.historyRead = () => { throw new Error('corrupt history'); };
  assert.throws(() => service.hasResume(), /corrupt history/);
});

test('cover path reuses only an existing native cover in the app store', () => {
  let exists = false;
  const api = { fileIo: { accessSync: () => exists } };
  const { CoverStore } = load('../entry/src/main/ets/service/CoverStore.ets', { '@kit.CoreFileKit': api });
  const store = new CoverStore('/files');
  assert.equal(store.localPath('fixture'), '');
  exists = true;
  assert.match(store.localPath('fixture'), /^\/files\/covers\/v1\/[a-f0-9]+\.png$/);
});

test('bridge resolves capability and keeps launch pending until native page returns', async () => {
  const row = { canonicalId: 'fixture', titleEn: 'Fixture', titleZhHans: '', builtin: true, sourceUuidHex: '', sourceRelativePath: '', packageFormat: 0, originalFilename: 'fixture.nes' };
  const pushed = [];
  const keys = [];
  const owner = load('../entry/src/main/ets/flutter/FoundationRouteOwner.ts');
  const imports = {
    '@kit.ArkUI': { router: { pushUrl: async route => { pushed.push(route); } } },
    '@kit.LocalizationKit': { i18n: { System: { getSystemLanguage: () => 'en' } } },
    'libentry.so': { default: { appOpen() {}, catalogSnapshot: () => [row], historyContentKey: () => 'actual-content-key', nearbyMvpSnapshot: () => ({ state: 0 }) } },
    '../service/CatalogProductService': { CatalogProductService: class { loadRowsFromSnapshot(games, rows) { return rows; } }, localizedGameTitle: () => 'Fixture' },
    '../service/PlayService': { builtinGamesSync: () => ({}), takeRomOpenError: () => '', PlayService: class { async readRom() { return new Uint8Array(8); } }, RomLaunchLocator: class {} },
    '../service/SaveHistoryService': { SaveHistoryService: class { constructor(path, key) { keys.push([path,key]); } hasResume() { return true; } } },
    '../service/CheckpointStore': { CheckpointStore: class { read() { return undefined; } } },
    '../service/CoverStore': { CoverStore: class { localPath() { return '/files/covers/fixture.png'; } } },
    './FoundationProjection': load('../entry/src/main/ets/flutter/FoundationProjection.ts'), './FoundationRouteOwner': owner
  };
  const { FoundationChannelHandler } = load('../entry/src/main/ets/flutter/FoundationChannelHandler.ets', imports);
  const handler = new FoundationChannelHandler({ filesDir: '/files', cacheDir: '/cache' });
  const responses = [];
  const result = { success: value => responses.push(value), error: (...args) => assert.fail(args.join(':')), notImplemented: () => assert.fail('implemented method required') };
  const call = method => ({ method, argument: () => 'fixture' });
  handler.onMethodCall(call('resumeCapability'), result);
  await new Promise(setImmediate);
  assert.equal(responses[0].state, 'available');
  assert.deepEqual(keys[0], ['/files/save-history.db', 'actual-content-key']);
  handler.onMethodCall(call('launch'), result);
  await new Promise(setImmediate);
  assert.equal(pushed[0].url, 'pages/RunGame');
  assert.equal(pushed[0].params.foundationReturn, true);
  assert.equal(responses.length, 1);
  handler.onPageHide(); handler.onPageShow();
  assert.equal(responses[1].status, 'returned');
  handler.onMethodCall(call('catalogSnapshot'), result);
  assert.equal(responses[2].games[0].coverPath, '/files/covers/fixture.png');
  handler.onMethodCall({ method: 'openNative', argument: () => 'nearby' }, result);
  await new Promise(setImmediate);
  assert.equal(pushed[1].url, 'pages/NearbyFriends', 'idle native nearby opens its existing entry page');
});
