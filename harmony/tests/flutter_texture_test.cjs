const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
function fixture() {
  const source = path.resolve(__dirname, '../entry/src/main/ets/flutter/FoundationTextureHandler.ets');
  assert.ok(fs.existsSync(source), 'native texture owner must exist');
  const ts = require('D:/soft/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
  const events = [];
  let next = 0;
  const renderer = {
    getTextureId: () => ++next,
    registerTexture: id => ({ getNativeWindowId: () => id + 100 }),
    setTextureBufferSize: () => {}, unregisterTexture: id => events.push(['release', id])
  };
  const native = {
    textureProbeOpen: () => events.push(['open']),
    textureProbeAttach: window => events.push(['attach', window]),
    textureProbeDetach: () => events.push(['detach']),
    textureProbeActive: value => events.push(['active', value]),
    textureProbeInput: value => events.push(['input', value]),
    textureProbeClose: () => events.push(['close']),
    textureProbeStats: () => ({ sourceFrames: 3 })
  };
  const context = { exports: {}, console, require: name => name === 'libentry.so' ? { default: native } :
    name === '../service/PlayService' ? { builtinGamesSync: () => ({ all: () => [{ assetPath: () => 'manifest-entry' }] }) } : {} };
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(source, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  const handler = new context.exports.FoundationTextureHandler({ resourceManager: { getRawFileContentSync: () => new Uint8Array([1]) } }, { getFlutterRenderer: () => renderer });
  function call(method, args = {}) {
    let response;
    handler.onMethodCall({ method, argument: key => args[key] }, {
      success: value => response = value, error: (_, message) => { throw Error(message); }, notImplemented: () => assert.fail('unknown')
    });
    return response;
  }
  return { handler, events, call };
}
test('texture detach stops media before releasing surface but preserves core for twenty cycles', () => {
  const f = fixture();
  for (let i = 0; i < 20; i++) {
    assert.equal(f.call('attach', { owner: 'page' }), i + 1);
    f.call('detach', { owner: 'page' });
  }
  assert.equal(f.events.filter(e => e[0] === 'open').length, 1);
  assert.equal(f.events.filter(e => e[0] === 'close').length, 0);
  for (let i = 0; i < f.events.length; i++) if (f.events[i][0] === 'release') assert.equal(f.events[i-1][0], 'detach');
  f.handler.dispose();
  assert.equal(f.events.filter(e => e[0] === 'close').length, 1);
});
test('late old-page input, cleanup and active cannot affect a new owner', () => {
  const f = fixture();
  f.call('attach', { owner: 'old' }); f.call('attach', { owner: 'new' });
  const n = f.events.length;
  f.call('detach', { owner: 'old' }); f.call('input', { owner: 'old', buttons: 255 }); f.call('active', { owner: 'old', active: true });
  assert.equal(f.events.length, n);
  f.call('input', { owner: 'new', buttons: 3 });
  assert.deepEqual(f.events.at(-1), ['input', 3]);
});
test('host background cannot be undone by a delayed Dart active command', () => {
  const f = fixture();
  f.call('attach', { owner: 'page' });
  f.handler.onHostActive(false);
  f.call('active', { owner: 'page', active: true });
  assert.deepEqual(f.events.at(-1), ['active', false]);
  f.call('input', { owner: 'page', buttons: 3 });
  assert.deepEqual(f.events.at(-1), ['input', 0]);
  f.handler.onHostActive(true);
  assert.deepEqual(f.events.at(-1), ['active', true]);
});
