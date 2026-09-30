const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),test=require('node:test');
const ts=require('D:/soft/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
function load(file,imports={},runtime={}) {const ctx={exports:{},console,setTimeout,clearTimeout,setInterval,clearInterval,...runtime,require:n=>imports[n]||{}};vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(__dirname,'../entry/src/main/ets/',file),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,ctx);return ctx.exports;}
function fixture(options={}) {
 let layout='recommended';
 let settings={audioEnabled:1,buttonScale:1.8,deadZone:.27,localeTag:'en'};const pushed=[], events=[];const reads=[],replies=[];let holdRead=false, poll=()=>{};
 const row={canonicalId:'content-id',titleEn:'Fixture',titleZhHans:'',sourceUuidHex:'a'.repeat(32),sourceRelativePath:'fixture.nes',packageFormat:0,originalFilename:'fixture.nes',available:true,multiplayerSupported:options.supported!==false};
 const imports={'@kit.AbilityKit':{bundleManager:{BundleFlag:{GET_BUNDLE_INFO_DEFAULT:0},getBundleInfoForSelf:async()=>({versionName:'3.0.6'})}},'@kit.ArkUI':{router:{pushUrl:async(value)=>pushed.push(value),getLength:()=>2,back(){}}},'@kit.ArkTS':{util:{generateRandomUUID:()=> 'process'}},'@kit.LocalizationKit':{i18n:{System:{getSystemLanguage:()=> 'en'}}},'@kit.ArkData':{preferences:{getPreferences:async()=>({get:async(k,d)=>d,put:async()=>{},flush:async()=>{}})}},'libentry.so':{default:{settingsGet:()=>settings,settingsApply:value=>{if(options.failSettings)throw new Error('write_failed');settings=value;},controlLayoutGet:()=>layout,controlLayoutRecommended:()=> 'recommended',controlLayoutApply:value=>layout=value,historyContentKey:()=> 'hash-key',nearbyMvpSnapshot:()=>({state:0})}},'./ProductPolicy':load('flutter/ProductPolicy.ts'),'./ProductBuildInfo':{productBuildRevision:async()=> '1234567890abcdef1234567890abcdef12345678'},'./ProductSources':{ProductSources:class{}},'./ProductCatalog':{ProductCatalog:class{async initialize(){}canonical(id){return id;}legacy(id){return id;}async row(){return row;}async item(){return row;}}},'../service/PlayService':{builtinGamesSync:()=>({}),takeRomOpenError:()=> '',RomLaunchLocator:class{},PlayService:class{async readRom(){if(holdRead)await new Promise(resolve=>reads.push(resolve));return new Uint8Array(8);}}},'../service/SaveHistoryService':{SaveHistoryService:class{hasResume(){return true;}}},'../service/CheckpointStore':{CheckpointStore:class{}},'../service/CatalogProductService':{localizedGameTitle:()=> 'Fixture'},'../service/NearbyRoomGame':{nearbyRoomGame:{select(){}}},'../pages/LicenseModel':{LicenseModel:{byFileName:()=>undefined}}};
 let nearby={role:1,state:options.nearbyState??0,roomGeneration:1};const mutations=[];let releaseSelect;
 Object.assign(imports['libentry.so'].default,{
  nearbyMvpSnapshot:()=>nearby,
  nearbyMvpReturnLobby:()=>{mutations.push('returnLobby');nearby={...nearby,role:1,state:7};return true;},
  nearbyMvpSelectGame:()=>{mutations.push('sync-select');return true;},
  nearbyMvpSelectGameAsync:async(_rom,_key,roomGeneration)=>{mutations.push('select');if(options.blockSelect)await new Promise(resolve=>releaseSelect=resolve);if(nearby.roomGeneration===roomGeneration)nearby={...nearby,state:5};return {selected:true,roomGeneration,status:'selected'};},
  nearbyMvpConfirm:()=>{mutations.push('confirm');return true;}
 });
 imports['@kit.ArkUI'].router.back=()=>mutations.push('back');
 imports['../service/NearbyRoomGame'].nearbyRoomGame.select=()=>mutations.push('room');
 const {ProductChannelHandler}=load('flutter/ProductChannelHandler.ets',imports,{setInterval:fn=>{poll=fn;return 1;},clearInterval:()=>{poll=()=>{};}});
 const handler=new ProductChannelHandler({filesDir:'/files',cacheDir:'/cache'}, {invokeMethod:(...value)=>events.push(value)});
 let generation=handler.attach({route:'hall',purpose:'single',returnToken:'hall'},undefined,options.beforeNative);let sequence=0;
 function call(method,args={}) {const envelope={...args,hostGeneration:generation,requestId:++sequence};return new Promise(resolve=>handler.onMethodCall({method,argument:k=>envelope[k]??null},{success:value=>{replies.push({id:envelope.requestId,value});resolve({value});},error:code=>{replies.push({id:envelope.requestId,code});resolve({code});}}));}
 return {handler,call,pushed,events,mutations,replies,setLayout:value=>layout=value,releaseSelect:()=>releaseSelect(),replaceRoom:()=>nearby={role:1,state:3,roomGeneration:nearby.roomGeneration+1},poll:()=>poll(),sameHost(){handler.detach(generation);generation=handler.attach({route:'hall',purpose:'nearby',returnToken:'hall'});},playing:()=>nearby={...nearby,role:1,state:6,paused:false},readyLobby:()=>nearby={...nearby,role:1,state:3},get settings(){return settings;},hold:()=>holdRead=true,resume:()=>reads.shift()(),switchHost(){handler.detach(generation);generation=handler.attach({route:'settings',purpose:'single',returnToken:'settings'});}};
}
test('product reply includes host envelope and canonical item directly',async()=>{const f=fixture();const r=await f.call('catalogItem',{canonicalId:'content-id'});assert.equal(r.value.canonicalId,'content-id');assert.equal(r.value.instanceId,'process');assert.equal(r.value.hostGeneration,1);assert.ok(r.value.requestId>0);});
test('presentation context is available before catalog and only current positive raster opens its host',async()=>{
 const f=fixture();let shown=0;f.handler.detach(1);
 f.handler.catalog.initialize=async()=>{throw new Error('catalog unavailable');};
 const generation=f.handler.attach({route:'settings',purpose:'single',returnToken:'same'},()=>shown++);
 async function invoke(method,args={}) {return new Promise(resolve=>f.handler.onMethodCall({method,argument:k=>({requestId:900,hostGeneration:generation,...args})[k]??null},{success:value=>resolve({value}),error:code=>resolve({code})}));}
 const safe=await invoke('presentationContext');assert.ok(safe.value?.context?.presentationToken,'failure UI must receive target without catalog');
 const token=safe.value.context.presentationToken;
 assert.equal(safe.value.context.route,'settings');assert.equal(shown,0);
 assert.equal((await invoke('presentationReady',{token:'old',frameNumber:1})).code,'stale_host');assert.equal(shown,0);
 assert.equal((await invoke('presentationReady',{token,frameNumber:0})).code,'invalid_argument');assert.equal(shown,0);
 assert.equal((await invoke('presentationReady',{token,frameNumber:20})).value.accepted,true);assert.equal(shown,1);
 await invoke('presentationReady',{token,frameNumber:21});assert.equal(shown,1,'duplicate raster cannot repeat host reveal');
 f.handler.detach(generation);assert.equal((await invoke('presentationReady',{token,frameNumber:22})).code,'stale_host');
 f.handler.attach({route:'settings',purpose:'single',returnToken:'same'},()=>shown++);
 const last=f.events.filter(e=>e[0]==='contextChanged').at(-1)[1];assert.notEqual(last.context.presentationToken,token,'same return route must receive a fresh presentation identity');
});
test('native latest scalar merge preserves layout and returns authoritative boolean',async()=>{const f=fixture();const r=await f.call('patchSetting',{key:'audioEnabled',value:false});assert.equal(r.value.values.audioEnabled,false);assert.equal(f.settings.buttonScale,1.8);assert.equal(f.settings.deadZone,.27);});
test('a replaced host cannot launch after its asynchronous ROM read completes',async()=>{const f=fixture();f.hold();const result=f.call('launch',{canonicalId:'content-id',purpose:'single'});await new Promise(setImmediate);f.switchHost();f.resume();await new Promise(setImmediate);assert.equal(f.pushed.length,0);await result;});
test('license reader rejects path traversal before touching resources',async()=>{const f=fixture();assert.equal((await f.call('licenseText',{id:'../../private'})).code,'invalid_argument');});
test('nearby return-to-lobby wait cannot mutate or navigate a replacement host',async()=>{
 const f=fixture({nearbyState:6});const result=f.call('launch',{canonicalId:'content-id',purpose:'nearby'});
 await new Promise(setImmediate);assert.deepEqual(f.mutations,['returnLobby']);
 f.switchHost();f.readyLobby();await result;
 assert.deepEqual(f.mutations,['returnLobby']);assert.equal(f.pushed.length,0);
});
test('unsupported nearby item is rejected before any session mutation',async()=>{
 const f=fixture({nearbyState:3,supported:false});const result=await f.call('launch',{canonicalId:'content-id',purpose:'nearby'});
 assert.equal(result.value.status,'unavailable');assert.deepEqual(f.mutations,[]);
});

test('old same-token launch completion preserves the new pending request and selection guard',async()=>{
 const f=fixture({nearbyState:3});f.hold();const old=f.call('launch',{canonicalId:'content-id',purpose:'nearby'});await new Promise(setImmediate);
 f.sameHost();await old;const current=f.call('launch',{canonicalId:'content-id',purpose:'nearby'});await new Promise(setImmediate);
 f.resume();await new Promise(setImmediate);
 assert.equal(f.replies.filter(r=>r.id===1).length,1,'old request replies exactly once');
 const overlap=await f.call('launch',{canonicalId:'content-id',purpose:'nearby'});assert.equal(overlap.code,'route_busy');
 f.playing();f.poll();assert.deepEqual(f.mutations,[],'old finally must not release the current selection guard');
 f.readyLobby();f.resume();await current;assert.deepEqual(f.mutations,['select','confirm','room','back']);
 assert.equal(f.replies.filter(r=>r.id===2).length,1);
});

test('bootstrap publishes the generated host build revision',async()=>{const f=fixture();assert.equal((await f.call('bootstrap')).value.buildRevision,'1234567890abcdef1234567890abcdef12345678');});

test('blocked nearby select leaves main callbacks responsive and confirms only after completion',async()=>{
 const f=fixture({nearbyState:3,blockSelect:true});const launch=f.call('launch',{canonicalId:'content-id',purpose:'nearby'});await new Promise(setImmediate);
 assert.deepEqual(f.mutations,['select']);const settings=await f.call('settings');assert.equal(settings.value.values.audioEnabled,true);
 f.releaseSelect();await launch;assert.deepEqual(f.mutations,['select','confirm','room','back']);
});
test('host replacement during native select suppresses confirm, room metadata and navigation',async()=>{
 const f=fixture({nearbyState:3,blockSelect:true});const launch=f.call('launch',{canonicalId:'content-id',purpose:'nearby'});await new Promise(setImmediate);assert.deepEqual(f.mutations,['select']);
 f.switchHost();f.releaseSelect();await launch;assert.deepEqual(f.mutations,['select']);
});
test('room replacement during native select suppresses followups even with unchanged host lease',async()=>{
 const f=fixture({nearbyState:3,blockSelect:true});const launch=f.call('launch',{canonicalId:'content-id',purpose:'nearby'});await new Promise(setImmediate);assert.deepEqual(f.mutations,['select']);
 f.replaceRoom();f.releaseSelect();await launch;assert.deepEqual(f.mutations,['select']);
});
test('room replacement during ROM read never selects the replacement room',async()=>{
 const f=fixture({nearbyState:3});f.hold();const launch=f.call('launch',{canonicalId:'content-id',purpose:'nearby'});await new Promise(setImmediate);
 f.replaceRoom();f.resume();await launch;assert.deepEqual(f.mutations,[]);
});

test('settings projects saved native layout and rereads its owner after editor mutation', async()=>{
 const f=fixture(); assert.equal((await f.call('settings')).value.layoutSummary,'recommended');
 f.setLayout('edited'); assert.equal((await f.call('settings')).value.layoutSummary,'custom');
});
test('failed second reset write still exposes the first persisted layout on authoritative read', async()=>{
 const f=fixture({failSettings:true});f.setLayout('edited');
 assert.equal((await f.call('resetControls')).code,'operation_failed');
 const actual=(await f.call('settings')).value;
 assert.equal(actual.layoutSummary,'recommended');assert.equal(actual.values.audioEnabled,true);
});
test('native game launch waits for a valid outgoing picture and rechecks the host after capture',async()=>{
 let ready;const f=fixture({beforeNative:()=>new Promise(resolve=>ready=resolve)});
 const launch=f.call('launch',{canonicalId:'content-id',purpose:'single'});await new Promise(setImmediate);
 assert.equal(f.pushed.length,0,'router cannot hide the only valid Flutter surface before its picture is retained');
 f.switchHost();ready();await launch;assert.equal(f.pushed.length,0);
});
test('capture failure returns the existing localized launch error and keeps the hall retryable',async()=>{
 const f=fixture({beforeNative:async()=>{throw Error('capture failed');}});
 const pending=f.call('launch',{canonicalId:'content-id',purpose:'single'});await new Promise(setImmediate);
 assert.equal(f.pushed.length,0,'failed capture must keep the visible hall');
 const result=await pending;
 assert.equal(result.value.status,'unavailable');assert.equal(result.value.reason,'launch_unavailable');assert.equal(f.pushed.length,0);
});
test('valid outgoing picture admits a single native push and keeps the original return token',async()=>{
 let ready;const f=fixture({beforeNative:()=>new Promise(resolve=>ready=resolve)});
 const launch=f.call('launch',{canonicalId:'content-id',purpose:'single'});await new Promise(setImmediate);assert.equal(f.pushed.length,0);
 ready();await new Promise(setImmediate);assert.equal(f.pushed.length,1);assert.equal(f.pushed[0].url,'pages/RunGame');assert.equal(f.pushed[0].params.foundationReturn,true);
 f.sameHost();assert.equal((await launch).value.status,'returned');
});
for(const page of ['layout','nearby'])test(`${page} native route waits for capture and rejects a replaced host`,async()=>{
 let ready;const f=fixture({beforeNative:()=>new Promise(resolve=>ready=resolve)});
 const result=f.call('openNative',{page});await new Promise(setImmediate);
 assert.equal(f.pushed.length,0,'every Flutter-to-native push needs the retained outgoing frame');
 f.switchHost();ready();await result;assert.equal(f.pushed.length,0);
});
test('native editor capture failure keeps the Flutter page and returns a retryable error',async()=>{
 const f=fixture({beforeNative:async()=>{throw Error('capture failed');}});
 const pending=f.call('openNative',{page:'layout'});await new Promise(setImmediate);
 assert.equal(f.pushed.length,0);assert.equal((await pending).code,'route_unavailable');
});
