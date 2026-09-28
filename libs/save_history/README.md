# save_history

A standalone C++17 static library with a C ABI for local history of opaque state
and optional thumbnail bytes. It has no emulator, application, or platform SDK
dependency. SQLite is compiled privately into the archive. Callers own capture,
decode, UI, threading, and migration from their older storage format.

## Build, test, install, consume

Run from this directory with any CMake 3.16+ C/C++17 toolchain:

```sh
cmake -S . -B build -DSAVE_HISTORY_BUILD_TESTS=ON
cmake --build build --config Debug
ctest --test-dir build -C Debug --output-on-failure
cmake --install build --config Debug --prefix "$PWD/install"
cmake -S examples -B consumer-build -DCMAKE_PREFIX_PATH="$PWD/install"
cmake --build consumer-build --config Debug
ctest --test-dir consumer-build -C Debug --output-on-failure
```

Tests require Python 3 for the process-kill harness. Library builds do not.
`find_package(save_history 1 CONFIG REQUIRED)` provides
`save_history::save_history`. An embedded build may use `add_subdirectory` and
the same target. No SQLite header or installation is required by consumers.
The examples build one C translation unit and one C++ translation unit as
separate executables, using only the installed public header and archive.

## Contract

- Zero-initialize `sh_entry` / `sh_options` and set `struct_size = sizeof(...)`.
  An incompatible structure size returns `SH_INVALID`.
- Each store handle must be called serially, including close. The library has
  no executor, background worker, global current game, or clock. Multiple handles
  use SQLite locking; the busy timeout is 2.5 seconds.
- Paths and strings are UTF-8, NUL-terminated. The parent directory must already
  exist. Content key, format, and session are required, nonempty, and at most
  4096 bytes each. Labels are optional and at most 4096 bytes. Played time must
  fit signed 64-bit. Blobs must fit `INT_MAX` and SQLite's configured limits;
  state must be nonempty. Thumbnail may be empty.
- Inputs are borrowed only during a call. SQLite copies inserted data. The caller
  owns read buffers; no library allocation crosses the ABI. List strings and
  metadata are valid only during their callback. Copy anything needed later.
  A nonzero callback return stops iteration successfully. Do not re-enter the
  store from its callback. C++ exceptions are caught at the ABI boundary.
- `sh_put` creates immutable blobs and metadata except the editable label and
  pin flag. IDs are positive signed 64-bit values. `parent_id` is an optional
  lineage hint: it must exist with matching content/format at insertion but may
  later be pruned. It does not itself protect an old record.
- Set `make_head=1` to publish the new resume head in the insertion transaction.
  Resume uses `sh_get_head`, never “newest record”. Plain `sh_set_head` also
  requires an existing record with the exact content key and format.
- `sh_list` matches content and format exactly and sorts by `created_ms DESC,
  id DESC`. `limit=0` means all. Metadata includes `is_head`.
- `sh_read` checks identity/format and CRC-32 for the requested blob, even when
  only querying its size. `buffer=NULL, capacity=0` returns `SH_OK` plus the
  required size. A short buffer is untouched and returns
  `SH_BUFFER_TOO_SMALL`. CRC-32 detects accidental corruption; it is not an
  authentication mechanism. Thumbnail damage can be handled independently of
  a valid state by showing a placeholder.
- On insertion or prepare failure, output IDs are zero and no partial insertion,
  pruning, head update, or protection replacement commits. Other missing IDs
  and wrong content/format return `SH_NOT_FOUND`. Error codes are defined in the
  public header. `SH_BUSY` means database contention or an unfinished restore
  for that content/format; `SH_QUOTA` includes SQLite disk-full/size-limit errors.
  `SH_IO` is other storage failure. `sh_close(NULL)` is safe.

## Retention and disk behavior

Defaults are 60 ordinary automatic records per content key, 256 MiB of blob
payload per content key, and 1 GiB total blob payload. Zero-valued options select
these defaults. Byte accounting includes state and thumbnail payloads for all
records; it excludes SQLite page/index/journal overhead. The database file may
therefore exceed the payload limit, and freed pages are reused rather than
automatically vacuumed. This avoids large automatic database rewrites.

Retention excludes pinned records, manual records, legacy imports, every
current head, the latest protection point for each content/format, and target,
backup, and original-head references held by unfinished restores. Protected
records do not consume the count of 60 ordinary autosaves. Cleanup chooses the
oldest eligible record by timestamp and ID. Older protection records become
eligible for byte eviction after their replacement commits; pin one to retain
it indefinitely. The record being inserted is never silently evicted.

Insertion, head publication, replacement protection, and pruning share one
SQLite transaction. If protected records prevent satisfying a quota, the entire
transaction rolls back. Pinning and head changes may increase the protected
set; the next insertion applies retention. Explicit deletion rejects pinned,
head, latest-protection, and unfinished-operation references with `SH_PROTECTED`.
Manual and legacy records may be explicitly deleted when otherwise unprotected.

The database uses `journal_mode=DELETE`, `synchronous=FULL`, foreign keys,
and `BEGIN IMMEDIATE` for multi-step writes. Schema initialization/migration is
transactional at `user_version=1`; newer versions return `SH_UNSUPPORTED`.
There is no WAL tuning, external blob directory, encryption, or sync protocol.

## Restore and restart coordination

1. Pause the application's state producer on its owning executor and capture
   immutable current bytes. Call `sh_prepare_restore(target, current, ...)`.
   It validates the target state, commits the current bytes as protection, and
   records an unfinished operation. The previous head is unchanged.
2. Read and decode the target with the application's own runtime. Only after
   successful decode call `sh_finish_restore(operation)`, which atomically
   publishes the target head and marks the operation finished.
3. On decode or finish failure, restore the captured protection in the runtime
   and call `sh_recover_restore(operation)`. Recovery validates the backup and
   atomically publishes it as the resume head while completing the pending
   operation as recovered. A failed commit leaves both prior head and pending
   intent unchanged. Do not combine cancel and a separate head update: a crash
   between those commits would lose the recovery intent. If runtime rollback
   also fails, stay paused and retain the operation and disk evidence.

`sh_cancel_restore` remains available for cancellation that intentionally leaves
the prior head unchanged. Repeated finish, repeated cancel, or repeated recovery
succeeds, including after reopen. Switching between those three completion
outcomes returns `SH_CONFLICT`. While unfinished, inserts and direct head updates for
that content/format return `SH_BUSY`. The target and backup cannot be pruned.
On reopening, `sh_get_pending_restore` exposes the operation and its two record
IDs. The caller must reconcile the runtime and finish/cancel/recover; opening never
guesses which in-memory runtime state survived a crash.

For a restart, first `sh_put` the current bytes with `kind=SH_PROTECTION` and
`make_head=1`, then reset the runtime while preserving its persistent data.
Finally insert a snapshot of the fresh runtime with `make_head=1`. If reset or
the final insert fails, restore the durable protection and remain paused. This
sequence keeps a valid pre-restart resume head across process termination.
The library itself never resets a runtime or knows what its bytes mean.

## Verification evidence (2026-09-28)

Windows MSVC 19.44 / CMake 3.22.1 builds in repository-ignored
`.artifacts/save-history-host`. Initial executable failure was the assertion
`sh_open(":memory:", nullptr, &store) == SH_OK` against an unsupported stub.
Further recorded red assertions covered insert, retention, quota rollback, and
restore, and atomic recovery. The corresponding green suite passes eleven cases: open, byte persistence
and metadata operations, protected retention, quota rollback, corruption,
restore/reopen/idempotency, failed backup, actual COMMIT failure with a locked
reader, schema initialization/version rejection, recovery commit rollback and
idempotency, and a killed transaction with
dirty rollback-journal pages. The latter is a real subprocess kill using the
same SQLite database, not an in-memory mock.

Installed-package consumers pass both C and C++ executables. Logs are under
`.artifacts/save-history-host/` (`red-*.log`, `green-*.log`), with consumers in
`.artifacts/save-history-consumers`. These are library-host results, not mobile
device latency, power, storage-throughput, or user-interface certification.

Original library code follows the repository's GNU GPL v2 license, reproduced
in [LICENSE](LICENSE). SQLite is public domain; pinned source provenance and
verified archive hash are in [vendor/sqlite/README.md](vendor/sqlite/README.md).
