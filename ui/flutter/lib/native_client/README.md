# Native client boundary — B01

The G1 foundation client is an experimental, typed projection of existing native
owners. It does not replace the broader REQ-009 client or create a new C ABI.

The validation page consumes immutable snapshots and canonical-ID commands.
Core loading, persistence, nearby state and simulation stay with native owners.
OS-specific resource access goes through narrow platform adapters. Frames and
PCM do not travel through Dart messages. The page controller invalidates catalog
and selection requests on refresh/disposal; even a late reply for the same
canonical ID cannot replace a newer selection query. Disposal does not close
native services. Launch requests are serialized and returning refreshes progress.

## Experimental channel contract

`flynes/foundation`, standard method codec; no extra plugins. Harmony reuses the
existing app/N-API owner through its Stage host. This is a bounded G1 bridge;
public FFI consolidation remains a later client design task.

| Method | Arguments | Result |
| --- | --- | --- |
| `catalogSnapshot` | none | `{generation, games: [{canonicalId, titleEn, titleZhHans, available, unavailableReason}]}` |
| `resumeCapability` | `{canonicalId}` | `{state: available / none / unavailable, reason?}` |
| `launch` | `{canonicalId}` | `{status: returned / cancelled / unavailable, reason?}` after native return |
| `openNative` | `{page: settings / sources / nearby}` | completes after native return |

Generation is monotonically increasing within the host bridge's lifetime, not a
claim about an existing C++ catalog revision. Availability describes the source,
not whether a bridge method has been implemented. The native adapter must query
the current head (iOS legacy slot) to provide progress, never infer from play
history. Unimplemented methods report unavailable; they do not return fake
success. Dart keeps queries in `querying` until a real reply.

The first Harmony slice implements catalog only. It cannot certify launching,
resume, game containers or G1. Missing host services produce an error state with
retry, not a synthetic fallback catalog. Full categories/search and other G2 UI
remain outside this validation page.
