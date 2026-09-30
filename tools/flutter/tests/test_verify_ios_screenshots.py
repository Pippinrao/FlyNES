import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import subprocess
import sys

from PIL import Image

TOOL = Path(__file__).resolve().parents[1] / 'verify_ios_screenshots.py'
SPEC = importlib.util.spec_from_file_location('ios_visuals', TOOL)
ios = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ios)

TREE = """Attributes: Application, 0x1, pid: 13, label: 'FlyNES'
Element subtree:
 →Application, 0x1, pid: 13, label: 'FlyNES'
    Window (Main), 0x2, {{0.0, 0.0}, {50.0, 50.0}}
      Other, 0x3, {{0.0, 0.0}, {50.0, 50.0}}
        Button, 0x4, {{2.0, 3.0}, {24.0, 24.0}}, identifier: 'play', label: 'Start', Selected
        Switch, 0x5, {{2.0, 28.0}, {24.0, 20.0}}, label: 'Sound', value: 1
Path to element:
 →Application, 0x99, pid: 13, label: 'FlyNES'
Query chain:
 →Find: Target Application 'com.flynes.app'
"""
ENV = {'environmentId': 'reviewed-ios-environment', 'platform': 'ios', 'sdk': '3.38.10',
       'runtime': 'iOS 16.4', 'device': 'iPhone SE 2', 'pixelRatio': 2}


class IOSVisualGateTest(unittest.TestCase):
    def fixture(self, root):
        expected, actual, output = root/'expected', root/'actual', root/'report'
        for directory in (expected, actual):
            directory.mkdir()
            Image.new('RGB', (100, 100), 'black').save(directory/'hall.png')
            (directory/'hall-semantics.txt').write_text(TREE, encoding='utf-8')
            (directory/'environment.json').write_text(json.dumps(ENV), encoding='utf-8')
        return expected, actual, output

    def test_addresses_pid_and_anonymous_wrappers_are_not_semantic_evidence(self):
        before = ios.parse_xctest(TREE)
        after = ios.parse_xctest(TREE.replace('0x4', '0xabcd').replace('pid: 13', 'pid: 700')
                                 .replace("      Other, 0x3, {{0.0, 0.0}, {50.0, 50.0}}\n", ''))
        self.assertEqual(before, after)
        self.assertEqual(len(before['facts']), 2)
        self.assertEqual(len(before['geometry']), 2)
        self.assertIn('Start', str(before['facts']))

    def test_multiline_labels_values_flags_and_duplicate_order_survive(self):
        tree = TREE.replace("label: 'Start'", "label: 'Owner's game\nvalue: keep this text'")
        tree = tree.replace('Path to element:',
                            "        Button, 0x9, {{27.0, 3.0}, {20.0, 24.0}}, label: 'Again'\n"
                            "        Button, 0xa, {{27.0, 28.0}, {20.0, 20.0}}, label: 'Again', Disabled\nPath to element:")
        parsed = ios.parse_xctest(tree)
        self.assertIn("Owner's game\nvalue: keep this text", str(parsed['facts']).replace('\\n', '\n'))
        self.assertIn('Selected', str(parsed['facts']))
        self.assertIn('Disabled', str(parsed['facts']))
        self.assertEqual(len(parsed['geometry']), 4)
        self.assertNotEqual(ios.parse_xctest(tree.replace('value: 1', 'value: 0'))['facts'], parsed['facts'])
        self.assertNotEqual(ios.parse_xctest(tree.replace("label: 'Again', Disabled", "label: 'Different', Disabled"))['facts'], parsed['facts'])

    def test_empty_non_xctest_and_malformed_rectangles_are_rejected(self):
        for tree in ('', 'SemanticsNode#1 label: Start', TREE.replace('24.0, 24.0', 'nan, 24.0'),
                     TREE.replace('24.0, 24.0', '-1.0, 24.0'), TREE.replace("label: 'Start'", "label: 'unclosed")):
            with self.subTest(tree=tree), self.assertRaises(ValueError):
                ios.parse_xctest(tree)

    def test_unquoted_value_preserves_commas_and_multiline_legal_text(self):
        value = 'First line, literal pid: 42\nSecond line, remains text'
        parsed = ios.parse_xctest(TREE.replace('value: 1', 'value: ' + value))
        self.assertEqual(parsed['facts'][1]['attributes']['value'], value)

    def test_matching_xctest_capture_outputs_all_artifacts_without_approval_claim(self):
        with tempfile.TemporaryDirectory() as folder:
            paths = self.fixture(Path(folder))
            report = ios.verify(*paths)
            self.assertTrue(report['passed'])
            for suffix in ('actual.png', 'expected.png', 'diff.png'):
                self.assertTrue((paths[2]/f'hall-{suffix}').is_file())
            self.assertTrue((paths[2]/'report.json').is_file())
            self.assertNotIn('reviewSha256', json.dumps(report))

    def test_native_xctest_exif_orientation_is_honored_without_resampling(self):
        with tempfile.TemporaryDirectory() as folder:
            expected, actual, output = self.fixture(Path(folder))
            tree = TREE.replace('{50.0, 50.0}', '{80.0, 50.0}')
            for directory in (expected, actual):
                (directory/'hall-semantics.txt').write_text(tree, encoding='utf-8')
            logical = Image.new('RGB', (160, 100), 'black')
            for x in range(10):
                for y in range(20): logical.putpixel((x,y), (255,30,40))
            native = logical.transpose(Image.Transpose.ROTATE_270)
            exif = native.getexif(); exif[274] = 8
            native.save(expected/'hall.png', exif=exif)
            logical.save(actual/'hall.png')
            before = (expected/'hall.png').read_bytes()
            report = ios.verify(expected, actual, output)
            self.assertTrue(report['passed'], report)
            self.assertEqual(report['cases'][0]['outlierRatio'], 0)
            self.assertEqual((expected/'hall.png').read_bytes(), before)
            self.assertEqual((output/'hall-expected.png').read_bytes(), before)
            with Image.open(output/'hall-diff.png') as diff: self.assertEqual(diff.size, (160,100))

    def test_wrong_text_missing_control_and_changed_value_fail_identical_pixels(self):
        for changed in (TREE.replace("'Start'", "'Stop'"),
                        '\n'.join(line for line in TREE.splitlines() if 'Switch,' not in line),
                        TREE.replace('value: 1', 'value: 0'), TREE.replace(', Selected', ', Disabled')):
            with self.subTest(changed=changed), tempfile.TemporaryDirectory() as folder:
                paths = self.fixture(Path(folder))
                (paths[1]/'hall-semantics.txt').write_text(changed, encoding='utf-8')
                report = ios.verify(*paths)
                self.assertFalse(report['passed'])
                self.assertTrue(report['cases'][0]['integrityFailures'])

    def test_geometry_is_measured_in_xctest_points_with_one_point_limit(self):
        for delta, passed in ((1, True), (1.01, False)):
            with self.subTest(delta=delta), tempfile.TemporaryDirectory() as folder:
                paths = self.fixture(Path(folder))
                (paths[1]/'hall-semantics.txt').write_text(TREE.replace('{2.0, 3.0}', f'{{{2 + delta}, 3.0}}'), encoding='utf-8')
                report = ios.verify(*paths)
                self.assertEqual(report['passed'], passed)
                self.assertEqual(bool(report['cases'][0]['geometryFailures']), not passed)

    def test_existing_channel_eight_and_half_percent_limits_are_used(self):
        for channel, pixels, passed in ((8, 10000, True), (9, 50, True), (9, 51, False)):
            with self.subTest(channel=channel, pixels=pixels), tempfile.TemporaryDirectory() as folder:
                paths = self.fixture(Path(folder))
                image = Image.new('RGB', (100, 100), 'black')
                for index in range(pixels): image.putpixel((index % 100, index // 100), (channel, 0, 0))
                image.save(paths[1]/'hall.png')
                report = ios.verify(*paths)
                self.assertEqual(report['passed'], passed)
                self.assertEqual(report['channelTolerance'], 8)
                self.assertEqual(report['maxOutlierRatio'], .005)
                self.assertEqual(report['maxGeometryDelta'], 1)

    def test_missing_image_semantics_or_environment_fails(self):
        for side in (0, 1):
            for name in ('hall.png', 'hall-semantics.txt', 'environment.json'):
                with self.subTest(side=side, name=name), tempfile.TemporaryDirectory() as folder:
                    paths = self.fixture(Path(folder)); (paths[side]/name).unlink()
                    self.assertFalse(ios.verify(*paths)['passed'])

    def test_incomplete_different_or_invalid_environment_fails(self):
        for environment in ({}, {'environmentId': 'same'}, {**ENV, 'runtime': 'iOS 17'},
                            {**ENV, 'pixelRatio': True}, {**ENV, 'environmentId': ''}):
            with self.subTest(environment=environment), tempfile.TemporaryDirectory() as folder:
                paths = self.fixture(Path(folder))
                (paths[1]/'environment.json').write_text(json.dumps(environment), encoding='utf-8')
                self.assertFalse(ios.verify(*paths)['passed'])
        with tempfile.TemporaryDirectory() as folder:
            paths = self.fixture(Path(folder)); (paths[0]/'environment.json').write_text('{')
            self.assertFalse(ios.verify(*paths)['passed'])

    def test_added_capture_or_orphan_semantics_and_empty_directories_fail(self):
        for name in ('extra.png', 'extra-semantics.txt'):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as folder:
                paths = self.fixture(Path(folder)); (paths[1]/name).write_bytes(b'extra')
                self.assertFalse(ios.verify(*paths)['passed'])
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); (root/'expected').mkdir(); (root/'actual').mkdir()
            self.assertFalse(ios.verify(root/'expected', root/'actual', root/'report')['passed'])

    def test_bad_png_size_mismatch_and_empty_tree_fail_with_report(self):
        for problem in ('invalid', 'size', 'empty'):
            with self.subTest(problem=problem), tempfile.TemporaryDirectory() as folder:
                paths = self.fixture(Path(folder))
                if problem == 'invalid': (paths[1]/'hall.png').write_bytes(b'invalid')
                elif problem == 'size': Image.new('RGB', (101, 100)).save(paths[1]/'hall.png')
                else: (paths[1]/'hall-semantics.txt').write_text('')
                self.assertFalse(ios.verify(*paths)['passed'])
                self.assertTrue((paths[2]/'report.json').is_file())

    def test_output_cannot_overwrite_or_be_inside_inputs(self):
        with tempfile.TemporaryDirectory() as folder:
            paths = self.fixture(Path(folder))
            for output in (paths[0], paths[1]/'diffs', Path(folder)):
                with self.subTest(output=output), self.assertRaises(ValueError):
                    ios.verify(paths[0], paths[1], output)

    def test_declared_pixel_ratio_must_explain_actual_xctest_point_viewport(self):
        with tempfile.TemporaryDirectory() as folder:
            paths = self.fixture(Path(folder))
            for directory in paths[:2]:
                (directory/'environment.json').write_text(json.dumps({**ENV, 'pixelRatio': 3}))
            self.assertFalse(ios.verify(*paths)['passed'])

    def test_cli_reports_failure_in_exit_code(self):
        with tempfile.TemporaryDirectory() as folder:
            paths = self.fixture(Path(folder))
            command = [sys.executable, str(TOOL), '--expected', str(paths[0]),
                       '--actual', str(paths[1]), '--output', str(paths[2])]
            self.assertEqual(subprocess.run(command, capture_output=True).returncode, 0)
            (paths[1]/'hall-semantics.txt').unlink()
            self.assertEqual(subprocess.run(command, capture_output=True).returncode, 1)


if __name__ == '__main__': unittest.main()
