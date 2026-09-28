# Public Dart VM heap evidence collector

`collect_vm_heap.dart` records the heap of one explicitly selected runnable user
isolate, or the unique runnable Flutter `main` isolate. It uses only public
`vm_service` APIs. It never launches an app, creates a port forward, attaches a
debugger that resumes an isolate, installs packages, or changes an SDK.

Default behavior is read-only. `--request-gc` explicitly opts into a public
`getAllocationProfile(gc: true)` request. Actual candidate measurements and GC
requests require a frozen numerical budget and an exclusive measurement
window; the flag is an explicit opt-in, not a passed-budget claim.

## Existing local dependencies

Use the Dart binary and already generated package configuration in the pinned
Flutter-OH SDK. The inspected package configuration resolves `vm_service` to the
existing **15.0.2** cache directory; do not substitute a guessed package version
or run `pub get` merely to execute this standalone script:

```powershell
$heapDart = 'E:/workspace/lib/flutter/flutter-ohos-3.41.10-1.0.0/bin/cache/dart-sdk/bin/dart.exe'
$heapPackages = 'E:/workspace/lib/flutter/flutter-ohos-3.41.10-1.0.0/packages/flutter_tools/.dart_tool/package_config.json'
& $heapDart --packages=$heapPackages analyze tools/flutter/collect_vm_heap.dart
```

Final static analysis passed with the existing cache, including the optional
checkpoint handshake. Five offline preflight tests reject before connecting;
two local fake-protocol tests cover missing/negative values for every before/after
heap field in ordinary and checkpoint mode. Those offline tests do not connect
to a real VM. Separately, the OH simulator run has now collected real matched
round-5/20 Dart heap values through this CLI; see the
[candidate evidence](../../docs/flutter-migration/verification/2026-09-29-ohos-flutter-candidate-performance.md).

## Endpoint handling and isolate selection

Create a private local text file containing the current app's **forwarded
loopback** VM Service URI, using a local editor or the task's private evidence
workflow. Do not put an authenticated URI on the CLI, in chat, in a tracked file,
or in this document. The input can be a single URI or log text with repetitions
of one identical URI, up to 64 KiB. Multiple distinct endpoints are rejected.

Only `localhost`, `127.0.0.1`, and `::1` are allowed. HTTP(S) service roots become
WS(S) endpoints by appending `/ws`; an explicit WS(S) endpoint must already end
with `/ws`. Device logs advertising `0.0.0.0` must first be mapped to the actual
exclusive localhost forward. The collector neither discovers nor creates that
forward. It does not disable VM authentication.

Neither stdout, stderr nor the JSON report stores the service URI or input file
contents. Connection/RPC failures are reported using sanitized codes; raw
exception messages and stacks are suppressed because they may contain the URI's
authentication token. The root library URI in the report is Dart source identity,
not the VM Service endpoint.

Without `--isolate-id`, automatic selection requires exactly one non-system,
runnable isolate named `main`, with a root library and Flutter service extensions
or `package:flutter/` library evidence. Zero/multiple matches fail before heap or
GC collection. The reserved failure JSON lists runnable user isolate identities
for review. With `--isolate-id`, only that exact runnable, non-system isolate with
a root library is accepted. System isolates are never selected, even explicitly.

## Collection

Once the fixed-budget measurement window is assigned and the app is running, and the private URI file points at its
exclusive local forward, use fresh output names for each checkpoint:

```powershell
# Read-only: no reset, GC, resume, evaluation, or application extension RPC.
& $heapDart --packages=$heapPackages tools/flutter/collect_vm_heap.dart `
    --vm-uri-file .artifacts/vm-endpoint-private.txt `
    --output .artifacts/dart-heap-round5-readonly.json

# In the assigned GC diagnostic window: use the verified isolate id.
& $heapDart --packages=$heapPackages tools/flutter/collect_vm_heap.dart `
    --vm-uri-file .artifacts/vm-endpoint-private.txt `
    --isolate-id '<verified-isolate-id>' --request-gc `
    --output .artifacts/dart-heap-round5-gc.json
```

The output parent directory must exist. The file is exclusively created **before
connecting**; an existing file is refused, and failure evidence is kept rather
than deleted or reused. Each RPC/connection has a 15-second timeout. The command
returns nonzero on collection failure and still writes a reserved failure report
when possible. It never clears app data or removes evidence.

The JSON records VM PID/version/start time, isolate id/name/group/root library,
and time-bounded before/after `getMemoryUsage` results: `heapUsage`,
`heapCapacity`, `externalUsage`, all **bytes**. Negative/missing protocol values
become null. Any such value in the six before/after heap fields fails collection
with nonzero exit, `complete: false`, and `errorCode: incomplete-heap-values` in
the evidence JSON; checkpoint mode emits no acknowledgement. The external count covers only memory registered by the embedder
with Dart; it is not all native memory, texture memory, or graphics memory.

`gcOptionEnabled` records the requested CLI mode. `gcRequested` becomes true only
when the GC RPC is about to be issued. `gcObserved` becomes true only after a
request and a strictly increasing, available `dateLastServiceGC` timestamp.
Unchanged, missing, or reset timestamps never certify GC. Another VM Service
client could also request GC, so the measurement window must exclude such
clients; the report states this attribution limit. The public API itself only
promises an attempt, not that GC will run.

## Coordinating OH roundtrips

ArkTS `hidebug` metrics and this CLI's Dart metrics are separate columns. They
must not be added to PSS or confused with Android ART/Java heap. The OH test
harness now supports a bounded, test-only rendezvous at rounds 5 and 20:

1. In the assigned measurement window, add `-s g1WaitForDartHeap true` to the existing memory-only
   test invocation; allow a total runner timeout of at least 600000 ms. The
   harness completes its Ark snapshot, stays on the returned Flutter page, writes
   a unique `.ready.json`, and waits at most 180 seconds. Default runs do not wait.
2. Using the existing explicit-device evidence workflow, copy the logged ready
   file from this task app's sandbox to a new local evidence path. It contains
   `runToken`, round, PID, ready/expiry epoch timestamps and the loopback TCP
   `ackPort`; it contains no VM URI.
3. Run the CLI with that file and a new local acknowledgement output:

   ```powershell
   & $heapDart --packages=$heapPackages tools/flutter/collect_vm_heap.dart `
       --vm-uri-file .artifacts/vm-endpoint-private.txt `
       --checkpoint-file .artifacts/round5.ready.json `
       --ack-output .artifacts/round5.ack.json `
       --output .artifacts/dart-heap-round5.json --request-gc
   ```

4. Only after exit 0 and `complete: true`, create a second, task-owned public
   `hdc -t <task-device> fport tcp:<unused-host-port> tcp:<ready.ackPort>`.
   Connect a host TCP client to that loopback port and send the actual CLI
   acknowledgement as **one compact ASCII JSON line followed by LF**. Do not
   transmit the pretty-printed JSON as multiple lines. Close the client, remove
   only this forward, and receive the resulting sandbox `.ack.json` as evidence.
   The fixture persists the validated acknowledgement itself. API20 public
   `hdc file send -b` sandbox writes returned permission denied on this HVD;
   reads worked. No root daemon, VM evaluation, or product hook is used.
   Do not reuse an old run's file or extend its 180-second deadline.
   The harness validates run token, round, PID, isolate id and evidence hash
   shape, then resumes the next round. At round 20, repeat using new files and
   the already verified `--isolate-id`. Retain all files; the CLI's SHA-256
   references the exact flushed local evidence JSON.

The two checkpoint options must be paired. The CLI rejects expired/malformed
ready files, reused output/ack paths, and a VM PID that differs from the held
app. Host and emulator clocks must agree sufficiently for the stated window;
clock mismatch fails closed. An ack is produced only after complete nonmissing
heap readings and successful evidence flush, while the checkpoint is still
live. It acknowledges collection, **not successful GC or a passed budget**.
`gcRequested` and `gcObserved` remain separate fields in the ack/evidence.

The test-only listener binds only `127.0.0.1`, accepts at most four connections,
limits a single newline-delimited acknowledgement to 16 KiB, and closes all
connections and the listener in `finally`. It exists only during the checkpoint.
The harness records rejected/incomplete acknowledgements and fails on timeout; it never
silently continues or labels unacknowledged measurements as matched. Ark and Dart
measurements are sequential within the held checkpoint, not simultaneous.
`afterDart` records a fresh Ark/PSS observation after the external completion.
No production service, app hook, long-lived poller or Android handshake is added.
Without this opt-in handshake, Dart data is standalone diagnostic data and must
not be labelled as matched round-5/20 samples.

No frame-time or latency budget should be measured during these GC/heap probes.
An available VM Service is required (normally debug/profile); this tool does not
enable it in Release and does not change build mode. Successful collection alone
does not prove leak freedom or approve a memory-growth budget.

Offline verification (preflight checks and a local fake protocol server; no real VM):

```powershell
python -m unittest discover -s tools/flutter/tests -p test_collect_vm_heap_offline.py -v
```
