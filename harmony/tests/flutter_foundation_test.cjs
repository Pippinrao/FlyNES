const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const source = path.resolve(__dirname, '../entry/src/main/ets/flutter/FoundationProjection.ts');

function load() {
  assert.ok(fs.existsSync(source), 'Foundation projection must exist for the debug route and native catalog response');
  const ts = require(process.env.FLYNES_TYPESCRIPT || 'D:/soft/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
  const compiled = ts.transpileModule(fs.readFileSync(source, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const context = { exports: {} };
  vm.runInNewContext(compiled, context);
  return context.exports;
}

test('foundation route is accepted only for the exact debug Want', () => {
  const api = load();
  assert.equal(api.isFlutterFoundationRoute('flutter_foundation', true), true);
  assert.equal(api.isFlutterFoundationRoute('flutter_foundation', false), false);
  assert.equal(api.isFlutterFoundationRoute('nearby_lobby', true), false);
  assert.equal(api.isFlutterFoundationRoute(undefined, true), false);
});

test('catalog source locators determine availability independently of launch bridge', () => {
  const api = load();
  const rows = [
    { canonicalId: 'game:fixture', titleEn: 'Fixture', titleZhHans: '测试', builtin: true, sourceUuidHex: '', sourceRelativePath: '' },
    { canonicalId: 'game:imported', titleEn: 'Imported', titleZhHans: '', builtin: false, sourceUuidHex: '0123456789abcdef0123456789abcdef', sourceRelativePath: 'fixture.nes' },
    { canonicalId: 'game:missing', titleEn: 'Missing', titleZhHans: '', builtin: false, sourceUuidHex: '', sourceRelativePath: '' }
  ];
  const snapshot = api.foundationSnapshot(rows, 7);
  assert.equal(snapshot.generation, 7);
  assert.equal(snapshot.games.length, 3);
  assert.equal(snapshot.games[0].canonicalId, rows[0].canonicalId);
  assert.equal(snapshot.games[0].titleZhHans, rows[0].titleZhHans);
  assert.equal(snapshot.games[0].available, true);
  assert.equal(snapshot.games[1].available, true);
  assert.equal(snapshot.games[2].available, false);
  assert.ok(snapshot.games[2].unavailableReason.length > 0);
  assert.equal(api.foundationSnapshot([], 8).games.length, 0);
});

test('channel queries the native owner and product projection, and never invents unsupported actions', () => {
  const channelSource = path.resolve(__dirname, '../entry/src/main/ets/flutter/FoundationChannelHandler.ets');
  assert.ok(fs.existsSync(channelSource), 'Native foundation channel handler must exist');
  const ts = require(process.env.FLYNES_TYPESCRIPT || 'D:/soft/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
  const events = [];
  const row = { canonicalId: 'game:catalog', titleEn: 'Real projection', titleZhHans: '', builtin: true, sourceUuidHex: '', sourceRelativePath: '' };
  const imports = {
    'libentry.so': { default: { appOpen: () => events.push('open'), catalogSnapshot: () => { events.push('native'); return []; } } },
    '../service/CatalogProductService': { CatalogProductService: class { loadRowsFromSnapshot() { events.push('projection'); return [row]; } } },
    '../service/PlayService': { builtinGamesSync: () => ({}) },
    './FoundationProjection': load()
  };
  const context = { exports: {}, console, require: name => imports[name] || extraImport(name) };
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(channelSource, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  const handler = new context.exports.FoundationChannelHandler({ filesDir: 'files', cacheDir: 'cache' });
  let response;
  let unsupported = 0;
  const result = { success: value => response = value, error: () => assert.fail('unexpected channel error'), notImplemented: () => unsupported++ };
  handler.onMethodCall({ method: 'catalogSnapshot' }, result);
  assert.deepEqual(events, ['open', 'native', 'projection']);
  assert.equal(response.games[0].titleEn, 'Real projection');
  handler.onMethodCall({ method: 'unknown-method' }, result);
  assert.equal(unsupported, 1);
  assert.equal(events.length, 3);
  const firstGeneration = response.generation;
  const reattached = new context.exports.FoundationChannelHandler({ filesDir: 'files', cacheDir: 'cache' });
  reattached.onMethodCall({ method: 'catalogSnapshot' }, result);
  assert.ok(response.generation > firstGeneration, 'A replacement Flutter handler must not reset the process snapshot sequence');
});

test('real catalog service projects exactly the verified native snapshot', () => {
  const ts = require(process.env.FLYNES_TYPESCRIPT || 'D:/soft/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
  let queries = 0;
  const native = { appOpen() {}, catalogSnapshot() {
    queries++;
    if (queries > 1) throw new Error('second query failed');
    return [{ canonicalId: 'game:import', titleEn: 'Imported', titleZhHans: '', builtin: false, sourceUuidHex: '0123456789abcdef0123456789abcdef', sourceRelativePath: 'fixture.nes' }];
  } };
  function compile(file, imports) {
    const context = { exports: {}, console, require: name => imports[name] || extraImport(name) };
    vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.resolve(__dirname, file), 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText, context);
    return context.exports;
  }
  const service = compile('../entry/src/main/ets/service/CatalogProductService.ets', { 'libentry.so': { default: native } });
  const channel = compile('../entry/src/main/ets/flutter/FoundationChannelHandler.ets', {
    'libentry.so': { default: native }, '../service/CatalogProductService': service,
    '../service/PlayService': { builtinGamesSync: () => ({ all: () => [] }) }, './FoundationProjection': load()
  });
  let response;
  new channel.FoundationChannelHandler({ filesDir: 'files', cacheDir: 'cache' }).onMethodCall({ method: 'catalogSnapshot' }, {
    success: value => response = value, error: () => assert.fail('unexpected error'), notImplemented: () => assert.fail('unexpected unsupported')
  });
  assert.equal(queries, 1, 'must not discard verified snapshot and perform a fallible second query');
  assert.equal(response.games[0].canonicalId, 'game:import');
});

test('foundation entry retains a dedicated Flutter UI thread for the API20 host', () => {
  const ts = require(process.env.FLYNES_TYPESCRIPT || 'D:/soft/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
  class ShellArgs {
    constructor() { this.values = ['--existing-host-option']; }
    add(value) { this.values.push(value); }
    toArray() { return this.values; }
  }
  const imports = {
    '@ohos/flutter_ohos': { FlutterEntry: class { getFlutterShellArgs() { return new ShellArgs(); } }, FlutterShellArgs: ShellArgs }
  };
  const context = { exports: {}, require: name => imports[name] || extraImport(name) };
  const file = path.resolve(__dirname, '../entry/src/main/ets/flutter/FoundationFlutterEntry.ets');
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(file, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  const args = new context.exports.FoundationFlutterEntry().getFlutterShellArgs().toArray();
  assert.ok(args.includes('--existing-host-option'));
  assert.ok(args.includes('--merged-platform-ui-thread=disabled'));
});

function extraImport(name) {
  if (name === './ProductChannelHandler') return { ProductRouteContext: class {}, ProductChannelHandler: class {} };
  if (name === '../service/CoverStore') return { CoverStore: class { localPath() { return ''; } } };
  if (name !== './FoundationRouteOwner') return {};
  const ts = require(process.env.FLYNES_TYPESCRIPT || 'D:/soft/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
  const context = { exports: {} };
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.resolve(__dirname, '../entry/src/main/ets/flutter/FoundationRouteOwner.ts'), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  return context.exports;
}

test('page and ability pause detach the surface, restore semantics, and preserve native return', () => {
  const ts = require(process.env.FLYNES_TYPESCRIPT || 'D:/soft/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
  const calls = [];
  const lifecycle = { appIsInactive: () => calls.push('inactive'), appIsPaused: () => calls.push('paused') };
  const imports = {
    '@kit.ArkUI': { router: { getLength: () => '2', back: () => calls.push('native-back') } },
    '@ohos/flutter_ohos': { FlutterEntry: class {
      getFlutterView() { return { setActive: value => calls.push(value), onSurfaceDestroyed: () => calls.push('surface-detached'), onSurfaceCreated: () => calls.push('surface-attached') }; }
      getFlutterEngine() { return { getLifecycleChannel: () => lifecycle, getFlutterNapi: () => ({ setSemanticsEnabled: value => calls.push('semantics-' + value) }) }; }
      onPageHide() { calls.push('paused'); }
      onPageShow() { calls.push('resumed'); }
    } }
  };
  const context = { exports: {}, require: name => imports[name] || extraImport(name) };
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.resolve(__dirname, '../entry/src/main/ets/flutter/FoundationFlutterEntry.ets'), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  const entry = new context.exports.FoundationFlutterEntry();
  entry.onPageHide();
  assert.deepEqual(calls, ['surface-detached', 'paused']);
  entry.background();
  assert.equal(calls.at(-1), 'paused');
  assert.equal(calls.filter(value => value === 'surface-detached').length, 1);
  entry.foreground();
  assert.equal(calls.at(-1), 'paused', 'covered page stays detached on ability foreground');
  entry.onPageShow();
  assert.deepEqual(calls.slice(-4), ['surface-attached', 'semantics-true', 'resumed', 'semantics-true']);
  entry.background();
  assert.deepEqual(calls.slice(-2), ['surface-detached', 'paused']);
  entry.foreground();
  assert.deepEqual(calls.slice(-2), ['surface-attached', 'semantics-true']);
  assert.equal(entry.popSystemNavigator(), true);
  assert.equal(calls.at(-1), 'native-back');
});
