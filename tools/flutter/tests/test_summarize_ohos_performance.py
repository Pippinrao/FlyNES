import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

path = Path(__file__).resolve().parents[1] / 'summarize_ohos_performance.py'
module = None
if path.exists():
    spec = importlib.util.spec_from_file_location('oh_summary', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

class OhosSummaryTest(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(module, 'reviewable summary tool required')

    def test_incomplete_or_failed_capture_never_passes(self):
        self.assertFalse(module.summarize({})['captureComplete'])
        self.assertFalse(module.summarize({'complete': True, 'failure': 'failed'})['captureComplete'])

    def test_boolean_is_not_a_numeric_measurement(self):
        result = module.stats([True, False, -1, float('nan')])
        self.assertEqual(result['count'], 0)
        self.assertIsNone(result['maximum'])

    def test_zero_native_allocator_is_unavailable_not_zero_memory(self):
        result = module.summarize({'memory': [{'nativeAllocatedBytes': 0, 'pssKb': 1024}]})
        self.assertIsNone(result['memory']['nativeAllocatedBytes']['p95'])
        self.assertFalse(result['memory']['nativeAllocatedBytes']['available'])
        self.assertEqual(result['memory']['pssKb']['p95'], 1024)

    def test_memory_read_failure_cannot_report_complete_capture(self):
        report = {'complete': True, 'emulatedMs': 65000, 'newAutoRows': [{'id': 1}],
                  'counters': [{'beginMs': 0}], 'inputs': [{}],
                  'memory': [{'beginMs': 1, 'pssKb': -1, 'error': 'PSS read failed'}]}
        result = module.summarize(report)
        self.assertFalse(result['captureComplete'])
        self.assertEqual(result['validPssSamples'], 0)
        self.assertEqual(result['memoryReadErrors'],
                         [{'sampleIndex': 0, 'beginMs': 1, 'error': 'PSS read failed'}])
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'capture.json'
            source.write_text(json.dumps(report), encoding='utf-8')
            completed = subprocess.run([sys.executable, str(path), str(source)],
                                       text=True, capture_output=True)
            self.assertEqual(completed.returncode, 2, completed.stdout + completed.stderr)
            self.assertFalse(json.loads(completed.stdout)['captureComplete'])

    def test_partial_pss_failure_is_incomplete_but_zero_allocator_is_allowed(self):
        report = {'complete': True, 'emulatedMs': 65000, 'newAutoRows': [{'id': 1}],
                  'counters': [{'beginMs': 0}], 'inputs': [{}],
                  'memory': [{'pssKb': 1024, 'nativeAllocatedBytes': 0}]}
        self.assertTrue(module.summarize(report)['captureComplete'])
        for invalid in (-1, 0, None, True, float('nan')):
            report['memory'] = [{'pssKb': 1024}, {'pssKb': invalid}]
            with self.subTest(invalid=invalid):
                self.assertFalse(module.summarize(report)['captureComplete'])

    def test_observation_gap_and_save_window_are_explicit(self):
        counters = [{'beginMs': t, 'runtime': {'sourceFrames': n}, 'renderer': {}}
                    for t, n in [(0, 0), (20, 1), (40, 1), (100, 2)]]
        result = module.summarize({'counters': counters, 'memory': [
            {'beginMs': 0, 'endMs': 5, 'head': 7}, {'beginMs': 100, 'endMs': 110, 'head': 8}]})
        self.assertEqual(result['sourceGrowthObservationGapMs']['maximum'], 80)
        self.assertEqual(result['headChanges'][0]['newObservationEndMs'], 110)

    def test_resets_are_flagged_and_never_negative_delta(self):
        result = module.summarize({'counters': [
            {'beginMs': 0, 'runtime': {'audioUnderflows': 4}, 'renderer': {}},
            {'beginMs': 20, 'runtime': {'audioUnderflows': 9}, 'renderer': {}},
            {'beginMs': 40, 'runtime': {'audioUnderflows': 1}, 'renderer': {}}]})
        self.assertEqual(result['audio']['audioUnderflows']['observedIncrementsLowerBound'], 5)
        self.assertEqual(result['audio']['audioUnderflows']['resets'], 1)

if __name__ == '__main__':
    unittest.main()
