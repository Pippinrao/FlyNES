import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flynes_ui/main.dart' as entry;

void main() {
  testWidgets(
    'foundation uses approved dark visual and honest unavailable state',
    (tester) async {
      tester.platformDispatcher.localeTestValue = const Locale('zh', 'CN');
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      const channel = MethodChannel('flynes/foundation');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => throw MissingPluginException(),
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      entry.main();
      await tester.pumpAndSettle();

      expect(find.text('FlyNES'), findsOneWidget);
      final context = tester.element(find.byType(Scaffold));
      expect(Theme.of(context).brightness, Brightness.dark);
      expect(
        Theme.of(context).scaffoldBackgroundColor,
        const Color(0xFF121316),
      );
      expect(find.text('游戏库暂时不可用'), findsOneWidget);
      expect(find.byKey(const ValueKey('native-settings')), findsOneWidget);
      expect(find.text('Flutter 迁移基础工程'), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
