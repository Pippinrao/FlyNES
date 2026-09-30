import importlib.util
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('run_two_ios_ui_peers.py')
spec = importlib.util.spec_from_file_location('two_ui', SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class TwoAppUIContractTests(unittest.TestCase):
    def test_rejects_same_simulator_and_unknown_filter(self):
        with self.assertRaises(ValueError):
            module.validate_request('A', 'A', module.TESTS, 480)
        with self.assertRaises(ValueError):
            module.validate_request('A', 'B', {'host': 'NearbyLiveRoomUITests/testFake', 'guest': module.TESTS['guest']}, 480)
        with self.assertRaises(ValueError):
            module.validate_request('A', 'B', module.TESTS, 99999)

    def test_only_exact_successful_role_tests_pass(self):
        item = {'identifier': {'_value': module.TESTS['host']}, 'testStatus': {'_value': 'Success'}}
        self.assertTrue(module.validate_result(item, module.TESTS['host']))
        self.assertFalse(module.validate_result(item, module.TESTS['guest']))
        self.assertFalse(module.validate_result([item, item], module.TESTS['host']))
        item['testStatus']['_value'] = 'Skipped'
        self.assertFalse(module.validate_result(item, module.TESTS['host']))
        self.assertFalse(module.validate_result({}, module.TESTS['host']))

    def test_fixture_identity_and_real_ui_input_are_required(self):
        report = {'run': 'R', 'role': 'host', 'pid': 7, 'phase': 'done',
                  'replaceCount': 1, 'firstInputDelta': 2, 'secondInputDelta': 3,
                  'firstGeneration': 2, 'resumedGeneration': 2, 'secondGeneration': 3}
        self.assertTrue(module.validate_phase(report, 'R', 'host'))
        for field, value in [('run', 'old'), ('role', 'guest'), ('firstInputDelta', 0),
                             ('secondInputDelta', 0), ('replaceCount', 2),
                             ('resumedGeneration', 3), ('secondGeneration', 2)]:
            changed = dict(report, **{field: value})
            self.assertFalse(module.validate_phase(changed, 'R', 'host'), field)

    def test_owned_cleanup_preserves_changed_or_unregistered_files(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            owned = root / 'secret'; untouched = root / 'other'
            owned.write_bytes(b'invite'); untouched.write_bytes(b'user')
            registry = module.OwnedFiles(); registry.observe(owned)
            owned.write_bytes(b'changed')
            self.assertEqual(len(registry.cleanup()), 1)
            self.assertTrue(owned.exists()); self.assertEqual(untouched.read_bytes(), b'user')
            owned.write_bytes(b'invite')
            self.assertEqual(registry.cleanup(), [])
            self.assertFalse(owned.exists())

if __name__ == '__main__': unittest.main()
