import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flynes_ui/design_system/app_theme.dart';
import 'package:flynes_ui/features/product/product_licenses.dart';
import 'package:flynes_ui/native_client/product_client.dart';

class LicenseClient implements ProductClient {
  final calls = <String>[];
  Completer<ProductMap>? pending;
  final pendingBodies = <String, Completer<ProductMap>>{};
  bool longBodies = false;
  bool listFails = false;
  int extraItems = 0;
  @override
  Future<ProductMap> bootstrap() async => {};
  @override
  Future<ProductMap> call(String method, [ProductMap args = const {}]) async {
    calls.add(method);
    if (method == 'licenses') {
      if (listFails) throw const ProductFailure('operation_failed');
      return {
        'items': [
          {
            'id': 'a',
            'title': 'Component A',
            'sourceUrl': 'https://example.org/a',
          },
          {'id': 'b', 'title': 'Component B', 'sourceUrl': ''},
          for (var index = 0; index < extraItems; index++)
            {
              'id': 'extra-$index',
              'title': 'Component $index',
              'sourceUrl': '',
            },
        ],
      };
    }
    if (method == 'licenseText') {
      if (pendingBodies.containsKey(args['id'])) {
        return pendingBodies[args['id']]!.future;
      }
      return args['id'] == 'a' && pending != null
          ? pending!.future
          : {
              'text':
                  'License ${args['id']}\n${'Permission to use this component.\n' * (longBodies ? 100 : 1)}',
            };
    }
    return {};
  }

  @override
  void dispose() {}
}

void main() {
  late LicenseClient client;
  setUp(() => client = LicenseClient());
  Future<void> show(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(960, 540));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: ProductLicenses(client: client, locale: 'en'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
  }

  testWidgets(
    'U20 license body is Flutter content and copy uses platform adapter',
    (tester) async {
      await show(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('License a'), findsOneWidget);
      await tester.tap(find.byTooltip('Copy license'));
      await tester.pumpAndSettle();
      expect(client.calls, contains('copyText'));
      expect(find.text('License copied'), findsOneWidget);
      expect(
        MediaQuery.accessibleNavigationOf(
          tester.element(find.text('License copied')),
        ),
        isFalse,
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      await tester.pump();
      final exitFade = tester
          .widgetList<FadeTransition>(
            find.ancestor(
              of: find.text('License copied'),
              matching: find.byType(FadeTransition),
            ),
          )
          .first;
      expect(exitFade.opacity.value, closeTo(0, .001));
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('License copied'), findsNothing);
      expect(client.calls, isNot(contains('openNative')));
    },
  );
  testWidgets('U20 late body for A cannot replace selected B', (tester) async {
    client.pending = Completer<ProductMap>();
    await show(tester);
    await tester.tap(find.text('Component B'));
    await tester.pump();
    client.pending!.complete({'text': 'Old A body'});
    await tester.pumpAndSettle();
    expect(find.textContaining('License b'), findsOneWidget);
    expect(find.text('Old A body'), findsNothing);
  });
  testWidgets('U20 list failure retries the list before loading any body', (
    tester,
  ) async {
    client.listFails = true;
    await show(tester);
    await tester.pumpAndSettle();
    expect(find.text('Retry').hitTestable(), findsOneWidget);
    expect(
      find.text('This operation could not be completed. Please retry.'),
      findsOneWidget,
    );
    expect(find.textContaining('could not be saved'), findsNothing);
    expect(find.text('Component A'), findsNothing);
    expect(client.calls, ['licenses']);
    client.listFails = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(client.calls, ['licenses', 'licenses', 'licenseText']);
    expect(find.textContaining('License a'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });
  testWidgets('A09 switching back retains loaded license without rereading', (
    tester,
  ) async {
    await show(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Component B'));
    await tester.pumpAndSettle();
    final before = client.calls.where((m) => m == 'licenseText').length;
    client.pending = Completer<ProductMap>();
    await tester.tap(find.text('Component A'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(client.calls.where((m) => m == 'licenseText').length, before);
    expect(find.textContaining('License a'), findsOneWidget);
  });
  testWidgets('U20 short license starts directly below its title', (
    tester,
  ) async {
    await show(tester);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(SelectableText)).dy, lessThan(150));
  });
  testWidgets(
    'A09 uncached license arrival fades for 120ms without moving navigation',
    (tester) async {
      await show(tester);
      await tester.pumpAndSettle();
      final navigation = tester.getRect(find.text('Component A').first);
      final pending = Completer<ProductMap>();
      client.pendingBodies['b'] = pending;
      await tester.tap(find.text('Component B'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      pending.complete({'text': 'New license body'});
      await tester.pump();
      double opacity() => tester
          .widgetList<FadeTransition>(
            find.ancestor(
              of: find.text('New license body'),
              matching: find.byType(FadeTransition),
            ),
          )
          .first
          .opacity
          .value;
      expect(
        opacity(),
        0,
        reason: 'uncached body must enter through the existing switcher',
      );
      await tester.pump(const Duration(milliseconds: 60));
      expect(opacity(), closeTo(.5, .01));
      expect(tester.getRect(find.text('Component A').first), navigation);
      await tester.pump(const Duration(milliseconds: 60));
      expect(opacity(), 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('U20 each license body restores its independent scroll offset', (
    tester,
  ) async {
    client.longBodies = true;
    await show(tester);
    await tester.pumpAndSettle();
    Finder body(String id) => find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value == 'license-$id',
    );
    double offset(String id) =>
        tester.widget<SingleChildScrollView>(body(id)).controller!.offset;
    await tester.drag(body('a'), const Offset(0, -240));
    await tester.pumpAndSettle();
    final a = offset('a');
    expect(a, greaterThan(100));
    await tester.tap(find.text('Component B'));
    await tester.pumpAndSettle();
    await tester.drag(body('b'), const Offset(0, -150));
    await tester.pumpAndSettle();
    final b = offset('b');
    expect(b, greaterThan(50));
    await tester.tap(find.text('Component A'));
    await tester.pumpAndSettle();
    expect(offset('a'), closeTo(a, 1));
    await tester.tap(find.text('Component B'));
    await tester.pumpAndSettle();
    expect(offset('b'), closeTo(b, 1));
  });
  testWidgets(
    'U20 compact license detail Back restores the component list position',
    (tester) async {
      client.extraItems = 30;
      await show(tester);
      await tester.binding.setSurfaceSize(const Size(420, 540));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Component 12'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('Component 12')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      expect(find.text('Component 12').hitTestable(), findsOneWidget);
      final before = tester
          .widget<ListView>(find.byType(ListView))
          .controller!
          .offset;
      expect(before, greaterThan(200));
      await tester.tap(find.text('Component 12'));
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      final restored = tester
          .widget<ListView>(find.byType(ListView))
          .controller!
          .offset;
      expect(restored, closeTo(before, 1));
      expect(find.text('Component 12').hitTestable(), findsOneWidget);
    },
  );
}
