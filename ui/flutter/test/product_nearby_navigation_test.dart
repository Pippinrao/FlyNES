import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flynes_ui/app/product_app.dart';
import 'package:flynes_ui/native_client/product_client.dart';
import 'product_app_test.dart' show AppClient;

class NearbyPickerClient extends AppClient {
  @override
  Future<ProductMap> bootstrap() async => {
    ...await super.bootstrap(),
    'context': {'route': 'hall', 'purpose': 'nearby', 'returnToken': 'room'},
  };
}

void main() {
  testWidgets('nearby picker has an explicit return to its existing room', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(960, 540));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = NearbyPickerClient();
    await tester.pumpWidget(ProductApp(client: client));
    await tester.pumpAndSettle();
    expect(find.text('Choose game'), findsOneWidget);
    expect(find.byTooltip('Return to room'), findsOneWidget);
    await tester.tap(find.byTooltip('Return to room'));
    await tester.pumpAndSettle();
    expect(client.calls.where((m) => m == 'closeHost').length, 1);
    expect(client.calls, isNot(contains('openNative')));
    expect(client.calls, isNot(contains('launch')));
  });

  testWidgets('nearby back closes search before returning to room', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(960, 540));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = NearbyPickerClient();
    await tester.pumpWidget(ProductApp(client: client));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(client.calls, isNot(contains('closeHost')));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(client.calls.where((m) => m == 'closeHost').length, 1);
  });

  testWidgets('nearby back dismisses keyboard then search then host', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(960, 540));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.view.resetViewInsets);
    final client = NearbyPickerClient();
    await tester.pumpWidget(ProductApp(client: client));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 160);
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      isTrue,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      isFalse,
    );
    expect(client.calls, isNot(contains('closeHost')));
    tester.view.resetViewInsets();
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(client.calls, isNot(contains('closeHost')));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(client.calls.where((m) => m == 'closeHost').length, 1);
  });
}
