# Android / HarmonyOS nearby simulator verification — 2026-09-29

Working tree: `codex/flutter-foundation`, base `dab7dc32ac48d384b8d5705e7bda6bff3bd2b368`, version `3.0.3`, with the uncommitted G1 integration changes. Final evidence: ignored `out/nearby-mvp/gate-20260929-020847/`; diagnostic evidence and screenshots: ignored `.artifacts/flutter-g0/android-foundation/`.

Only Android `emulator-5582` and HarmonyOS `127.0.0.1:5557` were operated. No uninstall, data reset, library reset, firewall disabling, version change or production LAN-selection change was performed. Android packages were updated with `install -r`; HarmonyOS used the already installed fixed packages in `.artifacts/flutter-ohos-probe/final-packages/`.

## Failure and correction

The initial product-play run (`gate-20260929-015611`) timed out joining. Android's production LAN selection correctly chose its available Wi-Fi interface `wlan0`, address `10.0.2.16`, but the emulator console UDP redirect delivers to Ethernet `10.0.2.15`. Merely overriding the test socket's source address still failed (`gate-20260929-020011`): the app's default Android Network remained Wi-Fi, so replies followed the wrong network.

Task-scoped UDP probes verified Windows-to-Android delivery, an Android reply of 23 bytes, and an actual 1,200-byte HarmonyOS QUIC initial packet arriving at the Windows host gateway. This isolated the failure to the emulator network selection rather than QR authentication, an incorrect HarmonyOS host gateway, or a need to disable the firewall. Evidence: `udp-eth-probe.txt`, `udp-any-probe.txt`, `udp-android-return.txt`, `udp-oh-to-host.txt`.

The runner now supplies an explicit `emulatorRedirectBindAddress=10.0.2.15` only for its simulator ProductPlay path. The instrumentation validates emulator hardware, the exact address and a matching assigned Android Network, then binds its process to that Network before creating the native socket. Teardown restores the previous binding. The physical-hotspot path and production network policy are unchanged. The existing task-port redirect rewrites only the invite endpoint; the real product protocol retains the invite token and pin. Owned redirects are removed on completion; the final console check reported no active redirections.

After networking worked, `gate-20260929-020514` passed real play and room/resume assertions but failed selecting the next game: the Espresso click targeted a clipped title TextView. The harness now clicks the containing RecyclerView item. `gate-20260929-020659` then passed both apps. The final rerun additionally requires Android's actual AudioTrack playback head to advance, rather than treating submitted samples as consumed audio.

## Final result

`gate-20260929-020847` completed **PASS, one cross-platform round out of one**, from `02:08:48` to `02:09:45 +08:00`.

| App test | Result | Duration |
|---|---|---:|
| Android ProductPlay instrumentation | 1 passed | 52.823 s |
| HarmonyOS ProductPlay Hypium | 1 passed, 0 failures, 0 errors | 53.741 s |

Both real apps loaded the same manifest-selected multiplayer ROM and advanced actual emulation. Assertions exercised START, SELECT, A, B and RIGHT through product controls and checked sampled player input. Android logs include P1 RIGHT at frame 710 and P2 RIGHT at frame 979. Android's AudioTrack consumed **675,648 playback frames**, with 679,680 submitted samples; HarmonyOS independently asserted its audio sink had started and consumed samples. These are functional observations, not controlled performance measurements.

The test paused and verified stopped core progress while retaining the connection, continued play, returned to the room, resumed the same game/session, and selected a second manifest game through the real library. Both apps verified second-game progress over the retained session. Android recorded `event=product_lobby_switch second_game=PASS`. No assertion was removed to obtain a pass.

Screenshots `nearby-g1-host.png` and `nearby-g1-guest.jpeg` were pulled and visually inspected; both show the same real game scene and native controls. The test does not compare pixel hashes. The `GAME_CENTER_INTERACTIVE` marker appeared while opening the library, but its elapsed value in this long-running session is not a cold-start measurement.

## Reproduction and artifacts

```powershell
pwsh -File tools/quality/run_nearby_mvp.ps1 `
  -AndroidSerial emulator-5582 -HarmonyTarget 127.0.0.1:5557 `
  -HarmonyAppPath .artifacts/flutter-ohos-probe/final-packages/entry-default-unsigned.hap `
  -HarmonyTestPath .artifacts/flutter-ohos-probe/final-packages/entry-ohosTest-unsigned.hap `
  -ZlibRoot E:/workspace/codes/games/FlyNES/.artifacts/host-deps/zlib-1.3.1-install `
  -CrossOnly -ProductPlay -CrossRounds 1 -CrossDurationMinutes 0 -PlayHoldSeconds 10
```

The final `run.txt` records both app and test-package hashes, so instrumentation is tied to the installed build rather than only the app artifact:

| Artifact | SHA-256 |
|---|---|
| Android app APK | `8ACDA848B7B1F8856F280D47F847036B9DD2A80B8C04F21319EDACA1CF29DFF8` |
| Android test APK | `35301086660C81A089FA0D9CF86FC86467CF27527B5030409A8E04E9CF9B39D7` |
| HarmonyOS app HAP | `FC1694F3C48CE0E0D2F5E84BCD1D3425FE7D568DEC70B881625D1F6EA8470FD2` |
| HarmonyOS test HAP | `12AA91AEFD0274B49E82836EBF3C8B6117F53CEFFC5BEC0A3DDBA4FC8177787C` |

Final logs are `cross-round-1/android-instrumentation.txt`, `cross-round-1-harmony.log`, `cross-round-1/summary.txt` and `run.txt`. The companion capture is `nearby-playback-head-final.log`, with build evidence `nearby-playback-head-build.log`.

## Scope

This is two-app simulator functional acceptance over explicit emulator NAT adaptation. The summary records `emulatorNat=True opticalQr=false`: the invitation is supplied through the test harness, so this run does not certify camera/optical QR scanning. Separate pairing-QR tests are not substituted for this gameplay result. It does not certify a physical shared-router/hotspot path, physical refresh rate, latency, power, temperature, or a Flutter performance budget.
