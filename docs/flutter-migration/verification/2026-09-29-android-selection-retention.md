# Android selected-game retention regression — 2026-09-29

Base: `c0511d69`, version `3.0.4`; the changes below are uncommitted. Only task AVD `emulator-5582` was operated, using replacement installs without removing data. No version change was made.

## Failure

The opt-in startup observation exposed a real native Home issue after clearing a previously retained BUILTIN filter. The full native adapter contained 2,231 rows, but the selected playable identity was replaced with the first unavailable fixture row. The primary action remained disabled for the full 30-second observation. Evidence: `.artifacts/flutter-g0/android-foundation/startup-native-all-instrumented-20260929/pilot.log` and `pilot.json`. The report retains null interactive timings and `result=incomplete`; preferences were restored successfully.

`HomeSelectionRetentionTest` then reproduced the cause deterministically using a real available catalog row and an in-memory unavailable first row. Applying a one-row startup window incorrectly replaced the existing selection before the full projection arrived. The expected identity and actual `selection-test-unavailable` appear in `home-selection-red.log`. This test changes no catalog or save data and restores UI preferences.

## Minimal product correction

- `HomeActivity.renderGames` resolves the selected identity against the current visible list, rather than treating the row-view cache as the catalog. A selected item outside the current filter is not retained. A partial startup window does not invalidate an identity absent from that window; the action stays disabled until its full row arrives.
- `GameCenterSnapshot.findRow` supports identity lookup. The existing lazy codec had no lookup API, so its implementation now scans encoded identities and decodes only the matching row. Startup lookup examines only real window rows, not generated placeholders.
- The selected row is cached individually for launch/detail behavior. The fix does not populate the entire Home row map, reorder the library, scroll to a game automatically, or alter ROM/save identity.

The product diff is three Java files, 40 insertions and five removals. A new unit test searches the last identity in a 2,224-row lazy projection, verifies only one row was decoded, and checks missing/window-excluded identities. The UI test also verifies an explicit search excludes the prior selection and disables the unavailable replacement.

## Verification

- Android unit suite: **583 tests, zero failures/errors, two skips**; `home-selection-final-build.log` and `app/build/test-results/testDebugUnitTest/`.
- Relevant instrumentation: **10/10 PASS in 69.522 s**; `home-selection-ui-final.log`. Includes Home selection retention (1), continuous library (2), recreation lifecycle (1), and existing Flutter foundation functional regressions (6), including 20 real game round trips. These are functional checks, not candidate performance samples.
- `git diff --check` passed.

All named logs above are under ignored `.artifacts/flutter-g0/android-foundation/` unless otherwise specified.

| Verified artifact | SHA-256 |
|---|---|
| Installed corrected production debug APK | `002D8224783670DE1DDE07443DAE481B07471EF1A255577757527C528088F9FC` |
| Test APK used for the 10 passing UI tests | `F7B44ABE06339C57A53C402F14D0BB9C9EF0E7F9DFF57D0BAB68BB20992D8887` |

The startup observation harness was subsequently tightened to require a separately verified `g1ExpectedSelectedCanonicalId`, avoiding a pre-launch scan/decode of the lazy directory, and to assert native selection matches that identity. This test-only revision compiled successfully (`startup-observation-no-prewarm-build.log`) but was not installed or measured in this handoff. Its APK hash is `FF089EAA4119DB38E11EC5B1AD0EE39AD2ED58EE4A22CE0275A7A5DCA31D12E9`.

## Measurement status and next invocation

The old `c0511d69` production APK hash `76F73DF423F413804E54ACABB3E1F9291A2524E99274CD08123F358E1FAB6E31` remains the identity of the earlier native measurement history. The incomplete filtered sample batch in `startup-native-instrumented-20260929/` is not a full-directory paired baseline. No corrected-package 12-run startup or 65-second baseline, and no Flutter candidate performance measurement, was performed in this fix task.

After installing the final test package in an explicitly assigned device window, invoke one sample per process, confirming `pidof com.flynes.emu` returns no PID after force-stop:

```powershell
adb -s emulator-5582 shell am force-stop com.flynes.emu
adb -s emulator-5582 shell pidof com.flynes.emu
adb -s emulator-5582 shell am instrument -w -r `
  -e g1StartupObservation true -e g1StartupRoute native `
  -e g1ExpectedSelectedCanonicalId '<independently verified available canonical ID>' `
  -e class com.flynes.emu.G1StartupObservationTest `
  com.flynes.emu.test/.SingleDeviceCertificationRunner
```

JSON is written to the app's external-files directory as `g1-startup-native-<pid>.json`. Route `flutter` exists for a later authorized paired run. UI timestamps are polling/ActivityScenario/runner software upper bounds, not precise Dart submission or physical presentation times. Native readiness and projection callbacks are separate upper bounds; negative activity-relative values mean the callback was observed before the Activity request. All samples include requested polling interval, actual poll count, PID, process origin, configured filters/selection, directory scope, restoration result, and memory observations.
