# Same-revision native package size baseline

`prepare_native_size_baseline.py` prepares an auditable native-only export for
the G1 or G2 Release package-size comparison. It does not build or measure anything.
This is a derived control build, not the historical 2.1.2 product. Comparing the
old single-ABI 2.1.2 package against the dual-ABI Flutter package would mix native
changes and architecture counts into the Flutter increment.

Preparation must wait for the current native Home selection fix and all intended
native fixes to be committed. Then review and record that exact HEAD. The tool
requires its full SHA via `--expect-head`, verifies it descends from
`c0511d6911d31f86f3ec2987b736cde02780291b`, and archives that commit plus its
Nestopia gitlink commit using `git archive`. It never copies untracked files,
working-tree edits, signing material, local SDK configuration, private ROMs,
or another worktree. It does not create a branch, worktree or Git repository.

## Export and review

Run from the Flutter foundation repository in PowerShell, after the intended
fixes are committed and the chosen revision has been reviewed:

```powershell
$sizeRevision = (git rev-parse HEAD).Trim()
$sizeOutput = Join-Path (Get-Location) ('.artifacts/native-size-' + $sizeRevision.Substring(0, 12))
python tools/flutter/prepare_native_size_baseline.py --expect-head $sizeRevision --output $sizeOutput
if ($LASTEXITCODE -ne 0) { throw 'Native baseline preparation failed' }
Get-Content (Join-Path $sizeOutput 'manifest.json')
Get-Content (Join-Path $sizeOutput 'native-only.patch')
$nativeSizeRoot = Join-Path $sizeOutput 'source'
```

The output must be absent or empty and strictly below this repository's ignored
`.artifacts/`. Existing contents, path traversal, junctions and symlinks are
rejected. Failure never clears output; preserve partial evidence and choose a
new empty destination after fixing the cause. No automatic retry deletes files.

Review artifacts:

- `manifest.json`: source revision, required native ancestor, exact Nestopia
  commit, recipe/patch SHA-256, every changed path and before/after hashes.
- `native-only.patch`: unified diff for the full transformation, including deleted
  embedding files. It can be inspected independently of any package.
- `source-files.json`: SHA-256 of every archived file before and after stripping.
  All paths outside the explicit edit/delete allowlist remain byte-identical.
- `source/`: generated control source tree. No builds or local configuration are
  copied into it. `buildPerformed` and `sizeMeasured` remain false in the manifest;
  later build evidence is recorded separately, not retroactively claimed here.

The Android transformation removes the Flutter Gradle include/repository/app
dependency, activity manifest registration, lazy Flutter engine and bridge,
and the three Flutter-only Java classes. `HomeActivity` and `MainActivity` keep
their current behavior; the removed bridge's `return_to_foundation` constant is
inlined. `AndroidResumeService`, `FoundationResumeQuery`, `AudioThread`, all C++
and the native save/renderer fixes remain byte-identical.

The Harmony transformation removes the four HAR overrides/dependencies/lock
entries, Hvigor HAR guard wiring, FlutterManager registration, two experimental
routes, their pages and the six Flutter bridge files. Native ability background
events, native routes, renderer, N-API, save history and CMake remain unchanged.
The generated lockfile edit is part of the derived control patch; a later
`ohpm install --all` may regenerate it and must be captured with build evidence.
Existing tests that reference stripped experimental pages are left in the export
but are not part of the Release main target. This recipe is not an instrumentation
or Hypium build recipe.

Source-anchor drift, extra production embedding references, or an ABI change
causes preparation to fail for review rather than silently stripping more code.
Both LF and CRLF archives are supported. Matching normalizes only the explicit
edit allowlist, restores each edited file's original line endings, and never
normalizes the untouched native files. A mixed-line-ending edited file is
rejected for review.
The text fixtures currently cover both platform transformations. Neither native
control Release build has been run as part of preparing this tool, so successful
compilation and packaged ABI/content inspection remain required.

## G2 same-revision controls

G2 uses two explicit, platform-specific recipes. `--recipe android-g2` removes
the Android Flutter module, product bridge and launcher route while preserving
the current native session/catalog/save owners. `--recipe harmony-g2` removes
the Harmony Flutter HARs and pages, routes ordinary startup to `GameCenter`,
sets the native-baseline mode before that page loads, and routes native pause,
nearby selection and return to their existing native pages. Both recipes reject
unreviewed route or embedding changes, preserve both native ABIs, and leave the
other platform's source intact. They are size controls, not G2 user-facing
packages; do not install them over data-retention test apps.

After committing the exact G2 candidate source and reviewing its revision,
export each recipe into a distinct empty directory below `.artifacts/`:

```powershell
$sizeRevision = (git rev-parse HEAD).Trim()
python tools/flutter/prepare_native_size_baseline.py --expect-head $sizeRevision --recipe android-g2 --output .artifacts/g2-native-android-$($sizeRevision.Substring(0,12))
python tools/flutter/prepare_native_size_baseline.py --expect-head $sizeRevision --recipe harmony-g2 --output .artifacts/g2-native-harmony-$($sizeRevision.Substring(0,12))
```

Review both manifests, source inventories and patches, then build each Release
control with the platform commands below. Build the G2 Flutter counterparts
from that same exact revision and compare actual unsigned dual-ABI APK/HAP ZIP
byte sizes. Changing the candidate source requires a new matched export.

## Deferred matched Release builds

Do not execute this section during ongoing controlled measurements. Candidate
size comparison uses the frozen numerical budget. In an assigned measurement
window, build both packages from the recorded revision, using the same
installed compiler/toolchain versions, Release mode and **arm64-v8a + x86_64**.
Do not compare profile (whose current OH native host is Debug), debug, test,
signed versus unsigned, or single-ABI versus dual-ABI artifacts.

For the native Android control, use the existing JDK 17 / Android SDK 36 / NDK
27.0.12077973 environment and run only the production Release target in the export:

```powershell
Push-Location $nativeSizeRoot
try {
    ./gradlew.bat :app:assembleRelease
    if ($LASTEXITCODE -ne 0) { throw 'Native Android Release build failed' }
} finally { Pop-Location }
```

No Flutter bootstrap is needed in the stripped export. `ANDROID_HOME` must point
to the existing SDK; do not copy the checkout's ignored `local.properties` or
credentials. Output: `source/app/build/outputs/apk/release/app-release-unsigned.apk`.
Build the Flutter counterpart at `manifest.sourceRevision` using the pinned
`Build-Android.ps1 -Configuration Release`. Any later production edit requires a
new reviewed revision and new matched control export.

For the native Harmony control, use the same DevEco/API20 installation as the
Flutter counterpart. Generate only licensed bundled resources from the archived
source of truth, then install dependencies and assemble the main Release target:

```powershell
$sizeDevEco = 'D:/soft/DevEco Studio'
$sizeNode = Join-Path $sizeDevEco 'tools/node/node.exe'
$sizeOhpm = Join-Path $sizeDevEco 'tools/ohpm/bin/pm-cli.js'
$sizeHvigor = Join-Path $sizeDevEco 'tools/hvigor/bin/hvigorw.js'
& (Join-Path $nativeSizeRoot 'tools/content/sync-builtin-content.ps1') -Root $nativeSizeRoot
$sizeSavedSdk = $env:DEVECO_SDK_HOME
$env:DEVECO_SDK_HOME = Join-Path $sizeDevEco 'sdk'
Push-Location (Join-Path $nativeSizeRoot 'harmony')
try {
    & $sizeNode $sizeOhpm install --all
    if ($LASTEXITCODE -ne 0) { throw 'Native OH dependencies failed' }
    & $sizeNode $sizeHvigor --mode module -p product=default -p buildMode=release assembleHap --no-daemon
    if ($LASTEXITCODE -ne 0) { throw 'Native OH Release build failed' }
} finally {
    Pop-Location
    $env:DEVECO_SDK_HOME = $sizeSavedSdk
}
```

Output: `source/harmony/entry/build/default/outputs/default/entry-default-unsigned.hap`.
Build the Flutter counterpart at the same revision with `Build-Ohos.ps1 -Mode
release`. Do not import or generate a signing identity; unsigned package sizes
are the comparison under this recipe.

Keep command logs, actual SDK/compiler versions, final package SHA-256 and byte
sizes, and package-entry inventories. Confirm both architectures and matching
native libraries/resources in each pair; explain any differing native `.so`
bytes (including source-path/build-id effects) before attributing the difference
to Flutter. Report `candidate bytes - control bytes` per platform, for the same
package type and compression/signing settings. Archive size alone is not runtime
memory, download-store size, latency or performance certification.

## Text-only verification

```powershell
python -m unittest discover -s tools/flutter/tests -p test_prepare_native_size_baseline.py -v
```

These tests read committed textual fixtures, transform them in memory and use
temporary text/tar fixtures for path protections. They do not export the full
repository, build packages, operate devices or measure candidate sizes.

## Actual control build verification (2026-09-29)

The export at `.artifacts/ns5/` was created from `eaafd7d0a38d3a60ffe7d2db8aad8f04857d6370` (3.0.5), including the selected-game fix. The first actual archive attempt exposed CRLF anchor handling absent from `git show` fixtures; the added CRLF regression failed before the correction, then all eight text tests passed. The corrected exporter preserves each modified file's original newline convention and leaves untouched native bytes unchanged.

Both native-only production Release builds now pass: Android `assembleRelease` in 2m24s and Harmony `assembleHap` in 1m37s. Android uses the same SDK/NDK and two ABIs; Harmony CMakeCache explicitly records Release for arm64-v8a and x86_64. Both package inventories contain the two native architectures and no Flutter entries. Native libraries are ZIP_STORED (method 0). Neither unsigned control package was installed or represented as a release certificate.

| Native-only control | Bytes | SHA-256 |
| --- | ---: | --- |
| Android unsigned APK | 32512882 | 9b22b27e16c1e8e2639fe8a867c19fa8ba7980ce195def758bbf1899b7090c8f |
| Harmony unsigned HAP | 26884836 | cfec858704f9f6665835201b08dcd564b21fbc9445a151fca5b6a08c5f15a706 |

Evidence: `.artifacts/ns5/{manifest.json,native-only.patch,source-files.json,native-packages.json,android-native-release-build.log,ohos-native-release-build.log,ohos-dependencies.log,ohos-content.log}`. The complete ZIP entry inventory is in `native-packages.json`. This confirms buildable controls only; the matching candidate comparison follows the frozen numerical budget.
