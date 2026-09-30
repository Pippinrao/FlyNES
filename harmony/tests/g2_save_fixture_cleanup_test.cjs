const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const ts = require('D:/soft/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');

// Execute the real fixture's cleanup, including its report writer. The 65s
// emulation workload is irrelevant to restoration failing after that workload.
function cleanup(failure) {
  const source = fs.readFileSync(path.join(__dirname, '../entry/src/ohosTest/ets/test/G1NativeSavePerformance.test.ets'), 'utf8');
  const start = source.indexOf('      finally {', source.indexOf('report.complete = true;'));
  const open = source.indexOf('{', start);
  let depth = 1, end = open + 1;
  for (; depth && end < source.length; end++) {
    if (source[end] === '{') depth++;
    if (source[end] === '}') depth--;
  }
  assert.equal(depth, 0);
  const reports = [];
  const report = { complete: true, failure: '', uptimeEndMs: 1 };
  const context = { report, observer: -1, progress: { playedMs: 65000 }, original: { audioEnabled: 0 },
    route: 'native', hadInterval: true, oldInterval: 120000, context: { filesDir: '/files' },
    now: () => 10, wait: async () => {}, console, clearInterval() {},
    delegator: { getCurrentTopAbility: async () => ({ context: {} }) },
    window: { getLastWindow: async () => ({ getUIContext: () => ({ getRouter: () => ({ replaceUrl: async () => {} }) }) }) },
    nativePlay: { playRuntimeStatus() { throw Error('core closed'); }, settingsApply() { if (failure === 'throws') throw Error('restore storage failed'); }, settingsGet: () => ({ audioEnabled: 1 }) },
    options: { putSync() {}, deleteSync() {}, flush: async () => {}, getSync: () => 120000 },
    fileIo: { OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 }, openSync: () => ({ fd: 1 }),
      writeSync: (_, text) => reports.push(JSON.parse(text)), fsyncSync() {}, closeSync() {} },
    expect: value => ({ assertTrue: () => assert.equal(value, true) }) };
  vm.createContext(context);
  const code = `async function run() { ${source.slice(open + 1, end - 1)} }`;
  vm.runInContext(ts.transpileModule(code, { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText, context);
  return { run: () => context.run(), reports };
}

for (const failure of ['silent', 'throws']) {
  test(`save measurement fails and preserves evidence when settings restoration ${failure}`, async () => {
    const value = cleanup(failure);
    await assert.rejects(value.run(), /restor/);
    assert.equal(value.reports.length, 1, 'restoration failure must still persist evidence');
    assert.equal(value.reports[0].complete, false);
    assert.equal(value.reports[0].preferencesRestored, false);
    assert.match(value.reports[0].failure, /restor/);
  });
}
