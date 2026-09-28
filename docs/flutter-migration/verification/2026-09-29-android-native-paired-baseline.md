# Android native paired-observation baseline — 2026-09-29

Production revision `eaafd7d0a38d3a60ffe7d2db8aad8f04857d6370`, version `3.0.5` / `3000005`, task AVD `emulator-5582`. These are native-route simulator observations from the debug APK which also contains the lazy Flutter host. No Flutter candidate performance sample was run, and no performance budget is accepted by this report.

The parent task explicitly assigned a quiet window after Android/HarmonyOS builds and other device tests stopped. Each startup sample force-stopped the app and checked that no previous PID remained. The source fixture and app data were retained. No uninstall or data/library reset occurred.

## Artifact identity

Ignored evidence root: `.artifacts/flutter-g0/android-foundation/performance-eaafd7d0/`.

| Artifact | SHA-256 |
|---|---|
| Production debug APK, installed and frozen | `03A6A6AA3F8E60B45337896E9FF5DAFF66F337639A9C9B7272B6867E72FB8BE2` |
| Startup observation test APK | `FF089EAA4119DB38E11EC5B1AD0EE39AD2ED58EE4A22CE0275A7A5DCA31D12E9` |
| Exact-content save observation test APK | `1854423189C3B3588527C68367E7FCE8BDDC9912EAA2D1D025CC14A010DED8A0` |

Device-side hashes matched the frozen APKs. Production was unchanged between startup and save observations. After startup collection, the test-only save harness gained the `g1CanonicalId` option and was rebuilt/reinstalled; this is recorded separately in `native-save-20260929-quiet/packages.json`. It stages content through the existing `AndroidGameLaunchService.launchCanonical` before opening native MainActivity, and verifies the actual running core identity with the existing expected-content assertion.

## Startup, same future paired-test entry

Evidence: `native-startup-20260929-quiet/`. A new pilot passed, followed by two excluded warmups and **12/12 passing measured samples**, each in a distinct process. Every sample had category ALL, empty query, multiplayer filter off, **2,231 actual native adapter rows**, and the independently supplied selected identity `game:31811AEF54BC433D0D8B9344E0D5AB6417D9F06D97B743ABDDDFC9B3CAB719FF`. The test verifies the actual native selection; all UI preferences were restored after every sample. Selection preparation does not scan or decode the directory before launch.

| Software observation | P50, process origin | P95, process origin | P50, Activity request | P95, Activity request |
|---|---:|---:|---:|---:|
| Visible enabled primary action | 2,106 ms | 2,301 ms | 1,521 ms | 1,623 ms |
| Complete adapter's first visible card | 2,106 ms | 2,301 ms | 1,521 ms | 1,623 ms |
| Native readiness callback receipt | 2,607 ms | 2,675 ms | 1,985 ms | 2,116 ms |

P95 uses nearest rank `ceil(0.95 × 12)`, thus the largest sample. Ready-state PSS P95 was **149,991 KiB**. Each numbered JSON/log is retained, alongside `samples.json`, `summary.json`, and the exact `collect.ps1` invocation script.

These UI measurements are upper bounds first observable after ActivityScenario returns and the test polls. They include runner, Application, UI-automation, main-thread dispatch and synchronization overhead; requested polling interval is 25 ms. They are not actual first-frame presentation timestamps or exact Dart frame boundaries, and must not be compared numerically with the older direct `am start` baseline. The first-card and primary observations coincided because both were already visible at the initial poll. Native projection callbacks that completed before observer registration are labelled upper bounds; negative Activity-relative timestamps are preserved. The native route asserted the lazy Flutter engine remained null.

The previous `c0511d69` direct-start and partial instrumented results remain historical, including their BUILTIN filter and the subsequently corrected native selection bug. They are not silently replaced by this batch.

## Current-revision direct-start 200 ms gate

After the paired debug candidate runs, and before installing Release, the still-installed **same `03A6A6…8BE2` debug 3.0.5 APK** received one additional native-only batch using the existing `tools/flutter/collect_android_baseline.py`: two excluded warmups and all twelve measured `am start -W` launches. This retains the original production pre-draw marker and is **not** another instrumentation or Flutter candidate startup batch.

Evidence: `native-direct-start-20260929-quiet/collector/report.json`, individual numbered marker/start logs, `context.json`, and `preferences-restored.json`. Actual navigation was **BUILTIN**, empty query, with the absent multiplayer-filter key taking its existing false default. Every measured sample reported 2,231 rows in the native projection and seven in the complete filtered adapter. The test did not normalize the filter. An exact app-private preference backup was restored after collection; before/after SHA-256 both equal `8217881536cc0835af95cbd7e90c6c933306478fb140ccfbee52cd6d48b9dbe6`.

| Direct-start production marker | P95 |
|---|---:|
| Cached first cards pre-draw (`GAME_CENTER_VISIBLE`) | **389 ms** |
| Primary action visible/enabled/clickable pre-draw | 1,180 ms |
| Complete native projection available | 340 ms |
| Complete filtered adapter's first card pre-draw | 1,181 ms |
| Native ready | 2,163 ms |

The original **200 ms cached-first-card gate still fails on `eaafd7d0 / 3.0.5`**; its twelve measured values range from 338 to 389 ms. It is no longer necessary to infer the current result from the historical 3.0.4 failure. All values use the collector's original process-origin boundary; none can replace or be directly subtracted from the instrumentation table above. The collector's generic `otherNumericBudgets=pending_user_confirmation` field is unchanged tool metadata, not a reversal of the parent task's subsequent authorization of fixed candidate diagnostics.

## Same-content 65-second save workload

Evidence: `native-save-20260929-quiet/`, with `instrumentation.log`, `g1-native-save-performance.json`, `logcat-epoch.log`, `summary.json`, `media-observations.json`, and the frozen exact-content test APK.

The runtime asserted core PRG/CHR identity **`39211CB6B159B28E2853E1EFF2731BD8353ED886`** for the same canonical selection used above. This differs from the older default-MainActivity workload (`44B6EDDE…`); those old-ROM measurements are not a same-content comparison.

The test passed **1/1 in 68.648 s**, with **65,690 ms actual played progress** over **65,631 ms measured wall time**. The unchanged 60-second automatic-save interval produced record **154**, moving head **153 → 154**. History retained **61 → 61 records**, exercising its retention policy rather than only a nearly empty store. A future candidate should preserve comparable history scale and the same content/interval.

| Observation | Count | P50 | P95 |
|---|---:|---:|---:|
| Core frame callback gap | 3,948 | 2.2061 ms | 62.5844 ms |
| Core callback gap within ±2 s of save | 246 | 2.3288 ms | 62.3347 ms |
| Software touch dispatch to core sampling | 120 | 25.0521 ms | 56.8125 ms |
| PSS | 60 | 132,006 KiB | 144,316 KiB |
| Java used heap | 60 | 33,461,616 B | 45,506,896 B |
| Native allocated heap | 60 | 34,499,248 B | 34,749,808 B |

All 60 audio observations had positive actual AudioTrack playback heads; observed underrun increments were zero. Playback reached 2,854,912 frames, then one sampled head decrease occurred at 60,168 ms (`2,854,912 → 21,760`), near saving, before advancing again to 283,968 by the final sample. This is a track-reset/replacement observation, not evidence of uninterrupted playback or an underrun count. One-second sampling cannot exclude missed transient events.

All sampled renderer runtime-failure counts were zero, but actual presentation timestamp count remained zero and the emulator logged `eglGetFrameTimestampsANDROID` / `EGL_BAD_SURFACE`. Core callback timing therefore must not be represented as physical display pacing or latency. The summary tool reports `captureComplete=true`, zero invalid frame-gap pairs, and `performanceAccepted=null`.

The test restored audio/autosave settings and the prior interval through its finally block. The app was force-stopped after collection and the task-owned logcat collector stopped. Device/build ownership was then returned for the HarmonyOS native measurement window.

## Reproduction

The startup collector retained under the evidence directory supplies the canonical identity, force-stops/checks the PID before each invocation, validates the full adapter count and restored preferences, and excludes two warmups. For the save workload, using the exact-content test APK:

```powershell
adb -s emulator-5582 shell am instrument -w -r `
  -e g1NativePerformance true -e g1Entry native `
  -e g1CanonicalId game:31811AEF54BC433D0D8B9344E0D5AB6417D9F06D97B743ABDDDFC9B3CAB719FF `
  -e g1ExpectedContentKey 39211CB6B159B28E2853E1EFF2731BD8353ED886 `
  -e class com.flynes.emu.G1NativeSavePerformanceTest `
  com.flynes.emu.test/.SingleDeviceCertificationRunner
```

`tools/flutter/summarize_save_performance.py` generated the retained summary from the pulled JSON and epoch logcat, filtering touch events to the measured PID/time window. No physical refresh, audio quality, power, temperature, hardware input latency or candidate budget is certified.
