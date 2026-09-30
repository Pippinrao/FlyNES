const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),test=require('node:test');
const ts=require('D:/soft/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
function pageFixture(){
 let source=fs.readFileSync(path.join(__dirname,'../entry/src/main/ets/pages/FlutterFoundation.ets'),'utf8');
 source=source.slice(0,source.indexOf('  build()')).replace(/@Entry\s*@Component\s*struct FlutterFoundation/,'export class FlutterFoundation').replace(/@State /g,'')+'}\n';
 const frame={released:0,release(){this.released++;return Promise.resolve();}};let captured=false;
 const entry=class{aboutToAppear(){}getFlutterView(){return {getId:()=> 'view'};}onPageShow(){}onPageHide(){}aboutToDisappear(){}};
 const imports={'../flutter/FoundationFlutterEntry':{FoundationFlutterEntry:entry},'../flutter/ProductChannelHandler':{ProductRouteContext:class{}},'@kit.ArkUI':{router:{getParams:()=>({})}},'../flutter/ProductHandoffBackdrop':{ProductHandoffBackdrop:{capture:async()=>{captured=true;return 1;},take:()=>{const value=captured?frame:undefined;captured=false;return value;},clear(){}}}};
 const ctx={exports:{},getContext:()=>({eventHub:{on(){},off(){}}}),require:name=>imports[name]??{}};
 vm.runInNewContext(ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,ctx);
 const host=new ctx.exports.FlutterFoundation();host.aboutToAppear();host.onPageShow();return {host,frame};
}
test('preparing a picture does not hide the still-visible hall if native navigation fails',async()=>{
 const {host,frame}=pageFixture();host.flutterEntry.onPresented();await host.prepareNativeRoute();
 assert.equal(host.presented,true,'the current view stays usable until the platform actually hides it');assert.equal(host.backdrop,frame);
 host.onPageHide();assert.equal(host.presented,false);assert.equal(frame.released,0);host.aboutToDisappear();assert.equal(frame.released,1);
});
test('background invalidates capture but not the current host raster acknowledgment',()=>{
 const {host}=pageFixture();const ready=host.flutterEntry.onPresented;host.onHostBackground();host.onHostForeground();ready();
 assert.equal(host.presented,true,'returning current host must not be stuck behind an invalidated gate');
});
for(const action of ['return','background'])test(`outgoing bitmap releases once on ${action}, with no retained Flutter view`,async()=>{
 const {host,frame}=pageFixture();const retired=host.flutterEntry;retired.onPresented();await host.prepareNativeRoute();host.onPageHide();
 assert.equal(host.flutterEntry,undefined);assert.equal(host.flutterView,undefined);assert.equal(frame.released,0);
 if(action==='return'){host.onPageShow();host.flutterEntry.onPresented();assert.equal(host.presented,true);retired.onPresented();}
 else host.onHostBackground();
 assert.equal(frame.released,1);host.aboutToDisappear();assert.equal(frame.released,1);
});
test('hiding an outgoing Flutter page detaches its view but keeps the valid compositor picture',()=>{
 const source=fs.readFileSync(path.join(__dirname,'../entry/src/main/ets/pages/FlutterFoundation.ets'),'utf8');
 const body=source.slice(source.indexOf('  onPageShow()'),source.indexOf('  build()'));
 const calls=[];const frame={release(){calls.push('release');return Promise.resolve();}};
 const ctx={exports:{},detachActiveProductView:undefined,getContext:()=>({eventHub:{off(){}}})};
 vm.runInNewContext(ts.transpileModule(`export class Host {flutterEntry={onPageHide(){},aboutToDisappear(){}};viewId='old';flutterView={};presented=false;backdrop;releaseView=()=>{};outgoingBackdrop=true;attach(){}; ${body} }`,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,ctx);
 const host=new ctx.exports.Host();host.backdrop=frame;host.onPageHide();
 assert.equal(host.viewId,'');assert.equal(host.flutterEntry,undefined);assert.equal(host.backdrop,frame);assert.deepEqual(calls,[]);
 host.aboutToDisappear();assert.equal(host.backdrop,undefined);assert.deepEqual(calls,['release']);
});
