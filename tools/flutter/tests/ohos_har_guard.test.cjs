const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const vm = require('node:vm');
const test = require('node:test');
const files = ['flutter_embedding.har', 'arm64_v8a.har', 'x86_64.har', 'flutter_module.har'];
const revision = '244a0e8abb3085e8675589b13e219af8c41cb7aa';
function guard() {
  const source = path.resolve(__dirname, '../../../harmony/flutter-har-guard.ts');
  assert.ok(fs.existsSync(source), 'HAR mode guard must exist');
  const ts = require(process.env.FLYNES_TYPESCRIPT || 'D:/soft/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
  const context = { exports: {}, require };
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(source, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  return context.exports.verifyFlutterHarStage;
}
function fixture(t, mode) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'flynes-har-guard-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const rows = files.map(name => {
    const bytes = Buffer.from(`${mode}:${name}`);
    fs.writeFileSync(path.join(dir, name), bytes);
    return { name, sha256: crypto.createHash('sha256').update(bytes).digest('hex') };
  });
  const manifest = { schemaVersion: 1, mode, sdkRevision: revision, files: rows };
  const save = () => fs.writeFileSync(path.join(dir, 'manifest.json'), JSON.stringify(manifest));
  save();
  return { dir, manifest, save };
}
test('all three matching modes accept exactly the four pinned, hash-verified HARs', t => {
  const verify = guard();
  for (const mode of ['debug', 'profile', 'release']) verify(fixture(t, mode).dir, mode);
});
test('release and profile cannot consume a staged debug engine', t => {
  const verify = guard();
  const { dir } = fixture(t, 'debug');
  assert.throws(() => verify(dir, 'release'), /mode mismatch/);
  assert.throws(() => verify(dir, 'profile'), /mode mismatch/);
});
test('mixed or incompletely staged modules fail before host packaging', t => {
  const verify = guard();
  const f = fixture(t, 'release');
  fs.appendFileSync(path.join(f.dir, 'flutter_module.har'), 'stale debug module');
  assert.throws(() => verify(f.dir, 'release'), /hash mismatch/);
});
test('missing architecture or stale SDK provenance is rejected', t => {
  const verify = guard();
  const f = fixture(t, 'profile');
  f.manifest.files.pop(); f.save();
  assert.throws(() => verify(f.dir, 'profile'), /four HAR/);
  const g = fixture(t, 'release');
  g.manifest.sdkRevision = 'other-sdk'; g.save();
  assert.throws(() => verify(g.dir, 'release'), /SDK revision/);
});
