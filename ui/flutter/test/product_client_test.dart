import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flynes_ui/native_client/product_client.dart';

ProductMap reply(MethodCall call, [ProductMap body = const {}]) {
  final arguments = Map<String, Object?>.from(call.arguments as Map);
  return {
    'requestId': arguments['requestId'],
    'hostGeneration': 4,
    'instanceId': 'app-1',
    ...body,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flynes/product.v1');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late ChannelProductClient client;
  setUp(() => client = ChannelProductClient());
  tearDown(() {
    client.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });
  test(
    'presentation context acquires a lease without catalog bootstrap',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => reply(call, {
          'context': {'route': 'settings', 'presentationToken': 'token-4'},
        }),
      );
      final context = await client.call('presentationContext');
      expect((context['context'] as Map)['presentationToken'], 'token-4');
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect((call.arguments as Map)['hostGeneration'], 4);
        return reply(call, {'accepted': true});
      });
      await client.call('presentationReady', {
        'token': 'token-4',
        'frameNumber': 1,
      });
    },
  );

  test(
    'new host event invalidates pending replies and notifies route owner',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => reply(call, {'protocolVersion': 1}),
      );
      await client.bootstrap();
      final seen = <ProductMap>[];
      final subscription = client.events.listen(seen.add);
      await messenger.handlePlatformMessage(
        'flynes/product.v1',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('contextChanged', {
            'instanceId': 'app-1',
            'hostGeneration': 5,
            'context': {'route': 'settings'},
          }),
        ),
        (_) {},
      );
      await Future<void>.delayed(Duration.zero);
      expect(seen.length, 1);
      expect(seen.single['event'], 'contextChanged');
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect((call.arguments as Map)['hostGeneration'], 5);
        return reply(call, {'hostGeneration': 5});
      });
      await client.call('settings');
      await subscription.cancel();
    },
  );

  test('late bootstrap cannot replace the newer host lease', () async {
    final old = Completer<ProductMap>();
    var count = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'bootstrap' && ++count == 1) return old.future;
      return reply(call, {'protocolVersion': 1, 'hostGeneration': 5});
    });
    final first = client.bootstrap();
    await Future<void>.delayed(Duration.zero);
    await client.bootstrap();
    old.complete({
      'requestId': 1,
      'hostGeneration': 4,
      'instanceId': 'app-1',
      'protocolVersion': 1,
    });
    await expectLater(
      first,
      throwsA(
        isA<ProductFailure>().having((e) => e.code, 'code', 'stale_response'),
      ),
    );
    await client.call('settings');
  });

  test(
    'bootstrap negotiates protocol and stamps subsequent requests',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        final args = call.arguments as Map;
        expect(args['requestId'], isA<int>());
        expect(args['hostGeneration'], call.method == 'bootstrap' ? 0 : 4);
        return reply(call, {'protocolVersion': 1});
      });
      await client.bootstrap();
      await client.call('settings');
    },
  );

  test('an unsupported protocol cannot masquerade as product v1', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => reply(call, {'protocolVersion': 2}),
    );
    await expectLater(
      client.bootstrap(),
      throwsA(
        isA<ProductFailure>().having(
          (e) => e.code,
          'code',
          'protocol_mismatch',
        ),
      ),
    );
  });

  test(
    'a stale response is rejected even when its item ID still matches',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => reply(call, {
          'protocolVersion': 1,
          if (call.method != 'bootstrap') 'hostGeneration': 3,
        }),
      );
      await client.bootstrap();
      await expectLater(
        client.call('catalogItem', {'canonicalId': 'one'}),
        throwsA(
          isA<ProductFailure>().having((e) => e.code, 'code', 'stale_response'),
        ),
      );
    },
  );

  test(
    'disposing an observation rejects late replies without closing owners',
    () async {
      final pending = Completer<Object?>();
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'bootstrap') {
          return reply(call, {'protocolVersion': 1});
        }
        if (call.method == 'settings') return pending.future;
        return reply(call);
      });
      await client.bootstrap();
      final future = client.call('settings');
      await Future<void>.delayed(Duration.zero);
      client.dispose();
      pending.complete({
        'requestId': 2,
        'hostGeneration': 4,
        'instanceId': 'app-1',
      });
      await expectLater(future, throwsA(isA<ProductFailure>()));
      expect(calls, isNot(contains('close')));
      expect(calls, isNot(contains('cancelScan')));
    },
  );
}
