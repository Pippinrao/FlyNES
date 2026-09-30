import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flynes_ui/design_system/product_button.dart';

void main() {
  for (final label in ['Settings', '设置', 'Favorite', '返回']) {
    testWidgets('Icon has native label rather than only tooltip: $label', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      try {
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ProductButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.settings),
                tooltip: label,
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        final data = t.getSemantics(find.byType(IconButton)).getSemanticsData();
        expect(data.label, label);
        expect(find.byTooltip(label), findsOneWidget);
      } finally {
        handle.dispose();
      }
    });
  }
}
