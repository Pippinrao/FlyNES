"""Business checks for the same-revision Harmony G2 native size control."""
import importlib.util
import pathlib
import subprocess
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location(
    'native_size', ROOT / 'tools/flutter/prepare_native_size_baseline.py')
baseline = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(baseline)


class HarmonyG2SizeControlTest(unittest.TestCase):
    def source(self):
        edit = baseline.G2_HARMONY_EDIT_PATHS
        remove = baseline.G2_HARMONY_REMOVE_PATHS
        files = set(edit) | set(remove) | {
            'harmony/entry/build-profile.json5',
            'harmony/entry/src/main/cpp/napi_init.cpp',
            'harmony/entry/src/main/cpp/harmony_renderer.cpp',
            'harmony/entry/src/main/ets/service/SaveHistoryService.ets',
        }
        return {name: (ROOT / name).read_bytes() for name in files}

    def test_native_control_is_buildable_route_and_preserves_bottom_layer(self):
        source = self.source()
        result = baseline.harmony_g2_native_only(source)
        self.assertEqual(set(source) - set(result), set(baseline.G2_HARMONY_REMOVE_PATHS))
        for name in ('harmony/entry/src/main/cpp/napi_init.cpp',
                     'harmony/entry/src/main/cpp/harmony_renderer.cpp',
                     'harmony/entry/src/main/ets/service/SaveHistoryService.ets'):
            self.assertEqual(result[name], source[name], name)
        entry = result['harmony/entry/src/main/ets/entryability/EntryAbility.ets']
        self.assertIn(b"private testPage: string = 'pages/GameCenter'", entry)
        self.assertIn(b'nativeApp.appOpen', entry)
        self.assertNotIn(b'FlutterManager', entry)
        self.assertNotIn(b'flutter_texture_probe', entry)
        self.assertIn(b"pages/Settings", result['harmony/entry/src/main/ets/pages/RunGame.ets'])
        self.assertIn(b"pages/GameCenter", result['harmony/entry/src/main/ets/pages/NearbyLobby.ets'])
        for name, data in result.items():
            if name.endswith(('.ets', '.ts')) and name.startswith('harmony/entry/src/main/ets/'):
                self.assertNotIn(b'@ohos/flutter', data, name)
                self.assertNotIn(b'FlutterFoundation', data, name)
        self.assertEqual(baseline.review_changes(source, result, recipe='harmony-g2')[0][0]['action']
                         in ('modify', 'delete'), True)

    def test_changed_native_navigation_anchor_fails_closed(self):
        source = self.source()
        key = 'harmony/entry/src/main/ets/pages/RunGame.ets'
        source[key] = source[key].replace(b"url: 'pages/FlutterFoundation'",
                                          b"url: 'pages/UnknownPage'", 1)
        with self.assertRaisesRegex(ValueError, 'Source drift|navigation'):
            baseline.harmony_g2_native_only(source)

    def test_changed_redirect_logic_fails_closed(self):
        source = self.source()
        key = 'harmony/entry/src/main/ets/flutter/ProductRoutes.ets'
        source[key] = source[key].replace(b'return true;', b'return false;', 1)
        with self.assertRaisesRegex(ValueError, 'Product route source drift'):
            baseline.harmony_g2_native_only(source)

    def test_normal_entry_sets_native_mode_before_loading_control_page(self):
        source = self.source()
        entry = baseline.harmony_g2_native_only(source)[
            'harmony/entry/src/main/ets/entryability/EntryAbility.ets']
        node = r'''
const fs=require('node:fs'),vm=require('node:vm');
const ts=require('D:/soft/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const events=[],store=new Map(),AppStorage={setOrCreate:(k,v)=>{store.set(k,v);events.push(`flag:${v}`)},get:k=>store.get(k)};
class UIAbility{constructor(){this.context={applicationInfo:{debug:false},filesDir:'/files',cacheDir:'/cache',config:{},getApplicationContext:()=>({setFontSizeScale(){}}),eventHub:{emit(){}}}}}
const imports={'@kit.AbilityKit':{UIAbility},'@kit.PerformanceAnalysisKit':{hilog:{info(){}}},
'@kit.ArkUI':{window:{Orientation:{AUTO_ROTATION_LANDSCAPE:1}}},
'../ui/NearbyTestFontScale':{resolveTestFontSizeScale:()=>({accepted:false,rejection:''})},
'../service/ProductStartupObservation':{ProductStartupObservation:{ownerReady:()=>events.push('ready')}},
'libentry.so':{default:{appOpen:()=>events.push('open')}}};
const ctx={exports:{},console,AppStorage,require:name=>imports[name]||{}};
vm.runInNewContext(ts.transpileModule(fs.readFileSync(0,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,ctx);
const ability=new ctx.exports.default(); ability.onCreate({parameters:{}},{});
ability.onWindowStageCreate({getMainWindowSync:()=>({setPreferredOrientation(){},setWindowLayoutFullScreen(){},setWindowSystemBarEnable(){}}),loadContent:p=>events.push(`load:${p}`)});
if(!store.get('ProductNativeBaseline')||events.indexOf('flag:true')>events.indexOf('load:pages/GameCenter')||events.indexOf('open')>events.indexOf('load:pages/GameCenter')) throw Error(events.join(','));
console.log(events.join(','));
'''
        run = subprocess.run(['D:/soft/DevEco Studio/tools/node/node.exe', '-e', node],
                             input=entry, capture_output=True)
        self.assertEqual(run.returncode, 0, run.stderr.decode(errors='replace'))


if __name__ == '__main__':
    unittest.main()
