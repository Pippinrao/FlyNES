// Offline protocol fixture: this server is not a Dart VM Service.
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final cli = arguments[0];
  final packages = arguments[1];
  final root = Directory(arguments[2]);
  final checkpoint = arguments[3] == 'checkpoint';
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var memoryCall = 0;
  var damagedCall = 0;
  var damagedField = '';
  Object? damagedValue;
  server.listen((request) async {
    final socket = await WebSocketTransformer.upgrade(request);
    socket.listen((message) {
      final rpc = jsonDecode(message as String) as Map<String, dynamic>;
      Map<String, Object?> result;
      switch (rpc['method']) {
        case 'getVM':
          result = {
            'type': 'VM',
            'pid': 42,
            'isolates': [
              {
                'type': '@Isolate',
                'id': 'isolates/1',
                'name': 'main',
                'isSystemIsolate': false,
              },
            ],
          };
        case 'getIsolate':
          result = {
            'type': 'Isolate',
            'id': 'isolates/1',
            'name': 'main',
            'isSystemIsolate': false,
            'runnable': true,
            'rootLib': {
              'type': '@Library',
              'id': 'libraries/1',
              'uri': 'package:fixture/main.dart',
            },
            'extensionRPCs': ['ext.flutter.fixture'],
          };
        case 'getMemoryUsage':
          result = {
            'type': 'MemoryUsage',
            'heapUsage': 10,
            'heapCapacity': 20,
            'externalUsage': 0,
          };
          if (memoryCall++ == damagedCall) {
            if (damagedValue == null) {
              result.remove(damagedField);
            } else {
              result[damagedField] = damagedValue;
            }
          }
        case 'getAllocationProfile':
          result = {
            'type': 'AllocationProfile',
            'dateLastServiceGC': '100',
            'members': [],
          };
        default:
          throw StateError('Unexpected fixture RPC');
      }
      socket.add(
        jsonEncode({'jsonrpc': '2.0', 'id': rpc['id'], 'result': result}),
      );
    });
  });
  try {
    final uriFile = File('${root.path}/private.txt');
    await uriFile.writeAsString(
      'http://127.0.0.1:${server.port}/DO_NOT_PRINT_AUTH_TOKEN/',
    );
    var index = 0;
    for (final phase in [0, 1]) {
      for (final field in ['heapUsage', 'heapCapacity', 'externalUsage']) {
        for (final value in [null, -1]) {
          memoryCall = 0;
          damagedCall = phase;
          damagedField = field;
          damagedValue = value;
          final output = File('${root.path}/evidence-${index++}.json');
          final ack = File('${output.path}.ack');
          final args = [
            '--packages=$packages',
            cli,
            '--vm-uri-file',
            uriFile.path,
            '--output',
            output.path,
          ];
          if (checkpoint) {
            final ready = File('${output.path}.ready');
            final now = DateTime.now().millisecondsSinceEpoch;
            await ready.writeAsString(
              jsonEncode({
                'schemaVersion': 1,
                'state': 'waiting-for-dart',
                'runToken': 'fixture-42',
                'round': 5,
                'pid': 42,
                'readyEpochMs': now,
                'expiresEpochMs': now + 180000,
              }),
            );
            args.addAll([
              '--checkpoint-file',
              ready.path,
              '--ack-output',
              ack.path,
            ]);
          }
          final process = await Process.run(Platform.resolvedExecutable, args);
          final evidence =
              jsonDecode(await output.readAsString()) as Map<String, dynamic>;
          final label =
              '${checkpoint ? "checkpoint" : "ordinary"} phase=$phase field=$field value=$value';
          if (evidence['complete'] != false ||
              evidence['errorCode'] != 'incomplete-heap-values' ||
              process.exitCode == 0 ||
              await ack.exists()) {
            throw StateError(
              '$label: expected incomplete JSON/error/nonzero/no ACK; '
              'got complete=${evidence['complete']} error=${evidence['errorCode']} exit=${process.exitCode}',
            );
          }
          if ('${process.stdout}${process.stderr}'.contains(
            'DO_NOT_PRINT_AUTH_TOKEN',
          )) {
            throw StateError('Fixture auth marker leaked');
          }
        }
      }
    }
    stdout.writeln('PASS: 12 invalid heap cases ($checkpoint)');
  } finally {
    await server.close(force: true);
  }
}
