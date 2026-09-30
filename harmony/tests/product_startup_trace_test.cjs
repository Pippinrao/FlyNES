const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),test=require('node:test');
const ts=require('D:/soft/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
test('readiness timestamps start unknown and retain first successful owner/catalog events',()=>{
 const file=path.join(__dirname,'../entry/src/main/ets/service/ProductStartupObservation.ts');
 assert.ok(fs.existsSync(file),'independent native-owner and catalog completion markers are required');
 let clock=42;const ctx={exports:{},require:()=>({default:{TimeType:{STARTUP:0},getUptime:()=>clock}})};
 vm.runInNewContext(ts.transpileModule(fs.readFileSync(file,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,ctx);
 const trace=ctx.exports.ProductStartupObservation;assert.equal(trace.nativeOwnerReadyMs,-1);assert.equal(trace.catalogReadyMs,-1);
 trace.ownerReady();assert.equal(trace.nativeOwnerReadyMs,42);clock=100;trace.ownerReady();assert.equal(trace.nativeOwnerReadyMs,42);
 trace.catalogReady();assert.equal(trace.catalogReadyMs,100);clock=200;trace.catalogReady();assert.equal(trace.catalogReadyMs,100);
});

test('catalog publishes owner-ready after open and catalog-ready only after async initialization',async()=>{
 const events=[];let release;const gate=new Promise(r=>release=r);
 const imports={'libentry.so':{default:{appOpen(){events.push('open');},catalogSnapshot:()=>[]}},'../service/ProductStartupObservation':{ProductStartupObservation:{ownerReady:()=>events.push('owner'),catalogReady:()=>events.push('catalog')}},'../platform/HarmonySourceMap':{HarmonySourceMap:class{async load(){await gate;}}},'../service/PlayService':{builtinGamesSync:()=>({all:()=>[]})},'@kit.ArkData':{preferences:{getPreferences:async()=>({get:async()=> 'fixture'})}},'@kit.ArkTS':{util:{TextDecoder:{create:()=>({decodeWithStream:()=> 'fixture'})}}}};
 const ctx={exports:{},console,require:n=>imports[n]||{}};vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(__dirname,'../entry/src/main/ets/flutter/ProductCatalog.ets'),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,ctx);
 const owner=new ctx.exports.ProductCatalog({filesDir:'/files',cacheDir:'/cache',resourceManager:{getRawFileContent:async()=>new Uint8Array()}});
 const pending=owner.initialize();await new Promise(setImmediate);
 try{assert.deepEqual(events,['open','owner']);}finally{release();await pending;}
 assert.deepEqual(events,['open','owner','catalog']);await owner.initialize();assert.deepEqual(events,['open','owner','catalog']);
});

test('native fallback cannot publish catalog ready; a subsequent real snapshot can',()=>{
 let fail=true,ready=0;const ctx={exports:{},console,require:n=>n==='libentry.so'?{default:{catalogSnapshot(){if(fail)throw Error('transient read failure');return [];}}}:{}};
 vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(__dirname,'../entry/src/main/ets/service/CatalogProductService.ets'),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,ctx);
 const service=new ctx.exports.CatalogProductService(),games={all:()=>[]};
 service.loadRows(games,()=>ready++);assert.equal(ready,0,'fallback is not an observed successful catalog');
 fail=false;service.loadRows(games,()=>ready++);assert.equal(ready,1,'successful projection must publish its own completion');
});
