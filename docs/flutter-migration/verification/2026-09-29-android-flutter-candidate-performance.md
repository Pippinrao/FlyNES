# Android Flutter candidate diagnostics — 2026-09-29

**The debug candidate fails the fixed game PSS diagnostic budget.** Startup, sampled frame/input timing, audio lower-bound and owner/ART retention checks pass their individual diagnostic thresholds. This is simulator evidence, not a physical-device or overall G1 performance approval.

Production: `eaafd7d0a38d3a60ffe7d2db8aad8f04857d6370`, 3.0.5, `emulator-5582`. Installed app SHA-256 `03A6A6AA3F8E60B45337896E9FF5DAFF66F337639A9C9B7272B6867E72FB8BE2`; exact-content test APK `1854423189C3B3588527C68367E7FCE8BDDC9912EAA2D1D025CC14A010DED8A0`. Both hashes were verified on-device before collection. The native and Flutter routes use this same production APK and retained data. The parent assigned an exclusive quiet window after other builds/tests stopped.

Evidence root: ignored `.artifacts/flutter-g0/android-foundation/performance-eaafd7d0/`. The pre-candidate budget snapshot is `flutter-startup-20260929-quiet/budget-before-candidate.md`, SHA-256 `AFFDC08BD154B7267C755D8894A993C4FC91A320AE72F37C1D623639CA1C4429`. Thresholds were not changed after sampling. No production code, save interval, media clock or fixture library was changed to improve a result.

## Startup: two warmups and all twelve measured samples

`flutter-startup-20260929-quiet/` retains every JSON/instrumentation log, `collect.ps1`, `samples.json` and `summary.json`. All invocations passed in separate processes; each force-stop was followed by an empty-PID check. All samples restored the existing UI preferences. The native directory snapshot contained 2,231 rows; this count is not a claim that every Flutter card rendered. The Flutter route observed an actual visible card and enabled `launch-selected` semantics. Its default selected game's identity was independently verified by the subsequent real game launch.

| Software observation, P95 | Native | Flutter | Fixed limit | Result |
|---|---:|---:|---:|---|
| Primary interactive, process origin | 2,301 ms | 3,747 ms | 3,801 ms | Pass |
| Primary interactive, Activity request | 1,623 ms | 3,137 ms | 4,000 ms | Pass |
| Native readiness callback, process origin | 2,675 ms | 2,021 ms | 3,042.5 ms | Pass |

Flutter renderer-first-UI callback P95 was 2,606 ms from process origin / 1,967 ms from Activity request. First visible card P95 was 3,704 / 3,093 ms. Renderer callbacks were registered before UI display; they are separate from the later actionable catalog. These are callback/polling upper bounds including instrumentation, ActivityScenario synchronization and UI automation. They are not physical presentation timestamps or precise Dart frame submission timestamps. The old direct-start 200 ms native first-card gate remains a separate unresolved failure.

## Same-content save workload

`flutter-save-20260929-quiet/` contains the raw report, full epoch logcat, instrumentation output and summary produced by `tools/flutter/summarize_save_performance.py`. The actual flow opened Flutter, pressed its real primary action and entered native MainActivity. The core reported and the test asserted PRG/CHR identity **`39211CB6B159B28E2853E1EFF2731BD8353ED886`**, matching canonical `game:31811AEF54BC433D0D8B9344E0D5AB6417D9F06D97B743ABDDDFC9B3CAB719FF` and the paired native workload.

The test passed **1/1 in 71.547 s**, with **65,972 ms played** over **65,946 ms measured wall time**. A new automatic save **156** moved head **155 → 156** at the unchanged 60-second interval. History size remained **61 → 61**, comparable to the native retention workload.

| Observation | Native | Flutter | Fixed limit | Result |
|---|---:|---:|---:|---|
| Game PSS P95 | 144,316 KiB | **335,645 KiB** | 275,388 KiB | **Fail** |
| Core callback gap P95 | 62.5844 ms | 62.6635 ms | 70.84284 ms | Pass |
| Save-window core gap maximum | 64.0871 ms | 70.463 ms | 80.7871 ms | Pass |
| Software touch-to-core P95 | 56.8125 ms | 60.2335 ms | 73.5125 ms | Pass |
| Sampled underrun increment lower bound | 0 | 0 | 0 | Pass, lower bound only |

The PSS excess is **60,257 KiB above the fixed limit**, and the native-to-candidate difference is 191,329 KiB. No extra performance batch was taken to reduce the P95. There were 3,967 valid frame-gap observations, 243 save-window observations and 119 input-latency observations. All 60 sampled AudioTrack playback heads were positive. One playback-head decrease occurred at 60,453 ms (`2,859,264 → 28,288`), near automatic saving, as also observed in the native baseline. This is not evidence of uninterrupted audio. Sampled renderer failures were zero; actual presentation counts remained zero, so emulator callback timing cannot certify hardware presentation.

## Separate twenty-round-trip GC diagnostic

`flutter-roundtrip20-20260929-gc/` retains instrumentation, epoch logcat and 22 asynchronous `dumpsys meminfo` captures. The existing real round-trip test passed **1/1 in 48.224 s**. Every cycle ran the core, had one active native audio clock while playing, then returned to Flutter with zero audio threads and no history timer callbacks. Final retained destroyed game owners were **zero**.

This run deliberately requests ART GC/finalization after each return. It is separate from startup and 65-second timing; no GC was injected into those measurements. ART used heap at cycle 5 was **26,111,472 B**, and at cycle 20 **26,185,200 B**, growth **73,728 B (72 KiB)** versus the fixed 16 MiB diagnostic bound. The per-cycle weak reference may retain the current test local; the final owner count was zero after that local left scope.

Asynchronous PSS ranged **285,070–388,845 KiB**, with the last sampled value **318,503 KiB**. These samples are not synchronized hall/game checkpoints and are not the 65-second game's PSS distribution. Representative partitions:

| Sample | PSS | Java PSS | Native PSS | Code PSS | Private Other PSS | Reported Activities |
|---|---:|---:|---:|---:|---:|---:|
| First, meminfo-001 | 285,070 | 27,316 | 42,204 | 33,056 | 170,284 | 1 |
| Peak, meminfo-007 | 388,845 | 94,576 | 61,744 | 36,620 | 176,024 | 2 |
| Last, meminfo-022 | 318,503 | 32,644 | 55,532 | 36,684 | 173,284 | 2 |

All values in that table are KiB. Reported Graphics was zero, which does not establish that no graphics memory exists. The last sample preceded final ownership verification; its Activity count is not evidence of a retained owner after the test.

The 65-second Java allocated-heap P95 increased by 6,596,128 B and native allocated-heap P95 by 27,901,152 B over native. These allocation counters are not additive PSS partitions. ART use is stable in the separate GC run, while Private Other is already large in the first sample and remains large. This supports investigating a fixed Flutter/debug-runtime or mapped-memory cost, **but does not identify Dart/JIT as the cause**. No Dart VM heap was sampled here. Raw partitions and all 20 ART observations are in `candidate-comparison.json`, generated by `analyze-candidate.py`.

## Release follow-up scope

The parent authorized a subsequent minimal same-Release-APK native/Flutter 65-second PSS diagnostic, using a fixed +128 MiB increment formula. It must retain the debug failure and report its own package/build identity. The unsigned Release artifact is already frozen at `release-eaafd7d0/app-release-unsigned.apk`, SHA-256 `5ABED632DFF6BCE29DBC9534E5C2F54D5A60D11BCCF20E4F1979BDCEC722995E`.

Offline feasibility checks found matching frozen app/test signer identities, an existing local debug keystore, no release minification, and an unconditional native `touch-to-core-ns` log callback. The existing instrumentation accesses public memory APIs and unchanged native fields. This makes same-signature instrumentation against the non-debuggable target plausible; actual signing/installation and execution remain a separate validation step. No signing or Release install was performed during this candidate batch.

The save harness subsequently received a test-only reporting edit to derive debug/release from the **target application's** `ApplicationInfo.FLAG_DEBUGGABLE`, and record the flag/package explicitly. It was compiled only after the next authorized build window. The test APK identities above remain the ones actually used for this debug report. The separate [Release PSS follow-up](2026-09-29-android-release-pss.md) passed its fixed increment diagnostic and does not erase this debug PSS failure.

All Android processes and task-owned collectors were stopped after the prescribed three stages, and the window returned for HarmonyOS. This report does not approve physical latency, power, temperature, audio quality, Release performance, or overall G1.
