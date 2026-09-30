const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path'),test=require('node:test');
const ts=require('D:/soft/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
function fixture(fallback=false){
 const calls=[];let release;const gate=new Promise(r=>release=r);
 const io={OpenMode:{READ_ONLY:1,READ_WRITE:2,CREATE:4,TRUNC:8},
  async mkdir(){calls.push('mkdir');},async access(){return true;},async stat(){return {isDirectory:()=>true};},
  async copyFile(src,dst){calls.push([src,dst]);await gate;if(fallback&&typeof src==='string')throw Error('URI scheme requires descriptors');},
  async open(src){calls.push('open:'+src);return {fd:src.startsWith('file:')?10:11};},async close(file){calls.push('close:'+file.fd);},
  mkdirSync(){calls.push('sync-mkdir');},copyFileSync(){calls.push('sync-copy');},statSync(){throw Error('synchronous stat forbidden');},accessSync(){throw Error('synchronous access forbidden');}};
 const context={exports:{},console,require:n=>n==='@kit.CoreFileKit'?{fileIo:io}:{}};
 vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(__dirname,'../entry/src/main/ets/platform/HarmonyRomScan.ets'),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,context);
 return {scan:new context.exports.HarmonyRomScan(),calls,release};
}
for(const fallback of [false,true])test(`managed import yields to UI and uses async ${fallback?'descriptor fallback':'provider copy'}`,async()=>{
 const f=fixture(fallback);let settled=false;
 const importing=Promise.resolve().then(()=>f.scan.importDocumentUris(['file://docs/fixture.nes'],'/roms')).finally(()=>settled=true);
 await new Promise(setImmediate);assert.equal(settled,false,'copy must remain pending while provider IO is pending');
 f.release();assert.equal(await importing,1);
 if(fallback){assert.ok(f.calls.some(x=>Array.isArray(x)&&x[0]===10&&x[1]===11));assert.ok(f.calls.includes('close:10'));assert.ok(f.calls.includes('close:11'));}
});
