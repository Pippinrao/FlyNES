"""Summarize opt-in Android save-load observations; never grants a performance gate."""
import argparse
import json
import math
from pathlib import Path
import re


def distribution(values):
    ordered = sorted(value for value in values if isinstance(value, (int, float))
                     and not isinstance(value, bool) and math.isfinite(value) and value >= 0)
    def rank(percent):
        return ordered[max(0, math.ceil(percent * len(ordered)) - 1)] if ordered else None
    return {"count": len(ordered), "p50": rank(.5), "p95": rank(.95),
            "p99": rank(.99), "max": ordered[-1] if ordered else None}


def summarize(report, logs):
    frames = report.get("coreFrameEvents", [])
    memory = report.get("memoryAndAudio", [])
    saves = report.get("automaticSaves", [])
    gaps, save_gaps, invalid = [], [], 0
    for before, after in zip(frames, frames[1:]):
        gap = (after[1] - before[1]) / 1_000_000
        if gap < 0 or after[0] <= before[0]:
            invalid += 1
            continue
        gaps.append(gap)
        if any(abs(after[2] - save["createdMs"]) <= 2000 for save in saves):
            save_gaps.append(gap)
    inputs = []
    expression = re.compile(r"^\s*(\d+\.\d+)\s+(\d+)\s+\d+\s+D\s+FlyNES\s*:\s*touch-to-core-ns=(\d+)")
    for line in logs.splitlines():
        match = expression.match(line)
        if (match and int(match[2]) == report.get("processId")
                and report.get("startedEpochMs", math.inf) <= float(match[1]) * 1000
                <= report.get("finishedEpochMs", -math.inf)):
            inputs.append(int(match[3]) / 1_000_000)
    previous, increments, resets = None, 0, 0
    for sample in memory:
        value = sample.get("audioUnderruns", -1)
        if value < 0:
            continue
        if previous is not None:
            if value < previous:
                resets += 1
            else:
                increments += value - previous
        previous = value
    return {
        "mode": report.get("mode"), "contentKey": report.get("contentKey"),
        "playedMs": report.get("playedMs"), "wallMs": report.get("wallMs"),
        "historyRecordsBefore": report.get("recordsBefore"),
        "historyRecordsAfter": report.get("recordsAfter"), "newAutomaticSaveCount": len(saves),
        "coreFrameGapMs": distribution(gaps), "saveWindowCoreGapMs": distribution(save_gaps),
        "saveWindowRadiusMs": 2000, "invalidFrameGapCount": invalid,
        "softwareTouchToCoreMs": distribution(inputs),
        "pssKb": distribution([row.get("pssKb") for row in memory]),
        "javaUsedBytes": distribution([row.get("javaUsedBytes") for row in memory]),
        "nativeHeapBytes": distribution([row.get("nativeHeapBytes") for row in memory]),
        "observedUnderrunIncrementsLowerBound": increments if previous is not None else None,
        "audioCounterResetCount": resets,
        "captureComplete": report.get("playedMs", 0) >= 65000 and bool(saves) and bool(gaps) and bool(memory),
        "performanceAccepted": None,
        "limitations": ["Simulator software observations; no physical latency, audio quality or power certification",
                        "Core callbacks are not display presentation timestamps",
                        "One-second audio observations can miss increments around AudioTrack replacement",
                        "Save window association does not establish causation",
                        "Budget approval and a matching candidate are separate from collection"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--logcat", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    report = json.loads(args.input.read_text(encoding="utf-8-sig"))
    result = summarize(report, args.logcat.read_text(encoding="utf-8-sig"))
    with args.output.open("x", encoding="utf-8") as output:
        json.dump(result, output, indent=2, ensure_ascii=False)
        output.write("\n")


if __name__ == "__main__":
    main()
