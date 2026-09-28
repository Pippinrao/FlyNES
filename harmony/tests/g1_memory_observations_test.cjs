const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
function helpers() {
  const source = path.resolve(__dirname, '../entry/src/ohosTest/ets/test/G1MemoryObservations.ts');
  assert.ok(fs.existsSync(source), 'memory observation helpers must exist');
  const ts = require(process.env.FLYNES_TYPESCRIPT || 'D:/soft/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
  const context = { exports: {} };
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(source, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  return context.exports;
}

test('memory candidate requires opt-in and separate budget approval', () => {
  const { memoryRoundTripsEnabled } = helpers();
  assert.equal(memoryRoundTripsEnabled(undefined, undefined), false);
  assert.equal(memoryRoundTripsEnabled('false', 'true'), false);
  assert.throws(() => memoryRoundTripsEnabled('true', undefined), /budget approval/);
  assert.throws(() => memoryRoundTripsEnabled('true', 'false'), /budget approval/);
  assert.equal(memoryRoundTripsEnabled('true', 'true'), true);
});

test('zero or invalid allocator/heap readings are unavailable, not zero retained memory', () => {
  const { measuredPositive } = helpers();
  for (const unavailable of [0, -1, NaN, Infinity, Number.MAX_SAFE_INTEGER + 1]) {
    assert.equal(measuredPositive(unavailable), -1);
  }
  assert.equal(measuredPositive(1234), 1234);
});

test('a dump request is not GC evidence without an increasing valid counter', () => {
  const { gcCountEvidence } = helpers();
  assert.equal(gcCountEvidence(-1, 5), 'unavailable');
  assert.equal(gcCountEvidence(5, 2), 'counter-reset');
  assert.equal(gcCountEvidence(5, 5), 'not-observed');
  assert.equal(gcCountEvidence(0, 1), 'observed');
  assert.equal(gcCountEvidence(5, 6), 'observed');
});

test('Dart checkpoint acknowledgement rejects stale rounds, PID and absent evidence', () => {
  const { validateDartHeapAck } = helpers();
  const good = { schemaVersion: 1, runToken: 'run-42', round: 5, pid: 42,
    status: 'dart-heap-collected', evidenceSha256: 'a'.repeat(64),
    isolateId: 'isolates/99', gcRequested: true, gcObserved: true };
  assert.equal(validateDartHeapAck(JSON.stringify(good), 'run-42', 5, 42).isolateId, 'isolates/99');
  for (const change of [{ runToken: 'old-run' }, { round: 20 }, { pid: 43 },
    { status: 'failed' }, { evidenceSha256: '' }, { isolateId: '' }]) {
    assert.throws(() => validateDartHeapAck(JSON.stringify({ ...good, ...change }), 'run-42', 5, 42));
  }
  assert.throws(() => validateDartHeapAck('{', 'run-42', 5, 42));
});

test('Dart handshake opt-in is explicit and rejects ambiguous values', () => {
  const { dartHeapWaitEnabled } = helpers();
  assert.equal(dartHeapWaitEnabled(undefined), false);
  assert.equal(dartHeapWaitEnabled('false'), false);
  assert.equal(dartHeapWaitEnabled('true'), true);
  assert.throws(() => dartHeapWaitEnabled('yes'), /flag/);
});

test('runtime GC stats preserve BigInt values without making report JSON fail', () => {
  const { gcStatsForJson, gcCountFromStat } = helpers();
  const stats = gcStatsForJson({ 'ark.gc.gc-count': 0n, duration: 9007199254740993n, number: 4 });
  assert.equal(JSON.stringify(stats), '{"ark.gc.gc-count":"0","duration":"9007199254740993","number":"4"}');
  assert.equal(gcCountFromStat(stats['ark.gc.gc-count']), 0);
  assert.equal(gcCountFromStat('18'), 18);
  for (const value of [undefined, '', 'NaN', '-1', '9007199254740993']) {
    assert.equal(gcCountFromStat(value), -1);
  }
});

test('ACK transport framing accepts split newline frames and rejects excess bytes', () => {
  const { DartAckFrame } = helpers();
  const frame = new DartAckFrame();
  assert.equal(frame.push('{"run'), '');
  assert.equal(frame.push('Token":"a"}\n'), '{"runToken":"a"}');
  assert.throws(() => frame.push('again\n'), /complete/);
  assert.throws(() => new DartAckFrame().push('x'.repeat(16385)), /large/);
});
