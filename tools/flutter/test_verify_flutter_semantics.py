import json
from pathlib import Path
import tempfile
import unittest
import verify_flutter_semantics as checker

TREE = '''SemanticsNode#0
 │ Rect.fromLTRB(0.0, 0.0, 800.0, 360.0)
 └─SemanticsNode#12
   │ sortKey: OrdinalSortKey#abcde(order: 0.0)
   │ Rect.fromLTRB(16.0, 20.0, 64.0, 68.0)
   │ identifier: "source-remove-A"
   │ label: "Remove SemanticsNode#123 OrdinalSortKey#abcde"
   │ actions: focus, tap
   │ flags: isButton, isEnabled
'''

class FullSemanticsTests(unittest.TestCase):
    def test_only_runtime_identity_changes_pass(self):
        actual = TREE.replace('SemanticsNode#0\n', 'SemanticsNode#999\n').replace('└─SemanticsNode#12', '└─SemanticsNode#44').replace('sortKey: OrdinalSortKey#abcde', 'sortKey: OrdinalSortKey#01010')
        self.assertTrue(checker.compare_text(TREE, actual)['passed'])
        changed_label = TREE.replace('Remove SemanticsNode#123', 'Remove SemanticsNode#456')
        self.assertFalse(checker.compare_text(TREE, changed_label)['passed'])

    def test_identifier_hierarchy_missing_node_and_bounds_fail(self):
        for actual in [TREE.replace('source-remove-A', 'source-remove-B'),
                       TREE.replace(' └─SemanticsNode', '   └─SemanticsNode'),
                       TREE.split(' └─')[0], TREE.replace('64.0, 68.0', '66.0, 68.0'),
                       TREE.replace('focus, tap', 'focus'), TREE.replace('isEnabled', 'isHidden'),
                       TREE.replace('order: 0.0', 'order: 1.0')]:
            with self.subTest(actual=actual): self.assertFalse(checker.compare_text(TREE, actual)['passed'])
        self.assertFalse(checker.compare_text('', '')['passed'])
        self.assertFalse(checker.compare_text('not a tree', 'not a tree')['passed'])

    def fixture(self, root, ids=('one', 'two')):
        root.mkdir(parents=True)
        manifest = []
        for name in ids:
            (root / (name + '.semantics.txt')).write_text(TREE, encoding='utf-8')
            manifest.append({'id': name, 'semantics': name + '.semantics.txt'})
        (root / 'manifest.json').write_text(json.dumps(manifest))

    def test_complete_family_and_exact_inventory(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); self.fixture(root/'expected'); self.fixture(root/'actual')
            report=checker.verify(root/'expected',root/'actual',root/'output')
            self.assertTrue(report['passed']); self.assertEqual(len(report['cases']),2)
            self.fixture(root/'actual'/'unexpected-family', ('third',))
            self.assertFalse(checker.verify(root/'expected',root/'actual',root/'more')['passed'])

    def test_missing_file_case_family_and_duplicates_fail(self):
        for mutation in ('file','case','duplicate','family'):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp); self.fixture(root/'expected'/'visual'); self.fixture(root/'actual'/'visual')
                manifest=root/'actual'/'visual'/'manifest.json'
                if mutation=='file': (manifest.parent/'one.semantics.txt').unlink()
                elif mutation=='case': manifest.write_text(json.dumps([{'id':'one','semantics':'one.semantics.txt'}]))
                elif mutation=='duplicate': manifest.write_text(json.dumps([{'id':'one','semantics':'one.semantics.txt'}]*2))
                else: self.fixture(root/'expected'/'animation', ('frame',))
                report=checker.verify(root/'expected',root/'actual',root/'output')
                self.assertFalse(report['passed'])
                self.assertTrue(report['inventoryErrors'] or any(not x['passed'] for x in report['cases']))

    def test_difference_artifacts_and_unlisted_semantics_fail(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); self.fixture(root/'expected'); self.fixture(root/'actual')
            (root/'actual'/'one.semantics.txt').write_text(TREE.replace('source-remove-A','source-remove-B'))
            report=checker.verify(root/'expected',root/'actual',root/'output')
            self.assertFalse(report['passed']); changed=next(c for c in report['cases'] if c['id']=='one')
            self.assertIn('source-remove-B',Path(changed['diff']).read_text())
            (root/'actual'/'extra.semantics.txt').write_text(TREE)
            self.assertTrue(checker.verify(root/'expected',root/'actual',root/'more')['inventoryErrors'])

    def test_multiline_label_identity_text_and_line_endings_are_preserved(self):
        label = TREE + '   │ label: "Text\n   │ SemanticsNode#123\n   │ end"\n'
        self.assertFalse(checker.compare_text(label, label.replace('│ SemanticsNode#123', '│ SemanticsNode#456'))['passed'])
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); self.fixture(root/'expected'); self.fixture(root/'actual')
            (root/'expected'/'one.semantics.txt').write_bytes(TREE.encode())
            (root/'actual'/'one.semantics.txt').write_bytes(TREE.replace('\n','\r\n').encode())
            self.assertFalse(checker.verify(root/'expected',root/'actual',root/'output')['passed'])

if __name__=='__main__': unittest.main()
