# Nearby scanner UX restoration

**Goal:** Restore Android scan presentation to the approved nearby landscape design and audit the three native implementations.

**Authority:** The approved 2026-09-23 spec, its 2026-09-25 empty-room amendment, and the user's 2026-09-27 correction. The local v5 prototype predates the empty-room amendment; its manual-ready and back-disconnect copy must not be restored.

**Architecture:** Keep the native session/protocol unchanged. The scanner owns camera lifetime and connection presentation. Use the existing nearby typography, colors, safe-area convention and two-column arrangement. Successful backend initialization is not proof of a connected room.

**Execution:** Continue inline on consolidated main. Preserve the ongoing physical test evidence and existing changes.

## Steps

- [x] Add Android instrumentation assertions that the camera stays left of status/actions, that the header is outside the preview, and that scanning/failure fit 640/736/844dp by 312dp at font scales 1/1.3/2 in Chinese and English. Run against the old layout and capture the assertion failure.
- [x] Replace the scanner's fullscreen overlay with header + two columns in `activity_nearby_qr_scanner.xml`; apply safe-area insets in `NearbyQrScannerActivity.java`. Keep preview aspect ratio and all actions at least 48dp.
- [x] Keep post-scan connecting/failure in the scanner until the native snapshot is actually connected; stop camera after recognition, provide cancellation/retry and correct invalid/network/expired messages. Extend `NearbyQrScannerJoinTest.java` to cover failure staying on-page.
- [x] Run `:app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest`; install with `adb -s emulator-5566 install -r`, run the affected instrumentation classes directly, and inspect saved scanner screenshots. Do not use connectedDebugAndroidTest.
- [x] Record a source-backed three-platform comparison, separately identifying native system scanner differences, unresolved product gaps and evidence limits. Preserve the user-confirmed result that both physical phones now have audible sound.
- [ ] Replace-install on the Android phone only after recording/play has ended; repeat the camera usability check. Commit verified changes with the repository version hook.

## Approved room extension

The user subsequently approved `../specs/2026-09-27-nearby-room-resume-design.md`. This extension adds the explicit Continue ABI and v4 resume acknowledgement handshake, native room game/screenshot identity, and picker resume monitoring. The original scanner-only protocol constraint above applies only to the scanner work.

Red/green evidence and physical acceptance limits are recorded in `../../verification/2026-09-27-nearby-device-room.md`. The Android camera usability result is still pending after the QR sampling and worker correction.
