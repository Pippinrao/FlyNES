import importlib.util
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "summarize_save_performance.py"
summary = None
if SCRIPT.exists():
    spec = importlib.util.spec_from_file_location("save_summary", SCRIPT)
    summary = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(summary)


class SavePerformanceSummaryTest(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(summary, "summary tool must exist")

    def test_missing_measurements_remain_unavailable(self):
        result = summary.summarize({"coreFrameEvents": [], "memoryAndAudio": [], "automaticSaves": []}, "")
        self.assertIsNone(result["coreFrameGapMs"]["p95"])
        self.assertIsNone(result["pssKb"]["p95"])
        self.assertFalse(result["captureComplete"])

    def test_input_samples_filter_pid_and_time(self):
        report = {"processId": 42, "startedEpochMs": 100000, "finishedEpochMs": 102000}
        logs = "\n".join([
            "101.0 42 1 D FlyNES: touch-to-core-ns=3000000",
            "101.0 43 1 D FlyNES: touch-to-core-ns=999999999",
            "99.0 42 1 D FlyNES: touch-to-core-ns=999999999"])
        result = summary.summarize(report, logs)
        self.assertEqual(result["softwareTouchToCoreMs"]["count"], 1)
        self.assertEqual(result["softwareTouchToCoreMs"]["p95"], 3)

    def test_save_window_uses_record_time_and_skips_invalid_gaps(self):
        report = {"coreFrameEvents": [[1, 0, 1000], [2, 16000000, 1016],
                                      [3, 116000000, 1116], [4, 100000000, 1132]],
                  "automaticSaves": [{"createdMs": 1100}]}
        result = summary.summarize(report, "")
        self.assertEqual(result["coreFrameGapMs"]["count"], 2)
        self.assertEqual(result["saveWindowCoreGapMs"]["max"], 100)
        self.assertEqual(result["invalidFrameGapCount"], 1)

    def test_audio_counter_reset_is_not_a_negative_underrun(self):
        report = {"memoryAndAudio": [{"audioUnderruns": n} for n in [2, 5, 0, 1]]}
        result = summary.summarize(report, "")
        self.assertEqual(result["observedUnderrunIncrementsLowerBound"], 4)
        self.assertEqual(result["audioCounterResetCount"], 1)

    def test_complete_requires_elapsed_simulation_and_actual_new_save(self):
        report = {"playedMs": 65000, "wallMs": 66000,
                  "coreFrameEvents": [[1, 0, 0], [2, 16000000, 16]],
                  "memoryAndAudio": [{"pssKb": 123}], "automaticSaves": [{"createdMs": 60000}]}
        self.assertTrue(summary.summarize(report, "")["captureComplete"])
        report["automaticSaves"] = []
        self.assertFalse(summary.summarize(report, "")["captureComplete"])


if __name__ == "__main__":
    unittest.main()
