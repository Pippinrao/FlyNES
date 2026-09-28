import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "tools/flutter/prepare_native_size_baseline.py"
baseline = None
if SCRIPT.exists():
    spec = importlib.util.spec_from_file_location("native_size_baseline", SCRIPT)
    baseline = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(baseline)


class NativeSizeBaselineTest(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(baseline, "native size baseline exporter must exist")

    def source_fixture(self):
        # Read committed text only. No export, generated files, ROMs or builds.
        paths = set(baseline.EDIT_PATHS) | set(baseline.REMOVE_PATHS) | {
            "app/src/main/java/com/flynes/emu/AndroidResumeService.java",
            "app/src/main/java/com/flynes/emu/FoundationResumeQuery.java",
            "app/src/main/java/com/flynes/emu/AudioThread.java",
            "app/src/main/cpp/video/video_presenter_jni.cpp",
            "harmony/entry/src/main/cpp/harmony_renderer.cpp",
            "harmony/entry/src/main/cpp/napi_init.cpp",
            "harmony/entry/src/main/ets/service/SaveHistoryService.ets",
            "harmony/entry/src/main/ets/pages/RunGame.ets",
            "harmony/entry/build-profile.json5", "VERSION",
        }
        return {path: subprocess.check_output(
            ["git", "-C", str(ROOT), "show", f"HEAD:{path}"])
            for path in paths}

    def test_removes_embedding_and_keeps_native_fixes_and_build_shape(self):
        source = self.source_fixture()
        result = baseline.native_only(source)
        for path in source.keys() - set(baseline.EDIT_PATHS) - set(baseline.REMOVE_PATHS):
            self.assertEqual(result[path], source[path], path)
        self.assertNotIn(b"project(':flutter')", result["app/build.gradle"])
        self.assertIn(b"abiFilters 'arm64-v8a', 'x86_64'", result["app/build.gradle"])
        self.assertIn(b"minifyEnabled false", result["app/build.gradle"])
        java = "app/src/main/java/com/flynes/emu/"
        self.assertIn(b"AndroidResumeService resumeService", result[java + "FlyNesApplication.java"])
        for name in ("HomeActivity.java", "MainActivity.java"):
            self.assertEqual(result[java + name], source[java + name].replace(
                b"FoundationBridge.RETURN_TO_FOUNDATION", b'"return_to_foundation"'))
        entry = result["harmony/entry/src/main/ets/entryability/EntryAbility.ets"]
        self.assertIn(b"eventHub.emit('save-background')", entry)
        self.assertIn(b"eventHub.emit('app-foreground')", entry)
        self.assertIn(b"page === 'nearby_friends'", entry)
        self.assertNotIn(b"Flutter", entry)
        for path in baseline.REMOVE_PATHS:
            self.assertNotIn(path, result)
        for path in ("harmony/oh-package.json5", "harmony/entry/oh-package.json5",
                     "harmony/entry/oh-package-lock.json5"):
            self.assertNotIn("flutter", json.dumps(json.loads(result[path])).lower())

    def test_source_drift_is_rejected_instead_of_silent_partial_strip(self):
        source = self.source_fixture()
        source["settings.gradle"] = source["settings.gradle"].replace(
            b"include_flutter.groovy", b"different-generation.groovy")
        with self.assertRaisesRegex(ValueError, "settings.gradle"):
            baseline.native_only(source)

    def test_crlf_archive_preserves_native_bytes_and_edited_file_line_endings(self):
        # git archive can apply checkout conversion, unlike git show HEAD:path.
        source = {path: data.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
                  for path, data in self.source_fixture().items()}
        result = baseline.native_only(source)
        for path in source.keys() - set(baseline.EDIT_PATHS) - set(baseline.REMOVE_PATHS):
            self.assertEqual(result[path], source[path], path)
        for path in baseline.EDIT_PATHS:
            self.assertIn(b"\r\n", result[path], path)
            self.assertNotIn(b"\n", result[path].replace(b"\r\n", b""), path)
        for name in ("HomeActivity.java", "MainActivity.java"):
            path = baseline.JAVA + name
            self.assertEqual(result[path], source[path].replace(
                b"FoundationBridge.RETURN_TO_FOUNDATION", b'"return_to_foundation"'))

    def test_unlisted_embedding_dependency_is_rejected(self):
        source = self.source_fixture()
        source["app/src/main/java/com/flynes/emu/NewBridge.java"] = b"import io.flutter.NewApi;\n"
        with self.assertRaisesRegex(ValueError, "NewBridge.java"):
            baseline.native_only(source)

    def test_abi_drift_cannot_be_labelled_as_the_dual_abi_comparison(self):
        source = self.source_fixture()
        source["harmony/entry/build-profile.json5"] = source["harmony/entry/build-profile.json5"].replace(
            b'"arm64-v8a",', b"")
        with self.assertRaisesRegex(ValueError, "ABI"):
            baseline.native_only(source)

    def test_output_must_be_empty_and_below_this_repos_artifacts(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            valid = repo / ".artifacts" / "size-native"
            self.assertEqual(baseline.validate_output(repo, valid), valid)
            for invalid in (repo, repo / ".artifacts", repo / "outside"):
                with self.assertRaises(ValueError):
                    baseline.validate_output(repo, invalid)
            valid.mkdir(parents=True)
            (valid / "evidence.txt").write_text("keep")
            with self.assertRaisesRegex(ValueError, "empty"):
                baseline.validate_output(repo, valid)
            self.assertEqual((valid / "evidence.txt").read_text(), "keep")

    def test_archive_rejects_traversal_and_links_before_writing(self):
        for name, kind in (("../escape", tarfile.REGTYPE),
                           ("safe-link", tarfile.SYMTYPE),
                           ("C:/escape", tarfile.REGTYPE)):
            stream = io.BytesIO()
            with tarfile.open(fileobj=stream, mode="w") as archive:
                member = tarfile.TarInfo(name)
                member.type = kind
                member.linkname = "../escape" if kind == tarfile.SYMTYPE else ""
                archive.addfile(member)
            with self.assertRaises(ValueError):
                baseline.read_archive(stream.getvalue())

    def test_review_manifest_and_patch_cover_every_change(self):
        source = self.source_fixture()
        result = baseline.native_only(source)
        review, patch = baseline.review_changes(source, result)
        expected = {path for path in source if source[path] != result.get(path)}
        self.assertEqual({item["path"] for item in review}, expected)
        for item in review:
            self.assertEqual(len(item["beforeSha256"]), 64)
            self.assertIn("a/" + item["path"], patch)
            if item["path"] not in result:
                self.assertIsNone(item["afterSha256"])
                self.assertEqual(item["action"], "delete")
        self.assertNotIn("harmony_renderer.cpp", patch)


if __name__ == "__main__":
    unittest.main()
