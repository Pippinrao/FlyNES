import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flynes_ui/main.dart' as entry;

void main() {
  testWidgets('bootstrap is usable without native services', (tester) async {
    entry.main();
    await tester.pumpAndSettle();

    expect(find.text('FlyNES'), findsOneWidget);
    expect(find.text('Flutter 迁移基础工程'), findsOneWidget);
    expect(find.text('原生服务尚未接入'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
