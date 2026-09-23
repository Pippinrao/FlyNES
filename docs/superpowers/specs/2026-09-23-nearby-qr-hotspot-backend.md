# Nearby QR and hotspot-join backend (2026-09-23)

This increment adds only network-entry backend code on Android, iOS, and
HarmonyOS NEXT. The forthcoming UX will decide where scanning, permissions,
network status, and cancellation appear. Do not change the existing pages,
navigation, strings, friend features, or game-session protocol here.

Each guest backend accepts either the existing `flynes-lan-v1` invitation on
an already-connected LAN or `flynes-wifi-v1:<SSID>:<passphrase>:<invite>`.
Envelope fields use UTF-8 percent encoding. Parsing validates lengths, numeric
IPv4/port, and pin/token shape before invoking an OS or session operation.
After a hotspot envelope, the OS asks the user to join that Wi-Fi. The guest
waits for the requested network and a usable IPv4 address, then passes the
inner LAN invitation to the existing session and TLS pin. Cancellation fences
late callbacks and releases the requested network at session teardown. Network
ownership outlives the scanner; iOS maintains a process-scoped owner that
observes the session terminal state, and Android/Harmony retain their network
handle until the session is explicitly closed.

Android uses `WifiNetworkSpecifier`; iOS uses `NEHotspotConfiguration` and
checks the requested SSID plus Wi-Fi IPv4; HarmonyOS uses a candidate Wi-Fi
configuration with user action and waits for the linked SSID plus IPv4. Android
and iOS provide camera QR sources without attaching them to a page. HarmonyOS
already has a Scan Kit page path; the new backend accepts scanned text without
changing that page. Existing host/guest session APIs remain intact.

Out of scope: UI wiring or removal, friends, automatic LAN discovery,
automatic hotspot creation, system-settings guidance, ROM transfer, and
physical-device acceptance. The OS-specific Wi-Fi flow and camera require
signed physical-device verification; simulator builds and test doubles cannot
certify radio association or two-player gameplay.
