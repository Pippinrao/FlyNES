import 'dart:ui' show Tristate;
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flynes_ui/design_system/app_theme.dart';
import 'package:flynes_ui/design_system/product_strings.dart';
import 'package:flynes_ui/design_system/product_switch.dart';
import 'package:flynes_ui/features/product/product_controller.dart';
import 'package:flynes_ui/features/product/product_hall.dart';
import '../test/product_hall_test.dart' show HallClient;

// Behavioral SDK compatibility checks, independent of golden node IDs/strings.
List<SemanticsNode> nodes(WidgetTester tester) {
  final result = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    result.add(node);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  return result;
}

Rect screenRect(SemanticsNode node) {
  var rect = node.rect;
  SemanticsNode? current = node;
  while (current != null) {
    if (current.transform != null) {
      rect = MatrixUtils.transformRect(current.transform!, rect);
    }
    current = current.parent;
  }
  return rect;
}

void expectBounds(SemanticsNode node, Rect expected, String control) {
  final actual = screenRect(node);
  expect(actual.left, closeTo(expected.left, .01), reason: '$control left');
  expect(actual.top, closeTo(expected.top, .01), reason: '$control top');
  expect(actual.right, closeTo(expected.right, .01), reason: '$control right');
  expect(
    actual.bottom,
    closeTo(expected.bottom, .01),
    reason: '$control bottom',
  );
}

void perform(
  WidgetTester tester,
  SemanticsNode node,
  SemanticsAction action, [
  Object? arguments,
]) => tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
  node.id,
  action,
  arguments,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Same frozen font inputs as the cross-SDK captures under review.
  setUpAll(() async {
    for (final entry in {
      'Roboto': 'Roboto-Regular.ttf',
      'G2CJK': 'NotoSansCJK-Regular.ttc',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      final bytes = File(
        '../../.artifacts/flutter-g2/fonts/${entry.value}',
      ).readAsBytesSync();
      await (FontLoader(
        entry.key,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });
  void semanticTest(String description, WidgetTesterCallback body) {
    testWidgets(description, (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await body(tester);
      } finally {
        handle.dispose();
      }
    });
  }

  late HallClient client;
  late ProductController controller;
  late List<String> destinations;
  setUp(() {
    destinations = [];
    client = HallClient();
    controller = ProductController(client);
    controller.bootstrapData = {'locale': 'system'};
    controller.total = 2;
    controller.windows[0] = [
      for (final id in ['a', 'b'])
        {
          'canonicalId': id,
          'titleEn': 'Game $id',
          'titleZhHans': '游戏$id',
          'available': true,
          'favorite': false,
          'variantCount': 1,
        },
    ];
    controller.selectedId = 'a';
    controller.selected = controller.windows[0]!.first;
    controller.resumeState = 'none';
    client.queryResponse = {
      'catalogGeneration': 1,
      'viewRevision': 1,
      'offset': 0,
      'total': 2,
      'items': controller.windows[0],
      'selectedId': 'a',
    };
  });
  tearDown(() => controller.dispose());

  Future<ProductStrings> show(
    WidgetTester tester,
    double scale, {
    bool keyboard = false,
  }) async {
    const size = Size(800, 360);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark().copyWith(
          textTheme: AppTheme.dark().textTheme.apply(
            fontFamily: 'Roboto',
            fontFamilyFallback: const ['G2CJK'],
          ),
        ),
        home: Builder(
          builder: (context) => Localizations.override(
            context: context,
            locale: const Locale('en', 'XA'),
            child: MediaQuery(
              data: MediaQueryData(
                size: size,
                devicePixelRatio: 1,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                viewPadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                viewInsets: EdgeInsets.only(bottom: keyboard ? 180 : 0),
                textScaler: TextScaler.linear(scale),
              ),
              child: ProductHall(
                controller: controller,
                onSources: () => destinations.add('sources'),
                onSettings: () => destinations.add('settings'),
                onNearby: () => destinations.add('nearby'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    return ProductStrings(tester.element(find.byType(ProductHall)), 'system');
  }

  SemanticsNode action(WidgetTester tester, String label) =>
      nodes(tester).singleWhere(
        (node) =>
            node.getSemanticsData().label == label &&
            node.getSemanticsData().hasAction(SemanticsAction.tap),
      );

  for (final scale in [1.0, 2.0]) {
    semanticTest(
      'en-XA $scale icon and card semantics keep independent targets',
      (tester) async {
        final s = await show(tester, scale);
        final ids = <int>{};
        for (final name in ['Sources', 'Settings', 'Nearby']) {
          final label = s.text(name, '');
          final node = action(tester, label);
          expect(ids.add(node.id), isTrue);
          expectBounds(node, tester.getRect(find.byTooltip(label)), name);
          expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
          perform(tester, node, SemanticsAction.tap);
        }
        expect(destinations, ['sources', 'settings', 'nearby']);
        final card = find.byKey(const ValueKey('game-a'));
        final node = nodes(tester).singleWhere((node) {
          final data = node.getSemanticsData();
          return data.hasAction(SemanticsAction.tap) &&
              data.flagsCollection.isButton &&
              data.label.contains('Game a');
        });
        expect(ids.add(node.id), isTrue);
        expectBounds(
          node,
          tester
              .getRect(card)
              .intersect(
                tester.getRect(find.byKey(const ValueKey('catalog-grid'))),
              ),
          'game card',
        );
        perform(tester, node, SemanticsAction.tap);
        await tester.pumpAndSettle();
        expect(client.calls, contains('catalogItem'));
        expect(controller.selectedId, 'a');
        expect(controller.error, isEmpty);
      },
    );

    semanticTest(
      'en-XA $scale two-player semantic action stays on its switch',
      (tester) async {
        final s = await show(tester, scale);
        final node = nodes(tester).singleWhere(
          (node) =>
              node.getSemanticsData().flagsCollection.isToggled !=
              Tristate.none,
        );
        expectBounds(
          node,
          tester.getRect(find.byType(ProductSwitch)),
          'two-player',
        );
        expect(node.getSemanticsData().label, s.text('Two-player', '双人'));
        perform(tester, node, SemanticsAction.tap);
        await tester.pumpAndSettle();
        expect(client.queryArguments.last['multiplayerOnly'], isTrue);
        expect(controller.error, isEmpty);
      },
    );

    semanticTest('en-XA $scale search semantics edit only the bounded field', (
      tester,
    ) async {
      final s = await show(tester, scale, keyboard: true);
      final search = action(tester, s.text('Search', '搜索'));
      expectBounds(
        search,
        tester.getRect(find.byTooltip(s.text('Search', '搜索'))),
        'search icon',
      );
      perform(tester, search, SemanticsAction.tap);
      await tester.pumpAndSettle();
      final field = nodes(tester).singleWhere(
        (node) => node.getSemanticsData().flagsCollection.isTextField,
      );
      expectBounds(
        field,
        tester.getRect(find.byKey(const ValueKey('search-field'))),
        'search field',
      );
      expect(field.getSemanticsData().label, s.text('Search games', '搜索游戏'));
      expect(
        field.getSemanticsData().hasAction(SemanticsAction.setText),
        isTrue,
      );
      perform(tester, field, SemanticsAction.setText, 'Mario');
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'Mario',
      );
      expect(controller.query, 'Mario');
      final label = s.text('Close search', '关闭搜索');
      final close = action(tester, label);
      expect(close.id, isNot(field.id));
      expectBounds(
        close,
        tester.getRect(find.byTooltip(label)),
        'close search',
      );
      perform(tester, close, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(find.byType(EditableText), findsNothing);
    });
  }
}
