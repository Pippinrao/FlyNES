# Nearby QR and hotspot-join backend plan

1. Add failing tests for the common plain-LAN and hotspot-envelope grammar,
   including malformed invitations; implement a small parser on each platform.
2. Add failing tests for ordering and cancellation: a plain LAN invite joins
   directly, while a hotspot envelope requests the OS network first and joins
   only after readiness. Implement headless platform adapters.
3. Add QR camera-source lifecycle tests where a scanner service is needed,
   without connecting a screen or changing navigation.
4. Run affected Android unit/build checks, Harmony host CTest and product/test
   HAP builds, and iOS simulator build plus backend-focused tests. Record red
   and green evidence, and clearly separate simulator/compile checks from
   signed-device Wi-Fi, camera, and cross-device gameplay acceptance.

No existing friend page or other frontend file is edited in this plan; the
future UX change is a separate decision and implementation.
