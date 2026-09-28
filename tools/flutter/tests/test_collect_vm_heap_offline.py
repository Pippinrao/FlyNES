"""CLI preflight and local fake-protocol tests; never connect to a real VM."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[3]
SDK = Path(os.environ.get("FLYNES_FLUTTER_OH_SDK", "E:/workspace/lib/flutter/flutter-ohos-3.41.10-1.0.0"))
DART = SDK / "bin/cache/dart-sdk/bin/dart.exe"
PACKAGES = SDK / "packages/flutter_tools/.dart_tool/package_config.json"
SCRIPT = ROOT / "tools/flutter/collect_vm_heap.dart"


@unittest.skipUnless(DART.is_file() and PACKAGES.is_file(), "pinned cached SDK unavailable")
class VmHeapOfflineTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.uri = self.root / "private.txt"
        self.uri.write_text("http://127.0.0.1:1/DO_NOT_PRINT_AUTH_TOKEN/", encoding="utf-8")
        self.output = self.root / "evidence.json"

    def run_rejection(self, code, *extra):
        result = subprocess.run([str(DART), f"--packages={PACKAGES}", str(SCRIPT),
            "--vm-uri-file", str(self.uri), "--output", str(self.output), *extra],
            capture_output=True, text=True, timeout=15, cwd=ROOT)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(code, result.stderr)
        self.assertNotIn("DO_NOT_PRINT_AUTH_TOKEN", result.stdout + result.stderr)
        return result

    def checkpoint(self, expired=False):
        ready = self.root / "ready.json"
        start = int(time.time() * 1000) - (300000 if expired else 1000)
        ready.write_text(json.dumps({"schemaVersion": 1, "state": "waiting-for-dart",
            "runToken": "run-42", "round": 5, "pid": 42, "readyEpochMs": start,
            "expiresEpochMs": start + 180000}), encoding="utf-8")
        return ready

    def test_existing_evidence_is_never_reused(self):
        self.output.write_text("preserve")
        self.run_rejection("local-file-error")
        self.assertEqual(self.output.read_text(), "preserve")

    def test_nonlocal_endpoint_and_multiple_uris_fail_without_revealing_token(self):
        self.uri.write_text("http://example.invalid/DO_NOT_PRINT_AUTH_TOKEN/")
        self.run_rejection("only-loopback-vm-service-endpoints-allowed")
        self.uri.write_text("http://127.0.0.1:1/a/ http://127.0.0.1:2/DO_NOT_PRINT_AUTH_TOKEN/")
        self.run_rejection("uri-file-must-identify-one-endpoint")
        self.assertFalse(self.output.exists())

    def test_checkpoint_requires_ack_path(self):
        self.run_rejection("checkpoint-and-ack-must-be-paired", "--checkpoint-file", str(self.checkpoint()))
        self.assertFalse(self.output.exists())

    def test_expired_checkpoint_cannot_sample_an_unheld_page(self):
        self.run_rejection("checkpoint-expired-or-clock-mismatch", "--checkpoint-file",
            str(self.checkpoint(expired=True)), "--ack-output", str(self.root / "ack.json"))
        self.assertFalse(self.output.exists())

    def test_existing_ack_is_refused_before_connecting(self):
        ack = self.root / "ack.json"
        ack.write_text("preserve")
        self.run_rejection("ack-output-already-exists", "--checkpoint-file", str(self.checkpoint()),
            "--ack-output", str(ack))
        self.assertEqual(ack.read_text(), "preserve")
        self.assertFalse(self.output.exists())

    def check_incomplete_heap(self, mode):
        fixture = ROOT / "tools/flutter/tests/collect_vm_heap_fixture.dart"
        result = subprocess.run([str(DART), f"--packages={PACKAGES}", str(fixture),
            str(SCRIPT), str(PACKAGES), str(self.root), mode],
            capture_output=True, text=True, timeout=120, cwd=ROOT)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS: 12 invalid heap cases", result.stdout)

    def test_incomplete_heap_fails_ordinary_collection(self):
        self.check_incomplete_heap("ordinary")

    def test_incomplete_heap_fails_checkpoint_without_ack(self):
        self.check_incomplete_heap("checkpoint")


if __name__ == "__main__":
    unittest.main()
