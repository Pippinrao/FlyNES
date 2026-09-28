import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flynes_ui/design_system/app_theme.dart';
import 'package:flynes_ui/features/foundation/foundation_page.dart';
import 'package:flynes_ui/native_client/foundation_client.dart';
import 'package:flynes_ui/native_client/foundation_controller.dart';

class HallClient implements FoundationClient {
  CatalogSnapshot snapshot = CatalogSnapshot(
    generation: 1,
    games: List.generate(
      10,
      (i) => CatalogGame(
        canonicalId: 'test-$i',
        titleEn: 'Test game $i',
        titleZhHans: '测试游戏 $i',
      ),
    ),
  );
  ResumeCapability capability = const ResumeCapability(ResumeState.none);
  Completer<ResumeCapability>? pending;
  Completer<CatalogSnapshot>? pendingCatalog;
  int launches = 0;
  int reads = 0;
  final pages = <String>[];
  bool failCatalog = false;
  bool failResume = false;
  bool failNavigation = false;
  bool failLaunch = false;

  @override
  Future<CatalogSnapshot> catalogSnapshot() async {
    reads++;
    if (failCatalog) throw StateError('Test source unavailable');
    return pendingCatalog == null ? snapshot : pendingCatalog!.future;
  }

  @override
  Future<ResumeCapability> resumeCapability(String canonicalId) async =>
      failResume
      ? throw StateError('Test progress unavailable')
      : pending == null
      ? capability
      : pending!.future;

  @override
  Future<LaunchResult> launch(String canonicalId) async {
    launches++;
    if (failLaunch) throw StateError('Test launch unavailable');
    return const LaunchResult(LaunchStatus.returned);
  }

  @override
  Future<void> openNative(String page) async {
    if (failNavigation) throw StateError('Test page unavailable');
    pages.add(page);
  }
}

Future<void> mount(
  WidgetTester tester,
  HallClient client, {
  double scale = 1,
  Size size = const Size(900, 420),
  EdgeInsets padding = EdgeInsets.zero,
  FoundationController? controller,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.localeTestValue = const Locale('en');
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearLocaleTestValue);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale), padding: padding),
        child: child!,
      ),
      home: controller == null
          ? FoundationPage(client: client)
          : FoundationPage(controller: controller),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('native cover preserves aspect ratio and missing cover keeps title', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('flynes-cover-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final cover = File('${directory.path}/cover.png')
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAADklEQVR4nGP4z8DwH4QBEfcD/ePF9e8AAAAASUVORK5CYII=',
        ),
      );
    const channel = MethodChannel('flynes/foundation');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        'generation': 1,
        'games': [
          {
            'canonicalId': 'cover',
            'titleEn': 'Covered game',
            'titleZhHans': '',
            'available': true,
            'coverPath': cover.path,
          },
          {
            'canonicalId': 'missing',
            'titleEn': 'Missing cover',
            'titleZhHans': '',
            'available': true,
            'coverPath': '${directory.path}/missing.png',
          },
        ],
      },
    );
    final client = HallClient()
      ..snapshot = await const ChannelFoundationClient().catalogSnapshot();
    final controller = FoundationController(client);
    addTearDown(controller.dispose);
    await tester.runAsync(() => mount(tester, client, controller: controller));
    expect(find.byType(Image), findsNWidgets(2));
    for (final image in tester.widgetList<Image>(find.byType(Image))) {
      expect(image.fit, BoxFit.contain);
    }
    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    final context = tester.element(find.byType(FoundationPage));
    final errors = <Object>[];
    await tester.runAsync(
      () => Future.wait(
        images.map(
          (image) => precacheImage(
            image.image,
            context,
            onError: (error, _) => errors.add(error),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(errors, hasLength(1));
    final pixels = tester
        .widgetList<RawImage>(find.byType(RawImage))
        .where((image) => image.image != null)
        .single
        .image!;
    expect(pixels.width, 2);
    expect(pixels.height, 1);
    expect(find.text('Missing cover'), findsWidgets);
    expect(tester.takeException(), isNull);

    // Native save replaces this same path while the native game is open.
    cover.writeAsBytesSync(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAACCAYAAACZgbYnAAAAEElEQVR4nGNg+M/wnwFEAAAR+AP9pRZvpgAAAABJRU5ErkJggg==',
      ),
    );
    client.snapshot = CatalogSnapshot(
      generation: 2,
      games: client.snapshot.games,
    );
    await tester.runAsync(() async {
      await controller.refresh();
      await tester.pump();
      await Future.wait(
        tester
            .widgetList<Image>(find.byType(Image))
            .map(
              (image) =>
                  precacheImage(image.image, context, onError: (_, _) {}),
            ),
      );
    });
    await tester.pumpAndSettle();
    final refreshed = tester
        .widgetList<RawImage>(find.byType(RawImage))
        .where((image) => image.image != null)
        .single
        .image!;
    expect(refreshed.width, 1);
    expect(refreshed.height, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('English unavailable source translates the native reason', (
    tester,
  ) async {
    final client = HallClient()
      ..snapshot = CatalogSnapshot(
        generation: 1,
        games: const [
          CatalogGame(
            canonicalId: 'missing-source',
            titleEn: 'Unavailable game',
            titleZhHans: '失效游戏',
            available: false,
            unavailableReason: '游戏来源不可用',
          ),
        ],
      );
    await mount(tester, client);
    await tester.pumpAndSettle();
    expect(find.text('Game source unavailable'), findsOneWidget);
    expect(find.text('游戏来源不可用'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('primary-play')))
          .onPressed,
      isNull,
    );
    expect(client.launches, 0);
  });

  testWidgets('English unavailable library has one translated state', (
    tester,
  ) async {
    await mount(tester, HallClient()..failCatalog = true);
    await tester.pumpAndSettle();
    expect(find.text('Game library unavailable'), findsOneWidget);
    expect(find.text('游戏库暂时不可用'), findsNothing);
  });

  testWidgets('English page translates generic host failure messages', (
    tester,
  ) async {
    final client = HallClient()..failResume = true;
    await mount(tester, client);
    await tester.pumpAndSettle();
    expect(find.text('Progress unavailable'), findsOneWidget);
    expect(find.text('暂时无法读取进度'), findsNothing);
    client.failResume = false;
    client.failNavigation = true;
    await tester.tap(find.byKey(const ValueKey('native-settings')));
    await tester.pumpAndSettle();
    expect(find.text('Unable to open this page'), findsOneWidget);
    client.failLaunch = true;
    await tester.tap(find.byKey(const ValueKey('game-test-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('primary-play')));
    await tester.pumpAndSettle();
    expect(find.text('Unable to start this game'), findsOneWidget);
  });

  testWidgets('Chinese large text respects a landscape safe area', (
    tester,
  ) async {
    await mount(
      tester,
      HallClient(),
      scale: 2,
      size: const Size(900, 420),
      padding: const EdgeInsets.fromLTRB(44, 0, 44, 21),
    );
    tester.platformDispatcher.localeTestValue = const Locale('zh', 'CN');
    await tester.pumpAndSettle();
    expect(find.text('测试游戏 0'), findsNWidgets(2));
    expect(find.text('开始'), findsOneWidget);
    final play = tester.getRect(find.byKey(const ValueKey('primary-play')));
    final grid = tester.getRect(find.byKey(const ValueKey('game-catalog')));
    expect(play.left, greaterThanOrEqualTo(44));
    expect(play.bottom, lessThanOrEqualTo(399));
    expect(grid.right, lessThanOrEqualTo(856));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Chinese unavailable state announces one clear message', (
    tester,
  ) async {
    final client = HallClient()..failCatalog = true;
    await mount(tester, client);
    tester.platformDispatcher.localeTestValue = const Locale('zh', 'CN');
    await tester.pumpAndSettle();
    expect(find.text('游戏库暂时不可用'), findsOneWidget);
    expect(find.byTooltip('设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('card selection and horizontal drag never launch a game', (
    tester,
  ) async {
    final client = HallClient();
    await mount(tester, client);
    await tester.tap(find.byKey(const ValueKey('game-test-1')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('game-detail')),
        matching: find.text('Test game 1'),
      ),
      findsOneWidget,
    );
    expect(client.launches, 0);
    await tester.drag(
      find.byKey(const ValueKey('game-catalog')),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();
    expect(client.launches, 0);
    await tester.tap(find.byKey(const ValueKey('primary-play')));
    await tester.pumpAndSettle();
    expect(client.launches, 1);
  });

  testWidgets(
    'primary label follows resume capability and querying disables it',
    (tester) async {
      final client = HallClient()..pending = Completer<ResumeCapability>();
      await mount(tester, client);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('primary-play')))
            .onPressed,
        isNull,
      );
      client.pending!.complete(const ResumeCapability(ResumeState.available));
      await tester.pumpAndSettle();
      expect(find.text('Continue'), findsOneWidget);
      client.pending = null;
      client.capability = const ResumeCapability(ResumeState.none);
      await tester.tap(find.byKey(const ValueKey('game-test-1')));
      await tester.pumpAndSettle();
      expect(find.text('Start'), findsOneWidget);
      client.capability = const ResumeCapability(
        ResumeState.unavailable,
        reason: 'Progress unavailable',
      );
      await tester.tap(find.byKey(const ValueKey('game-test-0')));
      await tester.pumpAndSettle();
      expect(find.text('Progress unavailable'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('primary-play')))
            .onPressed,
        isNull,
      );
      expect(find.text('Restart'), findsNothing);
      expect(find.text('History'), findsNothing);
    },
  );

  testWidgets('short landscape at 200 percent has one row without overflow', (
    tester,
  ) async {
    final client = HallClient();
    await mount(tester, client, scale: 2, size: const Size(640, 320));
    await tester.pumpAndSettle();
    final grid = tester.widget<GridView>(
      find.byKey(const ValueKey('game-catalog')),
    );
    expect(
      (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      1,
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const ValueKey('primary-play'))).height,
      88,
    );
  });

  testWidgets(
    'normal landscape has two rows and native navigation touch targets',
    (tester) async {
      final client = HallClient();
      await mount(tester, client);
      await tester.pumpAndSettle();
      final grid = tester.widget<GridView>(
        find.byKey(const ValueKey('game-catalog')),
      );
      expect(
        (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        2,
      );
      for (final page in ['settings', 'sources', 'nearby']) {
        final button = find.byKey(ValueKey('native-$page'));
        expect(tester.getSize(button).shortestSide, greaterThanOrEqualTo(48));
        await tester.tap(button);
        await tester.pumpAndSettle();
      }
      expect(client.pages, ['settings', 'sources', 'nearby']);
    },
  );

  testWidgets(
    'loading, empty library and late completion after destroy are safe',
    (tester) async {
      final client = HallClient()
        ..pendingCatalog = Completer<CatalogSnapshot>();
      await mount(tester, client);
      expect(find.text('Loading games…'), findsOneWidget);
      client.pendingCatalog!.complete(
        CatalogSnapshot(generation: 1, games: []),
      );
      await tester.pumpAndSettle();
      expect(find.text('No games yet'), findsOneWidget);
      client.pendingCatalog = null;
      client.pending = Completer<ResumeCapability>();
      await tester.pumpWidget(const SizedBox());
      await mount(tester, client);
      await tester.pumpWidget(const SizedBox());
      client.pending!.complete(const ResumeCapability(ResumeState.available));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('injected controller belongs to caller after page removal', (
    tester,
  ) async {
    final client = HallClient();
    final controller = FoundationController(client);
    await mount(tester, client, controller: controller);
    await tester.pumpWidget(const SizedBox());
    await controller.refresh();
    expect(controller.selected, isNotNull);
    controller.dispose();
  });
}
