# Nearby Three-Platform UX Implementation Plan

> **For agentic workers:** Execute task by task with TDD: add one failing platform test, observe the intended failure, make the smallest native UI change, then rerun the test. Do not change shared or platform backend logic. The user explicitly accepts an honest error when a role has no platform bridge yet; keep both roles visible on every platform.

**Goal:** Replace the old friends, discovery and pairing-code navigation with one QR flow and adaptive landscape pages on Android, HarmonyOS and iOS.

**Architecture:** Each platform keeps its native UI. The entry has exactly two role actions; invitation, scanning and lobby use the already present shared session interfaces wherever a platform bridge exists. Network selection and Android local-only hotspot are UI-owned platform orchestration around the existing host call; transport, protocol and game code remain untouched. A missing platform bridge must be reported, never simulated or silently disabled.

**Tech Stack:** Android Java/XML instrumentation, HarmonyOS ArkTS/Hypium, iOS SwiftUI/XCTest, existing shared C++ nearby ABI.

---

## File ownership and order

1. `docs/superpowers/specs/2026-09-23-nearby-three-platform-ux-design.md`: accepted UX, scope and adaptive layout criteria.
2. Android `NearbyFriendsActivity.java`, `activity_nearby_friends.xml`, `NearbyPairingActivity.java`, `activity_nearby_pairing.xml`, `NearbyLobbyActivity.java`, their strings and UI instrumentation: simplify entry, make a real QR invitation readable, place actions beside content, preserve the existing host session. Open a real camera directly; report that guest joining is not wired after scanning.
3. HarmonyOS `NearbyFriends.ets`, `NearbyPairing.ets`, `NearbyLobby.ets`, resources and Hypium UI tests: remove obsolete entry controls and launch the existing ScanKit call immediately from the scan action. Preserve the current guest session and game flow. Report that host creation is not wired without making a fake invite.
4. iOS `NearbyFriendsView.swift`, `NearbyPairingView.swift`, `NearbyLobbyView.swift`, strings and XCTest: remove friends/code/discovery and ScrollViews, use one fixed adaptive landscape composition. Open the camera directly and report missing host/join bridges honestly; do not show a fake invite from the older code-only route.
5. Verification records in `docs/verification/`: separate each emulator's UI assertions from actual two-app connection evidence.

## TDD cycle per platform

### Android

- [ ] Add an instrumentation assertion that entry contains only create and scan, both fully within the inset-adjusted root, and has no scroll container.
- [ ] Build and run that test on a selected emulator to observe the old entry fail.
- [ ] Replace the entry layout and remove obsolete listener code; rerun the same test to green.
- [ ] Add an instrumentation assertion for invite QR size, square shape, visible actions and no bottom rail at 640dp and 736dp landscape content widths.
- [ ] Run red, rearrange XML and activity layout behavior while keeping `NearbyMvpOwner.startHost(ipv4)` and native session calls intact, rerun green.
- [ ] Add a test for LAN-present, no-LAN and hotspot-start-failure UI states before adding Android Wi-Fi platform orchestration. Do not mint an invite before the existing host call returns a real invite.
- [ ] Run affected Android unit tests, build and instrumentation suite on the chosen emulator.

### HarmonyOS

- [ ] Add a Hypium assertion that the entry has only create and scan actions and fits at 1.0, 1.3 and 2.0 font scale without scrolling.
- [ ] Run it red on the connected emulator, then replace the old tabbed entry and rerun green.
- [ ] Add a Hypium assertion that tapping scan invokes ScanKit without a second app action, then move the existing `scanMvpQr()` trigger to page appearance or the entry route and rerun green.
- [ ] Add and run invitation/lobby visibility assertions before compacting their layout; retain native session calls.
- [ ] Run Harmony host CTest, Hypium and signed emulator installation.

### iOS

- [ ] Add XCTest assertions for exactly two role controls, absent friend/code/discovery controls and no scroll gesture needed on a short landscape simulator.
- [ ] Sync to the configured Mac, build and run red; replace the entry SwiftUI with two adaptive cards; build and rerun green.
- [ ] Add XCTest assertions that invite and lobby controls fit inside the safe area at regular and enlarged content size. Run red; remove fixed footer/ScrollView and simplify content; rerun green.
- [ ] Use the repository's `ios/scripts/build_simulator.sh` and `run_simulator_tests.py` on a specified simulator. Record unsupported transport paths truthfully until a bridge is available.

## Completion gate

- [ ] Review all three screens at short and wide landscape sizes; no four-direction application scroll, clipped action, distorted type or fixed bottom button cluster.
- [ ] Run `git diff --check`; inspect `git diff` for changes outside UX, resources, platform adapters and tests.
- [ ] Report each platform and role as one of: real two-app playable, emulator UI verified, compiled only, or blocked by missing platform bridge. Never infer multiplayer capability from a QR graphic or a passing layout test.
