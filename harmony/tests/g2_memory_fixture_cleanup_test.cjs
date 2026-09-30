const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const ts = require('D:/soft/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const directory = path.resolve(__dirname, '../entry/src/ohosTest/ets/test');

function load(name, imports = {}) {
  const context = { exports: {}, console, require: name => imports[name] || {} };
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(directory, name), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  return context.exports;
}

function fixture(failure) {
  const values = new Map([['category', 'favorites'], ['multiplayerOnly', true]]);
  const store = { hasSync: key => values.has(key), getSync: (key, fallback) => values.get(key) ?? fallback,
    putSync: (key, value) => values.set(key, value), deleteSync: key => values.delete(key), flushSync() {} };
  let monitor, body, removals = 0;
  const reports = [];
  const context = { filesDir: '/app/files', applicationInfo: { debug: true } };
  const delegator = {
    getAppContext: () => ({ filesDir: '/test/files' }),
    async addAbilityMonitor(value) { monitor = value; },
    async removeAbilityMonitor(value) { assert.equal(value, monitor); removals++; },
    async startAbility() { monitor.onAbilityCreate({ context }); if (failure === 'start') throw Error('start failed'); },
    async getCurrentTopAbility() { return { context }; }
  };
  const exports = load('G1MemoryRoundTrips.test.ets', {
    '@ohos/hypium': { describe: (_, fn) => fn(), it: (_, __, fn) => body = fn,
      expect: value => ({ assertTrue: () => assert.equal(value, true), assertFalse: () => assert.equal(value, false) }) },
    '@kit.TestKit': { abilityDelegatorRegistry: { getAbilityDelegator: () => delegator,
      getArguments: () => ({ parameters: { '-s memoryRoundTripsOnly': 'true', '-s g1CandidateApproved': 'true', '-s g1BuildMode': 'release' } }) } },
    '@kit.ArkData': { preferences: { getPreferencesSync: () => store } },
    '@kit.CoreFileKit': { fileIo: { accessSync: () => false, OpenMode: { CREATE: 1, WRITE_ONLY: 2 },
      openSync: () => ({ fd: 1 }), writeSync: (_, text) => reports.push(JSON.parse(text)), fsyncSync() {}, closeSync() {} } },
    '@ohos/flutter_ohos': { FlutterEngineCache: { getInstance: () => ({ contains: () => false }) } },
    '@ohos.UiTest': { Driver: { create: () => ({ waitForComponent: async () => ({}) }) }, ON: { id: () => ({}) } },
    '@ohos.process': { default: { pid: 42, tid: 42 } },
    '@ohos.systemDateTime': { default: { TimeType: { STARTUP: 0 }, getUptime: () => 1000 } },
    './G1MemoryObservations': load('G1MemoryObservations.ts'),
    './G1PerformanceObservations': load('G1PerformanceObservations.ts')
  });
  exports.default();
  return { run: () => body(), values, removals: () => removals, reports };
}

for (const failure of ['start', 'mode']) {
  test(`memory observation restores navigation and removes monitor after ${failure} failure`, async () => {
    const value = fixture(failure);
    await assert.rejects(value.run(), failure === 'start' ? /start failed/ : /build mode/);
    assert.equal(value.values.get('category'), 'favorites', 'failed observation must restore the actual saved category');
    assert.equal(value.values.get('multiplayerOnly'), true);
    assert.equal(value.removals(), 1, 'failed observation releases its monitor');
    assert.equal(value.reports.length, 1, 'failure evidence survives early startup errors');
    assert.notEqual(value.reports[0].failure, '');
  });
}
