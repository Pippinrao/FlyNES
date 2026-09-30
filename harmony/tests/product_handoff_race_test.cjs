const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),test=require('node:test');
const ts=require('D:/soft/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
function fixture(locale='en') {
 const source=fs.readFileSync(path.join(__dirname,'../entry/src/main/ets/pages/RunGame.ets'),'utf8');
 const body=source.slice(source.indexOf('  private openingProductSettings:'),source.indexOf('  private pauseLabel('));
 let resolve,reject;const pushed=[],cleared=[],closed=[];
 const context={exports:{},getContext:()=>({}),i18n:{System:{getSystemLanguage:()=> 'en'}},nativePlay:{renderSetPaused(){},settingsGet:()=>({localeTag:locale})},router:{pushUrl:async r=>pushed.push(r),back:()=>pushed.push('back'),replaceUrl:async r=>pushed.push(r)},ProductHandoffBackdrop:{capture:()=>new Promise((a,b)=>{resolve=a;reject=b;}),clear:()=>cleared.push(true)},closed};
 vm.runInNewContext(ts.transpileModule(`export class Host {started=true;paused=true;drawerOpen=true;resumeAfterSettings=false;foundationReturn=true;nearby=false;play={close:()=>closed.push(true)};stopLoop(){} ${body} }`,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,context);
 return {host:new context.exports.Host(),pushed,cleared,closed,resolve:()=>resolve(1),reject:()=>reject(Error('capture failed'))};
}
for(const failure of [false,true])test(`late snapshot ${failure?'failure':'success'} cannot reopen settings after Resume`,async()=>{
 const f=fixture();const pending=f.host.openProductSettings();f.host.paused=false;f.host.drawerOpen=false;f.host.productNavigationEpoch=(f.host.productNavigationEpoch??0)+1;
 failure?f.reject():f.resolve();await pending;
 assert.equal(f.pushed.length,0,'user resumed before capture completed');assert.equal(f.host.paused,false);assert.equal(f.host.drawerOpen,false);assert.equal(f.host.resumeAfterSettings,false);
});
test('return to hall waits for the paused snapshot before closing its native owner',async()=>{
 const f=fixture();f.host.handlePauseCommand('game_center');await new Promise(setImmediate);
 assert.equal(f.closed.length,0,'capture must complete before closing the live paused game');assert.equal(f.pushed.length,0);
 f.resolve();await new Promise(setImmediate);assert.equal(f.closed.length,1);assert.deepEqual(f.pushed,['back']);assert.equal(f.host.started,false);
});
test('failed hall capture keeps the paused owner and exposes a retryable localized error',async()=>{
 const f=fixture();f.host.handlePauseCommand('game_center');await new Promise(setImmediate);
 assert.equal(f.closed.length,0);f.reject();await new Promise(setImmediate);
 assert.equal(f.closed.length,0);assert.equal(f.pushed.length,0);assert.equal(f.host.drawerOpen,true);
 assert.match(f.host.productNavigationError,/try again/i);
 f.host.handlePauseCommand('game_center');await new Promise(setImmediate);f.resolve();await new Promise(setImmediate);assert.deepEqual(f.pushed,['back']);
});
test('Resume or background during hall capture cannot close or navigate the current game',async()=>{
 const f=fixture();f.host.handlePauseCommand('game_center');await new Promise(setImmediate);assert.equal(f.closed.length,0);
 f.host.productNavigationEpoch++;f.host.paused=false;f.host.drawerOpen=false;f.resolve();await new Promise(setImmediate);
 assert.equal(f.closed.length,0);assert.equal(f.pushed.length,0);assert.equal(f.host.drawerOpen,false);
});
test('capture failure has a Chinese retry message for the Chinese app locale',async()=>{
 const f=fixture('zh-Hans');f.host.handlePauseCommand('game_center');await new Promise(setImmediate);f.reject();await new Promise(setImmediate);
 assert.equal(f.host.productNavigationError,'无法打开页面，请重试。');assert.equal(f.host.started,true);assert.equal(f.host.drawerOpen,true);
});
