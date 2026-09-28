const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
function helpers() {
  const ts = require(process.env.FLYNES_TYPESCRIPT || 'D:/soft/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
  const source = path.resolve(__dirname, '../entry/src/ohosTest/ets/test/G1PerformanceObservations.ts');
  const context = { exports: {} };
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(source, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  return context.exports;
}
test('performance recording requires exact opt-in and rejects the unapproved Flutter candidate', () => {
  const { nativePerformanceEnabled } = helpers();
  assert.equal(nativePerformanceEnabled(undefined, undefined), false);
  assert.equal(nativePerformanceEnabled('false', 'native'), false);
  assert.equal(nativePerformanceEnabled('true', undefined), true);
  assert.equal(nativePerformanceEnabled('true', 'native'), true);
  assert.throws(() => nativePerformanceEnabled('true', 'flutter'), /budget/);
});
test('progress counts real source frames rather than wall time and ignores reset/paused deltas', () => {
  const { EmulatedProgress } = helpers();
  const progress = new EmulatedProgress();
  progress.sample(100, 60, true);
  progress.sample(4000, 60, true);
  assert.equal(progress.playedMs, 65000);
  progress.sample(4000, 60, false);
  progress.sample(4500, 60, false);
  progress.sample(4500, 60, true);
  assert.equal(progress.playedMs, 65000);
  progress.sample(0, 60, true);
  progress.sample(60, 60, true);
  assert.equal(progress.playedMs, 66000);
  progress.sample(120, 0, true);
  assert.equal(progress.playedMs, 66000);
});
