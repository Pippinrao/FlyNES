import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flynes_ui/native_client/foundation_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flynes/foundation');
  const client = ChannelFoundationClient();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('invalid identity never becomes a selectable catalog item', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        'generation': 1,
        'games': [
          {
            'canonicalId': '',
            'titleEn': 'Bad',
            'titleZhHans': '',
            'available': true,
          },
        ],
      },
    );
    await expectLater(client.catalogSnapshot(), throwsFormatException);
  });

  test('duplicate canonical IDs are rejected instead of guessed', () async {
    final row = {
      'canonicalId': 'a',
      'titleEn': 'A',
      'titleZhHans': '甲',
      'available': true,
    };
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        'generation': 8,
        'games': [row, row],
      },
    );
    await expectLater(client.catalogSnapshot(), throwsFormatException);
  });

  test('played metadata cannot imply resume capability', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => {'lastPlayed': 5});
    await expectLater(client.resumeCapability('a'), throwsFormatException);
  });

  test(
    'launch crosses only canonical ID and waits for native return',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'launch');
        expect(call.arguments, {'canonicalId': 'game:a'});
        return {'status': 'returned'};
      });
      expect((await client.launch('game:a')).status, LaunchStatus.returned);
    },
  );

  test('unknown native pages do not cross the host boundary', () async {
    var called = false;
    messenger.setMockMethodCallHandler(channel, (_) async {
      called = true;
      return null;
    });
    await expectLater(client.openNative('database'), throwsArgumentError);
    expect(called, isFalse);
  });
}
