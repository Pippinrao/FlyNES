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


def review_changes(source, result):
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
    if not {item["path"] for item in review}.issubset(set(EDIT_PATHS) | set(REMOVE_PATHS)):
        raise ValueError("Transformation modified a path outside the reviewed allowlist")
    return review, "".join(patch)


def git(repo, *arguments):
    return subprocess.check_output(["git", "-C", str(repo), *arguments], stderr=subprocess.PIPE)


def prepare(repo, output, expected_revision):
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
    result = native_only(source)
    changes, patch = review_changes(source, result)
    inventory = [{"path": path, "sourceSha256": sha256(data),
                  "exportSha256": sha256(result[path]) if path in result else None}
                 for path, data in sorted(source.items())]
    manifest = {
        "schemaVersion": 1, "purpose": "same-revision native-only Release package size baseline",
        "sourceRevision": revision, "requiredNativeAncestor": REQUIRED_NATIVE_ANCESTOR,
        "submodules": {SUBMODULE: sub_revision}, "changes": changes,
        "recipeSha256": sha256(Path(__file__).read_bytes()),
        "patchSha256": sha256(patch.encode("utf-8")),
        "buildPerformed": False, "sizeMeasured": False,
        "comparison": {"buildMode": "release", "abis": ["arm64-v8a", "x86_64"],
                       "androidArtifact": "unsigned APK", "harmonyArtifact": "unsigned HAP",
                       "candidateRequiredRevision": revision},
    }
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
    args = parser.parse_args()
    try:
        manifest = prepare(args.repo, args.output, args.expect_head)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Native size baseline preparation failed: {error}\n")
    print(json.dumps({"sourceRevision": manifest["sourceRevision"],
                      "output": str(args.output.resolve()), "changedFiles": len(manifest["changes"])}))


if __name__ == "__main__":
    main()
