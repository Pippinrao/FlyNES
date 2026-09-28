# Android foundation integration verification — 2026-09-29

Working tree: `codex/flutter-foundation`, base `dab7dc32ac48d384b8d5705e7bda6bff3bd2b368`, version `3.0.3`.
Evidence: ignored `.artifacts/flutter-g0/android-foundation/`. No commit, version change, uninstall or app-data reset was performed for this verification. Device operations in this report target only `emulator-5582`, AVD `FlyNES_FlutterG0_20260928`, Android API 35.

## Implemented boundary

- The production `com.flynes.emu` app embeds the source Flutter module. Its default native launcher and signing configuration remain unchanged. `FlutterFoundationActivity` is an explicit internal validation entry, with a lazy application-owned engine.
- `flynes/foundation` projects the existing catalog, native local cover paths, resume state, exact launch service and native settings/source/nearby pages. Rows preserve native order. No new game database, save database, ROM bundle or game-name table is introduced.
- Catalog payload SHA-1 and existing core PRG/CHR save identity are distinct. `AndroidResumeService` resolves the existing identity through a checked ROM/core load, caches by immutable payload SHA-256, reads the actual selected history head, and consults the legacy slot only when no head exists. Both native and Flutter halls use this projection. Queries do not migrate saves.
- Native `MainActivity` retains audio, rendering, input, pause and save ownership. A foundation-origin game-center action finishes the native owner and returns to Flutter for refresh. Pending launch results are discarded only when they match the staged request. Old host Activity results cannot complete the current host's route.
- The debug texture probe has a separate engine/core and uses no user save store. Its native media and owner lifecycle tests are maintained separately from the production game controls.

## Red/green findings

Initial instrumentation established missing host registration, absent bridge behavior, incorrect save-key mapping, and native navigation that did not return to Flutter. Each was corrected and rerun. Unit tests established the absent-head legacy fallback and staged-launch discard contract before their fixes. The stale-host native route regression also failed before the owner identity check.

The 20-game round trip exposed a real leak: destroyed game Activities retained two 4 MiB direct frame buffers each. An Android HPROF analyzed with Shark found ten strong paths from native-thread JNI locals through `WindowManagerImpl.mContext` and `ContextImpl.mOuterContext` to ten destroyed `MainActivity` instances. Audio threads and history timers had already stopped. The original acceptance exhausted the 192 MiB Java heap while saving at cycle 20.

Swappy's native refresh-rate callback attaches its worker to ART and obtains Activity-backed display objects ([upstream implementation](https://android.googlesource.com/platform/frameworks/opt/gamesdk/+/refs/heads/main/games-frame-pacing/common/SwappyCommon.cpp)). The adapter now uses Swappy's public thread-function hook to detach those newly created native workers from ART before thread exit; it preserves Swappy init/destroy ownership and does not change EGL policy or raise the heap limit. A diagnostic rerun passed 20 real cycles with Java used heap approximately 26.1 MiB throughout, only the current test local retained during each cycle, and zero retained game owners at the end. A subsequent ordinary run without per-cycle forced GC also passed all 20 cycles. Every cycle advanced actual emulation, had exactly one native audio thread while playing, and zero audio threads or history callbacks after returning.

Relevant evidence: `acceptance-instrumentation.log` (original OOM), `heap-analysis.log`, `swappy-fix-instrumentation.log`, `swappy-fixed-20-heap.log`, `roundtrip-final-logcat.log`. The heap dump is local ignored evidence and is not a release artifact.

The new texture owner-handoff test also exposed an existing `AudioThread` stop-before-start race. `stopLoop()` set the initially false flag to false, but the later `run()` changed it back to true. A deterministic lifecycle test failed on the old behavior. The parent task corrected the one-shot thread's initial flag and checked it before starting; both that regression and real texture owner replacement then passed in the final suite. Evidence: `audio-stop-before-start-red.log`, `audio-green-build.log`, `final-17-instrumentation.log`.

## Verification status

The final consolidated suite is **17/17 PASS in 175.762 seconds**, recorded in `final-17-instrumentation.log`. The earlier invocation `acceptance-final-instrumentation.log` includes two incorrect test class names and the subsequently fixed texture owner audio-start race; it is not used as a passing suite.

- Android unit suite: **582 tests, zero failures, two skips** (`audio-green-build.log`, XML under `app/build/test-results/testDebugUnitTest`).
- Host suite: parent task's fresh build and **132/132 CTest PASS** (`.artifacts/flutter-g0/host/shared-final-ctest.log`, 295.08 seconds).
- SDK mismatch preflight: rejected before module generation (`sdk-pin-reject.log`).
- Twenty real game round trips: passed; every prior owner collectible and no repeated audio clock or history timer.
- Existing native Home Continue label: passed after selecting the real played row through its RecyclerView, using the same core save identity as Flutter.
- Texture frame/audio/multitouch/background/20 attach-detach and owner-handoff tests: both passed. Recorded frames reached the Flutter texture, actual AudioTrack playback advanced, A+B input sampled `3 → 2 → 0`, background stopped stepping, and runtime failures remained zero. Final cycle submitted/uploaded frames reached 222 and AudioTrack playback reached 15,232 frames, with zero underruns in that snapshot (`final-functional-logcat.log`). These values are functional evidence, not controlled performance measurements.
- Replacement fixture seed and verification: both passed (`upgrade-seed.log`, `upgrade-verify.log`) across same-signature `install -r`, including selected old head, pending state, metadata/blob/thumbnail, legacy preservation and battery/interval data. This same-version check is distinct from the parent's actual historical-version [Android upgrade verification](2026-09-29-android-upgrade.md).
- Native pause, returned Flutter Continue and texture screenshots were pulled and visually checked: `foundation-native-pause.png`, `foundation-returned.png`, `foundation-texture-playing.png`.

| Instrumentation class | Passed |
|---|---:|
| `FlutterFoundationIntegrationTest` | 6 |
| `FoundationTextureIntegrationTest` | 2 |
| `save.HistoryUiTest` | 4 |
| `GameCenterLifecycleTest` | 1 |
| `ui.HomeContinuousLibraryTest` | 2 |
| `SwappyFailClosedTest` | 1 |
| `AudioThreadLifecycleIntegrationTest` | 1 |

## Build artifacts

Pinned-SDK Release build passed (`release-final-build.log`, 1 minute). First-run Gradle downloads stalled; the two exact official Flutter engine artifacts were fetched from Google Storage, verified against its MD5 metadata, and placed in Gradle's content-addressed cache before retry. Provenance and SHA-256 are in `release-dependency-recovery.json`. No dependency version or repository source was changed for this recovery.

Both product APKs retain `com.flynes.emu`, version `3.0.3` / `3000003`; instrumentation is the separate existing `com.flynes.emu.test` package. The release APK contains `libapp.so` for arm64-v8a and x86_64 and no debug kernel blob. Signature inspection confirms the current Release APK is unsigned; it was not installed. Exact verification-time package metadata is in `package-hashes.json`:

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| `app/build/outputs/apk/debug/app-debug.apk` | 160536799 | `CA660C60938B9B6BD69B90935C49B1D838CF0A1FC6CAFED3AD8BDDFE1CA53433` |
| `app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk` | 28186538 | `DB4D92AC0899EC2D711F6C9B7DF211A8158893A863DCAFA9C4ABBAF1D57A2D5C` |
| `app/build/outputs/apk/release/app-release-unsigned.apk` | 64656926 | `9457EDE6E40ABB2D38B9A205C1B5AB2B8BF7F2DEEE0DAAACECA68D0B45A5C057` |

## Reproduction and scope

Use `tools/flutter/Build-Android.ps1` as documented in `tools/flutter/README-Android.md`. It verifies Flutter 3.41.7 framework `cc0734ac716fbb8b90f3f9db8020958b1553afa7`, engine `59aa584fdf100e6c78c785d8a5b565d1de4b48ab` and Dart 3.11.5. Debug retains the existing local test signature; Release is unsigned under the existing Gradle configuration. Neither is described as a store certificate.

Build test APKs, replace-install with an explicit serial, and invoke `com.flynes.emu.test/.SingleDeviceCertificationRunner` directly. Do not use UTP on a retained installation. The final targeted set is listed above.

These are emulator functional results. They do not certify physical refresh, latency, temperature, power or performance budgets. Release packaging is not a performance result. The parent task owns shared/core host gates, historical Android upgrade verification, nearby interoperability and the cross-platform G0/G1 decision. This report alone does not mark G1 passed or change the default UI.
