import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flynes_ui/features/foundation/texture_probe_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flynes/foundation_texture');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  testWidgets(
    'late attachment from disposed page cannot detach its replacement',
    (tester) async {
      final first = Completer<int>();
      Object? currentOwner;
      var attachments = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        final args = call.arguments as Map?;
        if (call.method == 'attach') {
          currentOwner = args?['owner'];
          attachments++;
          return attachments == 1 ? first.future : 43;
        }
        if (call.method == 'detach' && currentOwner == args?['owner']) {
          currentOwner = null;
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await tester.pumpWidget(
        const MaterialApp(home: TextureProbePage(key: ValueKey('old'))),
      );
      await tester.pump();
      await tester.pumpWidget(
        const MaterialApp(home: TextureProbePage(key: ValueKey('new'))),
      );
      await tester.pumpAndSettle();
      final newOwner = currentOwner;
      expect(newOwner, isNotNull);
      first.complete(42);
      await tester.pumpAndSettle();
      expect(currentOwner, newOwner);
      expect(tester.widget<Texture>(find.byType(Texture)).textureId, 43);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
  testWidgets('texture lifecycle and simultaneous input cancel stay native', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'attach') return 42;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(const MaterialApp(home: TextureProbePage()));
    await tester.pumpAndSettle();
    expect(tester.widget<Texture>(find.byType(Texture)).textureId, 42);
    final a = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('pad-A'))),
      pointer: 1,
    );
    final b = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('pad-B'))),
      pointer: 2,
    );
    await tester.pump();
    expect(
      calls.where((call) => call.method == 'input').last.arguments['buttons'],
      3,
    );
    await a.cancel();
    await tester.pump();
    expect(
      calls.where((call) => call.method == 'input').last.arguments['buttons'],
      2,
    );
    await b.up();
    await tester.pump();
    expect(
      calls.where((call) => call.method == 'input').last.arguments['buttons'],
      0,
    );
    for (var i = 0; i < 20; i++) {
      await tester.tap(find.byKey(const ValueKey('texture-toggle')));
      await tester.pumpAndSettle();
      expect(find.byType(Texture), findsNothing);
      await tester.tap(find.byKey(const ValueKey('texture-toggle')));
      await tester.pumpAndSettle();
      expect(find.byType(Texture), findsOneWidget);
    }
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(
      calls.where((call) => call.method == 'active').last.arguments['active'],
      false,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(
      calls.where((call) => call.method == 'active').last.arguments['active'],
      true,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(calls.where((call) => call.method == 'detach'), hasLength(21));
    expect(calls.any((call) => call.method == 'close'), isFalse);
  });
}
