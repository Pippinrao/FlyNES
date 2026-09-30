const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const ts = require('D:/soft/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const context = { exports: {}, require: () => ({}) };
vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/flutter/ProductPolicy.ts'), 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);
const { ProductHostLease, patchProductSetting } = context.exports;
test('stale host cannot detach or answer for the newly attached native page', () => {
  const lease = new ProductHostLease();
  const hall = lease.acquire('hall');
  assert.ok(hall > 0);
  assert.equal(lease.release(hall), true);
  const settings = lease.acquire('settings');
  assert.ok(settings > hall);
  assert.equal(lease.release(hall), false);
  assert.equal(lease.accepts(settings), true);
  assert.equal(lease.accepts(hall), false);
  assert.equal(lease.token, 'settings');
});
test('scalar settings write preserves newest native layout and unrelated values', () => {
  const current = { audioEnabled: 1, buttonScale: 1.8, deadZone: .28, lastPlayedId: 'new-head', localeTag: 'en' };
  const next = patchProductSetting(current, 'audioEnabled', false);
  assert.equal(next.audioEnabled, 0);
  assert.equal(next.buttonScale, 1.8);
  assert.equal(next.deadZone, .28);
  assert.equal(next.lastPlayedId, 'new-head');
  assert.equal(current.audioEnabled, 1, 'patch cannot mutate an observed snapshot');
});
test('native settings policy blocks unqualified display paths and rejects invalid types', () => {
  for (const [key, value] of [['videoQualityPreset',3],['customRefreshPolicy',4],['customRefreshPolicy',5],['customTemporalMode',2],['audioEnabled',1],['directionMode',8],['buttonScale',2],['localeTag','fr']]) {
    assert.throws(() => patchProductSetting({}, key, value), undefined, `${key}=${value}`);
  }
  assert.equal(patchProductSetting({}, 'videoQualityPreset',4).videoQualityPreset,4);
  assert.equal(patchProductSetting({}, 'localeTag','zh-Hans').localeTag,'zh-Hans');
});

test('all public audio focus policies including IGNORE preserve unrelated native settings', () => {
  const current = { audioFocusPolicy: 1, buttonScale: 1.7, localeTag: 'en' };
  for (const value of [1, 2, 3]) {
    const next = patchProductSetting(current, 'audioFocusPolicy', value);
    assert.equal(next.audioFocusPolicy, value);
    assert.equal(next.buttonScale, 1.7);
    assert.equal(next.localeTag, 'en');
  }
  for (const value of [0, 4, 1.5, true]) assert.throws(() => patchProductSetting(current, 'audioFocusPolicy', value));
});
