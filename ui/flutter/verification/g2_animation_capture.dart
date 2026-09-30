// Controlled-clock actual captures. Reviewing a frame never auto-accepts it.
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flynes_ui/design_system/app_theme.dart';
import 'package:flynes_ui/design_system/product_button.dart';
import 'package:flynes_ui/design_system/product_switch.dart';
import 'package:flynes_ui/design_system/product_notice.dart';
import 'package:flynes_ui/design_system/product_animated_rows.dart';
import 'package:flynes_ui/design_system/product_motion.dart';
import 'package:flynes_ui/design_system/product_dialogs.dart';
import 'package:flynes_ui/features/product/product_controller.dart';
import 'package:flynes_ui/features/product/product_hall.dart';
import 'package:flynes_ui/features/product/product_settings.dart';
import 'package:flynes_ui/features/product/product_licenses.dart';
import 'package:flynes_ui/native_client/product_client.dart';
import 'package:flynes_ui/app/product_app.dart';
import '../test/product_hall_test.dart' show HallClient;
import '../test/product_settings_test.dart' show SettingsClient;
import '../test/product_app_test.dart' show AppClient;
import '../test/product_licenses_test.dart' show LicenseClient;

class AnimationFixtureController extends ProductController {
  AnimationFixtureController(super.client);
  void displayCategory(String value) {
    category = value;
    notifyListeners();
  }
}

class AnimationQueryClient extends HallClient {
  final queries = <ProductMap>[];
  @override
  Future<ProductMap> call(
    String method, [
    ProductMap arguments = const {},
  ]) async {
    if (method == 'catalogQuery') {
      queries.add({...arguments});
      final items = [
        if (arguments['multiplayerOnly'] != true)
          {
            'canonicalId': 'a',
            'titleEn': 'Game a',
            'available': true,
            'multiplayerSupported': false,
          },
        {
          'canonicalId': 'b',
          'titleEn': 'Game b',
          'available': true,
          'multiplayerSupported': true,
        },
      ];
      return {
        'catalogGeneration': 1,
        'viewRevision': queries.length,
        'offset': 0,
        'total': items.length,
        'items': items,
        'selectedId':
            items.any((item) => item['canonicalId'] == arguments['selectedId'])
            ? arguments['selectedId']
            : items.first['canonicalId'],
      };
    }
    return super.call(method, arguments);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final root = Directory(
    const String.fromEnvironment(
      'G2_ANIMATION_OUTPUT',
      defaultValue: '../../.artifacts/flutter-g2/animation-actual',
    ),
  );
  final manifest = <Map<String, Object?>>[];
  final boundary = GlobalKey();
  setUp(() {
    final semantics = TestWidgetsFlutterBinding.instance.ensureSemantics();
    addTearDown(semantics.dispose);
  });
  setUpAll(() async {
    root.createSync(recursive: true);
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
      '${root.path}/manifest.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest)),
  );
  Future<void> show(
    WidgetTester tester,
    Widget scene, {
    bool reduce = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(960, 540));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark().copyWith(
            textTheme:
                ThemeData(
                  fontFamily: 'Roboto',
                  fontFamilyFallback: const ['G2CJK'],
                ).textTheme.apply(
                  bodyColor: AppTheme.text,
                  displayColor: AppTheme.text,
                ),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
            child: child!,
          ),
          home: Scaffold(
            body: Padding(padding: const EdgeInsets.all(24), child: scene),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String id, int milliseconds) async {
    expect(tester.takeException(), isNull);
    final geometry = <String, List<double>>{};
    final counts = <String, int>{};
    for (final element in tester.allElements) {
      final widget = element.widget;
      final key = widget.key;
      if (key is! ValueKey<String> &&
          widget is! ButtonStyleButton &&
          widget is! IconButton &&
          widget is! TextField &&
          widget is! ProductButton &&
          widget is! ProductSwitch &&
          widget is! ListTile) {
        continue;
      }
      final render = element.findRenderObject();
      if (render is! RenderBox || !render.hasSize || !render.attached) continue;
      final type = widget.runtimeType.toString();
      final index = counts.update(
        type,
        (value) => value + 1,
        ifAbsent: () => 0,
      );
      final identity = key is ValueKey<String> ? key.value : '$type-$index';
      final point = render.localToGlobal(Offset.zero);
      geometry[identity] = [
        point.dx,
        point.dy,
        render.size.width,
        render.size.height,
      ];
    }
    // Component-only progress frames have no button, but retain their exact viewport.
    final viewport = tester.getRect(find.byKey(boundary));
    geometry['capture-viewport'] = [
      viewport.left,
      viewport.top,
      viewport.width,
      viewport.height,
    ];
    final semanticsText = tester
        .binding
        .renderViews
        .first
        .owner!
        .semanticsOwner!
        .rootSemanticsNode!
        .toStringDeep();
    File(
      '${root.path}/$id.geometry.json',
    ).writeAsStringSync(jsonEncode(geometry));
    File('${root.path}/$id.semantics.txt').writeAsStringSync(semanticsText);
    await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File('${root.path}/$id.png').writeAsBytesSync(png!.buffer.asUint8List());
      image.dispose();
    });
    manifest.add({
      'id': id,
      'elapsedMs': milliseconds,
      'image': '$id.png',
      'geometry': '$id.geometry.json',
      'semantics': '$id.semantics.txt',
      'review': 'pending',
      'clock': 'Flutter controlled test clock',
      'scope': 'shared component; native transition evidence separate',
    });
  }

  testWidgets('A01 press and release rendered frames', (tester) async {
    await show(
      tester,
      Center(
        child: ProductButton.filled(
          onPressed: () {},
          child: const Text('Continue'),
        ),
      ),
    );
    final control = find.byType(ProductButton);
    final originalSize = tester.getSize(control);
    final gesture = await tester.startGesture(tester.getCenter(control));
    await tester.pump();
    await capture(tester, 'A01-press-start', 0);
    await tester.pump(const Duration(milliseconds: 40));
    await capture(tester, 'A01-press-middle', 40);
    await tester.pump(const Duration(milliseconds: 40));
    await capture(tester, 'A01-press-end', 80);
    await gesture.up();
    await tester.pump();
    await capture(tester, 'A01-release-start', 0);
    await tester.pump(const Duration(milliseconds: 60));
    await capture(tester, 'A01-release-middle', 60);
    await tester.pump(const Duration(milliseconds: 60));
    await capture(tester, 'A01-release-end', 120);
    expect(tester.getSize(control), originalSize);
  });
  testWidgets('A04 real file decode cover fade frames', (tester) async {
    final path = '${root.path}/fixture-cover.png';
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 320, 160),
        Paint()..color = AppTheme.accent,
      );
      canvas.drawRect(
        const Rect.fromLTWH(80, 40, 160, 80),
        Paint()..color = AppTheme.background,
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(320, 160);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
      picture.dispose();
    });
    await show(tester, const SizedBox());
    late StateSetter update;
    var loaded = false;
    await show(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return Center(
            child: SizedBox(
              width: 320,
              height: 200,
              child: ProductCover(
                item: loaded ? {'coverPath': path, 'coverRevision': 1} : null,
                title: 'Adventure cover',
              ),
            ),
          );
        },
      ),
    );
    update(() => loaded = true);
    await tester.pump();
    for (
      var i = 0;
      i < 100 && tester.widget<RawImage>(find.byType(RawImage)).image == null;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    await capture(tester, 'A04-start', 0);
    await tester.pump(const Duration(milliseconds: 60));
    await capture(tester, 'A04-middle', 60);
    await tester.pump(const Duration(milliseconds: 60));
    await capture(tester, 'A04-end', 120);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('A02 A03 A06 actual hall selection and search frames', (
    tester,
  ) async {
    final c = AnimationFixtureController(AnimationQueryClient());
    addTearDown(c.dispose);
    c.bootstrapData = {'locale': 'en'};
    c.total = 2;
    c.windows[0] = [
      for (final id in ['a', 'b'])
        {'canonicalId': id, 'titleEn': 'Game $id', 'available': true},
    ];
    c.selectedId = 'a';
    c.selected = c.windows[0]!.first;
    c.resumeState = 'none';
    await show(
      tester,
      ProductHall(
        controller: c,
        onSources: () {},
        onSettings: () {},
        onNearby: () {},
      ),
    );
    await tester.tap(find.byKey(const ValueKey('game-b')));
    await tester.pump();
    await capture(tester, 'A02-start', 0);
    await capture(tester, 'A03-start', 0);
    await tester.pump(const Duration(milliseconds: 60));
    await capture(tester, 'A03-middle', 60);
    await tester.pump(const Duration(milliseconds: 20));
    await capture(tester, 'A02-middle', 80);
    await tester.pump(const Duration(milliseconds: 40));
    await capture(tester, 'A03-end', 120);
    await tester.pump(const Duration(milliseconds: 40));
    await capture(tester, 'A02-end', 160);
    c.displayCategory('favorites');
    await tester.pump();
    await capture(tester, 'A05-start', 0);
    await tester.pump(const Duration(milliseconds: 75));
    await capture(tester, 'A05-middle', 75);
    await tester.pump(const Duration(milliseconds: 75));
    await capture(tester, 'A05-end', 150);
    await tester.tap(find.byTooltip('Search'));
    await tester.pump();
    await capture(tester, 'A06-start', 0);
    await tester.pump(const Duration(milliseconds: 80));
    await capture(tester, 'A06-middle', 80);
    await tester.pump(const Duration(milliseconds: 80));
    await capture(tester, 'A06-end', 160);
    await tester.tap(find.byTooltip('Close search'));
    await tester.pump();
    expect(
      c.error,
      isEmpty,
      reason: 'Closing search must use a valid authoritative query fixture.',
    );
    await capture(tester, 'A06-close-start', 0);
    await tester.pump(const Duration(milliseconds: 80));
    await capture(tester, 'A06-close-middle', 80);
    await tester.pump(const Duration(milliseconds: 80));
    await capture(tester, 'A06-close-end', 160);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('A05 two-player query changes real result rows', (tester) async {
    final client = AnimationQueryClient();
    final c = ProductController(client)..bootstrapData = {'locale': 'en'};
    addTearDown(c.dispose);
    await c.refresh();
    await show(
      tester,
      ProductHall(
        controller: c,
        onSources: () {},
        onSettings: () {},
        onNearby: () {},
      ),
    );
    expect(c.total, 2);
    await tester.tap(find.byType(ProductSwitch));
    await tester.pump();
    expect(client.queries.last['multiplayerOnly'], true);
    expect(c.total, 1);
    await capture(tester, 'A05-two-player-start', 0);
    await tester.pump(const Duration(milliseconds: 75));
    await capture(tester, 'A05-two-player-middle', 75);
    await tester.pump(const Duration(milliseconds: 75));
    await capture(tester, 'A05-two-player-end', 150);
    expect(find.byKey(const ValueKey('game-a')), findsNothing);
    expect(find.byKey(const ValueKey('game-b')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  for (final fast in [false, true]) {
    testWidgets('A13 ${fast ? 'fast completion' : 'unknown work'} frames', (
      tester,
    ) async {
      var working = false;
      late StateSetter update;
      await show(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return Center(
              child: working
                  ? const DeferredProgress(label: 'Reading game sources')
                  : const Text('Sources ready'),
            );
          },
        ),
      );
      update(() => working = true);
      await tester.pump();
      if (fast) {
        await capture(tester, 'A13-fast-start', 0);
        await tester.pump(const Duration(milliseconds: 75));
        expect(find.byType(CircularProgressIndicator), findsNothing);
        await capture(tester, 'A13-fast-middle', 75);
        await tester.pump(const Duration(milliseconds: 25));
        update(() => working = false);
        await tester.pump();
        await capture(tester, 'A13-fast-end', 100);
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(CircularProgressIndicator), findsNothing);
      } else {
        await tester.pump(const Duration(milliseconds: 150));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        await capture(tester, 'A13-unknown-start', 150);
        await tester.pump(const Duration(milliseconds: 60));
        await capture(tester, 'A13-unknown-middle', 210);
        await tester.pump(const Duration(milliseconds: 60));
        await capture(tester, 'A13-unknown-end', 270);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('A09 actual asynchronous license content switch frames', (
    tester,
  ) async {
    final client = LicenseClient();
    await show(tester, ProductLicenses(client: client, locale: 'en'));
    final pending = Completer<ProductMap>();
    client.pendingBodies['b'] = pending;
    await tester.tap(find.text('Component B'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    pending.complete({'text': 'License B\nPermission to use this component.'});
    await tester.pump();
    await capture(tester, 'A09-license-start', 0);
    await tester.pump(const Duration(milliseconds: 60));
    await capture(tester, 'A09-license-middle', 60);
    await tester.pump(const Duration(milliseconds: 60));
    await capture(tester, 'A09-license-end', 120);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('A09 actual settings content switch frames', (tester) async {
    await show(
      tester,
      ProductSettings(
        client: SettingsClient(),
        locale: 'en',
        onLocaleChanged: (_) {},
        onSources: () {},
        onLicenses: () {},
      ),
    );
    await tester.tap(find.byKey(const ValueKey('section-audio')));
    await tester.pump();
    await capture(tester, 'A09-start', 0);
    await tester.pump(const Duration(milliseconds: 60));
    await capture(tester, 'A09-middle', 60);
    await tester.pump(const Duration(milliseconds: 60));
    await capture(tester, 'A09-end', 120);
    await tester.pumpWidget(const SizedBox());
  });
  for (final target in ['Settings', 'Sources']) {
    testWidgets('A07 A08 actual $target route frames', (tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: ProductApp(client: AppClient()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(target));
      await tester.pump();
      final id = target == 'Settings' ? 'A07' : 'A08';
      await capture(tester, '$id-start', 0);
      await tester.pump(const Duration(milliseconds: 110));
      await capture(tester, '$id-middle', 110);
      await tester.pump(const Duration(milliseconds: 110));
      await capture(tester, '$id-end', 220);
      await tester.pageBack();
      await tester.pump();
      await capture(tester, '$id-return-start', 0);
      await tester.pump(const Duration(milliseconds: 90));
      await capture(tester, '$id-return-middle', 90);
      await tester.pump(const Duration(milliseconds: 90));
      // Flush Navigator's completed-route removal at the same 180ms clock.
      await tester.pump();
      expect(find.byTooltip('Settings').hitTestable(), findsOneWidget);
      expect(find.byTooltip('Sources').hitTestable(), findsOneWidget);
      await capture(tester, '$id-return-end', 180);
      // A rendered opacity endpoint precedes Navigator semantics publication.
      // Keep it, and independently certify the following settled frame.
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump();
      final restoredSemantics = tester
          .binding
          .renderViews
          .first
          .owner!
          .semanticsOwner!
          .rootSemanticsNode!
          .toStringDeep();
      expect(restoredSemantics, contains('Settings'));
      expect(restoredSemantics, contains('Sources'));
      expect(restoredSemantics, contains('tap'));
      await capture(tester, '$id-return-settled', 196);
      await tester.pumpWidget(const SizedBox());
    });
  }
  for (final kind in ['A11', 'A12', 'A13', 'A14', 'A17']) {
    testWidgets('$kind rendered start middle end and disposal', (tester) async {
      var changed = false;
      late StateSetter update;
      await show(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return switch (kind) {
              'A11' || 'A17' => Center(
                child: ProductSwitch(
                  value: changed,
                  label: 'Sound',
                  onChanged: (_) {},
                ),
              ),
              'A12' => ProductAnimatedRows<String>(
                items: changed ? ['Built-in'] : ['Built-in', 'My games'],
                identity: (s) => s,
                builder: (s) => Card(
                  child: SizedBox(height: 140, child: Center(child: Text(s))),
                ),
              ),
              'A13' => Center(child: ProductProgress(value: changed ? .9 : .1)),
              _ => Column(
                children: [
                  ProductNotice(
                    message: changed ? 'Saved successfully' : '',
                    error: false,
                  ),
                  const Text('The selected game remains unchanged.'),
                ],
              ),
            };
          },
        ),
        reduce: kind == 'A17',
      );
      update(() => changed = true);
      await tester.pump();
      final duration = switch (kind) {
        'A11' => 150,
        'A12' => 180,
        'A13' => 120,
        'A14' => 160,
        _ => 0,
      };
      await capture(tester, '$kind-start', 0);
      await tester.pump(Duration(milliseconds: duration ~/ 2));
      await capture(tester, '$kind-middle', duration ~/ 2);
      await tester.pump(Duration(milliseconds: duration - duration ~/ 2));
      await capture(tester, '$kind-end', duration);
      if (kind == 'A12' || kind == 'A14') {
        update(() => changed = false);
        await tester.pump();
        final branch = kind == 'A12' ? 'insert' : 'exit';
        await capture(tester, '$kind-$branch-start', 0);
        await tester.pump(Duration(milliseconds: duration ~/ 2));
        await capture(tester, '$kind-$branch-middle', duration ~/ 2);
        await tester.pump(Duration(milliseconds: duration - duration ~/ 2));
        await capture(tester, '$kind-$branch-end', duration);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 4));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('A10 dialog rendered start middle end', (tester) async {
    late BuildContext host;
    await show(
      tester,
      Builder(
        builder: (context) {
          host = context;
          return const Center(child: Text('Sources'));
        },
      ),
    );
    if (!host.mounted) throw StateError('Capture host detached');
    productDialog<void>(
      host,
      const AlertDialog(
        title: Text('Remove source'),
        content: Text('Original games and saved progress will be kept.'),
      ),
    );
    await tester.pump();
    await capture(tester, 'A10-start', 0);
    await tester.pump(const Duration(milliseconds: 90));
    await capture(tester, 'A10-middle', 90);
    await tester.pump(const Duration(milliseconds: 90));
    await capture(tester, 'A10-end', 180);
    if (!host.mounted) throw StateError('Capture host detached');
    Navigator.of(host).pop();
    await tester.pump();
    await capture(tester, 'A10-exit-start', 0);
    await tester.pump(const Duration(milliseconds: 60));
    await capture(tester, 'A10-exit-middle', 60);
    await tester.pump(const Duration(milliseconds: 60));
    await capture(tester, 'A10-exit-end', 120);
    // Raster opacity ends at 120 ms; route removal publishes semantics next frame.
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      tester.getSemantics(find.text('Sources')).getSemanticsData().label,
      'Sources',
    );
    expect(find.text('Remove source'), findsNothing);
    await capture(tester, 'A10-exit-settled', 136);
    await tester.pumpAndSettle();
  });
}
