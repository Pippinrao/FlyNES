"""Data-preserving, process-cold Android measurements for an already seeded app.

No installation, fixture seeding, package compilation, log clearing, or data
deletion is performed. A caller must arrange an isolated pre-installed fixture.
The app itself can update its ordinary caches during launch. --apk describes a
local artifact only; this tool cannot prove that artifact is the installed APK.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import time


PACKAGE = "com.flynes.emu"
COMPONENT = PACKAGE + "/.HomeActivity"
MARKER_TIMEOUT_SECONDS = 15
SETTLE_SECONDS = 2
METRICS = (
    "firstPaintMs", "firstInteractiveMs", "shellVisibleMs", "startupCacheDecodedMs",
    "fullProjectionAvailableMs", "fullListFirstCardVisibleMs", "nativeReadyMs",
    "amStartTotalTimeMs", "amStartWallMs", "settledPssKb",
)
LOG_LINE = re.compile(
    r"^\s*(\d+\.\d+)\s+(\d+)\s+\d+\s+[VDIWEF]\s+FlyNesStartup\s*:\s*"
    r"([A-Z_]+)\s+(.*)$")


def parse_markers(logs, pid, launch_epoch, timed_out=False):
    events = {}
    for row in logs.splitlines():
        match = LOG_LINE.match(row)
        if not match or int(match[2]) != pid or float(match[1]) < launch_epoch:
            continue
        name = match[3]
        fields = dict(re.findall(r"(\w+)=([^\s]+)", match[4]))
        if not fields.get("elapsedMs", "").isdigit():
            continue
        if name in ("GAME_CENTER_VISIBLE", "GAME_CENTER_FULL_LIST_VISIBLE",
                    "CACHE_DECODED", "CATALOG_PROJECTION_AVAILABLE"):
            if not fields.get("count", "").isdigit():
                continue
        if name in ("GAME_CENTER_VISIBLE", "GAME_CENTER_FULL_LIST_VISIBLE"):
            if int(fields["count"]) == 0 or fields.get("cache") not in ("HIT", "MISS", "RECOVERY_NEEDED"):
                continue
        if name == "CACHE_DECODED" and fields.get("status") not in ("HIT", "MISS", "RECOVERY_NEEDED"):
            continue
        if name == "NATIVE_READY" and fields.get("status") not in ("OK", "FAILED"):
            continue
        if name == "CATALOG_PROJECTION_AVAILABLE" and fields.get("source") not in ("cache", "native"):
            continue
        events.setdefault(name, fields)

    def value(name, field="elapsedMs"):
        raw = events.get(name, {}).get(field)
        return int(raw) if raw is not None else None

    required = ("GAME_CENTER_VISIBLE", "CACHE_DECODED", "NATIVE_READY",
                "CATALOG_PROJECTION_AVAILABLE", "GAME_CENTER_FULL_LIST_VISIBLE")
    missing = [name for name in required if name not in events]
    failed = events.get("NATIVE_READY", {}).get("status") == "FAILED"
    return {
        "firstPaintMs": value("GAME_CENTER_VISIBLE"),
        "firstInteractiveMs": value("GAME_CENTER_INTERACTIVE"),
        "firstPaintReportedCount": value("GAME_CENTER_VISIBLE", "count"),
        "firstPaintCache": events.get("GAME_CENTER_VISIBLE", {}).get("cache"),
        "shellVisibleMs": value("GAME_CENTER_SHELL_VISIBLE"),
        "renderedFullListCount": None,
        "startupCacheDecodedMs": value("CACHE_DECODED"),
        "startupCacheCount": value("CACHE_DECODED", "count"),
        "startupCacheStatus": events.get("CACHE_DECODED", {}).get("status"),
        "nativeReadyMs": None if failed else value("NATIVE_READY"),
        "nativeStatus": events.get("NATIVE_READY", {}).get("status"),
        "fullProjectionAvailableMs": value("CATALOG_PROJECTION_AVAILABLE"),
        "fullProjectionCount": value("CATALOG_PROJECTION_AVAILABLE", "count"),
        "fullProjectionSource": events.get("CATALOG_PROJECTION_AVAILABLE", {}).get("source"),
        "fullProjectionStatus": "observed" if "CATALOG_PROJECTION_AVAILABLE" in events else "blocked_no_marker",
        "fullListFirstCardVisibleMs": value("GAME_CENTER_FULL_LIST_VISIBLE"),
        "fullListReportedCount": value("GAME_CENTER_FULL_LIST_VISIBLE", "count"),
        "status": "failed" if failed else ("blocked" if missing else "collected"),
        "timedOut": timed_out,
        "missingMarkers": missing,
    }


def nearest_rank_p95(values):
    valid = sorted(v for v in values if v is not None)
    return valid[math.ceil(len(valid) * .95) - 1] if valid else None


def aggregate(samples, expected_runs):
    measured = [s for s in samples if s.get("kind") == "measured"]
    metrics = {}
    for key in METRICS:
        values = [s.get(key) for s in measured]
        metrics[key] = {
            "samples": sum(v is not None for v in values),
            "expected": expected_runs, "p95": nearest_rank_p95(values),
        }
    first = metrics["firstPaintMs"]
    status = "blocked"
    if len(measured) == expected_runs and first["samples"] == expected_runs:
        status = "pass" if first["p95"] <= 200 else "fail"
    return {
        "metrics": metrics,
        "percentileMethod": "nearest-rank ceil(0.95 * N), missing values excluded",
        "firstVisible200msGate": {
            "status": status, "limitMs": 200, "p95Ms": first["p95"],
            "marker": "GAME_CENTER_VISIBLE", "scope": "first cached cards only",
        },
        "otherNumericBudgets": "pending_user_confirmation",
        "g1Acceptance": "not_evaluated",
    }


def parse_am_start(output):
    match = re.search(r"^TotalTime:\s*(\d+)\s*$", output, re.MULTILINE)
    return {"totalTimeMs": int(match[1]) if match else None}


def parse_pss(output):
    match = re.search(r"\bTOTAL PSS:\s*(\d+)", output)
    if not match:
        match = re.search(r"^\s*TOTAL\s+(\d+)\s", output, re.MULTILINE)
    return int(match[1]) if match else None


def make_parser():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", required=True, help="Explicit online adb target")
    parser.add_argument("--output", required=True, type=Path, help="New evidence directory (prefer .artifacts)")
    parser.add_argument("--runs", type=int, default=12)
    parser.add_argument("--warmups", type=int, default=2)
    parser.add_argument("--apk", type=Path, help="Existing APK to hash and size; never installed")
    parser.add_argument("--build-mode", choices=("debug", "release", "unknown"), default="unknown",
                        help="Caller-known installed build variant; unknown by default")
    return parser


def validate_options(args):
    if not 10 <= args.runs <= 100:
        raise ValueError("--runs must be 10..100")
    if not 0 <= args.warmups <= 20:
        raise ValueError("--warmups must be 0..20")
    if args.apk and (not args.apk.is_file() or args.apk.suffix.lower() != ".apk"):
        raise ValueError("--apk must name an existing .apk file")


def run_command(args, timeout=15, cwd=None):
    result = subprocess.run(args, capture_output=True, text=True, encoding="utf-8",
                            errors="replace", timeout=timeout, cwd=cwd, check=False)
    if result.returncode:
        # Avoid printing arbitrary device/app output (it can contain user data).
        raise RuntimeError(f"Command failed (exit {result.returncode}): {args[0]}")
    return result.stdout


def find_adb():
    candidates = [shutil.which("adb")]
    for variable in ("ANDROID_HOME", "ANDROID_SDK_ROOT"):
        if os.environ.get(variable):
            candidates.append(str(Path(os.environ[variable]) / "platform-tools" / "adb.exe"))
            candidates.append(str(Path(os.environ[variable]) / "platform-tools" / "adb"))
    if os.environ.get("LOCALAPPDATA"):
        candidates.append(str(Path(os.environ["LOCALAPPDATA"]) / "Android/Sdk/platform-tools/adb.exe"))
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            return candidate
    raise RuntimeError("adb unavailable; put it on PATH or set ANDROID_HOME")


class Device:
    def __init__(self, adb, serial):
        self.adb, self.serial = adb, serial

    def call(self, *args, timeout=15):
        return run_command([self.adb, "-s", self.serial, *args], timeout=timeout)


def git_metadata(root):
    revision = run_command(["git", "rev-parse", "HEAD"], cwd=root).strip()
    dirty = bool(run_command(["git", "status", "--porcelain", "--untracked-files=normal"], cwd=root).strip())
    return {"revision": revision, "dirty": dirty,
            "scope": "collector checkout; installed app revision not independently verified"}


def device_metadata(device, build_mode):
    if device.call("get-state").strip() != "device":
        raise RuntimeError("Target is not an online adb device")
    if not device.call("shell", "pm", "path", PACKAGE).strip().startswith("package:"):
        raise RuntimeError("Required app is not pre-installed; collector never installs it")
    properties = {}
    for key in ("ro.product.model", "ro.build.version.sdk", "ro.product.cpu.abi",
                "ro.kernel.qemu", "ro.boot.qemu", "ro.hardware"):
        properties[key] = device.call("shell", "getprop", key).strip() or None
    emulator = (properties["ro.kernel.qemu"] == "1" or properties["ro.boot.qemu"] == "1"
                or any(v in (properties["ro.hardware"] or "").lower() for v in ("ranchu", "goldfish")))
    package_dump = device.call("shell", "dumpsys", "package", PACKAGE)
    version = re.search(r"\bversionName=([^\s]+)", package_dump)
    code = re.search(r"\bversionCode=(\d+)", package_dump)
    # Read-only dexopt status; never run 'cmd package compile'. Missing/mixed
    # statuses do not qualify as the historical speed-AOT baseline.
    statuses = re.findall(r"\[status=([a-zA-Z0-9_-]+)\]", package_dump)
    compile_mode = "speed" if statuses and all(s == "speed" for s in statuses) else "unknown"
    return {
        "model": properties["ro.product.model"], "api": properties["ro.build.version.sdk"],
        "abi": properties["ro.product.cpu.abi"], "emulator": emulator,
        "measurementScope": "emulator_functional_timing_only" if emulator else "device_startup_observation",
        "physicalLatencyCertified": False,
        "installedVersionName": version[1] if version else None,
        "installedVersionCode": int(code[1]) if code else None,
        "buildMode": build_mode, "buildModeEvidence": "caller_declared" if build_mode != "unknown" else "unknown",
        "debuggable": bool(re.search(r"\bDEBUGGABLE\b", package_dump)),
        "compileMode": compile_mode, "compileModeEvidence": "dumpsys package dexopt status",
        "debugSpeedAotComparable": build_mode == "debug" and compile_mode == "speed"
                                   and bool(re.search(r"\bDEBUGGABLE\b", package_dump)),
    }


def collect_run(device, output, kind, number):
    prefix = f"{kind}-{number:02d}"
    device.call("shell", "am", "force-stop", PACKAGE)
    epoch = device.call("shell", "date", "+%s.%N").strip()
    if not re.fullmatch(r"\d+\.\d+", epoch):
        raise RuntimeError("Device cannot supply epoch time for stale-log exclusion")
    launch_epoch = float(epoch)
    started = time.monotonic()
    deadline = started + MARKER_TIMEOUT_SECONDS
    am_output = device.call("shell", "am", "start", "-W", "-n", COMPONENT,
                            timeout=MARKER_TIMEOUT_SECONDS)
    wall_ms = round((time.monotonic() - started) * 1000, 3)
    # Only persist known am fields; avoid unbounded/unrelated device logs.
    (output / f"{prefix}-am-start.log").write_text(am_output, encoding="utf-8")
    if re.search(r"(^Error:|Status:\s*(?!ok\b)\S+)", am_output, re.MULTILINE):
        raise RuntimeError("Activity launch failed; see am-start evidence")
    pid = None
    logs = ""
    sample = parse_markers(logs, -1, launch_epoch)
    while time.monotonic() < deadline:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        try:
            if pid is None:
                pid_output = device.call("shell", "pidof", PACKAGE, timeout=remaining).strip()
                if not re.fullmatch(r"\d+", pid_output):
                    raise RuntimeError("Expected exactly one main application PID")
                pid = int(pid_output)
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            raw = device.call("logcat", "-d", "-v", "epoch", f"--pid={pid}",
                              "-s", "FlyNesStartup:I", "*:S", timeout=remaining)
            logs = "\n".join(row for row in raw.splitlines()
                             if (match := LOG_LINE.match(row))
                             and int(match[2]) == pid and float(match[1]) >= launch_epoch)
            sample = parse_markers(logs, pid, launch_epoch)
            if sample["status"] == "failed" or not sample["missingMarkers"]:
                break
        except subprocess.TimeoutExpired:
            break
        time.sleep(min(.1, max(0, deadline - time.monotonic())))
    timed_out = bool(sample["missingMarkers"]) and sample["status"] != "failed"
    sample = parse_markers(logs, pid or -1, launch_epoch, timed_out=timed_out)
    sample.update(kind=kind, run=number, pid=pid, launchEpoch=launch_epoch,
                  amStartWallMs=wall_ms, amStartTotalTimeMs=parse_am_start(am_output)["totalTimeMs"],
                  settledPssKb=None, pssStatus="unavailable", pssSettleDelaySeconds=SETTLE_SECONDS)
    (output / f"{prefix}-markers.log").write_text(logs + "\n", encoding="utf-8")
    if pid is not None and sample["nativeReadyMs"] is not None:
        time.sleep(SETTLE_SECONDS)
        try:
            if device.call("shell", "pidof", PACKAGE).strip() == str(pid):
                memory = device.call("shell", "dumpsys", "meminfo", str(pid))
                sample["settledPssKb"] = parse_pss(memory)
                sample["pssStatus"] = "observed_after_delay" if sample["settledPssKb"] is not None else "unavailable"
        except (RuntimeError, subprocess.TimeoutExpired):
            pass
    return sample


def main(argv=None):
    parser = make_parser()
    args = parser.parse_args(argv)
    try:
        validate_options(args)
    except ValueError as exc:
        parser.error(str(exc))
    # Refuse to overwrite evidence, including files produced by another task.
    if args.output.exists() and any(args.output.iterdir()):
        parser.error("--output must be a new or empty directory")
    args.output.mkdir(parents=True, exist_ok=True)
    report = {
        "schemaVersion": 1, "generatedAt": datetime.now(timezone.utc).isoformat(),
        "serial": args.serial, "package": PACKAGE, "activity": COMPONENT,
        "requestedRuns": args.runs, "warmups": args.warmups, "samples": [],
        "status": "blocked", "apk": None,
        "scope": {
            "clockOrigin": "Process.getStartElapsedRealtime() (app elapsedRealtime milliseconds)",
            "firstPaint": "GAME_CENTER_VISIBLE: first cached cards pre-draw, not full directory render",
            "firstInteractive": "GAME_CENTER_INTERACTIVE: primary launch control visible, enabled and clickable at pre-draw",
            "startupCacheDecoded": "CACHE_DECODED: startup sidecar, not full projection",
            "fullProjectionAvailable": "CATALOG_PROJECTION_AVAILABLE: lazy directory projection available",
            "fullListFirstCardVisible": "GAME_CENTER_FULL_LIST_VISIBLE: first card pre-draw, not all cards rendered",
            "amStartWall": "host monotonic duration of adb am start -W; separate clock and boundary",
            "amStartTotalTime": "Android activity manager TotalTime; separate from process elapsed markers",
            "pss": "optional dumpsys meminfo after native readiness and 2-second settle delay; no steady-state certification",
            "fixture": "caller-prepared isolated seeded installation; collector does not verify fixture contents",
        },
    }
    try:
        report["git"] = git_metadata(Path(__file__).resolve().parents[2])
        if args.apk:
            report["apk"] = {"path": str(args.apk.resolve()), "sizeBytes": args.apk.stat().st_size,
                             "sha256": hashlib.sha256(args.apk.read_bytes()).hexdigest(),
                             "installedArtifactMatch": "unverified"}
        device = Device(find_adb(), args.serial)
        report["device"] = device_metadata(device, args.build_mode)
        for index in range(args.warmups + args.runs):
            kind = "warmup" if index < args.warmups else "measured"
            number = index + 1 if kind == "warmup" else index - args.warmups + 1
            sample = collect_run(device, args.output, kind, number)
            report["samples"].append(sample)
            print(f"{kind} {number}: {sample['status']}; first cards={sample['firstPaintMs']} ms; native={sample['nativeReadyMs']} ms", flush=True)
            if sample["status"] == "failed":
                break
        measured = [s for s in report["samples"] if s["kind"] == "measured"]
        report["status"] = "collected" if len(measured) == args.runs and all(
            s["status"] == "collected" for s in measured) else "blocked"
        if any(s["status"] == "failed" for s in report["samples"]):
            report["status"] = "failed"
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as exc:
        report["error"] = str(exc)
    report["summary"] = aggregate(report["samples"], args.runs)
    (args.output / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Evidence: {args.output.resolve() / 'report.json'}; status={report['status']}")
    return 0 if report["status"] == "collected" else 2


if __name__ == "__main__":
    raise SystemExit(main())
