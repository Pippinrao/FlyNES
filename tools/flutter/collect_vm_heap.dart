// Use the pinned Flutter SDK's existing flutter_tools package_config.json.
// This CLI never installs packages, forwards ports, starts apps, or prints URIs.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:vm_service/vm_service.dart';

const _rpcTimeout = Duration(seconds: 15);

class _Failure implements Exception {
  const _Failure(this.code);
  final String code;
}

class _Options {
  const _Options(
    this.uriFile,
    this.output,
    this.isolateId,
    this.requestGc,
    this.checkpointFile,
    this.ackOutput,
  );
  final File uriFile;
  final File output;
  final String? isolateId;
  final bool requestGc;
  final File? checkpointFile;
  final File? ackOutput;

  static _Options parse(List<String> arguments) {
    final values = <String, String>{};
    var requestGc = false;
    for (var index = 0; index < arguments.length; index++) {
      final flag = arguments[index];
      if (flag == '--request-gc') {
        if (requestGc) throw const _Failure('duplicate-option');
        requestGc = true;
        continue;
      }
      if (![
            '--vm-uri-file',
            '--output',
            '--isolate-id',
            '--checkpoint-file',
            '--ack-output',
          ].contains(flag) ||
          values.containsKey(flag) ||
          index + 1 >= arguments.length) {
        throw const _Failure('invalid-options');
      }
      final value = arguments[++index];
      if (value.isEmpty || value.startsWith('--')) {
        throw const _Failure('missing-option-value');
      }
      values[flag] = value;
    }
    if (values['--vm-uri-file'] == null || values['--output'] == null) {
      throw const _Failure('uri-file-and-output-required');
    }
    if (values.containsKey('--checkpoint-file') !=
        values.containsKey('--ack-output')) {
      throw const _Failure('checkpoint-and-ack-must-be-paired');
    }
    return _Options(
      File(values['--vm-uri-file']!),
      File(values['--output']!),
      values['--isolate-id'],
      requestGc,
      values['--checkpoint-file'] == null
          ? null
          : File(values['--checkpoint-file']!),
      values['--ack-output'] == null ? null : File(values['--ack-output']!),
    );
  }
}

class _Checkpoint {
  const _Checkpoint(
    this.runToken,
    this.round,
    this.pid,
    this.readyEpochMs,
    this.expiresEpochMs,
  );
  final String runToken;
  final int round;
  final int pid;
  final int readyEpochMs;
  final int expiresEpochMs;

  void requireLive() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now < readyEpochMs || now >= expiresEpochMs) {
      throw const _Failure('checkpoint-expired-or-clock-mismatch');
    }
  }

  Map<String, Object> toJson() => {
    'schemaVersion': 1,
    'runToken': runToken,
    'round': round,
    'pid': pid,
    'readyEpochMs': readyEpochMs,
    'expiresEpochMs': expiresEpochMs,
  };

  static Future<_Checkpoint> read(File file) async {
    if (!await file.exists() || await file.length() > 4096) {
      throw const _Failure('checkpoint-file-missing-or-too-large');
    }
    final value = jsonDecode(await file.readAsString());
    if (value is! Map<String, dynamic> ||
        value['schemaVersion'] != 1 ||
        value['state'] != 'waiting-for-dart' ||
        value['runToken'] is! String ||
        !RegExp(
          r'^[a-zA-Z0-9-]{1,80}$',
        ).hasMatch(value['runToken'] as String) ||
        ![5, 20].contains(value['round']) ||
        value['pid'] is! int ||
        value['pid'] <= 0 ||
        value['readyEpochMs'] is! int ||
        value['expiresEpochMs'] is! int) {
      throw const _Failure('invalid-checkpoint');
    }
    final point = _Checkpoint(
      value['runToken'] as String,
      value['round'] as int,
      value['pid'] as int,
      value['readyEpochMs'] as int,
      value['expiresEpochMs'] as int,
    );
    if (point.expiresEpochMs - point.readyEpochMs != 180000) {
      throw const _Failure('invalid-checkpoint-window');
    }
    point.requireLive();
    return point;
  }
}

Future<Uri> _localWebSocketUri(File file) async {
  if (!await file.exists() || await file.length() > 65536) {
    throw const _Failure('uri-file-missing-or-too-large');
  }
  // A private text file may contain one URI or log lines repeating that URI.
  // Never retain/log its text, path/query auth token, or a connection exception.
  final text = await file.readAsString();
  final matches = RegExp(
    r'''(?:https?|wss?)://[^\s"'<>]+''',
  ).allMatches(text).map((match) => match.group(0)!).toSet();
  if (matches.length != 1) {
    throw const _Failure('uri-file-must-identify-one-endpoint');
  }
  final uri = Uri.tryParse(matches.single);
  if (uri == null ||
      !['http', 'https', 'ws', 'wss'].contains(uri.scheme) ||
      !['127.0.0.1', 'localhost', '::1'].contains(uri.host) ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment ||
      uri.port <= 0) {
    throw const _Failure('only-loopback-vm-service-endpoints-allowed');
  }
  if (uri.scheme == 'ws' || uri.scheme == 'wss') {
    if (!uri.path.endsWith('/ws')) {
      throw const _Failure('websocket-endpoint-must-end-in-ws');
    }
    return uri;
  }
  return uri.replace(
    scheme: uri.scheme == 'https' ? 'wss' : 'ws',
    path: '${uri.path.endsWith('/') ? uri.path : '${uri.path}/'}ws',
  );
}

Map<String, Object?> _identity(Isolate isolate) => {
  'id': isolate.id,
  'name': isolate.name,
  'isSystemIsolate': isolate.isSystemIsolate,
  'runnable': isolate.runnable,
  'isolateGroupId': isolate.isolateGroupId,
  'rootLibrary': {
    'id': isolate.rootLib?.id,
    'name': isolate.rootLib?.name,
    'uri': isolate.rootLib?.uri,
  },
};

bool _userRunnable(Isolate isolate) =>
    isolate.isSystemIsolate == false &&
    isolate.runnable == true &&
    isolate.id != null &&
    (isolate.rootLib?.uri?.isNotEmpty ?? false);

bool _flutterMain(Isolate isolate) =>
    _userRunnable(isolate) &&
    isolate.name == 'main' &&
    ((isolate.extensionRPCs?.any((name) => name.startsWith('ext.flutter.')) ??
            false) ||
        (isolate.libraries?.any(
              (library) => library.uri?.startsWith('package:flutter/') ?? false,
            ) ??
            false));

Future<Isolate> _selectIsolate(
  VmService service,
  String? requested,
  Map<String, Object?> report,
  int? expectedPid,
) async {
  final vm = await service.getVM().timeout(_rpcTimeout);
  report['vm'] = {
    'pid': vm.pid,
    'version': vm.version,
    'startTime': vm.startTime,
  };
  if (expectedPid != null && vm.pid != expectedPid) {
    throw const _Failure('checkpoint-app-pid-does-not-match-vm');
  }
  final isolates = <Isolate>[];
  for (final reference in vm.isolates ?? <IsolateRef>[]) {
    if (reference.isSystemIsolate != false || reference.id == null) continue;
    if (requested != null && reference.id != requested) continue;
    try {
      final isolate = await service
          .getIsolate(reference.id!)
          .timeout(_rpcTimeout);
      if (_userRunnable(isolate)) isolates.add(isolate);
    } on SentinelException {
      // A naturally exited isolate is not a valid measurement target.
    }
  }
  report['runnableUserIsolates'] = isolates.map(_identity).toList();
  final candidates = requested == null
      ? isolates.where(_flutterMain).toList()
      : isolates;
  if (candidates.length != 1) {
    throw _Failure(
      requested == null
          ? 'specify-isolate-id-no-unique-flutter-main'
          : 'requested-isolate-missing-system-or-not-runnable',
    );
  }
  return candidates.single;
}

Future<Map<String, Object?>> _memory(VmService service, String id) async {
  final started = DateTime.now().toUtc().toIso8601String();
  final memory = await service.getMemoryUsage(id).timeout(_rpcTimeout);
  int? valid(int? bytes) => bytes != null && bytes >= 0 ? bytes : null;
  return {
    'startedAtUtc': started,
    'finishedAtUtc': DateTime.now().toUtc().toIso8601String(),
    'unit': 'bytes',
    'heapUsage': valid(memory.heapUsage),
    'heapCapacity': valid(memory.heapCapacity),
    'externalUsage': valid(memory.externalUsage),
  };
}

String _errorCode(Object error) {
  if (error is _Failure) return error.code;
  if (error is TimeoutException) return 'timeout';
  if (error is SentinelException) return 'isolate-exited';
  if (error is RPCError) return 'vm-rpc-error-${error.code}';
  if (error is FileSystemException) return 'local-file-error';
  if (error is SocketException || error is WebSocketException) {
    return 'local-vm-connection-error';
  }
  return 'collection-error';
}

Future<void> main(List<String> arguments) async {
  if (arguments.length == 1 && arguments.single == '--help') {
    stdout.writeln(
      'collect_vm_heap.dart --vm-uri-file <local-file> --output <new-json> '
      '[--isolate-id <id>] [--request-gc] [--checkpoint-file <ready-json> --ack-output <new-json>]\n'
      'Default: read-only. Automatic selection requires one runnable Flutter main '
      'isolate. Only loopback endpoints are accepted. Existing output is refused.',
    );
    return;
  }
  File? reservedOutput;
  VmService? service;
  _Checkpoint? checkpoint;
  File? ackOutput;
  String? selectedIsolateId;
  final client = HttpClient()..connectionTimeout = _rpcTimeout;
  final report = <String, Object?>{
    'schemaVersion': 1,
    'startedAtUtc': DateTime.now().toUtc().toIso8601String(),
    'complete': false,
    'scope':
        'Dart isolate heap only; not Ark/ART, process PSS or all native/GPU memory.',
    'endpointRecorded': false,
    'gcOptionEnabled': false,
    'gcRequested': false,
    'gcObserved': false,
    'gcEvidence': 'not-requested',
    'limitations': [
      'Public getAllocationProfile(gc:true) attempts GC; it does not guarantee GC.',
      'Observed means dateLastServiceGC increased; another client may also request GC.',
      'externalUsage contains only external memory registered with the Dart VM.',
      'This CLI does not start, resume or forward. Optional checkpoint acknowledgement is transferred by the operator.',
    ],
  };
  try {
    final options = _Options.parse(arguments);
    if (options.checkpointFile != null) {
      checkpoint = await _Checkpoint.read(options.checkpointFile!);
      ackOutput = options.ackOutput!;
      if (await FileSystemEntity.type(ackOutput.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw const _Failure('ack-output-already-exists');
      }
      if (ackOutput.absolute.path == options.output.absolute.path) {
        throw const _Failure('ack-and-evidence-paths-must-differ');
      }
      report['checkpoint'] = checkpoint.toJson();
    }
    final uri = await _localWebSocketUri(options.uriFile);
    // Reserve before connecting or requesting GC. A failure leaves evidence,
    // never truncates an earlier run, and never silently reuses its path.
    await options.output.create(exclusive: true);
    reservedOutput = options.output;
    report['gcOptionEnabled'] = options.requestGc;
    report['isolateSelection'] = options.isolateId == null
        ? 'unique-flutter-main'
        : 'explicit-id';
    final socket = await WebSocket.connect(
      uri.toString(),
      customClient: client,
    ).timeout(_rpcTimeout);
    // Suppress transport error text (it may contain the authenticated URL).
    // The stream then closes; pending RPCs fail with sanitized codes below.
    service = VmService(
      socket.handleError((Object _) {}),
      socket.add,
      disposeHandler: () => socket.close(),
    );
    final isolate = await _selectIsolate(
      service,
      options.isolateId,
      report,
      checkpoint?.pid,
    );
    final id = isolate.id!;
    selectedIsolateId = id;
    report['isolate'] = _identity(isolate);
    report['before'] = await _memory(service, id);
    final beforeProfile = await service
        .getAllocationProfile(id)
        .timeout(_rpcTimeout);
    report['dateLastServiceGCBefore'] = beforeProfile.dateLastServiceGC;
    report['gcRequestStartedAtUtc'] = options.requestGc
        ? DateTime.now().toUtc().toIso8601String()
        : null;
    report['gcRequested'] = options.requestGc;
    if (options.requestGc) report['gcEvidence'] = 'requested-response-pending';
    final afterProfile = await service
        .getAllocationProfile(id, gc: options.requestGc ? true : null)
        .timeout(_rpcTimeout);
    report['gcRequestFinishedAtUtc'] = options.requestGc
        ? DateTime.now().toUtc().toIso8601String()
        : null;
    report['dateLastServiceGCAfter'] = afterProfile.dateLastServiceGC;
    final beforeGc = beforeProfile.dateLastServiceGC;
    final afterGc = afterProfile.dateLastServiceGC;
    final timestampsKnown =
        beforeGc != null && afterGc != null && beforeGc >= 0 && afterGc >= 0;
    final observed = options.requestGc && timestampsKnown && afterGc > beforeGc;
    report['gcObserved'] = observed;
    report['gcEvidence'] = !options.requestGc
        ? 'not-requested'
        : !timestampsKnown
        ? 'timestamp-unavailable'
        : observed
        ? 'dateLastServiceGC-increased'
        : 'no-increasing-dateLastServiceGC';
    report['after'] = await _memory(service, id);
    for (final phase in ['before', 'after']) {
      final memory = report[phase] as Map<String, Object?>;
      if (memory['heapUsage'] == null ||
          memory['heapCapacity'] == null ||
          memory['externalUsage'] == null) {
        throw const _Failure('incomplete-heap-values');
      }
    }
    checkpoint?.requireLive();
    report['complete'] = true;
  } catch (error) {
    final code = _errorCode(error);
    report['errorCode'] = code;
    stderr.writeln(
      'Dart heap collection failed: $code. URI and exception details suppressed.',
    );
    exitCode = 1;
  } finally {
    try {
      await service?.dispose().timeout(_rpcTimeout);
    } catch (_) {
      report['disconnectError'] = true;
    }
    client.close(force: true);
    report['finishedAtUtc'] = DateTime.now().toUtc().toIso8601String();
    if (reservedOutput != null) {
      try {
        final serialized =
            '${const JsonEncoder.withIndent('  ').convert(report)}\n';
        await reservedOutput.writeAsString(serialized, flush: true);
        if (report['complete'] == true &&
            checkpoint != null &&
            ackOutput != null) {
          checkpoint.requireLive();
          final ack = <String, Object?>{
            'schemaVersion': 1,
            'runToken': checkpoint.runToken,
            'round': checkpoint.round,
            'pid': checkpoint.pid,
            'status': 'dart-heap-collected',
            'evidenceSha256': sha256
                .convert(utf8.encode(serialized))
                .toString(),
            'isolateId': selectedIsolateId,
            'gcRequested': report['gcRequested'],
            'gcObserved': report['gcObserved'],
          };
          await ackOutput.create(exclusive: true);
          await ackOutput.writeAsString('${jsonEncode(ack)}\n', flush: true);
          stdout.writeln(
            'Matched checkpoint acknowledgement written; transfer it to the held test checkpoint.',
          );
        }
        stdout.writeln(
          'Dart heap evidence written. complete=${report['complete']}, gcObserved=${report['gcObserved']}',
        );
      } catch (error) {
        stderr.writeln(
          'Evidence or acknowledgement write failed: ${_errorCode(error)}. Existing output was not reused.',
        );
        exitCode = 1;
      }
    }
  }
}
