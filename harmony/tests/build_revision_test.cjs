const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),test=require('node:test'),{execFileSync}=require('node:child_process');
const ts=require('D:/soft/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
function load(file,imports){const ctx={exports:{},Buffer,require:n=>imports?imports[n]||{}:require(n)};vm.runInNewContext(ts.transpileModule(fs.readFileSync(file,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,ctx);return ctx.exports;}
function submoduleFixture(){
 const base=fs.mkdtempSync(path.resolve(__dirname,'../../.artifacts/flutter-g2/harmony/submodule-revision-'));
 const git=(repo,...args)=>execFileSync('git',['-C',repo,...args],{encoding:'utf8',stdio:['ignore','pipe','pipe']}).trim();
 const commit=repo=>{git(repo,'add','.');git(repo,'-c','user.name=Fixture','-c','user.email=fixture@example.invalid','-c','commit.gpgsign=false','commit','--allow-empty','-qm','fixture');return git(repo,'rev-parse','HEAD');};
 const create=name=>{const repo=path.join(base,name);fs.mkdirSync(repo);git(repo,'init','-q');fs.writeFileSync(path.join(repo,'.gitignore'),'evidence/\nbuild-revision.json\n');fs.writeFileSync(path.join(repo,'source.cpp'),'source one\n');return repo;};
 const nested=create('nested');commit(nested);const vendor=create('vendor');
 git(vendor,'-c','protocol.file.allow=always','submodule','add','-q',nested,'nested');const first=commit(vendor),second=commit(vendor);
 const repo=create('root');git(repo,'-c','protocol.file.allow=always','submodule','add','-q',vendor,'vendor');commit(repo);
 git(repo,'-c','protocol.file.allow=always','submodule','update','--init','--recursive');
 const checkout=path.join(repo,'vendor'),leaf=path.join(checkout,'nested'),head=git(repo,'rev-parse','HEAD');
 const {writeBuildRevision}=load(path.join(__dirname,'../build-revision.ts'));const output=path.join(repo,'build-revision.json');
 const record=()=>{writeBuildRevision(repo,output);const value=JSON.parse(fs.readFileSync(output,'utf8'));assert.equal(value.sourceRevision,head);return value;};
 return {git,repo,checkout,leaf,first,second,head,record};
}
test('submodule checkout identity fingerprints distinct commits even when source bytes match',()=>{
 const f=submoduleFixture(),second=f.record();f.git(f.checkout,'checkout','-q',f.first);const first=f.record();
 assert.notEqual(first.sourceFingerprint,second.sourceFingerprint);assert.equal(first.dirty,true);
 f.git(f.checkout,'checkout','-q',f.second);assert.deepEqual(f.record(),second);
});
test('dirty submodule source states change the fingerprint while ignored evidence does not',()=>{
 const f=submoduleFixture(),clean=f.record();fs.writeFileSync(path.join(f.checkout,'source.cpp'),'dirty one\n');const first=f.record();
 assert.notEqual(first.sourceFingerprint,clean.sourceFingerprint);fs.writeFileSync(path.join(f.checkout,'source.cpp'),'dirty two\n');const second=f.record();assert.notEqual(second.sourceFingerprint,first.sourceFingerprint);
 fs.mkdirSync(path.join(f.checkout,'evidence'));fs.writeFileSync(path.join(f.checkout,'evidence','local.log'),'ignored local evidence');assert.deepEqual(f.record(),second);
});
test('nested submodule tracked and untracked source changes participate recursively',()=>{
 const f=submoduleFixture(),clean=f.record();fs.writeFileSync(path.join(f.leaf,'source.cpp'),'nested dirty\n');const tracked=f.record();
 assert.notEqual(tracked.sourceFingerprint,clean.sourceFingerprint);fs.writeFileSync(path.join(f.leaf,'new.cpp'),'nested untracked\n');const untracked=f.record();assert.notEqual(untracked.sourceFingerprint,tracked.sourceFingerprint);
 fs.mkdirSync(path.join(f.leaf,'evidence'));fs.writeFileSync(path.join(f.leaf,'evidence','local.log'),'ignored nested evidence');assert.deepEqual(f.record(),untracked);
});
test('host revision is deterministic, identifies uncommitted source, excludes ignored evidence, and refreshes after commit',()=>{
 const root=path.resolve(__dirname,'../../.artifacts/flutter-g2/harmony');const repo=fs.mkdtempSync(path.join(root,'revision-fixture-'));
 const git=(...args)=>execFileSync('git',['-C',repo,...args],{encoding:'utf8'}).trim();
 git('init','-q');fs.writeFileSync(path.join(repo,'.gitignore'),'build-revision.json\nevidence/\n');fs.writeFileSync(path.join(repo,'source.ts'),'export const value=1;\n');
 git('add','.');git('-c','user.name=Fixture','-c','user.email=fixture@example.invalid','-c','commit.gpgsign=false','commit','-qm','fixture');
 const {writeBuildRevision}=load(path.join(__dirname,'../build-revision.ts'));const output=path.join(repo,'build-revision.json');const head=git('rev-parse','HEAD');
 assert.equal(writeBuildRevision(repo,output),head);const clean=fs.readFileSync(output,'utf8');assert.equal(writeBuildRevision(repo,output),head);assert.equal(fs.readFileSync(output,'utf8'),clean);
 fs.mkdirSync(path.join(repo,'evidence'));fs.writeFileSync(path.join(repo,'evidence','log'),'private local evidence');assert.equal(writeBuildRevision(repo,output),head);assert.equal(fs.readFileSync(output,'utf8'),clean);
 fs.writeFileSync(path.join(repo,'new-source.ts'),'export const added=true;\n');const dirty=writeBuildRevision(repo,output);assert.match(dirty,new RegExp(`^${head}-dirty\\.[a-f0-9]{12}$`));assert.equal(writeBuildRevision(repo,output),dirty);
 fs.writeFileSync(path.join(repo,'new-source.ts'),'export const added=false;\n');assert.notEqual(writeBuildRevision(repo,output),dirty);
 git('add','.');git('-c','user.name=Fixture','-c','user.email=fixture@example.invalid','-c','commit.gpgsign=false','commit','-qm','next fixture');assert.equal(writeBuildRevision(repo,output),git('rev-parse','HEAD'));assert.notEqual(writeBuildRevision(repo,output),head);
});
test('host reader exposes only valid generated revisions and reports unavailable on missing or malformed resources',async()=>{
 const {productBuildRevision}=load(path.join(__dirname,'../entry/src/main/ets/flutter/ProductBuildInfo.ets'),{'@kit.ArkTS':{util:{TextDecoder:{create:()=>({decodeWithStream:raw=>Buffer.from(raw).toString('utf8')})}}}});
 const revision='a'.repeat(40)+'-dirty.'+'b'.repeat(12);
 const context=body=>({resourceManager:{getRawFileContent:async name=>{assert.equal(name,'build-revision.json');return Buffer.from(body);}}});
 assert.equal(await productBuildRevision(context(JSON.stringify({buildRevision:revision}))),revision);
 assert.equal(await productBuildRevision(context('{"buildRevision":"fake"}')),'');assert.equal(await productBuildRevision(context('invalid-json')),'');
 assert.equal(await productBuildRevision({resourceManager:{getRawFileContent:async()=>{throw Error('missing');}}}),'');
});
