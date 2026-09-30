const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const ts = require('D:/soft/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
function load(file, imports) {
  const context = { exports: {}, console, require: name => imports[name] || {} };
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(__dirname, '../entry/src/main/ets', file), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  return context.exports;
}
test('read-only play diagnostics distinguish closed owner and replacement without advancing history', () => {
  const native = { nearbyMvpOpenPlay: () => true, playSetAudioMuted() {}, playClose() {} };
  const { PlayService } = load('service/PlayService.ets', { 'libentry.so': { default: native } });
  assert.equal(typeof PlayService.lifecycleSnapshot, 'function', 'cycle evidence needs an actual owner observation');
  const first = new PlayService();
  first.openNearby();
  const before = PlayService.lifecycleSnapshot();
  assert.equal(before.activeOwners, 1);
  first.history = { clockSnapshot: () => ({ playedMs: 17, sinceSaveMs: 9 }) };
  assert.equal(PlayService.lifecycleSnapshot().playedMs, 17);
  assert.equal(PlayService.lifecycleSnapshot().sinceSaveMs, 9);
  first.close(); first.close();
  assert.equal(PlayService.lifecycleSnapshot().activeOwners, 0);
  const next = new PlayService(); next.openNearby();
  assert.ok(PlayService.lifecycleSnapshot().generation > before.generation);
  next.close();
});
test('history clock observation is detached, read-only and stable with zero paused source progress', () => {
  const { SaveHistoryService } = load('service/SaveHistoryService.ets', {});
  const history = new SaveHistoryService('ignored', 'key');
  assert.equal(typeof history.clockSnapshot, 'function', 'observe actual autosave accounting');
  history.advance(0, 60, true); history.advance(60, 60, false);
  const snapshot = history.clockSnapshot();
  assert.equal(snapshot.playedMs, 1000); assert.equal(snapshot.sinceSaveMs, 1000);
  history.advance(60, 60, false);
  snapshot.playedMs = -1;
  assert.equal(history.clockSnapshot().playedMs, 1000);
  assert.equal(history.clockSnapshot().sinceSaveMs, 1000);
});
