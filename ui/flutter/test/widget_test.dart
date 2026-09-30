import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flynes_ui/main.dart' as entry;

void main() {
  testWidgets('normal entry uses product hall and honest unavailable state', (
    tester,
  ) async {
    tester.platformDispatcher.localeTestValue = const Locale('zh', 'CN');
    tester.platformDispatcher.localesTestValue = const [Locale('zh', 'CN')];
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    const channel = MethodChannel('flynes/product.v1');
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

    expect(find.text('全部'), findsOneWidget);
    final context = tester.element(find.byType(Scaffold));
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(Theme.of(context).scaffoldBackgroundColor, const Color(0xFF121316));
    expect(find.text('操作未能完成，请重试。'), findsOneWidget);
    expect(find.byTooltip('设置'), findsOneWidget);
    expect(find.text('Flutter 迁移基础工程'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
