const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const ts = require('D:/soft/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = path.resolve(__dirname, '../entry/src/ohosTest/ets/test/ProductRetentionCleanup.ts');
function load() {
  const context = { exports: {}, Error };
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(source, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  return context.exports.retentionCleanup;
}
test('failed owner/head/settings restoration still restores cover/navigation and writes report', async () => {
  const calls = [];
  const steps = ['owner', 'head', 'cover', 'settings', 'navigation', 'report'].map(name => async () => {
    calls.push(name);
    if (['owner', 'head', 'settings'].includes(name)) throw Error(name);
  });
  const errors = await load()(steps);
  assert.deepEqual(calls, ['owner', 'head', 'cover', 'settings', 'navigation', 'report']);
  assert.deepEqual(Array.from(errors), ['owner', 'head', 'settings']);
});
test('successful cleanup awaits each asynchronous owner before the next step', async () => {
  const calls = [];
  const errors = await load()([
    async () => { calls.push('close.begin'); await Promise.resolve(); calls.push('close.end'); },
    async () => { calls.push('restore'); }
  ]);
  assert.deepEqual(calls, ['close.begin', 'close.end', 'restore']);
  assert.equal(errors.length, 0);
});
