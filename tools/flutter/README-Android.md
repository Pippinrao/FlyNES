# Android foundation host

`app/` is the product host (`com.flynes.emu`), including the Flutter source module
in `ui/flutter/`. `.android/` remains generated input, never a separately shipped
app. Default navigation still starts the native `HomeActivity`; the internal
`FlutterFoundationActivity` is the G1 validation route. Instrumentation opens it
explicitly in the existing package.

`FlyNesApplication` lazily owns one foundation engine and the narrow
`flynes/foundation` bridge. The bridge borrows the existing catalog, exact launch
service, history store and native pages. `MainActivity` retains the real game,
audio, renderer, input and history lifecycle. A foundation-origin pause/library
action finishes that native game activity, then the Dart page refreshes.
The debug texture probe uses a separate activity-owned engine and core, with
`flutter_texture_probe=true`; it never reads or writes user saves.
The Swappy adapter balances ART attachments on its native worker exit through
the library's public thread hook, so repeated game owners can be collected.

`AndroidResumeService` is shared by both halls. Catalog payload SHA-1 is not the
existing save key: a checked ROM is loaded in a short-lived core to obtain the
same PRG/CHR identity as `MainActivity`, cached by immutable payload SHA-256.
The query reads `head`, and only if no head exists reads the legacy slot. It
does not migrate data; real launch continues to perform native restore checks.

Run from the repository root:

```powershell
pwsh -File tools/flutter/Build-Android.ps1 -FlutterCommand E:/workspace/lib/flutter/flutter/bin/flutter.bat -IncludeTests
pwsh -File tools/flutter/Build-Android.ps1 -FlutterCommand E:/workspace/lib/flutter/flutter/bin/flutter.bat -Configuration Release
```

The script checks Flutter 3.41.7 framework revision
`cc0734ac716fbb8b90f3f9db8020958b1553afa7`, engine revision
`59aa584fdf100e6c78c785d8a5b565d1de4b48ab`, and Dart 3.11.5 before regenerating
module files. The existing Gradle app controls identity, build type, signing and
version metadata; `VERSION` remains authoritative. Debug uses the existing local
test signature, not a store certificate. The current release configuration
builds an unsigned APK; no new signing identity is introduced by Flutter.

Builds do not install or clear data. Preserve a compatible installed package with
`adb -s <explicit serial> install -r` and invoke instrumentation directly, as
documented in `docs/DEVELOPMENT.md`; do not use UTP on retained installations.
Current evidence and outstanding G1 gates are in
`docs/flutter-migration/verification/2026-09-29-android-foundation.md`.
