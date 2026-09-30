"""G2 control recipe business checks; no export/build/device side effects."""
import importlib.util
import inspect
import io
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('g2_size_baseline', ROOT/'tools/flutter/prepare_native_size_baseline.py')
baseline = importlib.util.module_from_spec(spec)
spec.loader.exec_module(baseline)


class AndroidG2SizeBaselineTest(unittest.TestCase):
    def source(self):
        paths = set(baseline.EDIT_PATHS) | set(baseline.REMOVE_PATHS)
        paths.update(str(p.relative_to(ROOT)).replace('\\', '/')
                     for p in (ROOT/'app/src/main/java').rglob('*.java'))
        paths.update(['harmony/entry/build-profile.json5', 'VERSION',
                      'app/src/main/cpp/video/video_presenter_jni.cpp',
                      'shared/src/app/flynes_app.cpp'])
        return {p: (ROOT/p).read_bytes() for p in paths}

    def transform(self, source):
        # Before the new recipe exists, demonstrate the old G1 recipe rejecting
        # the real nested G2 launcher rather than a missing Python API error.
        recipe = getattr(baseline, 'android_g2_native_only', baseline.native_only)
        try:
            return recipe(source)
        except ValueError as error:
            self.fail(f'Current G2 Android snapshot must have a reviewed native-only recipe: {error}')

    def test_current_g2_launcher_and_hosts_export_without_touching_native_owners(self):
        source = self.source()
        result = self.transform(source)
        manifest = result['app/src/main/AndroidManifest.xml']
        self.assertNotIn(b'FlutterFoundationActivity', manifest)
        self.assertEqual(manifest.count(b'android.intent.category.LAUNCHER'), 1)
        self.assertIn(b'.HomeActivity', manifest)
        for path, before in source.items():
            if path.startswith(('shared/', 'harmony/', 'app/src/main/cpp/')):
                self.assertEqual(before, result[path], path)
        self.assertEqual(source[baseline.JAVA+'save/HistorySession.java'], result[baseline.JAVA+'save/HistorySession.java'])
        self.assertEqual(source[baseline.JAVA+'AudioThread.java'], result[baseline.JAVA+'AudioThread.java'])
        self.assertIn(b"abiFilters 'arm64-v8a', 'x86_64'", result['app/build.gradle'])
        self.assertIn(b'minifyEnabled false', result['app/build.gradle'])
        app = result[baseline.JAVA+'FlyNesApplication.java']
        self.assertIn(b'catalogRuntime.start();', app)
        self.assertIn(b'resumeService = new AndroidResumeService(this);', app)
        for path, data in result.items():
            if path.startswith(baseline.JAVA) and path.endswith('.java'):
                for token in (b'io.flutter.', b'FoundationBridge', b'ProductBridge', b'FlutterFoundationActivity'):
                    self.assertNotIn(token, data, path)

    def test_export_keeps_crlf_and_does_not_accept_an_unknown_embedding_owner(self):
        source = {p: data.replace(b'\r\n', b'\n').replace(b'\n', b'\r\n')
                  for p, data in self.source().items()}
        result = self.transform(source)
        for path in ('settings.gradle', 'app/build.gradle', baseline.JAVA+'FlyNesApplication.java'):
            self.assertIn(b'\r\n', result[path])
            self.assertNotIn(b'\n', result[path].replace(b'\r\n', b''))
        source[baseline.JAVA+'Unexpected.java'] = b'import io.flutter.NewOwner;\r\n'
        with self.assertRaisesRegex(ValueError, 'Unexpected.java'):
            baseline.android_g2_native_only(source)

    def test_transport_drift_and_abi_changes_are_rejected(self):
        for path, old, new in (
            (baseline.JAVA+'FlyNesApplication.java', b'foundationEngine = new', b'nativeOwnerChange(); foundationEngine = new'),
            (baseline.JAVA+'ProductRoutes.java', b'public final class', b'public class'),
            (baseline.JAVA+'MainActivity.java', b'prepareHallHandoff(this)', b'prepareHallHandoff(other)'),
            ('app/build.gradle', b"'arm64-v8a', 'x86_64'", b"'arm64-v8a'"),
        ):
            source=self.source();self.assertIn(old,source[path]);source[path]=source[path].replace(old,new)
            with self.subTest(path=path), self.assertRaisesRegex(ValueError, 'drift|ABI'):
                baseline.android_g2_native_only(source)

    def test_embedding_in_another_java_package_is_not_silently_kept(self):
        source=self.source()
        source['app/src/main/java/other/NewOwner.java']=b'package other; import io.flutter.NewApi;'
        with self.assertRaisesRegex(ValueError,'other/NewOwner.java'):
            baseline.android_g2_native_only(source)

    def test_review_is_android_only_and_rejects_unlisted_changes(self):
        source=self.source();result=self.transform(source)
        kwargs={'recipe':'android-g2'} if 'recipe' in inspect.signature(baseline.review_changes).parameters else {}
        try:
            changes,patch=baseline.review_changes(source,result,**kwargs)
        except ValueError as error:
            self.fail(f'G2 review must use the explicit Android allowlist: {error}')
        expected={p for p in source if source[p]!=result.get(p)}
        self.assertEqual(expected,{row['path'] for row in changes})
        self.assertTrue(all(not row['path'].startswith('harmony/') for row in changes))
        self.assertIn('ProductRoutes.java',patch)
        altered=dict(result);altered[baseline.JAVA+'AudioThread.java']+=b'// unexpected\n'
        with self.assertRaisesRegex(ValueError,'allowlist'):
            baseline.review_changes(source,altered,recipe='android-g2')

    def test_cli_offers_explicit_android_recipe_without_changing_legacy_default(self):
        help_text=subprocess.check_output([sys.executable,str(ROOT/'tools/flutter/prepare_native_size_baseline.py'),'--help'],text=True)
        self.assertIn('--recipe {g1-both,android-g2,harmony-g2}',help_text)
        self.assertIn('g1-both',help_text)

    def test_prepare_records_android_recipe_and_exports_only_supplied_committed_objects(self):
        # Synthetic Git transport, isolated temporary output; not a certification
        # export from the real dirty worktree or its older HEAD.
        source=self.source()
        def archive(files):
            out=io.BytesIO()
            with tarfile.open(fileobj=out,mode='w') as tar:
                for name,data in files.items():
                    info=tarfile.TarInfo(name);info.size=len(data);tar.addfile(info,io.BytesIO(data))
            return out.getvalue()
        with tempfile.TemporaryDirectory() as directory:
            repo=Path(directory).resolve();output=repo/'.artifacts'/'control'
            revision='1'*40;subrevision='2'*40
            def fake_git(where,*args):
                if args==('rev-parse','--show-toplevel'):return str(where).encode()
                if args==('rev-parse','HEAD'):return revision.encode()
                if args[0]=='merge-base':return b''
                if args[0]=='ls-tree':return f'160000 commit {subrevision}\t{baseline.SUBMODULE}\n'.encode()
                if args[:2]==('archive','--format=tar'):
                    return archive({'pinned.txt':b'pinned submodule'}) if args[2]==subrevision else archive(source)
                raise AssertionError(args)
            with patch.object(baseline,'git',side_effect=fake_git):
                with self.assertRaisesRegex(ValueError,'HEAD differs'):
                    baseline.prepare(repo,output,'3'*40,'android-g2')
                self.assertFalse(output.exists())
                manifest=baseline.prepare(repo,output,revision,'android-g2')
            self.assertEqual(manifest['recipe'],'android-g2')
            self.assertEqual(manifest['sourceRevision'],revision)
            self.assertEqual(manifest['comparison']['platforms'],['android'])
            self.assertNotIn('harmonyArtifact',manifest['comparison'])
            self.assertFalse(manifest['buildPerformed']);self.assertFalse(manifest['sizeMeasured'])
            self.assertEqual((output/'source'/baseline.SUBMODULE/'pinned.txt').read_bytes(),b'pinned submodule')
            inventory=json.loads((output/'source-files.json').read_text())
            for row in inventory:
                if row['path'].startswith(('harmony/','shared/','app/src/main/cpp/')):
                    self.assertEqual(row['sourceSha256'],row['exportSha256'])


if __name__ == '__main__':
    unittest.main()
