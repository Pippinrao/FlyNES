# Android Release PSS follow-up — 2026-09-29

**The same-Release-APK native-to-Flutter PSS increment passes the fixed +128 MiB simulator diagnostic. The debug candidate PSS failure remains a failure.** This was a targeted follow-up, one 65-second run per route, without repeating candidate startup or changing production code.

The preceding [3.0.5 direct-start supplement](2026-09-29-android-native-paired-baseline.md#current-revision-direct-start-200-ms-gate) also establishes the current production revision's independent cached-first-card gate: P95 **389 ms**, above **200 ms**. The Release memory result does not waive that gate.

## Frozen inputs and execution

Production source `eaafd7d0a38d3a60ffe7d2db8aad8f04857d6370`, version 3.0.5 / 3000005, fixed Flutter 3.41.7. Evidence root: ignored `.artifacts/flutter-g0/android-foundation/release-eaafd7d0/`.

| Artifact | SHA-256 |
|---|---|
| Frozen unsigned dual-ABI Release APK | `5ABED632DFF6BCE29DBC9534E5C2F54D5A60D11BCCF20E4F1979BDCEC722995E` |
| Independently signed local-test Release APK | `C79B32460CFABCDD8F933276DFAED25FC62083D0DF620096F22725DE3D87F417` |
| Test APK reporting actual target build mode | `6F4F8C4FF9410A9732AC0C9DDFAD651C006EA568601C6D2C12A115E204A1CEDE` |

Signing used the existing Gradle debug signing configuration only as a **local test identity**, not a production/store certificate. Credentials passed directly to the signing subprocess environment and were not printed. The first ignored signing-helper invocation mistakenly ran against Flutter's included Gradle project; its error log is retained. The helper was limited to the Android app project and signing then succeeded. App/test/prior-installed signer identities matched before replacement installation.

`install -r` retained app data. Device-side installed hashes matched the signed APK and test APK above. Both runtime reports independently recorded `targetDebuggable=false`, `targetApplicationFlags=547929668`, target package `com.flynes.emu`, and release-specific mode strings. Existing instrumentation actually executed against the non-debuggable target; this is not merely an assumed compatibility claim. The test-only mode reporting change reads the target application's flags; it does not modify the production APK.

The parent assigned a quiet window with no concurrent builds or other device tests. Both routes used the same installed APK, existing 60-second auto-save interval, audio enabled, and comparable **61-record history retention**. Native staged canonical `game:31811AEF54BC433D0D8B9344E0D5AB6417D9F06D97B743ABDDDFC9B3CAB719FF` through the real exact-launch service. Flutter entered its actual UI and invoked its primary action. Both running cores asserted PRG/CHR identity **`39211CB6B159B28E2853E1EFF2731BD8353ED886`**.

## Result and pre-frozen budget

Native completed first. Before starting Flutter, `performance/pss-budget-before-flutter.json` recorded native PSS P95 **112,316 KiB** plus the already fixed **131,072 KiB** allowance, producing a candidate limit of **243,388 KiB**.

| Observation | Native Release | Flutter-entry Release |
|---|---:|---:|
| Instrumentation result | 1/1 pass, 67.003 s | 1/1 pass, 68.494 s |
| Actual played progress | 65,573 ms | 65,656 ms |
| Measured wall time | 65,477 ms | 65,633 ms |
| New automatic save | 178 | 180 |
| Head transition | 177 → 178 | 179 → 180 |
| History records | 61 → 61 | 61 → 61 |
| PSS P95 | 112,316 KiB | **173,886 KiB** |
| Java used heap P95 | 52,350,800 B | 53,870,384 B |
| Native allocated heap P95 | 33,985,968 B | 59,433,664 B |

The PSS increment is **61,570 KiB (60.13 MiB)**, below the fixed 128 MiB allowance. `performance/comparison.json` records this narrow diagnostic pass and explicitly retains the debug failure. The earlier same-debug-APK increment was 191,329 KiB and exceeded its fixed absolute limit by 60,257 KiB; see the [debug candidate report](2026-09-29-android-flutter-candidate-performance.md).

This difference supports further investigation of build-mode-dependent runtime/mapping cost. It does not prove that the entire debug excess is Dart/JIT, because the builds differ and PSS is not a Dart heap measurement. No Dart VM heap sample or mapping attribution was added to this follow-up.

## Retained secondary observations and limits

The unchanged harness also captured 119 input observations per route and 60 memory/audio snapshots. Core callback gap P95 was 67.1298 / 67.1951 ms; save-window maximum 68.226 / 67.8756 ms; software touch-to-core P95 63.1066 / 61.9325 ms (native / Flutter). These are retained observations, not a newly invented Release latency budget.

All sampled playback heads were positive, sampled underrun increments were zero, and each route showed one playback-head decrease near automatic saving: native at 60,018 ms (`2,850,560 → 16,320`), Flutter at 60,175 ms (`2,845,120 → 11,968`). Renderer runtime-failure snapshots remained zero; actual presentation timestamps remained unavailable (count zero). No uninterrupted-audio or physical display-latency claim follows.

Each route directory under `performance/native/` and `performance/flutter/` retains its original JSON, epoch logcat, instrumentation log, and existing-tool summary. `performance/environment.json`, `comparison.json`, and `media-and-memory-details.json` tie observations to mode and package identity. No extra run was added to improve a percentile.

The app and task-owned logcat collectors were stopped after the second run, and the device window returned to HarmonyOS. At handoff the simulator still held the local-test-signed Release APK and the mode-aware test APK; no silent reinstall to debug occurred. These simulator diagnostics do not certify physical memory pressure, frame presentation, input latency, power, temperature, audio quality, or overall G1 acceptance.
