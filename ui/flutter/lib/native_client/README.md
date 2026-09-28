# Native client boundary — B01

This is the reserved boundary for the Dart application client (REQ-009).
There is deliberately no invented C ABI, fake catalog, or no-op native service.

Future feature pages consume typed commands and immutable snapshots from this
client. Core loading, persistence, nearby state and simulation stay in C++.
OS-specific resource access goes through narrow platform adapters. Frames and
PCM do not travel through Dart messages. Callback ownership, cancellation and
session generations must be agreed with B02 before adding the bridge.

The bootstrap page works without this client; that does not certify native
integration. Add only the interfaces required by the next assigned requirement.
