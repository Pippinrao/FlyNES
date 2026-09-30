import importlib.util
import hashlib
import os
import shutil
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    'collector', Path(__file__).resolve().parents[1] / 'collect_ios_simulator_evidence.py')
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)


def rows():
    return {role: [dict(index=i, warmup=i < 2, pid=1000 + offset + i,
                       launchCommandWallMs=100 + i,
                       memory=[dict(rssKiB=20000 + offset, pid=1000 + offset + i,
                                    beginMs=3000 + j * 500, endMs=3005 + j * 500)
                               for j in range(5)], errors=[])
                   for i in range(14)]
            for role, offset in [('native', 0), ('flutter', 100)]}


class EvidenceTests(unittest.TestCase):
    def test_overlay_accepts_relocation_only_with_identical_persistent_inventory(self):
        inventory = {'Documents/save.bin': 'a' * 64, 'Library/Preferences/settings.plist': 'b' * 64}
        try:
            result = collector.verify_data_overlay('/old/UUID', '/new/UUID', inventory, dict(inventory))
        except RuntimeError as error:
            self.fail('Identical persisted bytes must survive container relocation: ' + str(error))
        self.assertTrue(result['relocated'])
        self.assertTrue(result['preserved'])

    def test_overlay_rejects_same_path_changed_missing_or_added_files(self):
        before = {'Documents/save.bin': 'a' * 64}
        for after in ({'Documents/save.bin': 'b' * 64}, {},
                      {**before, 'Library/Preferences/new.plist': 'c' * 64}):
            with self.subTest(after=after), self.assertRaises(RuntimeError):
                collector.verify_data_overlay('/same/UUID', '/same/UUID', before, after)

    def test_overlay_without_before_inventory_cannot_be_certified(self):
        with self.assertRaises(RuntimeError):
            collector.verify_data_overlay('/same/UUID', '/same/UUID', None, {})

    def test_snapshot_hashes_only_declared_persistent_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve()
            expected = {}
            for name in ('Documents/saves/slot.bin', 'Library/Application Support/catalog.db',
                         'Library/Preferences/com.flynes.app.plist'):
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(name.encode())
                expected[name] = hashlib.sha256(name.encode()).hexdigest()
            for name in ('tmp/temp', 'Library/Caches/cover', 'SystemData/private', 'Library/other'):
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b'ignored')
            self.assertEqual(collector.persistent_data_snapshot(root), expected)
            with self.assertRaises((OSError, RuntimeError)):
                collector.persistent_data_snapshot(root / 'missing-container')

    def test_real_same_path_clear_or_mutation_is_detected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve()
            (root / 'Documents').mkdir()
            save = root / 'Documents/save.bin'
            save.write_bytes(b'original')
            before = collector.persistent_data_snapshot(root)
            save.write_bytes(b'replaced')
            with self.assertRaises(RuntimeError):
                collector.verify_data_overlay(root, root, before, collector.persistent_data_snapshot(root))
            save.unlink()
            with self.assertRaises(RuntimeError):
                collector.verify_data_overlay(root, root, before, collector.persistent_data_snapshot(root))

    def test_snapshot_rejects_links_without_reading_external_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp).resolve()
            root, outside = base / 'container', base / 'external'
            (root / 'Documents').mkdir(parents=True)
            outside.mkdir()
            secret = outside / 'private'
            secret.write_bytes(b'must not read')
            link = root / 'Documents/link'
            try:
                link.symlink_to(secret)
            except OSError as error:
                self.skipTest('Host cannot create test symlinks: ' + str(error))
            with patch.object(collector.os, 'open', side_effect=AssertionError('Opened external data')):
                with self.assertRaises(RuntimeError):
                    collector.persistent_data_snapshot(root)
            link.unlink()
            link.symlink_to(outside, target_is_directory=True)
            with self.assertRaises(RuntimeError):
                collector.persistent_data_snapshot(root)
            link.unlink()
            link.symlink_to(outside / 'missing')
            with self.assertRaises(RuntimeError):
                collector.persistent_data_snapshot(root)
            link.unlink()
            alias = base / 'alias'
            alias.symlink_to(root, target_is_directory=True)
            with self.assertRaises(RuntimeError):
                collector.persistent_data_snapshot(alias)
            # An intermediate Library link must also be rejected.
            (root / 'Library').symlink_to(outside, target_is_directory=True)
            with self.assertRaises(RuntimeError):
                collector.persistent_data_snapshot(root)

    def test_each_install_takes_fresh_snapshot_before_any_later_ui_write(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp).resolve()
            current = base / 'uuid-before'
            (current / 'Documents').mkdir(parents=True)
            (current / 'Documents/save.bin').write_bytes(b'first save')
            events = []

            class Commands:
                def run(self, command, timeout=45):
                    nonlocal current
                    events.append(command[2])
                    if command[2] == 'install':
                        replacement = base / ('uuid-' + command[-1])
                        shutil.copytree(current, replacement)
                        shutil.rmtree(current)
                        current = replacement
                        return '', 0, 'install'
                    return str(current), 0, 'container'

            report = {}
            commands = Commands()
            collector.install_preserving_data(commands, 'sim', {'path': 'native'}, 'native', report)
            (current / 'Documents/save.bin').write_bytes(b'legitimate native UI save')
            collector.install_preserving_data(commands, 'sim', {'path': 'flutter'}, 'flutter', report)
            overlays = report['dataOverlays']
            self.assertTrue(all(item['preserved'] and item['relocated'] for item in overlays))
            self.assertNotEqual(overlays[0]['afterInventory'], overlays[1]['beforeInventory'])
            self.assertEqual(overlays[1]['beforeInventory'], overlays[1]['afterInventory'])
            self.assertEqual(events, ['get_app_container', 'install', 'get_app_container'] * 2)

    def test_install_failure_keeps_before_and_after_inventory_for_diagnosis(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve()
            (root / 'Documents').mkdir()
            save = root / 'Documents/save.bin'
            save.write_bytes(b'kept before install')

            class Commands:
                def run(self, command, timeout=45):
                    if command[2] == 'install':
                        save.unlink()
                        return '', 0, 'install'
                    return str(root), 0, 'container'

            report = {}
            with self.assertRaises(RuntimeError):
                collector.install_preserving_data(Commands(), 'sim', {'path': 'native'}, 'native', report)
            record = report['dataOverlays'][0]
            self.assertFalse(record['preserved'])
            self.assertEqual(len(record['beforeInventory']), 1)
            self.assertEqual(record['afterInventory'], {})

    def test_launch_parser_requires_exact_bundle_and_positive_pid(self):
        self.assertEqual(collector.parse_launch_pid('com.flynes.app: 123\n'), 123)
        for bad in ('', 'other.app: 123', 'com.flynes.app: 0',
                    'com.flynes.app: 12\ncom.flynes.app: 13', 'com.flynes.app: -1'):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                collector.parse_launch_pid(bad)

    def test_rss_requires_same_process_and_executable_and_positive_value(self):
        executable = '/a path/FlyNES.app/FlyNES'
        self.assertEqual(collector.parse_rss(' 123 2048 ' + executable, 123, executable), 2048)
        for bad in ('123 0 ' + executable, '124 2048 ' + executable,
                    '123 2048 /another/FlyNES', '', '123 -5 ' + executable):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                collector.parse_rss(bad, 123, executable)

    def test_complete_debug_capture_never_claims_interactive_pss_or_gate_pass(self):
        result = collector.summarize(rows())
        self.assertTrue(result['diagnosticCaptureComplete'])
        self.assertEqual(result['performanceGate']['status'], 'not_evaluated')
        self.assertIsNone(result['routes']['flutter']['firstInteractiveMs'])
        self.assertIsNone(result['routes']['flutter']['nativeReadyMs'])
        self.assertIsNone(result['routes']['flutter']['pssKiB'])
        self.assertIsNone(result['routes']['flutter']['physicalFootprintBytes'])
        self.assertEqual(result['routes']['native']['launchCommandWallMs']['count'], 12)
        self.assertEqual(result['routes']['native']['launchCommandWallMs']['p95'], 113)
        self.assertEqual(result['fixedWindowRssP95DeltaKiB'], 100)

    def test_incomplete_or_bad_samples_are_never_complete(self):
        changes = [lambda r: r['native'].pop(),
                   lambda r: r['flutter'][2]['memory'].pop(),
                   lambda r: r['native'][3]['memory'][0].update(rssKiB=None),
                   lambda r: r['native'][3]['memory'][0].update(pid=999),
                   lambda r: r['native'][3]['memory'][0].update(endMs=0),
                   lambda r: r['native'][3]['memory'][1].update(beginMs=3020, endMs=3025),
                   lambda r: r['native'][3].update(pid=r['native'][2]['pid']),
                   lambda r: r['native'][0].update(warmup=False),
                   lambda r: r['native'][3].update(launchCommandWallMs=float('nan')),
                   lambda r: r['native'][3]['errors'].append('process vanished')]
        for change in changes:
            data = rows()
            change(data)
            with self.subTest(change=change):
                self.assertFalse(collector.summarize(data)['diagnosticCaptureComplete'])

    def test_launch_command_explicitly_replaces_process_without_data_reset(self):
        command = collector.launch_command('task-device')
        self.assertEqual(command[:3], ['xcrun', 'simctl', 'launch'])
        self.assertIn('--terminate-running-process', command)
        self.assertIn('task-device', command)
        self.assertEqual(command[-1], 'com.flynes.app')
        self.assertNotIn('erase', command)
        self.assertNotIn('uninstall', command)

    def test_environment_requires_explicit_debug_and_fixture_provenance(self):
        valid = dict(buildMode='Debug', fixtureId='seed-1', sourceRevision='abc',
                     coreRevision='def', flutterSdk='3.38.10')
        self.assertEqual(collector.validate_environment(valid), valid)
        for change in ({'buildMode': 'Release'}, {'buildMode': 'Profile'},
                       {'fixtureId': ''}, {'coreRevision': None}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                collector.validate_environment({**valid, **change})

    def test_artifact_identity_checks_simulator_bundle_and_debug_kernel(self):
        with tempfile.TemporaryDirectory() as tmp:
            app = Path(tmp) / 'FlyNES.app'
            app.mkdir()
            info = dict(CFBundleIdentifier='com.flynes.app', CFBundleExecutable='FlyNES',
                        DTPlatformName='iphonesimulator', CFBundleShortVersionString='3.0.0')
            (app / 'Info.plist').write_bytes(plistlib.dumps(info))
            (app / 'FlyNES').write_bytes(b'native executable fixture')
            native = collector.app_metadata(app, 'native')
            self.assertEqual(native['artifactFilesSha256']['FlyNES'], collector.sha256(app / 'FlyNES'))
            for name in ('Frameworks/Flutter.framework/Flutter', 'Frameworks/App.framework/App'):
                target = app / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(b'framework fixture')
            with self.assertRaises(ValueError):
                collector.app_metadata(app, 'native')
            with self.assertRaises(FileNotFoundError):
                collector.app_metadata(app, 'flutter')
            kernel = app / 'Frameworks/App.framework/flutter_assets/kernel_blob.bin'
            kernel.parent.mkdir()
            kernel.write_bytes(b'debug kernel fixture')
            self.assertEqual(len(collector.app_metadata(app, 'flutter')['artifactFilesSha256']), 5)
            info['DTPlatformName'] = 'iphoneos'
            (app / 'Info.plist').write_bytes(plistlib.dumps(info))
            with self.assertRaises(ValueError):
                collector.app_metadata(app, 'flutter')


if __name__ == '__main__':
    unittest.main()
