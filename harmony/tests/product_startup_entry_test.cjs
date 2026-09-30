const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),test=require('node:test');
const ts=require('D:/soft/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
function boot(controlled,debug=false,want={}){
 const pages=[],state=new Map(controlled?[['ProductNativeBaseline',true]]:[]);
 class Ability {context={applicationInfo:{debug},config:{fontSizeScale:1},getApplicationContext:()=>({})};}
 const imports={'@kit.AbilityKit':{UIAbility:Ability},'@kit.PerformanceAnalysisKit':{hilog:{info(){}}},'@kit.ArkUI':{window:{Orientation:{AUTO_ROTATION_LANDSCAPE:0}}},'../ui/NearbyTestFontScale':{resolveTestFontSizeScale:()=>({accepted:false,rejection:''})},'@ohos/flutter_ohos':{FlutterManager:{getInstance:()=>({pushUIAbility(){},pushWindowStage(){}})}},'../flutter/FoundationProjection':{isFlutterFoundationRoute:()=>false}};
 const context={exports:{},console,require:n=>imports[n]||{},AppStorage:{get:k=>state.get(k),setOrCreate:(k,v)=>state.set(k,v)}};
 vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(__dirname,'../entry/src/main/ets/entryability/EntryAbility.ets'),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,context);
 const a=new context.exports.default();a.onCreate(want,{});a.onWindowStageCreate({getMainWindowSync:()=>({setPreferredOrientation(){},setWindowLayoutFullScreen(){},setWindowSystemBarEnable(){}}),loadContent:p=>pages.push(p)});return pages;
}
test('ordinary Release and debug start first product page in Flutter',()=>{for(const debug of [false,true])assert.deepEqual(boot(false,debug),['pages/FlutterFoundation']);});
test('Release external debug Want cannot enable native baseline',()=>assert.deepEqual(boot(false,false,{parameters:{'flynes.test.page':'native_baseline'}}),['pages/FlutterFoundation']));
test('in-process controlled baseline selects native before first loadContent',()=>assert.deepEqual(boot(true,false),['pages/GameCenter']));
