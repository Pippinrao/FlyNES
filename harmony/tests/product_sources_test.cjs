const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),test=require('node:test');
const ts=require('D:/soft/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const A='a'.repeat(32),B='b'.repeat(32),MAP='source_map_v1',REMOVALS='source_removals_v1';
function load(file,imports={}){const ctx={exports:{},console,canIUse:imports.canIUse||(()=>true),require:n=>imports[n]||{}};vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(__dirname,'../entry/src/main/ets',file),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,ctx);return ctx.exports;}
function fixture(options={}){
 const sources=[{uuid:A,uri:options.missingLocator?'':'old-uri'}];if(options.shared)sources.push({uuid:B,uri:'new-uri'});
 let persisted=new Map([[MAP,JSON.stringify({builtin:'c'.repeat(32),sources})]]);if(options.pending)persisted.set(REMOVALS,JSON.stringify([A]));
 let working=new Map(persisted),removed=false,flushFailed=false;const grants=new Set(options.persisted?['new-uri']:[]),active=new Set(grants),calls=[];
 const statuses=sources.map(s=>({uuidHex:s.uuid,sourceScope:2,freshness:options.partial?2:1,lastCompleteness:options.partial?2:1}));
 const rows=['same-game','same-game','second-game'].map(canonicalId=>({canonicalId,sourceUuidHex:A}));
 let releaseLoad,releaseJournal,loadHeld=false,journalHeld=false;const loadGate=new Promise(r=>releaseLoad=r),journalGate=new Promise(r=>releaseJournal=r);
 let releaseScan,emitProgress;const scanGate=new Promise(r=>releaseScan=r);
 const store={async get(k,f){if(options.delayedList&&k===MAP&&!loadHeld){loadHeld=true;await loadGate;}return working.get(k)||f;},async put(k,v){working.set(k,v);},async flush(){calls.push('flush');if(options.delayedList&&!journalHeld&&JSON.parse(working.get(REMOVALS)||'[]').length){journalHeld=true;persisted=new Map(working);await journalGate;return;}if((options.failBeforeCommit||removed&&options.failCleanup)&&!flushFailed){flushFailed=true;throw Error('storage failed');}if(options.failRollback&&calls.includes('scan'))throw Error('rollback storage failed');persisted=new Map(working);}};
 const native={sourceRemove(id){calls.push('native-remove');if(options.failRemove)throw Error('native failed');const at=statuses.findIndex(s=>s.uuidHex===id);if(at<0)throw Error('not found');statuses.splice(at,1);removed=true;},sourceStatusList:()=>statuses,catalogSnapshot:()=>removed?[]:rows};
 const map=load('platform/HarmonySourceMap.ets',{'@kit.ArkData':{preferences:{getPreferences:async()=>store}},'@kit.ArkTS':{util:{generateRandomUUID:()=> 'd'.repeat(32)}}});
 const imports={canIUse:()=>options.folderSyscap!==false,'@ohos.deviceInfo':{default:{deviceType:options.deviceType||'2in1',sdkApiVersion:options.api||20}},'libentry.so':{default:native},'./ProductPolicy':load('flutter/ProductPolicy.ts'),'../platform/HarmonySourceMap':map,'../platform/HarmonyRomScan':{HarmonyRomScan:class{async scanDirectory(uuid,uri,scope,progress){calls.push('scan');if(options.holdScan){emitProgress=progress;progress({phase:2,processedFiles:0});await scanGate;}if(options.scanCancelled){progress({phase:4,processedFiles:1});throw Error('scan cancelled');}if(options.failScan)throw Error('scan failed');}cancelActiveScan(){return true;}}},'@kit.CoreFileKit':{picker:{DocumentSelectOptions:class{},DocumentSelectMode:{FILE:1,FOLDER:2},DocumentViewPicker:class{async select(){return options.cancelled?[]:['new-uri'];}}},fileShare:{OperationMode:{READ_MODE:1},async checkPersistentPermission(){calls.push('check');return [grants.has('new-uri')];},async persistPermission(){calls.push('persist');grants.add('new-uri');},async activatePermission(){calls.push('activate');active.add('new-uri');if(options.failActivate)throw Error('activate failed');},async deactivatePermission(){calls.push('deactivate');if(options.failDeactivate)throw Error('revoke failed');active.delete('new-uri');},async revokePermission(){calls.push('revoke');grants.delete('new-uri');}}}};
 const Owner=load('flutter/ProductSources.ets',imports).ProductSources,create=()=>new Owner({filesDir:'/files'},()=>calls.push('changed'));
 return {owner:create(),releaseScan,emitProgress:(value)=>emitProgress(value),calls,grants,active,statuses,releaseLoad,releaseJournal,savedMap:()=>JSON.parse(persisted.get(MAP)).sources,savedRemovals:()=>JSON.parse(persisted.get(REMOVALS)||'[]'),recreate(){working=new Map(persisted);return create();}};
}
test('native removal failure retains locator; successful commit deletes it',async()=>{const f=fixture({failRemove:true});await assert.rejects(f.owner.remove(A));assert.equal(f.savedMap()[0].uri,'old-uri');assert.equal(f.statuses.length,1);const ok=fixture();await ok.owner.remove(A);assert.equal(ok.savedMap().length,0);assert.equal(ok.statuses.length,0);});
test('committed removal cleanup failure survives recreation and reconciles without a second native removal',async()=>{const f=fixture({failCleanup:true});await assert.rejects(f.owner.remove(A),/source_cleanup_failed/);assert.equal(f.statuses.length,0);assert.deepEqual(f.savedRemovals(),[A]);const result=await f.recreate().list();assert.equal(result.items.some(s=>s.uuid===A),false);assert.equal(f.savedMap().length,0);assert.deepEqual(f.savedRemovals(),[]);assert.equal(f.calls.filter(c=>c==='native-remove').length,1);});
test('removal intent must persist before native commit',async()=>{const f=fixture({failBeforeCommit:true});await assert.rejects(f.owner.remove(A));assert.equal(f.calls.includes('native-remove'),false);assert.equal(f.statuses.length,1);assert.equal(f.savedMap()[0].uri,'old-uri');});
test('uncommitted removal intent retains source on restart',async()=>{const f=fixture({pending:true});const result=await f.owner.list();assert.equal(result.items.some(s=>s.uuid===A),true);assert.equal(f.savedMap()[0].uri,'old-uri');assert.deepEqual(f.savedRemovals(),[]);assert.equal(f.calls.includes('native-remove'),false);});
test('failed regrant restores locator and compensates newly acquired permission',async()=>{const f=fixture({failScan:true});await assert.rejects(f.owner.pick('folder',A));assert.equal(f.savedMap()[0].uri,'old-uri');assert.equal(f.grants.has('new-uri'),false);assert.equal(f.active.has('new-uri'),false);assert.ok(f.calls.indexOf('deactivate')>f.calls.indexOf('scan'));assert.ok(f.calls.indexOf('revoke')>f.calls.indexOf('deactivate'));});
test('activation failure compensates new permission before scan',async()=>{const f=fixture({failActivate:true});await assert.rejects(f.owner.pick('folder',A));assert.equal(f.grants.has('new-uri'),false);assert.equal(f.active.has('new-uri'),false);assert.equal(f.calls.includes('scan'),false);assert.equal(f.savedMap()[0].uri,'old-uri');});
test('failed regrant never revokes preexisting or shared permission',async()=>{for(const protectedGrant of [{persisted:true},{shared:true}]){const f=fixture({...protectedGrant,failScan:true});await assert.rejects(f.owner.pick('folder',A));assert.equal(f.grants.has('new-uri'),true);assert.equal(f.calls.includes('revoke'),false);assert.equal(f.calls.includes('deactivate'),false);assert.equal(f.savedMap()[0].uri,'old-uri');}});
test('failed locator rollback retains permission required by persisted registration',async()=>{const f=fixture({failScan:true,failRollback:true});await assert.rejects(f.owner.pick('folder',A),/source_reauthorize_cleanup_failed/);assert.equal(f.savedMap()[0].uri,'new-uri');assert.equal(f.grants.has('new-uri'),true);assert.equal(f.calls.includes('revoke'),false);});
test('successful regrant preserves UUID; cancellation mutates no permission',async()=>{const f=fixture();await f.owner.pick('folder',A);assert.deepEqual(f.savedMap(),[{uuid:A,uri:'new-uri'}]);const cancelled=fixture({cancelled:true});assert.equal((await cancelled.owner.pick('folder',A)).status,'cancelled');assert.equal(cancelled.calls.includes('persist'),false);});
test('source count is unique canonical games rather than variants',async()=>{const f=fixture();assert.equal((await f.owner.list()).items.find(s=>s.uuid===A).count,2);});

test('delayed list load cannot reconcile away an in-flight removal intent',async()=>{
 const f=fixture({delayedList:true});const listing=f.owner.list();await new Promise(setImmediate);
 const removing=f.owner.remove(A);await new Promise(setImmediate);f.releaseLoad();await listing;await new Promise(setImmediate);
 try {assert.deepEqual(f.savedRemovals(),[A],'journal remains durable until native removal commits');assert.equal(f.calls.includes('native-remove'),false);}
 finally {f.releaseJournal();await removing;}
 assert.equal(f.savedMap().length,0);assert.deepEqual(f.savedRemovals(),[]);
});

test('reselecting registered folder reuses UUID instead of duplicating source',async()=>{
 const f=fixture({shared:true});await f.owner.pick('folder');
 assert.deepEqual(f.savedMap(),[{uuid:A,uri:'old-uri'},{uuid:B,uri:'new-uri'}]);
});
test('missing locator projects unavailable with stable actionable permission reason',async()=>{
 const f=fixture({missingLocator:true});const row=(await f.owner.list()).items.find(s=>s.uuid===A);
 assert.equal(row.status,'unavailable');assert.equal(row.reason,'permission_required');assert.equal(row.canReauthorize,true);
});
test('retained stale entries after partial scan are projected as partial, not false ready',async()=>{
 const f=fixture({partial:true});const row=(await f.owner.list()).items.find(s=>s.uuid===A);
 assert.equal(row.status,'partial');assert.equal(row.count,2);
});

 test('cancelled rescan retains old library and reports cancellation rather than failure',async()=>{
 const f=fixture({scanCancelled:true});const result=await f.owner.scan(A);
 assert.equal(result.status,'cancelled');const row=(await f.owner.list()).items.find(s=>s.uuid===A);
 assert.equal(row.status,'cancelled');assert.equal(row.reason,'');assert.equal(row.count,2);assert.equal(f.savedMap()[0].uri,'old-uri');
});
test('cancelled reauthorization restores old locator and releases only new grant',async()=>{
 const f=fixture({scanCancelled:true});assert.equal((await f.owner.pick('folder',A)).status,'cancelled');
 assert.equal(f.savedMap()[0].uri,'old-uri');assert.equal(f.grants.has('new-uri'),false);assert.equal((await f.owner.list()).items[0].status,'cancelled');
});

test('cancelled scan cannot hide permission cleanup failure',async()=>{
 const f=fixture({scanCancelled:true,failDeactivate:true});await assert.rejects(f.owner.pick('folder',A),/source_reauthorize_cleanup_failed/);
 assert.equal(f.savedMap()[0].uri,'old-uri');assert.equal(f.grants.has('new-uri'),true);
 assert.equal((await f.owner.list()).items[0].reason,'source_reauthorize_cleanup_failed');
});

test('commit phase is completing and cancellation remains unavailable',async()=>{
 const f=fixture({holdScan:true});const scan=f.owner.scan(A);await new Promise(setImmediate);
 try { f.emitProgress({phase:6,processedFiles:2});const row=(await f.owner.list()).items[0];assert.equal(row.phase,'committing');assert.equal(row.canCancel,false);assert.throws(()=>f.owner.cancel(A,row.operationId),/cancellation_unavailable/); }
 finally {f.releaseScan();await scan;}
});
test('accepted cancel stays cancelling while worker acknowledges and cannot submit twice',async()=>{
 const f=fixture({holdScan:true});const scan=f.owner.scan(A);await new Promise(setImmediate);
 try { const first=(await f.owner.list()).items[0];f.owner.cancel(A,first.operationId);f.emitProgress({phase:2,processedFiles:1});const row=(await f.owner.list()).items[0];assert.equal(row.phase,'cancelling');assert.equal(row.canCancel,false);assert.throws(()=>f.owner.cancel(A,row.operationId),/cancellation_unavailable/); }
 finally {f.releaseScan();await scan;}
});

test('unsupported phone folder picker reports capability and rejects without mutation',async()=>{
 for(const options of [{deviceType:'phone',api:20},{deviceType:'tablet',api:20},{deviceType:'unknown',api:26},{folderSyscap:false}]) {
  const f=fixture(options);const before=JSON.stringify(f.savedMap());
  assert.equal((await f.owner.list()).folderSelection?.available,false);
  assert.equal((await f.owner.list()).folderSelection?.reason,'folder_selection_unsupported');
  await assert.rejects(f.owner.pick('folder'),/folder_selection_unsupported/);
  assert.equal(JSON.stringify(f.savedMap()),before);assert.equal(f.calls.includes('persist'),false);assert.equal(f.calls.includes('scan'),false);
 }
});
test('supported folder capability requires both public syscap and supported device API',async()=>{
 for(const options of [{deviceType:'2in1',api:20},{deviceType:'phone',api:26},{deviceType:'tablet',api:26}]) {
  const f=fixture(options);assert.equal((await f.owner.list()).folderSelection?.available,true);await f.owner.pick('folder');assert.equal(f.calls.includes('scan'),true);
 }
});
