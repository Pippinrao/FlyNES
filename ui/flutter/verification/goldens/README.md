# G2 reviewed visual fixtures

These are reviewed test fixtures, not build output or device screenshots. Each
directory contains its capture manifest, PNGs, geometry, semantics, frozen
environment and review hashes. The original review records are in `reviews/`.
Native screenshots, recordings and measured performance remain under ignored
`.artifacts/flutter-g2/`; these fixtures do not certify the full G2 gate.

Use Flutter 3.41.7 / Dart 3.11.5 and the framework/engine revisions recorded in
`environment.json`. The frozen tester runs on Windows 10.0.26200.0 at DPR 1.
Do not relax the environment or image thresholds to make a different setup pass.

Fonts are read from the installed Flutter SDK (`material_fonts/roboto-regular.ttf`
and `materialicons-regular.otf`) and the frozen Android 15 task image
(`/system/fonts/NotoSansCJK-Regular.ttc`). The Android system Roboto has a different
hash and must not be substituted. SDK font licenses are adjacent to the SDK fonts;
the CJK font is supplied by the Android image. Fonts are not redistributed here.

From the repository root, with an explicitly selected matching task emulator:

```powershell
tools/flutter/Prepare-G2VisualFonts.ps1 -FlutterSdk <flutter-sdk> -Adb <adb.exe> -AndroidSerial <serial>
tools/flutter/Check-G2Visuals.ps1 -FlutterCommand <flutter-sdk>/bin/flutter.bat
```

The check captures all five runners and compares the four static families using
`tools/flutter/verify_g2_visuals.py` and its `review.json`. This produces independent
actual/expected/diff images on failure. The fixed tolerances are channel 8,
outlier fraction 0.005, and control geometry 1 logical pixel. Semantic differences
fail independently. Neither capture nor comparison updates these fixtures.

Any update requires the approved UX change, actual image review and new review
hashes. A newly captured image is not automatically a correct baseline.
