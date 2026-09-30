import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flynes_ui/design_system/app_theme.dart';
import 'package:flynes_ui/design_system/product_button.dart';
import 'package:flynes_ui/features/product/product_controller.dart';
import 'package:flynes_ui/features/product/product_hall.dart';
import 'package:flynes_ui/native_client/product_client.dart';

class HallClient implements ProductClient {
  final calls = <String>[];
  Completer<ProductMap>? detail;
  ProductMap? queryResponse;
  final queryArguments = <ProductMap>[];
  @override
  Future<ProductMap> bootstrap() async => {'locale': 'en'};
  @override
  Future<ProductMap> call(
    String method, [
    ProductMap arguments = const {},
  ]) async {
    calls.add(method);
    if (method == 'catalogQuery' && queryResponse != null) {
      queryArguments.add(Map.of(arguments));
      return queryResponse!;
    }
    if (method == 'catalogItem') {
      if (detail != null) return detail!.future;
      return {
        'canonicalId': arguments['canonicalId'],
        'titleEn': 'Game ${arguments['canonicalId']}',
        'titleZhHans': '游戏',
        'favorite': false,
        'available': true,
        'variantCount': 1,
      };
    }
    return {'state': 'none'};
  }

  @override
  void dispose() {}
}

class NonlinearLargeScaler extends TextScaler {
  const NonlinearLargeScaler();
  @override
  double scale(double fontSize) => fontSize * (fontSize <= 12 ? 2 : 1.75);
  @override
  double get textScaleFactor => 2;
}

void main() {
  late ProductController controller;
  late HallClient client;
  setUp(() {
    client = HallClient();
    controller = ProductController(client);
    controller.total = 2;
    controller.bootstrapData = {'locale': 'en'};
    controller.windows[0] = [
      for (final id in ['a', 'b'])
        {
          'canonicalId': id,
          'titleEn': 'Game $id',
          'titleZhHans': '游戏$id',
          'available': true,
          'favorite': false,
        },
    ];
    controller.selectedId = 'a';
    controller.selected = {...controller.windows[0]!.first, 'variantCount': 1};
    controller.resumeState = 'none';
  });
  tearDown(() => controller.dispose());
  Future<void> show(
    WidgetTester tester, {
    double scale = 1,
    TextScaler? textScaler,
    Size size = const Size(960, 540),
    EdgeInsets viewInsets = EdgeInsets.zero,
    bool reduce = false,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: textScaler ?? TextScaler.linear(scale),
            viewInsets: viewInsets,
            disableAnimations: reduce,
          ),
          child: ProductHall(
            controller: controller,
            onSources: () {},
            onSettings: () {},
            onNearby: () {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('U05 editable search exposes a label to native accessibility', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await show(tester);
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.byType(EditableText)).getSemanticsData().label,
        contains('Search games'),
      );
    } finally {
      semantics.dispose();
    }
  });
  testWidgets(
    'A06 opening search can reverse at midpoint without leaving focus or a late query',
    (tester) async {
      client.queryResponse = {
        'catalogGeneration': 1,
        'viewRevision': 1,
        'offset': 0,
        'total': 2,
        'items': controller.windows[0],
        'selectedId': 'a',
      };
      await show(tester);
      await tester.tap(find.byTooltip('Search'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      await tester.enterText(
        find.byKey(const ValueKey('search-field')),
        'pending',
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(controller.query, '');
      expect(controller.error, isEmpty);
      final queries = client.calls.where((s) => s == 'catalogQuery').length;
      expect(queries, 1);
      expect(client.queryArguments.single['query'], '');
      expect(
        client.queryArguments.any((args) => args['query'] == 'pending'),
        isFalse,
      );
      expect(
        find.byKey(const ValueKey('search-field')).hitTestable(),
        findsNothing,
      );
      await tester.pump(const Duration(milliseconds: 160));
      await tester.pump();
      expect(find.byKey(const ValueKey('search-field')), findsNothing);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(client.calls.where((s) => s == 'catalogQuery').length, queries);
      await tester.pump(const Duration(milliseconds: 200));
      expect(client.calls.where((s) => s == 'catalogQuery').length, queries);
    },
  );
  testWidgets(
    'A03 third selection during detail fade owns actions and ignores a disposed late reply',
    (tester) async {
      controller.total = 3;
      controller.windows[0]!.add({
        'canonicalId': 'c',
        'titleEn': 'Game c',
        'available': true,
      });
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('game-b')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      client.detail = Completer<ProductMap>();
      await tester.tap(find.byKey(const ValueKey('game-c')));
      await tester.pump();
      expect(controller.selectedId, 'c');
      expect(controller.resumeState, 'querying');
      final launch = tester.widget<ProductButton>(
        find.byKey(const ValueKey('launch-button')),
      );
      expect(launch.onPressed, isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      client.detail!.complete({
        'canonicalId': 'c',
        'titleEn': 'Late c',
        'available': true,
      });
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(client.calls, isNot(contains('launch')));
      // Replace only the test-owned disposed controller before the common teardown.
      controller = ProductController(client);
    },
  );
  testWidgets(
    'U02 nonlinear system 200 percent uses large layout and 88px action',
    (tester) async {
      await show(
        tester,
        textScaler: const NonlinearLargeScaler(),
        size: const Size(800, 360),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('launch-button'))).height,
        88,
      );
      expect(find.byKey(const ValueKey('detail-cover')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'U02 all four categories and separate source/settings actions are accessible',
    (tester) async {
      await show(tester);
      for (final title in ['Recent', 'Favorites', 'All', 'Built-in']) {
        expect(find.text(title), findsOneWidget);
      }
      expect(find.byTooltip('Sources'), findsOneWidget);
      expect(find.byTooltip('Settings'), findsOneWidget);
    },
  );
  testWidgets('U02 categories retain independent horizontal anchors', (
    tester,
  ) async {
    controller.windows[0] = [
      for (var i = 0; i < 60; i++)
        {'canonicalId': 'card-$i', 'titleEn': 'Game $i', 'available': true},
    ];
    controller.total = 60;
    await show(tester);
    final grid = find.byKey(const ValueKey('catalog-grid'));
    await tester.drag(grid, const Offset(-900, 0));
    await tester.pumpAndSettle();
    final offset = tester.widget<GridView>(grid).controller!.offset;
    expect(offset, greaterThan(100));
    controller.category = 'favorites';
    controller.notifyListeners();
    await tester.pumpAndSettle();
    expect(tester.widget<GridView>(grid).controller!.offset, 0);
    await tester.drag(grid, const Offset(-300, 0));
    await tester.pumpAndSettle();
    controller.category = 'all';
    controller.notifyListeners();
    await tester.pumpAndSettle();
    expect(
      tester.widget<GridView>(grid).controller!.offset,
      closeTo(offset, 1),
    );
  });
  testWidgets('U06 failed catalog does not assert a verified empty library', (
    tester,
  ) async {
    controller.total = 0;
    controller.windows.clear();
    controller.selected = null;
    controller.error = 'storage_failed';
    await show(tester);
    expect(find.text('Your library is empty'), findsNothing);
    expect(find.text('Manage sources'), findsNothing);
    expect(find.text('Library unavailable'), findsOneWidget);
  });
  testWidgets(
    'U07 narrow summary preserves spacing before two-player control',
    (tester) async {
      await show(tester, size: const Size(600, 540));
      final summary = find.text('2 games · swipe to browse');
      expect(
        tester.getRect(find.text('Two-player')).left -
            tester.getRect(summary).right,
        greaterThanOrEqualTo(8),
      );
    },
  );
  testWidgets(
    'A03 cover changes with the detail fade rather than jumping immediately',
    (tester) async {
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('game-b')));
      await tester.pump();
      final cover = find
          .byWidgetPredicate(
            (widget) =>
                widget is ProductCover && widget.item?['canonicalId'] == 'b',
          )
          .first;
      final fades = find.ancestor(
        of: cover,
        matching: find.byType(FadeTransition),
      );
      expect(fades, findsWidgets);
      expect(tester.widget<FadeTransition>(fades.first).opacity.value, 0);
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        tester.widget<FadeTransition>(fades.first).opacity.value,
        closeTo(.5, .01),
      );
      await tester.pumpAndSettle();
    },
  );
  testWidgets('A05 category results fade for 120 ms without moving the grid', (
    tester,
  ) async {
    await show(tester);
    await tester.pumpAndSettle();
    final grid = find.byKey(const ValueKey('catalog-grid'));
    final before = tester.getRect(grid);
    controller.category = 'favorites';
    controller.notifyListeners();
    await tester.pump();
    final opacity = find
        .ancestor(of: grid, matching: find.byType(Opacity))
        .first;
    expect(tester.widget<Opacity>(opacity).opacity, 0);
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.widget<Opacity>(opacity).opacity, closeTo(.5, .01));
    expect(tester.getRect(grid), before);
    await tester.pumpAndSettle();
  });
  testWidgets(
    'U03 tap selects without starting; library scrolls only horizontally',
    (tester) async {
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('game-b')));
      await tester.pumpAndSettle();
      expect(controller.selectedId, 'b');
      expect(client.calls, isNot(contains('launch')));
      final grid = tester.widget<GridView>(
        find.byKey(const ValueKey('catalog-grid')),
      );
      expect(grid.scrollDirection, Axis.horizontal);
      expect(
        (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        2,
      );
    },
  );
  testWidgets('U04 failed resume capability cannot display Start', (
    tester,
  ) async {
    controller.resumeState = 'unavailable';
    controller.error = 'history_unavailable';
    await show(tester);
    expect(find.text('Start'), findsNothing);
    expect(find.text('Retry'), findsWidgets);
  });
  testWidgets('A06 search reveal animates height and opacity together', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.byTooltip('Search'));
    await tester.pump();
    final search = find.byKey(const ValueKey('search-field'));
    final fade = find.ancestor(
      of: search,
      matching: find.byType(FadeTransition),
    );
    expect(fade, findsWidgets);
    expect(tester.widget<FadeTransition>(fade.first).opacity.value, 0);
    await tester.pump(const Duration(milliseconds: 80));
    expect(
      tester.widget<FadeTransition>(fade.first).opacity.value,
      closeTo(.5, .05),
    );
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.widget<FadeTransition>(fade.first).opacity.value, 1);
    expect(search.hitTestable(), findsOneWidget);
  });
  testWidgets(
    'A17 detail crossfade drops outgoing content on live reduced motion',
    (tester) async {
      controller.selected = {...controller.selected!, 'titleEn': 'Old detail'};
      await show(tester);
      controller.selected = {...controller.selected!, 'titleEn': 'New detail'};
      controller.notifyListeners();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('Old detail'), findsOneWidget);
      await show(tester, reduce: true);
      expect(find.text('Old detail'), findsNothing);
      expect(find.text('New detail'), findsWidgets);
    },
  );
  testWidgets(
    'A17 category indicator settles when reduced motion changes mid-flight',
    (tester) async {
      await show(tester);
      controller.category = 'favorites';
      controller.notifyListeners();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      Color color() =>
          (tester
                      .widgetList<DecoratedBox>(
                        find.ancestor(
                          of: find.text('Favorites'),
                          matching: find.byType(DecoratedBox),
                        ),
                      )
                      .first
                      .decoration
                  as BoxDecoration)
              .color!;
      expect(color(), isNot(AppTheme.accent));
      await show(tester, reduce: true);
      expect(color(), AppTheme.accent);
    },
  );
  testWidgets(
    'A03 pending selection retains painted detail while disabling old actions',
    (tester) async {
      await show(tester);
      client.detail = Completer<ProductMap>();
      await tester.tap(find.byKey(const ValueKey('game-b')));
      await tester.pump(const Duration(milliseconds: 160));
      expect(find.text('Select a game'), findsNothing);
      expect(find.text('Game a'), findsWidgets);
      expect(find.text('Reading…'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('launch-button')));
      expect(client.calls, isNot(contains('launch')));
      client.detail!.complete({
        'canonicalId': 'b',
        'titleEn': 'New detail',
        'available': true,
      });
      await tester.pumpAndSettle();
      expect(find.text('New detail'), findsWidgets);
    },
  );
  testWidgets(
    'U03 details show localized secondary title and unavailable source; large text prioritizes status',
    (tester) async {
      controller.selected = {
        ...controller.selected!,
        'titleZhHans': '中文副标题',
        'available': false,
      };
      await show(tester);
      expect(find.text('中文副标题'), findsOneWidget);
      expect(find.text('Source unavailable'), findsOneWidget);
      await show(tester, scale: 2);
      expect(find.text('中文副标题'), findsNothing);
      expect(find.text('Source unavailable'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'A01 primary press enters in 80 ms and releases in 120 ms without resizing',
    (tester) async {
      await show(tester);
      final button = find.byKey(const ValueKey('launch-button'));
      final size = tester.getSize(button);
      final gesture = await tester.startGesture(tester.getCenter(button));
      await tester.pump(const Duration(milliseconds: 10));
      final materialButton = find.descendant(
        of: button,
        matching: find.byType(FilledButton),
      );
      final pressed = tester.widget<FilledButton>(
        materialButton.evaluate().isEmpty ? button : materialButton,
      );
      expect(
        pressed.style?.animationDuration,
        const Duration(milliseconds: 80),
      );
      await gesture.cancel();
      await tester.pump();
      final released = tester.widget<FilledButton>(
        materialButton.evaluate().isEmpty ? button : materialButton,
      );
      expect(
        released.style?.animationDuration,
        const Duration(milliseconds: 120),
      );
      expect(tester.getSize(button), size);
    },
  );
  testWidgets(
    'A11 filter switch moves from start through middle to end in 150 ms',
    (tester) async {
      await show(tester);
      final thumb = find.byKey(const ValueKey('product-switch-thumb'));
      expect(
        thumb,
        findsOneWidget,
        reason:
            'The shared switch exposes a stable moving thumb for animation geometry.',
      );
      final start = tester.getCenter(thumb);
      controller.multiplayerOnly = true;
      controller.notifyListeners();
      await tester.pump();
      expect(tester.getCenter(thumb), start);
      await tester.pump(const Duration(milliseconds: 75));
      final middle = tester.getCenter(thumb);
      expect(middle.dx, greaterThan(start.dx));
      await tester.pump(const Duration(milliseconds: 75));
      final end = tester.getCenter(thumb);
      expect(end.dx, greaterThan(middle.dx));
      await tester.pump(const Duration(milliseconds: 75));
      expect(tester.getCenter(thumb), end);
    },
  );
  testWidgets(
    'U03 200 percent preserves action and uses one row without overflow',
    (tester) async {
      await show(tester, scale: 2);
      final grid = tester.widget<GridView>(
        find.byKey(const ValueKey('catalog-grid')),
      );
      expect(
        (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        1,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('launch-button'))).height,
        88,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('U03 compact normal-font cards retain covers beside titles', (
    tester,
  ) async {
    await show(tester, size: const Size(850, 392));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('game-a')),
        matching: find.byType(ProductCover),
      ),
      findsOneWidget,
    );
  });
  for (final size in [const Size(360, 640), const Size(600, 320)]) {
    testWidgets('U26 narrow $size at 200 percent remains operable', (
      tester,
    ) async {
      await show(tester, size: size, scale: 2);
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Settings').hitTestable(), findsOneWidget);
      expect(
        find.byKey(const ValueKey('launch-button')).hitTestable(),
        findsOneWidget,
      );
    });
  }
  testWidgets(
    'U05 keyboard leaves search and close operable in short landscape',
    (tester) async {
      await show(
        tester,
        size: const Size(800, 360),
        scale: 2,
        viewInsets: const EdgeInsets.only(bottom: 180),
      );
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('search-field')).hitTestable(),
        findsOneWidget,
      );
      expect(find.byTooltip('Close search').hitTestable(), findsOneWidget);
    },
  );
  for (final size in [
    const Size(800, 360),
    const Size(960, 540),
    const Size(1280, 800),
  ]) {
    for (final locale in ['en', 'zh-CN']) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('U02 matrix $size $locale $scale has accessible geometry', (
          tester,
        ) async {
          controller.bootstrapData = {'locale': locale};
          await show(tester, scale: scale, size: size);
          expect(tester.takeException(), isNull);
          expect(
            find.byKey(const ValueKey('launch-button')).hitTestable(),
            findsOneWidget,
          );
          await tester.tap(find.byTooltip(locale == 'en' ? 'Search' : '搜索'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            find.byKey(const ValueKey('search-field')).hitTestable(),
            findsOneWidget,
          );
        });
      }
    }
  }
}
