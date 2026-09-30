"""Prepare a reviewable, same-revision native-only Release size baseline.

This tool exports committed objects only; it never builds, installs, signs,
copies local configuration, edits the checkout, or measures package sizes.
"""
import argparse
import difflib
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import tarfile


REQUIRED_NATIVE_ANCESTOR = "c0511d6911d31f86f3ec2987b736cde02780291b"
SUBMODULE = "core/vendor/nestopiaue"
JAVA = "app/src/main/java/com/flynes/emu/"
ETS = "harmony/entry/src/main/ets/"
EDIT_PATHS = (
    "settings.gradle", "app/build.gradle", "app/src/main/AndroidManifest.xml",
    JAVA + "FlyNesApplication.java", JAVA + "HomeActivity.java", JAVA + "MainActivity.java",
    "harmony/hvigorfile.ts", "harmony/oh-package.json5",
    "harmony/entry/oh-package.json5", "harmony/entry/oh-package-lock.json5",
    ETS + "entryability/EntryAbility.ets",
    "harmony/entry/src/main/resources/base/profile/main_pages.json",
)
REMOVE_PATHS = (
    JAVA + "FlutterFoundationActivity.java", JAVA + "FoundationBridge.java",
    JAVA + "flutter/FoundationTextureProbe.java", "harmony/flutter-har-guard.ts",
    ETS + "pages/FlutterFoundation.ets", ETS + "pages/FlutterTextureProbe.ets",
    *(ETS + "flutter/" + name for name in (
        "FoundationChannelHandler.ets", "FoundationFlutterEntry.ets", "FoundationProjection.ts",
        "FoundationRouteOwner.ts", "FoundationTextureEntry.ets", "FoundationTextureHandler.ets")),
)
HAR_PACKAGES = frozenset(("@ohos/flutter_ohos", "@ohos/flutter_module",
                          "flutter_native_arm64_v8a", "flutter_native_x86_64"))
G2_ANDROID_EDIT_PATHS = (
    'settings.gradle', 'app/build.gradle', 'app/src/main/AndroidManifest.xml',
    *(JAVA + name for name in ('FlyNesApplication.java', 'ProductRoutes.java',
                               'MainActivity.java', 'HomeActivity.java', 'NearbyLobbyActivity.java')),
)
G2_ANDROID_REMOVE_PATHS = (
    *(JAVA + name for name in ('FlutterFoundationActivity.java', 'FoundationBridge.java',
                               'ProductBridge.java', 'flutter/FoundationTextureProbe.java')),
)
G2_HARMONY_EDIT_PATHS = (
    'harmony/hvigorfile.ts', 'harmony/oh-package.json5',
    'harmony/entry/oh-package.json5', 'harmony/entry/oh-package-lock.json5',
    ETS + 'entryability/EntryAbility.ets',
    'harmony/entry/src/main/resources/base/profile/main_pages.json',
    ETS + 'flutter/ProductRoutes.ets', ETS + 'pages/RunGame.ets',
    ETS + 'pages/NearbyLobby.ets',
)
G2_HARMONY_REMOVE_PATHS = (
    'harmony/flutter-har-guard.ts',
    ETS + 'pages/FlutterFoundation.ets', ETS + 'pages/FlutterTextureProbe.ets',
    *(ETS + 'flutter/' + name for name in (
        'ProductSources.ets', 'ProductPolicy.ts', 'ProductHandoffBackdrop.ets',
        'ProductChannelHandler.ets', 'ProductCatalog.ets', 'ProductBuildInfo.ets',
        'FoundationTextureHandler.ets', 'FoundationTextureEntry.ets',
        'FoundationRouteOwner.ts', 'FoundationProjection.ts',
        'FoundationFlutterEntry.ets', 'FoundationChannelHandler.ets')),
)


def harmony_g2_native_only(source):
    """Strip G2 Flutter transport for a same-bottom-revision native HAP."""
    result = dict(source)
    for path in (*G2_HARMONY_EDIT_PATHS, *G2_HARMONY_REMOVE_PATHS):
        if path not in source:
            raise ValueError(f'Required source missing: {path}')
    if 'harmony/entry/build-profile.json5' not in source:
        raise ValueError('Required Harmony ABI profile missing')
    crlf = set()
    for path in G2_HARMONY_EDIT_PATHS:
        data = source[path]
        if b'\r\n' in data:
            if b'\n' in data.replace(b'\r\n', b''):
                raise ValueError(f'Mixed source line endings require review: {path}')
            crlf.add(path)
            result[path] = data.replace(b'\r\n', b'\n')
    abis = json.loads(source['harmony/entry/build-profile.json5'])[
        'buildOption']['externalNativeOptions']['abiFilters']
    if abis != ['arm64-v8a', 'x86_64']:
        raise ValueError('Harmony ABI configuration changed')

    def replace(path, old, new='', count=1):
        text = result[path].decode('utf-8')
        if text.count(old) != count:
            raise ValueError(f'Source drift in {path}: expected {count} exact navigation anchor(s)')
        result[path] = text.replace(old, new).encode('utf-8')

    def replace_block(path, pattern, replacement, expected_hash):
        text = result[path].decode('utf-8')
        matches = list(re.finditer(pattern, text))
        if len(matches) != 1 or sha256(matches[0].group().encode()) != expected_hash:
            raise ValueError(f'Source drift in {path}: navigation block requires review')
        match = matches[0]
        result[path] = (text[:match.start()] + replacement + text[match.end():]).encode('utf-8')

    hvigor = 'harmony/hvigorfile.ts'
    replace(hvigor, 'import { appTasks, OhosAppContext, OhosPluginId } from \'@ohos/hvigor-ohos-plugin\';',
            'import { appTasks } from \'@ohos/hvigor-ohos-plugin\';')
    replace(hvigor, "import { verifyFlutterHarStage } from './flutter-har-guard';\n")
    replace(hvigor, '  const context = node.getContext(OhosPluginId.OHOS_APP_PLUGIN) as OhosAppContext;\n'
            "  verifyFlutterHarStage(join(__dirname, '.artifacts/flutter-har'), context.getBuildMode());\n")
    replace(hvigor, '// A host build may consume only the exact mode and bytes staged by Build-Ohos.\n')
    replace(hvigor, 'afterNodeEvaluate(node => {', 'afterNodeEvaluate(_node => {')
    for path, section in (('harmony/oh-package.json5', 'overrides'),
                          ('harmony/entry/oh-package.json5', 'dependencies')):
        data = json.loads(result[path])
        if not HAR_PACKAGES.issubset(data[section]):
            raise ValueError(f'HAR dependency drift in {path}')
        for name in HAR_PACKAGES:
            del data[section][name]
        result[path] = (json.dumps(data, indent=2, ensure_ascii=False) + '\n').encode()
    lock_path = 'harmony/entry/oh-package-lock.json5'
    lock = json.loads(result[lock_path])
    for section in ('specifiers', 'packages'):
        removed = [key for key in lock[section] if any(key.startswith(name + '@') for name in HAR_PACKAGES)]
        if len(removed) != 4:
            raise ValueError(f'HAR lock drift in {lock_path}')
        for key in removed:
            del lock[section][key]
    result[lock_path] = (json.dumps(lock, indent=2, ensure_ascii=False) + '\n').encode()

    entry = ETS + 'entryability/EntryAbility.ets'
    replace(entry, "import { ExclusiveAppComponent, FlutterManager } from '@ohos/flutter_ohos';\n")
    replace(entry, "import { isFlutterFoundationRoute } from '../flutter/FoundationProjection';\n")
    replace(entry, ' extends UIAbility implements ExclusiveAppComponent<UIAbility>', ' extends UIAbility')
    replace(entry, "private testPage: string = 'pages/FlutterFoundation'", "private testPage: string = 'pages/GameCenter'")
    replace(entry, '  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {\n',
            "  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {\n"
            "    AppStorage.setOrCreate('ProductNativeBaseline', true);\n")
    for line in ('    FlutterManager.getInstance().pushUIAbility(this);\n',
                 '    FlutterManager.getInstance().pushWindowStage(this, windowStage);\n',
                 '    FlutterManager.getInstance().popWindowStage(this);\n',
                 '  detachFromFlutterEngine(): void {}\n',
                 '  getAppComponent(): UIAbility { return this; }\n',
                 '  onDestroy(): void { FlutterManager.getInstance().popUIAbility(this); }\n'):
        replace(entry, line)
    replace(entry, "    } else if (isFlutterFoundationRoute(page, debug)) {\n"
            "      this.testPage = 'pages/FlutterFoundation';\n", '    } else if (page === \'native_game_center\') {\n'
            "      this.testPage = 'pages/GameCenter';\n")
    replace(entry, "    } else if (page === 'flutter_texture_probe') {\n"
            "      this.testPage = 'pages/FlutterTextureProbe';\n", '')
    replace(entry, "    const initialPage = AppStorage.get<boolean>('ProductNativeBaseline') === true ? 'pages/GameCenter' : this.testPage;",
            '    const initialPage = this.testPage;')

    pages = 'harmony/entry/src/main/resources/base/profile/main_pages.json'
    page_data = json.loads(result[pages])
    for page in ('pages/FlutterTextureProbe', 'pages/FlutterFoundation'):
        if page not in page_data['src']:
            raise ValueError('Flutter page list drift')
        page_data['src'].remove(page)
    result[pages] = (json.dumps(page_data, indent=2) + '\n').encode()
    routes = ETS + 'flutter/ProductRoutes.ets'
    if sha256(result[routes]) != 'e4115341119e6e31a7219b2f498430a36ae199871b1587f508c9e02181e1e6f2':
        raise ValueError('Product route source drift')
    result[routes] = ("/** Native-only same-revision size control. */\n"
                      "export function redirectProductRoute(_route: string): boolean { return false; }\n").encode()

    run = ETS + 'pages/RunGame.ets'
    replace(run, "import { ProductHandoffBackdrop } from '../flutter/ProductHandoffBackdrop';\n")
    run_pattern = r'  private async openProductSettings\(\): Promise<void> \{[\s\S]*?(?=  private handlePauseCommand\(id: string\): void \{)'
    run_replacement = '''  private async openProductSettings(): Promise<void> {
    if (!this.started || !this.paused || this.openingProductSettings) return;
    this.openingProductSettings = true;
    this.drawerOpen = false;
    this.resumeAfterSettings = true;
    try { await router.pushUrl({ url: 'pages/Settings' }); }
    catch (_) { this.resumeAfterSettings = false; this.drawerOpen = true; this.navigationFailed(); }
    finally { this.openingProductSettings = false; }
  }

  private async openProductHall(): Promise<void> {
    if (!this.started || !this.paused || this.openingProductSettings) return;
    this.openingProductSettings = true;
    try {
      this.stopLoop();
      this.play.close();
      nativePlay.renderSetPaused(true);
      this.started = false;
      this.drawerOpen = false;
      await router.replaceUrl({ url: 'pages/GameCenter' });
    } catch (_) { this.drawerOpen = true; this.navigationFailed(); }
    finally { this.openingProductSettings = false; }
  }

'''
    replace_block(run, run_pattern, run_replacement,
                  'e616600f975de0cce8843b813b13f861141034ca4882837ea69bf04cabd8bac8')
    near = ETS + 'pages/NearbyLobby.ets'
    replace(near, "url: 'pages/FlutterFoundation'", "url: 'pages/GameCenter'", 3)
    replace(near, "params: { purpose: 'nearby' }", "params: { nearbyChooseGame: true }", 2)
    for path in G2_HARMONY_REMOVE_PATHS:
        del result[path]
    for path, data in result.items():
        if path.startswith(ETS) and path.endswith(('.ets', '.ts')) and any(token in data for token in (
                b'@ohos/flutter', b'FlutterFoundation', b'ProductHandoffBackdrop')):
            raise ValueError(f'Unreviewed Flutter embedding dependency remains: {path}')
    for path in crlf:
        result[path] = result[path].replace(b'\n', b'\r\n')
    return result


def android_g2_native_only(source):
    """Android-only G2 control: exact transport blocks, native owners unchanged."""
    result = dict(source)
    crlf = set()
    for path in (*G2_ANDROID_EDIT_PATHS, *G2_ANDROID_REMOVE_PATHS):
        if path not in source:
            raise ValueError(f'Required source missing: {path}')
    for path in G2_ANDROID_EDIT_PATHS:
        if b'\r\n' in result[path]:
            if b'\n' in result[path].replace(b'\r\n', b''):
                raise ValueError(f'Mixed source line endings require review: {path}')
            crlf.add(path)
            result[path] = result[path].replace(b'\r\n', b'\n')
    if re.findall(rb'abiFilters\s+([^\r\n]+)', result['app/build.gradle']) != [b"'arm64-v8a', 'x86_64'"]:
        raise ValueError('ABI configuration changed; review the matched package comparison first')

    def replace(path, old, new=''):
        text = result[path].decode('utf-8')
        if text.count(old) != 1:
            raise ValueError(f'Source drift in {path}: expected one exact anchor')
        result[path] = text.replace(old, new).encode('utf-8')

    def checked_block(path, pattern, expected_hash, replacement=''):
        text = result[path].decode('utf-8')
        matches = list(re.finditer(pattern, text))
        if len(matches) != 1 or sha256(matches[0].group().encode()) != expected_hash:
            raise ValueError(f'Source drift in {path}: transport block requires review')
        match = matches[0]
        result[path] = (text[:match.start()] + replacement + text[match.end():]).encode()

    replace('settings.gradle', "        maven { url 'https://storage.googleapis.com/download.flutter.io' }\n")
    replace('settings.gradle', '// Generated module files are recreated by tools/flutter/Build-Android.ps1.\n'
            "apply from: new File(settingsDir, 'ui/flutter/.android/include_flutter.groovy')\n")
    replace('app/build.gradle', "    implementation project(':flutter')\n")
    launcher = ('            <intent-filter>\n'
                '                <action android:name="android.intent.action.MAIN" />\n'
                '                <category android:name="android.intent.category.LAUNCHER" />\n'
                '            </intent-filter>\n')
    manifest = 'app/src/main/AndroidManifest.xml'
    replace(manifest, '        <activity\n'
            '            android:name=".FlutterFoundationActivity"\n'
            '            android:exported="true"\n'
            '            android:hardwareAccelerated="true"\n'
            '            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"\n'
            '            android:screenOrientation="sensorLandscape">\n' + launcher + '        </activity>\n')
    home = ('        <activity\n            android:name=".HomeActivity"\n'
            '            android:exported="true"\n'
            '            android:configChanges="orientation|screenSize|keyboardHidden"\n'
            '            android:screenOrientation="sensorLandscape">\n')
    replace(manifest, home + '        </activity>\n', home + launcher + '        </activity>\n')
    application = JAVA + 'FlyNesApplication.java'
    checked_block(application, r'    private io\.flutter\.[\s\S]*?(?=    private AndroidResumeService resumeService;)',
                  '950f16f62af98100868a45ace22456b442de3eb536e597cd91e7eef9421f7357')
    checked_block(application, r'    /\*\* Lazily initialized[\s\S]*?(?=    AndroidResumeService resumeService\(\))',
                  'a5ae4ae32f1a564a4e291bb61e05747ae16c210456c14c3c9f24d98584feae28')
    checked_block(JAVA + 'MainActivity.java', r'        if \(destination == HomeActivity\.class[\s\S]*?\n        }\n',
                  '31d5ef30024afcc5b4a50386b73d87e7cff1e9474df20a156e666b5697fcea3e')
    replace(JAVA + 'MainActivity.java', '        ((FlyNesApplication)getApplication()).gameDestroyed(this);\n')
    replace(JAVA + 'HomeActivity.java', 'FoundationBridge.RETURN_TO_FOUNDATION', '"return_to_foundation"')
    replace(JAVA + 'NearbyLobbyActivity.java', '.putExtra(ProductBridge.PURPOSE_EXTRA,"nearby")',
            '.putExtra("nearby_choose_game",true)')
    checked_block(JAVA + 'ProductRoutes.java', r'\A[\s\S]*\Z',
                  'f489d34707a0c76e7fad2234b0f749b32ba1b03673b2d62ee7233cfea74a5e19',
                  '''package com.flynes.emu;

import android.app.Activity;
import android.content.Intent;

/** Derived native-only package-size control; never used by the live product. */
public final class ProductRoutes {
    static final String NATIVE_BASELINE="controlled_native_baseline";
    static Intent intent(Activity activity,String route) {
        Intent next=nativeIntent(activity,switch(route){
            case "settings"->SettingsActivity.class;case "licenses"->LicensesActivity.class;default->HomeActivity.class;});
        if("sources".equals(route))next.setAction(HomeActivity.ACTION_SHOW_SOURCES);
        return next;
    }
    static boolean baselineAllowed(boolean buildAllowed,boolean requested){return buildAllowed&&requested;}
    public static boolean isNativeBaseline(Activity activity){return true;}
    public static Intent nativeIntent(Activity owner,Class<?> destination){return new Intent(owner,destination);}
    static boolean redirect(Activity activity,String route){return false;}
}
''')
    for path in G2_ANDROID_REMOVE_PATHS:
        del result[path]
    for path, data in result.items():
        if path.startswith('app/src/main/java/') and path.endswith('.java') and any(token in data for token in (
                b'io.flutter.', b'com.flynes.emu.flutter.', b'FoundationBridge', b'ProductBridge', b'FlutterFoundationActivity')):
            raise ValueError(f'Unreviewed embedding dependency remains: {path}')
    for path in crlf:
        result[path] = result[path].replace(b'\n', b'\r\n')
    return result


def native_only(source):
    """Transform an immutable archive snapshot; reject changed stripping anchors."""
    result = dict(source)
    for path in (*EDIT_PATHS, *REMOVE_PATHS):
        if path not in source:
            raise ValueError(f"Required source missing: {path}")
    # git archive may apply working-tree EOL conversion. Normalize only the
    # explicit text edit allowlist for matching, then restore each file's EOL.
    # Every other archived byte (including all native fixes) stays untouched.
    crlf_paths = set()
    for path in EDIT_PATHS:
        data = source[path]
        if b"\r\n" in data:
            if b"\n" in data.replace(b"\r\n", b""):
                raise ValueError(f"Mixed source line endings require review: {path}")
            crlf_paths.add(path)
            result[path] = data.replace(b"\r\n", b"\n")
    android_abis = re.findall(rb"abiFilters\s+([^\r\n]+)", source["app/build.gradle"])
    harmony_abis = json.loads(source["harmony/entry/build-profile.json5"])[
        "buildOption"]["externalNativeOptions"]["abiFilters"]
    if (android_abis != [b"'arm64-v8a', 'x86_64'"]
            or harmony_abis != ["arm64-v8a", "x86_64"]):
        raise ValueError("ABI configuration changed; review the matched package comparison first")

    def replace(path, old, new="", count=1):
        text = result[path].decode("utf-8")
        if text.count(old) != count:
            raise ValueError(f"Source drift in {path}: expected {count} matching anchor(s)")
        result[path] = text.replace(old, new).encode("utf-8")

    def replace_pattern(path, pattern, new=""):
        text, count = re.subn(pattern, new, result[path].decode("utf-8"), flags=re.MULTILINE)
        if count != 1:
            raise ValueError(f"Source drift in {path}: expected one matching block")
        result[path] = text.encode("utf-8")

    replace("settings.gradle", "        maven { url 'https://storage.googleapis.com/download.flutter.io' }\n")
    replace("settings.gradle", "// Generated module files are recreated by tools/flutter/Build-Android.ps1.\n"
            "apply from: new File(settingsDir, 'ui/flutter/.android/include_flutter.groovy')\n")
    replace("app/build.gradle", "    implementation project(':flutter')\n")
    replace_pattern("app/src/main/AndroidManifest.xml",
                    r'        <activity\s+android:name="\.FlutterFoundationActivity"[^>]*?/>\n')
    application = JAVA + "FlyNesApplication.java"
    replace(application, "    private io.flutter.embedding.engine.FlutterEngine foundationEngine;\n")
    replace(application, "    private FoundationBridge foundationBridge;\n")
    replace_pattern(application,
                    r"    /\*\* Lazily initialized on the UI thread;[^\n]*\n"
                    r"[\s\S]*?    FoundationBridge foundationBridge\(\) \{ return foundationBridge; \}\n")
    # Keep native navigation/lifecycle fixes byte-for-byte except the dependency
    # on a constant whose declaring transport class is being removed.
    for name in ("HomeActivity.java", "MainActivity.java"):
        replace(JAVA + name, "FoundationBridge.RETURN_TO_FOUNDATION", '"return_to_foundation"')

    replace_pattern("harmony/hvigorfile.ts", r"\A[\s\S]*?(?=export default \{)",
                    "import { appTasks } from '@ohos/hvigor-ohos-plugin';\n\n")
    for path, section in (("harmony/oh-package.json5", "overrides"),
                          ("harmony/entry/oh-package.json5", "dependencies")):
        data = json.loads(result[path])
        if not HAR_PACKAGES.issubset(data[section]):
            raise ValueError(f"HAR dependency drift in {path}")
        for name in HAR_PACKAGES:
            del data[section][name]
        result[path] = (json.dumps(data, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    lock_path = "harmony/entry/oh-package-lock.json5"
    lock = json.loads(result[lock_path])
    for section in ("specifiers", "packages"):
        removed = [key for key in lock[section] if any(key.startswith(name + "@") for name in HAR_PACKAGES)]
        if len(removed) != 4:
            raise ValueError(f"HAR lock drift in {lock_path}")
        for key in removed:
            del lock[section][key]
    result[lock_path] = (json.dumps(lock, indent=2, ensure_ascii=False) + "\n").encode("utf-8")

    entry = ETS + "entryability/EntryAbility.ets"
    for line in (
        "import { ExclusiveAppComponent, FlutterManager } from '@ohos/flutter_ohos';\n",
        "import { isFlutterFoundationRoute } from '../flutter/FoundationProjection';\n",
        "    FlutterManager.getInstance().pushUIAbility(this);\n",
        "    FlutterManager.getInstance().pushWindowStage(this, windowStage);\n",
        "    FlutterManager.getInstance().popWindowStage(this);\n",
        "  detachFromFlutterEngine(): void {}\n",
        "  getAppComponent(): UIAbility { return this; }\n",
        "  onDestroy(): void { FlutterManager.getInstance().popUIAbility(this); }\n",
    ):
        replace(entry, line)
    replace(entry, " extends UIAbility implements ExclusiveAppComponent<UIAbility>", " extends UIAbility")
    replace(entry, "    if (page === 'flutter_texture_probe') {\n"
            "      this.testPage = 'pages/FlutterTextureProbe';\n"
            "    } else if (isFlutterFoundationRoute(page, debug)) {\n"
            "      this.testPage = 'pages/FlutterFoundation';\n"
            "    } else if (page === 'nearby_friends') {", "    if (page === 'nearby_friends') {")
    pages = "harmony/entry/src/main/resources/base/profile/main_pages.json"
    for page in ("FlutterTextureProbe", "FlutterFoundation"):
        replace(pages, f'    "pages/{page}",\n')
    for path in REMOVE_PATHS:
        del result[path]

    for path, data in result.items():
        if path.startswith(JAVA) and path.endswith(".java"):
            forbidden = (b"io.flutter.", b"com.flynes.emu.flutter.", b"FoundationBridge", b"FlutterFoundationActivity")
        elif path.startswith(ETS) and path.endswith((".ets", ".ts")):
            forbidden = (b"@ohos/flutter", b"../flutter/", b"FlutterManager", b"ExclusiveAppComponent")
        else:
            continue
        if any(token in data for token in forbidden):
            raise ValueError(f"Unreviewed embedding dependency remains: {path}")
    for path in crlf_paths:
        result[path] = result[path].replace(b"\n", b"\r\n")
    return result


def validate_output(repo, output):
    """Resolve before writing; no overwrite, ancestor target, symlink or junction."""
    repo = Path(repo).resolve()
    output = Path(output).absolute()
    artifacts = repo / ".artifacts"
    try:
        relative = output.relative_to(artifacts)
    except ValueError as error:
        raise ValueError("Output must be inside this repository's .artifacts directory") from error
    if not relative.parts or ".." in relative.parts:
        raise ValueError("Output must be a child of .artifacts, not its root")
    for parent in (output, *output.parents):
        if parent == repo:
            break
        if parent.is_symlink() or getattr(parent, "is_junction", lambda: False)():
            raise ValueError("Output path must not pass through a symlink or junction")
    resolved = output.resolve()
    if not resolved.is_relative_to(artifacts):
        raise ValueError("Resolved output escapes .artifacts")
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        raise ValueError("Output must be absent or an empty directory; existing evidence is never overwritten")
    return resolved


def read_archive(data):
    """Read regular committed files only, without extracting archive paths."""
    files = {}
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:") as archive:
        for member in archive:
            path = PurePosixPath(member.name)
            if (path.is_absolute() or ".." in path.parts or ".git" in path.parts
                    or "\\" in member.name or ":" in member.name):
                raise ValueError(f"Unsafe archive path: {member.name}")
            if member.isdir():
                continue
            if not member.isfile() or str(path) in files:
                raise ValueError(f"Unsupported archive member: {member.name}")
            files[str(path)] = archive.extractfile(member).read()
    return files


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def recipe_configuration(recipe):
    if recipe == 'g1-both':
        return native_only, EDIT_PATHS, REMOVE_PATHS
    if recipe == 'android-g2':
        return android_g2_native_only, G2_ANDROID_EDIT_PATHS, G2_ANDROID_REMOVE_PATHS
    if recipe == 'harmony-g2':
        return harmony_g2_native_only, G2_HARMONY_EDIT_PATHS, G2_HARMONY_REMOVE_PATHS
    raise ValueError(f'Unknown native size recipe: {recipe}')


def review_changes(source, result, recipe='g1-both'):
    _, edits, removals = recipe_configuration(recipe)
    review, patch = [], []
    for path in sorted(source.keys() | result.keys()):
        before, after = source.get(path), result.get(path)
        if before == after:
            continue
        review.append({"path": path, "action": "delete" if after is None else "modify",
                       "beforeSha256": sha256(before) if before is not None else None,
                       "afterSha256": sha256(after) if after is not None else None})
        patch.extend(difflib.unified_diff(
            (before or b"").decode("utf-8").splitlines(keepends=True),
            (after or b"").decode("utf-8").splitlines(keepends=True),
            fromfile="a/" + path if before is not None else "/dev/null",
            tofile="b/" + path if after is not None else "/dev/null"))
    if not {item["path"] for item in review}.issubset(set(edits) | set(removals)):
        raise ValueError("Transformation modified a path outside the reviewed allowlist")
    return review, "".join(patch)


def git(repo, *arguments):
    return subprocess.check_output(["git", "-C", str(repo), *arguments], stderr=subprocess.PIPE)


def prepare(repo, output, expected_revision, recipe='g1-both'):
    transform, _, _ = recipe_configuration(recipe)
    repo = Path(repo).resolve()
    if Path(git(repo, "rev-parse", "--show-toplevel").decode().strip()).resolve() != repo:
        raise ValueError("--repo must name the current repository root")
    output = validate_output(repo, output)
    revision = git(repo, "rev-parse", "HEAD").decode().strip()
    if revision != expected_revision:
        raise ValueError("HEAD differs from --expect-head; commit the intended fixes and review the new revision")
    git(repo, "merge-base", "--is-ancestor", REQUIRED_NATIVE_ANCESTOR, revision)
    tree = git(repo, "ls-tree", "-r", revision).decode().splitlines()
    gitlinks = [line.split("\t", 1) for line in tree if line.startswith("160000 ")]
    if len(gitlinks) != 1 or gitlinks[0][1] != SUBMODULE:
        raise ValueError("Expected exactly the reviewed Nestopia submodule")
    sub_revision = gitlinks[0][0].split()[2]
    sub_repo = repo / SUBMODULE
    if Path(git(sub_repo, "rev-parse", "--show-toplevel").decode().strip()).resolve() != sub_repo.resolve():
        raise ValueError("Initialize the pinned Nestopia submodule first; never copy its working files")
    source = read_archive(git(repo, "archive", "--format=tar", revision))
    sub_files = read_archive(git(sub_repo, "archive", "--format=tar", sub_revision))
    source.update({f"{SUBMODULE}/{path}": data for path, data in sub_files.items()})
    result = transform(source)
    changes, patch = review_changes(source, result, recipe)
    inventory = [{"path": path, "sourceSha256": sha256(data),
                  "exportSha256": sha256(result[path]) if path in result else None}
                 for path, data in sorted(source.items())]
    manifest = {
        "schemaVersion": 1, "purpose": "same-revision native-only Release package size baseline",
        "recipe": recipe,
        "sourceRevision": revision, "requiredNativeAncestor": REQUIRED_NATIVE_ANCESTOR,
        "submodules": {SUBMODULE: sub_revision}, "changes": changes,
        "recipeSha256": sha256(Path(__file__).read_bytes()),
        "patchSha256": sha256(patch.encode("utf-8")),
        "buildPerformed": False, "sizeMeasured": False,
        "comparison": {"buildMode": "release", "abis": ["arm64-v8a", "x86_64"],
                       "androidArtifact": "unsigned APK", "harmonyArtifact": "unsigned HAP",
                       "candidateRequiredRevision": revision},
    }
    if recipe == 'android-g2':
        del manifest['comparison']['harmonyArtifact']
        manifest['comparison']['platforms'] = ['android']
    if recipe == 'harmony-g2':
        del manifest['comparison']['androidArtifact']
        manifest['comparison']['platforms'] = ['harmony']
    # All transforms and guards finish before the first filesystem mutation.
    validate_output(repo, output)
    output.mkdir(parents=True, exist_ok=True)
    for path, data in result.items():
        destination = output / "source" / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        with destination.open("xb") as handle:
            handle.write(data)
    for name, value in (("manifest.json", manifest), ("source-files.json", inventory)):
        with (output / name).open("x", encoding="utf-8", newline="\n") as handle:
            json.dump(value, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
    with (output / "native-only.patch").open("x", encoding="utf-8", newline="\n") as handle:
        handle.write(patch)
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--output", type=Path, required=True,
                        help="absent/empty child directory of this repository's .artifacts")
    parser.add_argument("--expect-head", required=True, help="reviewed full HEAD SHA, including all intended fixes")
    parser.add_argument('--recipe', choices=('g1-both', 'android-g2', 'harmony-g2'), default='g1-both',
                        help='explicit transform recipe; G2 recipes strip Flutter from one platform only')
    args = parser.parse_args()
    try:
        manifest = prepare(args.repo, args.output, args.expect_head, args.recipe)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Native size baseline preparation failed: {error}\n")
    print(json.dumps({"sourceRevision": manifest["sourceRevision"],
                      "output": str(args.output.resolve()), "changedFiles": len(manifest["changes"])}))


if __name__ == "__main__":
    main()
