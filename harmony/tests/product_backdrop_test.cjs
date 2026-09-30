const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),test=require('node:test');
const ts=require('D:/soft/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
function fixture(){
 const pending=[];const context={exports:{},require:name=>name==='@kit.ArkUI'?{window:{getLastWindow:async()=>({snapshot:()=>new Promise(resolve=>pending.push(resolve))})}}:{}};
 const source=fs.readFileSync(path.join(__dirname,'../entry/src/main/ets/flutter/ProductHandoffBackdrop.ets'),'utf8');
 vm.runInNewContext(ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,context);
 return {store:context.exports.ProductHandoffBackdrop,pending};
}
const frame=()=>({released:0,release(){this.released++;return Promise.resolve();}});
test('a late older capture cannot replace or release the newer route picture',async()=>{
 const f=fixture(),old=frame(),next=frame();const a=f.store.capture({});await new Promise(setImmediate);
 const b=f.store.capture({});await new Promise(setImmediate);f.pending[1](next);const token=await b;
 f.pending[0](old);await a;assert.equal(f.store.take(token),next);assert.equal(old.released,1);assert.equal(next.released,0);
});
test('clear while capture is suspended releases its late pixel map instead of resurrecting it',async()=>{
 const f=fixture(),pixel=frame();const capture=f.store.capture({});await new Promise(setImmediate);f.store.clear();f.pending[0](pixel);await capture;
 assert.equal(f.store.take(),undefined);assert.equal(pixel.released,1);
});
test('invalidated owner never publishes its snapshot and stale clear cannot delete a replacement',async()=>{
 const f=fixture(),old=frame(),next=frame();let active=true;
 const capture=f.store.capture({},()=>active);await new Promise(setImmediate);active=false;f.pending[0](old);const stale=await capture;
 assert.equal(f.store.take(),undefined);assert.equal(old.released,1);
 const current=f.store.capture({});await new Promise(setImmediate);f.pending[1](next);const token=await current;
 f.store.clear(stale);assert.equal(f.store.take(token),next);assert.equal(next.released,0);
});
