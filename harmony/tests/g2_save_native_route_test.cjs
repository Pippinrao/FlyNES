const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');

function check(state, hasEngine = false) {
  const source = fs.readFileSync(path.join(__dirname,
    '../entry/src/ohosTest/ets/test/G1NativeSavePerformance.test.ets'), 'utf8');
  const start = source.indexOf("      if (route === 'native') {");
  const end = source.indexOf('      await wait(300);', start);
  assert.ok(start >= 0 && end > start);
  vm.runInNewContext(source.slice(start, end), {
    route: 'native', nav: { getState: () => state }, console,
    FlutterEngineCache: { getInstance: () => ({ contains: () => hasEngine }) },
    expect: value => ({ assertFalse: () => assert.equal(value, false),
      assertTrue: () => assert.equal(value, true), assertEqual: other => assert.equal(value, other) })
  });
}
test('native route accepts API20 directory path plus file name', () => {
  check({ path: 'pages/', name: 'GameCenter' });
});
test('native route rejects actual Flutter product page', () => {
  assert.throws(() => check({ path: 'pages/', name: 'FlutterFoundation' }));
});
test('native baseline rejects an already allocated Flutter engine', () => {
  assert.throws(() => check({ path: 'pages/', name: 'GameCenter' }, true));
});
