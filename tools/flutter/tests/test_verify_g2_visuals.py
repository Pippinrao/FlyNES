import importlib.util
from pathlib import Path
import tempfile
import json
import unittest
from PIL import Image

spec = importlib.util.spec_from_file_location('visuals', Path(__file__).resolve().parents[1] / 'verify_g2_visuals.py')
visuals = importlib.util.module_from_spec(spec)
spec.loader.exec_module(visuals)

class VisualGateTest(unittest.TestCase):
    def fixture(self, root):
        actual, expected = root/'actual', root/'expected'
        actual.mkdir(); expected.mkdir()
        case = {'id':'hall','image':'hall.png','geometry':'hall.json','semantics':'hall.txt', 'width':100,'height':100,'locale':'en','textScale':1}
        for directory in [actual, expected]:
            Image.new('RGBA',(100,100)).save(directory/'hall.png')
            (directory/'hall.json').write_text(json.dumps({'button':[10,10,48,48]}))
            (directory/'hall.txt').write_text('SemanticsNode#1\n label: "Start"\n actions: focus, tap\n flags: isButton, isEnabled\n')
            (directory/'manifest.json').write_text(json.dumps([case]))
            (directory/'environment.json').write_text(json.dumps({'sdk':'frozen-sdk', 'fonts':{'Roboto':'abc'},'surface':'flutter-tester'}))
        review = root/'review.json'
        review.write_text(json.dumps({'hall':{'status':'reviewed','sha256':visuals.sha256(expected/'hall.png'), 'geometrySha256':visuals.sha256(expected/'hall.json'),'semanticsSha256':visuals.sha256(expected/'hall.txt')}}))
        return actual,expected,review,root/'report'

    def test_environment_and_semantic_changes_fail_even_when_pixels_match(self):
        with tempfile.TemporaryDirectory() as folder:
            paths=self.fixture(Path(folder))
            self.assertTrue(visuals.verify(*paths)['passed'])
            (paths[0]/'hall.txt').write_text('SemanticsNode#9\n label: "Start"\n flags: isButton\n')
            self.assertFalse(visuals.verify(*paths)['passed'])
        with tempfile.TemporaryDirectory() as folder:
            paths=self.fixture(Path(folder))
            (paths[0]/'environment.json').write_text(json.dumps({'sdk':'other-sdk'}))
            self.assertFalse(visuals.verify(*paths)['passed'])

    def test_multiline_labels_and_wrapped_flags_are_compared(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder)
            text='SemanticsNode#1\n │ label:\n │   "Edit layout\n │   Recommended layout"\n │ flags: isButton,\n │   isEnabled\n'
            before=root/'before.txt';after=root/'after.txt'
            before.write_text(text,encoding='utf-8')
            after.write_text(text.replace('Recommended','Custom'),encoding='utf-8')
            self.assertNotEqual(visuals.semantic_facts(before),visuals.semantic_facts(after))
            self.assertIn('Recommended layout',str(visuals.semantic_facts(before)))
            after.write_text(text.replace('SemanticsNode#1','SemanticsNode#999'),encoding='utf-8')
            self.assertEqual(visuals.semantic_facts(before),visuals.semantic_facts(after))

    def test_metadata_like_words_inside_quoted_multiline_label_are_text(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder)
            text='SemanticsNode#1\n │ label:\n │   "License\n │   Source: https://example.org\n │   value: permission granted"\n │ textDirection: ltr\n'
            before=root/'before.txt';after=root/'after.txt'
            before.write_text(text,encoding='utf-8')
            after.write_text(text.replace('example.org','changed.example'),encoding='utf-8')
            self.assertNotEqual(visuals.semantic_facts(before),visuals.semantic_facts(after))
            self.assertIn('value: permission granted',visuals.semantic_facts(before)[0][1])

    def test_empty_or_unreviewed_geometry_is_not_evidence(self):
        with tempfile.TemporaryDirectory() as folder:
            paths=self.fixture(Path(folder))
            (paths[0]/'hall.json').write_text('{}')
            (paths[1]/'hall.json').write_text('{}')
            self.assertFalse(visuals.verify(*paths)['passed'])
        with tempfile.TemporaryDirectory() as folder:
            paths=self.fixture(Path(folder))
            (paths[0]/'hall.txt').write_text('')
            (paths[1]/'hall.txt').write_text('')
            self.assertFalse(visuals.verify(*paths)['passed'])

    def test_animation_frame_time_cannot_change_with_identical_pixels(self):
        with tempfile.TemporaryDirectory() as folder:
            paths = self.fixture(Path(folder))
            for directory, elapsed in ((paths[0], 120), (paths[1], 60)):
                manifest = json.loads((directory/'manifest.json').read_text())
                manifest[0].update(elapsedMs=elapsed, clock='Flutter controlled test clock')
                (directory/'manifest.json').write_text(json.dumps(manifest))
            self.assertFalse(visuals.verify(*paths)['passed'], 'end pixels must not impersonate a middle frame')
    def test_channel_and_pixel_limits_are_fixed(self):
        expected = Image.new('RGBA', (100, 100), (30,30,30,255))
        actual = Image.new('RGBA', (100, 100), (38,38,38,255))
        self.assertTrue(visuals.compare(expected,actual)['passed'])
        for x in range(51): actual.putpixel((x,0),(39,30,30,255))
        self.assertFalse(visuals.compare(expected,actual)['passed'])
        self.assertAlmostEqual(visuals.compare(expected,actual)['outlierRatio'], .0051)

    def test_geometry_overrides_small_pixel_difference(self):
        image = Image.new('RGBA',(100,100))
        self.assertFalse(visuals.compare(image,image, {'button':[10,10,48,48]}, {'button':[12,10,48,48]})['passed'])
        self.assertTrue(visuals.compare(image,image, {'button':[10,10,48,48]}, {'button':[11,10,48,48]})['passed'])

    def test_missing_semantics_and_size_are_failures(self):
        image = Image.new('RGBA',(100,100))
        self.assertFalse(visuals.compare(image,image, {'button':[10,10,48,48]}, {})['passed'])
        self.assertFalse(visuals.compare(image,Image.new('RGBA',(101,100)))['passed'])

if __name__ == '__main__': unittest.main()
