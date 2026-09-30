// Explicit state evidence, never golden acceptance. Uses real Flutter product
// widgets with deterministic service fixtures; no native page is simulated.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flynes_ui/design_system/app_theme.dart';
import 'package:flynes_ui/design_system/product_button.dart';
import 'package:flynes_ui/design_system/product_switch.dart';
import 'package:flynes_ui/features/product/product_controller.dart';
import 'package:flynes_ui/features/product/product_hall.dart';
import 'package:flynes_ui/features/product/product_settings.dart';
import 'package:flynes_ui/features/product/product_sources.dart';
import 'package:flynes_ui/features/product/product_licenses.dart';
import 'package:flynes_ui/native_client/product_client.dart';
import '../test/product_settings_test.dart' show SettingsClient;

class StateClient implements ProductClient {
  final calls = <String>[];
  final arguments = <ProductMap>[];
  Completer<ProductMap>? startup;
  Completer<ProductMap>? head;
  bool startupFails = false;
  bool catalogFails = false;
  bool licenseFails = false;
  String? operationFailure;
  String headState = 'none';
  String purpose = 'single';
  List<ProductMap> games = [
    {
      'canonicalId': 'fixture-a',
      'titleEn': 'Fixture Adventure',
      'titleZhHans': '测试冒险',
      'available': true,
      'favorite': false,
      'variantCount': 2,
      'multiplayerSupported': true,
    },
  ];
  List<ProductMap> sources = [
    {
      'uuid': 'fixture-source',
      'name': 'My game folder',
      'type': 'folder',
      'count': 12,
      'status': 'ready',
      'builtin': false,
      'canReauthorize': false,
      'canCancel': false,
    },
  ];
  @override
  Future<ProductMap> bootstrap() async {
    calls.add('bootstrap');
    if (startupFails) throw const ProductFailure('service_unavailable');
    if (startup != null) return startup!.future;
    return {
      'locale': 'en',
      'context': {'route': 'hall', 'purpose': purpose},
    };
  }

  @override
  Future<ProductMap> call(String method, [ProductMap args = const {}]) async {
    calls.add(method);
    arguments.add(args);
    switch (method) {
      case 'catalogQuery':
        if (catalogFails) throw const ProductFailure('service_unavailable');
        return {
          'catalogGeneration': 1,
          'viewRevision': 1,
          'total': games.length,
          'offset': 0,
          'items': games,
          'selectedId': games.isEmpty ? '' : games.first['canonicalId'],
        };
      case 'catalogItem':
        return games.first;
      case 'resumeCapability':
        if (head != null) return head!.future;
        return {'state': headState, 'reason': 'history_unavailable'};
      case 'sources':
        return {'items': sources};
      case 'scanSource':
        if (operationFailure != null) throw ProductFailure(operationFailure!);
        return {'status': 'started', 'operationId': 'fixture-operation'};
      case 'licenses':
        return {
          'items': [
            {
              'id': 'fixture-license',
              'title': 'Fixture component',
              'sourceUrl': 'https://example.org/license',
            },
          ],
        };
      case 'licenseText':
        if (licenseFails) throw const ProductFailure('service_unavailable');
        return {
          'text': 'Fixture license text. Permission to use this test fixture.',
        };
      case 'pickSource':
        return {'status': 'cancelled'};
      default:
        return {};
    }
  }

  @override
  void dispose() {}
}

class StateCapture {
  final root = Directory('../../.artifacts/flutter-g2/state-actual');
  final manifest = <ProductMap>[];
  final boundary = GlobalKey();
  Size size = const Size(960, 540);
  EdgeInsets safeArea = EdgeInsets.zero;
  double scale = 1;

  Future<void> show(
    WidgetTester tester,
    Widget page, {
    Size surface = const Size(960, 540),
    EdgeInsets safe = EdgeInsets.zero,
    double textScale = 1,
  }) async {
    size = surface;
    safeArea = safe;
    scale = textScale;
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final fonts = AppTheme.dark().textTheme.apply(
      fontFamily: 'Roboto',
      fontFamilyFallback: const ['G2CJK'],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark().copyWith(textTheme: fonts),
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
          data: MediaQueryData(
            size: size,
            devicePixelRatio: 1,
            padding: safeArea,
            viewPadding: safeArea,
            textScaler: TextScaler.linear(scale),
          ),
          child: RepaintBoundary(key: boundary, child: child!),
        ),
        home: page,
      ),
    );
    await settle(tester);
  }

  // Fixed pumps leave application-owned polling/spinners active and observable.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    await tester.pump();
    expect(
      tester.takeException(),
      isNull,
      reason: 'No layout overflow or error',
    );
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    expect(finder.hitTestable(), findsOneWidget);
    await tester.tap(finder);
    await settle(tester);
  }

  Future<void> capture(
    WidgetTester tester,
    String id,
    List<String> ux,
    List<String> steps,
    List<String> expectedText, {
    List<Finder> operable = const [],
    List<String> assertions = const [],
  }) async {
    final semanticsHandle = tester.ensureSemantics();
    try {
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'No overflow in $id');
      for (final value in expectedText) {
        expect(find.textContaining(value), findsWidgets, reason: '$id: $value');
      }
      for (final control in operable) {
        expect(
          control.hitTestable(),
          findsOneWidget,
          reason: '$id operability',
        );
      }
      final actionable = find
          .byWidgetPredicate(
            (widget) =>
                (widget is ProductButton && widget.onPressed != null) ||
                (widget is ListTile && widget.onTap != null) ||
                (widget is IconButton && widget.onPressed != null) ||
                (widget is BackButton && widget.onPressed != null),
          )
          .hitTestable();
      expect(
        actionable,
        findsWidgets,
        reason: '$id must retain an operable control',
      );
      for (final element
          in find.byType(ProductButton).hitTestable().evaluate()) {
        final rect = tester.getRect(
          find.byElementPredicate((e) => identical(e, element)),
        );
        expect(
          rect.width,
          greaterThanOrEqualTo(48),
          reason: '$id minimum button width',
        );
        expect(
          rect.height,
          greaterThanOrEqualTo(48),
          reason: '$id minimum button height',
        );
      }
      final geometry = <String, Object?>{};
      var index = 0;
      for (final element in tester.allElements) {
        final widget = element.widget;
        final key = widget.key;
        if (key is! ValueKey<String> &&
            widget is! ProductButton &&
            widget is! ListTile &&
            widget is! TextField &&
            widget is! AlertDialog &&
            widget is! SimpleDialog) {
          continue;
        }
        final box = element.findRenderObject();
        if (box is RenderBox && box.hasSize && box.attached) {
          final point = box.localToGlobal(Offset.zero);
          geometry[key is ValueKey<String>
              ? key.value
              : '${widget.runtimeType}-${index++}'] = [
            point.dx,
            point.dy,
            box.size.width,
            box.size.height,
          ];
        }
      }
      expect(geometry, isNotEmpty);
      final semantics = tester
          .binding
          .renderViews
          .first
          .owner!
          .semanticsOwner!
          .rootSemanticsNode!
          .toStringDeep();
      expect(semantics, contains('SemanticsNode'));
      File(
        '${root.path}/$id.geometry.json',
      ).writeAsStringSync(jsonEncode(geometry));
      File('${root.path}/$id.semantics.txt').writeAsStringSync(semantics);
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 1);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File(
          '${root.path}/$id.png',
        ).writeAsBytesSync(png!.buffer.asUint8List());
        image.dispose();
      });
      manifest.add({
        'id': id,
        'ux': ux,
        'fixture': 'deterministic-service-no-rom-no-native-page',
        'steps': steps,
        'expectedText': expectedText,
        'assertions': [
          'no Flutter exception/overflow',
          '${operable.length} named controls hit-testable',
          '${actionable.evaluate().length} visible enabled controls',
          'visible ProductButton targets at least 48x48',
          ...assertions,
        ],
        'width': size.width,
        'height': size.height,
        'locale': 'en',
        'textScale': scale,
        'safeArea': [
          safeArea.left,
          safeArea.top,
          safeArea.right,
          safeArea.bottom,
        ],
        'image': '$id.png',
        'geometry': '$id.geometry.json',
        'semantics': '$id.semantics.txt',
        'review': 'pending',
      });
    } finally {
      semanticsHandle.dispose();
    }
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  }
}

Widget hall(ProductController c) => ProductHall(
  controller: c,
  onSources: () {},
  onSettings: () {},
  onNearby: () {},
);
Widget settings(SettingsClient c) => ProductSettings(
  client: c,
  locale: 'en',
  onLocaleChanged: (_) {},
  onSources: () {},
  onLicenses: () {},
  version: '3.0.6',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final h = StateCapture();
  setUpAll(() async {
    h.root.createSync(recursive: true);
    for (final font in {
      'Roboto': 'Roboto-Regular.ttf',
      'G2CJK': 'NotoSansCJK-Regular.ttc',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      final bytes = File(
        '../../.artifacts/flutter-g2/fonts/${font.value}',
      ).readAsBytesSync();
      await (FontLoader(
        font.key,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });
  tearDownAll(
    () => File(
      '${h.root.path}/manifest.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(h.manifest)),
  );

  testWidgets('U01 startup loading, failure and real retry', (tester) async {
    final client = StateClient()..startup = Completer<ProductMap>();
    final c = ProductController(client);
    addTearDown(c.dispose);
    unawaited(c.initialize());
    await h.show(tester, hall(c));
    await h.capture(
      tester,
      'startup-loading',
      ['U01'],
      ['Hold bootstrap unresolved for 240ms'],
      ['Loading'],
      operable: [find.byTooltip('Settings')],
    );
    client.startup!.completeError(const ProductFailure('service_unavailable'));
    await h.settle(tester);
    await h.capture(
      tester,
      'startup-error',
      ['U01', 'U21'],
      ['Bootstrap fails with stable service_unavailable code'],
      ['Please retry', 'Retry'],
      operable: [find.text('Retry').first],
    );
    client.startup = null;
    await h.tap(tester, find.text('Retry').first);
    expect(client.calls.where((m) => m == 'bootstrap').length, 2);
    await h.capture(
      tester,
      'startup-retry-success',
      ['U01'],
      ['Tap Retry; bootstrap and catalog/head succeed'],
      ['Fixture Adventure', 'Start'],
      operable: [find.byKey(const ValueKey('launch-button'))],
      assertions: ['bootstrap called twice; product hall recovered'],
    );
    await h.close(tester);
  });

  for (final state in [
    'none',
    'available',
    'querying',
    'unavailable',
    'source-unavailable',
    'nearby',
  ]) {
    testWidgets('Hall head $state', (tester) async {
      final client = StateClient()..headState = state;
      if (state == 'querying') client.head = Completer<ProductMap>();
      if (state == 'source-unavailable') {
        client.games.first['available'] = false;
      }
      if (state == 'nearby') client.purpose = 'nearby';
      final c = ProductController(client);
      addTearDown(c.dispose);
      unawaited(c.initialize());
      await h.show(tester, hall(c));
      final label = switch (state) {
        'available' => 'Continue',
        'querying' => 'Reading…',
        'unavailable' => 'Retry',
        'nearby' => 'Choose game',
        _ => 'Start',
      };
      final launch = tester.widget<ProductButton>(
        find.byKey(const ValueKey('launch-button')),
      );
      expect(
        launch.onPressed == null,
        state == 'querying' || state == 'source-unavailable',
      );
      if (state == 'nearby') {
        expect(client.calls, isNot(contains('resumeCapability')));
      }
      await h.capture(
        tester,
        'head-$state',
        [state == 'nearby' ? 'U08' : 'U04'],
        ['Bootstrap real controller with fixture head state $state'],
        [label, if (state == 'source-unavailable') 'Source unavailable'],
        assertions: [
          'Launch enabled state checked',
          if (state == 'nearby') 'no head query in nearby purpose',
        ],
      );
      await h.close(tester);
    });
  }

  for (final kind in [
    'recent',
    'favorites',
    'search',
    'two-player',
    'all',
    'catalog-failure',
  ]) {
    testWidgets('Hall empty/error $kind', (tester) async {
      final client = StateClient()..games = [];
      final c = ProductController(client);
      addTearDown(c.dispose);
      c.bootstrapData = {'locale': 'en'};
      c.category = kind == 'recent' || kind == 'favorites' ? kind : 'all';
      if (kind == 'search') c.query = 'no-match';
      if (kind == 'two-player') c.multiplayerOnly = true;
      client.catalogFails = kind == 'catalog-failure';
      await c.refresh();
      await h.show(tester, hall(c));
      final label = switch (kind) {
        'recent' => 'No recently played games',
        'favorites' => 'No favorite games yet',
        'search' => 'No matching games',
        'two-player' => 'No supported two-player games',
        'catalog-failure' => 'Please retry',
        _ => 'Your library is empty',
      };
      final action = switch (kind) {
        'search' => 'Clear search',
        'two-player' => 'Turn off filter',
        'recent' || 'favorites' => 'Show all',
        'catalog-failure' => 'Retry',
        _ => 'Manage sources',
      };
      await h.capture(
        tester,
        'hall-$kind',
        ['U06'],
        ['Query $kind fixture through ProductController'],
        [label],
        operable: [find.text(action).first],
      );
      await h.close(tester);
    });
  }

  final phases = <String, String>{
    'queued': 'Waiting to scan',
    'enumerating': 'Reading files',
    'scanning-known': 'Scanning',
    'scanning-unknown': 'Scanning',
    'cancelling': 'Cancelling',
    'committing': 'Finishing',
    'completed': '12 games',
    'partial': 'Some files',
    'failed': 'Scan failed',
    'permission-lost': 'Source unavailable',
    'committed-refresh-failure': 'scan was saved',
  };
  for (final item in phases.entries) {
    testWidgets('Source ${item.key}', (tester) async {
      final client = StateClient();
      final row = client.sources.first;
      row['phase'] = item.key.startsWith('scanning') ? 'scanning' : item.key;
      row['canCancel'] = [
        'queued',
        'enumerating',
        'scanning-known',
        'scanning-unknown',
      ].contains(item.key);
      row['operationId'] = 'fixture-operation';
      if (item.key == 'scanning-known') {
        row['total'] = 20;
        row['completed'] = 7;
      }
      if (item.key == 'permission-lost') {
        row['phase'] = 'idle';
        row['status'] = 'permission_lost';
        row['reason'] = 'permission_required';
        row['canReauthorize'] = true;
      }
      if (item.key == 'committed-refresh-failure') {
        row['phase'] = 'idle';
        client.operationFailure = 'scan_committed_refresh_failed';
      }
      await h.show(tester, ProductSources(client: client, locale: 'en'));
      if (item.key == 'committed-refresh-failure') {
        await h.tap(tester, find.text('Scan'));
      }
      if (item.key == 'committing') {
        expect(find.text('Cancel scan'), findsNothing);
      }
      if (item.key == 'scanning-known') {
        expect(
          tester
              .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator),
              )
              .value,
          closeTo(.35, .001),
        );
      }
      if (item.key == 'scanning-unknown') {
        expect(find.byType(LinearProgressIndicator), findsNothing);
      }
      final active = const {'queued','enumerating','ingesting','scanning','cancelling','committing'}.contains(row['phase']);
      if (active) {
        expect(tester.widget<TextButton>(find.ancestor(of:find.text('Scan'),matching:find.byType(TextButton))).onPressed, isNull);
      }
      await h.capture(
        tester,
        'source-${item.key}',
        ['U09', 'U11', if (item.key == 'permission-lost') 'U12'],
        ['Observe fixture phase ${item.key}; fixed clock, no repeated scan'],
        [item.value],
        operable: [
          if (!active) find.text(item.key == 'permission-lost' ? 'Reauthorize' : 'Scan'),
        ],
        assertions: [
          if (active) 'Duplicate Scan disabled while operation remains active',
          if (item.key == 'committing') 'No cancel action while committing',
          if (item.key == 'scanning-known') 'authoritative 7/20 progress=.35',
          if (item.key == 'scanning-unknown') 'No fake numeric progress',
        ],
      );
      await h.close(tester);
      expect(client.calls, isNot(contains('cancelScan')));
    });
  }

  testWidgets('Source remove confirmation cancel and picker cancellation', (
    tester,
  ) async {
    final client = StateClient();
    await h.show(tester, ProductSources(client: client, locale: 'en'));
    await h.tap(tester, find.text('Remove'));
    await h.capture(
      tester,
      'source-remove-confirm',
      ['U13', 'U21'],
      ['Tap Remove; capture real shared confirmation'],
      ['Remove source', 'will be kept'],
      operable: [find.text('Cancel'), find.text('Confirm')],
    );
    await h.tap(tester, find.text('Cancel'));
    expect(client.calls, isNot(contains('removeSource')));
    await h.tap(tester, find.text('Add file'));
    expect(client.calls.where((m) => m == 'pickSource').length, 1);
    expect(client.calls, isNot(contains('scanSource')));
    await h.capture(
      tester,
      'source-picker-cancelled',
      ['U10', 'U13'],
      [
        'Cancel remove, request platform picker, fixture returns cancelled; no native screen fabricated',
      ],
      ['My game folder'],
      operable: [find.text('Add file')],
      assertions: [
        'No removeSource or scanSource call; original source retained',
      ],
    );
    await h.close(tester);
  });

  testWidgets('Settings custom axes and hardware lock dialog', (tester) async {
    final client = SettingsClient();
    client.values.addAll({
      'videoQualityPreset': 4,
      'customRefreshPolicy': 3,
      'customTemporalMode': 1,
      'customSpatialMode': 2,
      'customPostEffect': 1,
      'aspectMode': 1,
    });
    await h.show(tester, settings(client));
    await h.capture(
      tester,
      'settings-custom-axes',
      ['U15'],
      ['Open settings with authoritative Custom preset'],
      ['Refresh policy', 'Time processing', 'Image scaling', 'Post-processing'],
      operable: [find.byKey(const ValueKey('setting-customRefreshPolicy'))],
    );
    await h.tap(
      tester,
      find.byKey(const ValueKey('setting-videoQualityPreset')),
    );
    final extreme = find.widgetWithText(ListTile, 'Extreme');
    expect(tester.widget<ListTile>(extreme).onTap, isNull);
    await h.capture(
      tester,
      'settings-locked-option',
      ['U15', 'U21'],
      ['Open Quality preset; no verified capability supplied'],
      ['Extreme', 'requires verified device support'],
      assertions: ['Extreme option disabled'],
    );
    await h.close(tester);
  });

  testWidgets('Controls bottom and reset cancel', (tester) async {
    final client = SettingsClient();
    await h.show(tester, settings(client));
    await h.tap(tester, find.byKey(const ValueKey('section-controls')));
    await tester.scrollUntilVisible(
      find.text('Reset controls'),
      120,
      scrollable: find.descendant(
        of: find.byKey(const PageStorageKey('settings-scroll-controls')),
        matching: find.byType(Scrollable),
      ),
    );
    await h.settle(tester);
    await h.capture(
      tester,
      'controls-bottom',
      ['U16'],
      ['Scroll Controls to reset action'],
      ['Distinct A/B haptics', 'Reset controls'],
      operable: [find.text('Reset controls')],
    );
    await h.tap(tester, find.text('Reset controls'));
    await h.capture(
      tester,
      'controls-reset-confirm',
      ['U16', 'U21'],
      ['Open reset confirmation'],
      ['saved layout?'],
      operable: [find.text('Cancel'), find.text('Confirm')],
    );
    await h.tap(tester, find.text('Cancel'));
    expect(client.calls, isNot(contains('resetControls')));
    await h.close(tester);
  });

  testWidgets('Audio rollback and locale chooser', (tester) async {
    final client = SettingsClient()..fail = true;
    await h.show(tester, settings(client));
    await h.tap(tester, find.byKey(const ValueKey('section-audio')));
    await h.tap(tester, find.byKey(const ValueKey('setting-audioEnabled')));
    expect(
      tester
          .widget<ProductSwitchTile>(
            find.byKey(const ValueKey('setting-audioEnabled')),
          )
          .value,
      isTrue,
    );
    await h.capture(
      tester,
      'audio-write-failure',
      ['U17', 'U21'],
      ['Owner rejects sound patch; acknowledged value retained'],
      ['previous value is retained'],
      operable: [find.text('Retry')],
      assertions: ['Sound remains on after failed write'],
    );
    await h.tap(tester, find.byKey(const ValueKey('section-game')));
    await h.tap(tester, find.byKey(const ValueKey('setting-localeTag')));
    await h.capture(
      tester,
      'locale-chooser',
      ['U18', 'U21'],
      ['Open application language chooser'],
      ['Follow system', 'English', 'Simplified Chinese'],
      operable: [find.widgetWithText(ListTile, 'Simplified Chinese')],
    );
    await h.close(tester);
  });

  testWidgets('License failure retry and copy acknowledgement', (tester) async {
    final client = StateClient()..licenseFails = true;
    await h.show(tester, ProductLicenses(client: client, locale: 'en'));
    await h.capture(
      tester,
      'license-read-failure',
      ['U20', 'U21'],
      ['License body owner returns stable failure'],
      ['Please retry', 'Fixture component'],
      operable: [find.text('Retry')],
    );
    client.licenseFails = false;
    await h.tap(tester, find.text('Retry'));
    await h.tap(tester, find.byTooltip('Copy license'));
    expect(client.calls, contains('copyText'));
    await h.capture(
      tester,
      'license-copy-confirmation',
      ['U20', 'U21'],
      ['Retry body succeeds; copy adapter acknowledges'],
      ['License copied', 'Fixture license text'],
      operable: [find.byTooltip('Copy license')],
    );
    await h.close(tester);
  });

  for (final page in [
    'settings-list',
    'settings-detail',
    'licenses-list',
    'licenses-detail',
    'sources',
    'hall',
  ]) {
    testWidgets('Narrow safe area $page', (tester) async {
      final client = StateClient();
      final c = ProductController(client);
      addTearDown(c.dispose);
      if (page == 'hall') await c.initialize();
      final widget = page.startsWith('settings')
          ? settings(SettingsClient())
          : page.startsWith('licenses')
          ? ProductLicenses(client: client, locale: 'en')
          : page == 'sources'
          ? ProductSources(client: client, locale: 'en')
          : hall(c);
      await h.show(
        tester,
        widget,
        surface: const Size(600, 540),
        safe: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      );
      if (page == 'settings-detail') {
        await h.tap(tester, find.byKey(const ValueKey('section-audio')));
      }
      if (page == 'licenses-detail') {
        await h.tap(tester, find.text('Fixture component'));
      }
      final expected = switch (page) {
        'settings-list' => 'Display',
        'settings-detail' => 'Audio focus',
        'licenses-list' => 'Fixture component',
        'licenses-detail' => 'Fixture license text',
        'sources' => 'Your game sources',
        _ => 'Fixture Adventure',
      };
      await h.capture(
        tester,
        'narrow-safe-$page',
        [
          if (page.startsWith('settings')) 'U14',
          if (page.startsWith('licenses')) 'U20',
          if (page == 'sources') 'U09',
          if (page == 'hall') 'U02',
          'U26',
        ],
        [
          '600x540 with 24px side/top and 16px bottom safe area; $page',
          'English fixture only; not pseudolocalization evidence',
        ],
        [expected],
      );
      await h.close(tester);
    });
  }
}
