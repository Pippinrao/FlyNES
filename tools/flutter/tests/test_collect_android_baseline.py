"""Offline regression tests; these never contact adb or mutate an installation."""
import importlib.util
from pathlib import Path
import unittest
from tempfile import TemporaryDirectory
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "collect_android_baseline.py"
baseline = None
if SCRIPT.exists():
    spec = importlib.util.spec_from_file_location("baseline", SCRIPT)
    baseline = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(baseline)


def line(event, fields, pid=42, epoch=1000.5):
    return f"{epoch:.3f} {pid} 99 I FlyNesStartup: {event} {fields}\n"


class CollectorExistsTest(unittest.TestCase):
    def test_collector_is_implemented(self):
        self.assertIsNotNone(baseline, "safe baseline collector has not been implemented")


@unittest.skipIf(baseline is None, "collector not implemented yet")
class ParserTests(unittest.TestCase):
    def test_current_process_first_cards_are_not_full_projection(self):
        logs = line("GAME_CENTER_VISIBLE", "elapsedMs=92 count=2224 cache=HIT")
        logs += line("CACHE_DECODED", "elapsedMs=50 status=HIT count=2224")
        logs += line("NATIVE_READY", "elapsedMs=850 status=OK")
        sample = baseline.parse_markers(logs, 42, 1000.0)
        self.assertEqual(sample["firstPaintMs"], 92)
        self.assertEqual(sample["firstPaintReportedCount"], 2224)
        self.assertIsNone(sample["renderedFullListCount"])
        self.assertEqual(sample["startupCacheDecodedMs"], 50)
        self.assertEqual(sample["nativeReadyMs"], 850)
        self.assertIsNone(sample["fullProjectionAvailableMs"])
        self.assertEqual(sample["fullProjectionStatus"], "blocked_no_marker")

    def test_old_pid_and_old_timestamp_and_wrong_tag_are_ignored(self):
        logs = line("GAME_CENTER_VISIBLE", "elapsedMs=1 count=9000 cache=HIT", pid=7)
        logs += line("NATIVE_READY", "elapsedMs=1 status=OK", epoch=999.0)
        logs += line("CACHE_DECODED", "elapsedMs=1 status=HIT count=9000").replace(
            "FlyNesStartup:", "Unrelated:")
        sample = baseline.parse_markers(logs, 42, 1000.0)
        self.assertIsNone(sample["firstPaintMs"])
        self.assertIsNone(sample["nativeReadyMs"])
        self.assertIsNone(sample["startupCacheDecodedMs"])

    def test_shell_marker_does_not_count_as_first_cards(self):
        sample = baseline.parse_markers(line("GAME_CENTER_SHELL_VISIBLE", "elapsedMs=20"), 42, 1000)
        self.assertIsNone(sample["firstPaintMs"])
        self.assertEqual(sample["shellVisibleMs"], 20)

    def test_first_exact_marker_wins_and_failed_native_has_no_ready_time(self):
        logs = line("GAME_CENTER_VISIBLE", "elapsedMs=99 count=4 cache=HIT")
        logs += line("GAME_CENTER_VISIBLE", "elapsedMs=800 count=2224 cache=HIT")
        logs += line("NATIVE_READY", "elapsedMs=900 status=FAILED")
        sample = baseline.parse_markers(logs, 42, 1000)
        self.assertEqual(sample["firstPaintMs"], 99)
        self.assertIsNone(sample["nativeReadyMs"])
        self.assertEqual(sample["status"], "failed")

    def test_missing_markers_timeout_is_blocked_not_zero(self):
        sample = baseline.parse_markers("", 42, 1000, timed_out=True)
        self.assertEqual(sample["status"], "blocked")
        self.assertTrue(sample["timedOut"])
        self.assertEqual(set(sample["missingMarkers"]), {
            "GAME_CENTER_VISIBLE", "CACHE_DECODED", "NATIVE_READY",
            "CATALOG_PROJECTION_AVAILABLE", "GAME_CENTER_FULL_LIST_VISIBLE"})
        self.assertIsNone(sample["firstPaintMs"])

    def test_malformed_and_negative_fields_are_missing(self):
        logs = line("GAME_CENTER_VISIBLE", "elapsedMs=-1 count=bad cache=HIT")
        logs += line("NATIVE_READY", "elapsedMs=oops status=OK")
        sample = baseline.parse_markers(logs, 42, 1000)
        self.assertIsNone(sample["firstPaintMs"])
        self.assertIsNone(sample["nativeReadyMs"])

    def test_full_projection_is_not_inferred_from_later_list_submit(self):
        logs = line("LIST_SUBMIT", "elapsedMs=999 count=2224")
        sample = baseline.parse_markers(logs, 42, 1000)
        self.assertIsNone(sample["fullProjectionAvailableMs"])

    def test_projection_and_full_list_first_card_have_separate_markers(self):
        logs = line("CATALOG_PROJECTION_AVAILABLE", "elapsedMs=401 count=2224 source=cache")
        logs += line("GAME_CENTER_FULL_LIST_VISIBLE", "elapsedMs=550 count=2224 cache=HIT")
        sample = baseline.parse_markers(logs, 42, 1000)
        self.assertEqual(sample["fullProjectionAvailableMs"], 401)
        self.assertEqual(sample["fullProjectionCount"], 2224)
        self.assertEqual(sample["fullProjectionSource"], "cache")
        self.assertEqual(sample["fullListFirstCardVisibleMs"], 550)
        self.assertIsNone(sample["renderedFullListCount"])

    def test_am_time_and_memory_missing_are_null(self):
        self.assertIsNone(baseline.parse_am_start("Status: ok")["totalTimeMs"])
        self.assertEqual(baseline.parse_am_start("TotalTime: 123\nWaitTime: 130")["totalTimeMs"], 123)
        self.assertIsNone(baseline.parse_pss("Permission denied"))
        self.assertEqual(baseline.parse_pss(" TOTAL PSS: 42321 TOTAL RSS: 50000"), 42321)
        self.assertEqual(baseline.parse_pss(" TOTAL 42321 100 200 123"), 42321)


@unittest.skipIf(baseline is None, "collector not implemented yet")
class AggregationTests(unittest.TestCase):
    def test_nearest_rank_p95_and_missing_values(self):
        self.assertEqual(baseline.nearest_rank_p95(list(range(1, 21))), 19)
        self.assertEqual(baseline.nearest_rank_p95([None, 70, 80]), 80)
        self.assertIsNone(baseline.nearest_rank_p95([None]))

    def test_warmups_excluded_and_partial_gate_blocked(self):
        samples = [{"kind": "warmup", "firstPaintMs": 1000}]
        samples += [{"kind": "measured", "firstPaintMs": 80} for _ in range(10)]
        result = baseline.aggregate(samples, 10)
        self.assertEqual(result["metrics"]["firstPaintMs"]["p95"], 80)
        self.assertEqual(result["firstVisible200msGate"]["status"], "pass")
        self.assertIsNone(result["metrics"]["fullProjectionAvailableMs"]["p95"])
        samples[-1]["firstPaintMs"] = None
        self.assertEqual(baseline.aggregate(samples, 10)["firstVisible200msGate"]["status"], "blocked")

    def test_minimum_runs_and_bound_timeout(self):
        parser = baseline.make_parser()
        args = parser.parse_args(["--serial", "test", "--output", "out"])
        self.assertEqual((args.runs, args.warmups), (12, 2))
        with self.assertRaises(ValueError):
            baseline.validate_options(parser.parse_args(["--serial", "test", "--output", "out", "--runs", "9"]))
        self.assertLessEqual(baseline.MARKER_TIMEOUT_SECONDS, 15)


@unittest.skipIf(baseline is None, "collector not implemented yet")
class CollectionTests(unittest.TestCase):
    def test_launch_exhausting_deadline_retains_am_time_and_missing_nulls(self):
        class Device:
            def call(self, *args, **kwargs):
                if args == ("shell", "am", "force-stop", baseline.PACKAGE):
                    return ""
                if args == ("shell", "date", "+%s.%N"):
                    return "1000.000000000"
                if args[:3] == ("shell", "am", "start"):
                    return "Status: ok\nTotalTime: 14900\n"
                raise AssertionError(f"Unexpected device command: {args}")
        with TemporaryDirectory() as folder, patch.object(baseline.time, "monotonic", side_effect=[0, 15, 15]):
            sample = baseline.collect_run(Device(), Path(folder), "measured", 1)
        self.assertEqual(sample["status"], "blocked")
        self.assertTrue(sample["timedOut"])
        self.assertEqual(sample["amStartTotalTimeMs"], 14900)
        self.assertEqual(sample["amStartWallMs"], 15000)
        self.assertIsNone(sample["firstPaintMs"])
        self.assertIsNone(sample["settledPssKb"])

    def test_complete_launch_filters_other_pids_and_keeps_command_surface_safe(self):
        logs = line("GAME_CENTER_VISIBLE", "elapsedMs=2 count=9 cache=HIT", pid=19)
        logs += line("GAME_CENTER_VISIBLE", "elapsedMs=100 count=2231 cache=HIT")
        logs += line("CACHE_DECODED", "elapsedMs=50 count=2231 status=HIT")
        logs += line("NATIVE_READY", "elapsedMs=800 status=OK")
        logs += line("CATALOG_PROJECTION_AVAILABLE", "elapsedMs=200 count=2231 source=cache")
        logs += line("GAME_CENTER_FULL_LIST_VISIBLE", "elapsedMs=900 count=2231 cache=HIT")
        class Device:
            def call(self, *args, **kwargs):
                if args == ("shell", "am", "force-stop", baseline.PACKAGE):
                    return ""
                if args == ("shell", "date", "+%s.%N"):
                    return "1000.000000000"
                if args[:3] == ("shell", "am", "start"):
                    return "Status: ok\nTotalTime: 102\n"
                if args == ("shell", "pidof", baseline.PACKAGE):
                    return "42"
                if args == ("logcat", "-d", "-v", "epoch", "--pid=42", "-s", "FlyNesStartup:I", "*:S"):
                    return logs
                if args == ("shell", "dumpsys", "meminfo", "42"):
                    return " TOTAL PSS: 98765 TOTAL RSS: 120000"
                raise AssertionError(f"Unexpected device command: {args}")
        with TemporaryDirectory() as folder, patch.object(baseline.time, "sleep"):
            sample = baseline.collect_run(Device(), Path(folder), "measured", 1)
            saved = (Path(folder) / "measured-01-markers.log").read_text()
        self.assertEqual(sample["status"], "collected")
        self.assertFalse(sample["timedOut"])
        self.assertEqual(sample["firstPaintMs"], 100)
        self.assertEqual(sample["settledPssKb"], 98765)
        self.assertNotIn("count=9 ", saved)


if __name__ == "__main__":
    unittest.main()
