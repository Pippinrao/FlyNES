// Explicit visual runner; requires the frozen fonts in ignored local evidence.
// This captures actuals for review. It never accepts or updates golden images.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flynes_ui/design_system/app_theme.dart';
import 'package:flynes_ui/features/product/product_controller.dart';
import 'package:flynes_ui/features/product/product_hall.dart';
import 'package:flynes_ui/features/product/product_settings.dart';
import 'package:flynes_ui/features/product/product_sources.dart';
import 'package:flynes_ui/features/product/product_licenses.dart';
import 'package:flynes_ui/native_client/product_client.dart';
import '../test/product_hall_test.dart' show HallClient;
import '../test/product_settings_test.dart' show SettingsClient;
import '../test/product_sources_test.dart' show SourceClient;

class VisualLicenseClient implements ProductClient {
  VisualLicenseClient() {
    final manifest =
        jsonDecode(
              File(
                '../../content/assets/builtin-games.json',
              ).readAsStringSync(),
            )
            as Map;
    for (final item in manifest['games'] as List) {
      final license = item['license'] as Map;
      final text = File(
        '../../content/assets/licenses/${license['file']}',
      ).readAsStringSync();
      items.add({
        'id': license['file'],
        'title': item['titleEn'],
        'sourceUrl': license['sourceUrl'],
        'text': text,
      });
    }
    items.sort(
      (a, b) =>
          (b['text'] as String).length.compareTo((a['text'] as String).length),
    );
  }
  final items = <ProductMap>[];
  @override
  Future<ProductMap> bootstrap() async => {};
  @override
  Future<ProductMap> call(String method, [ProductMap args = const {}]) async {
    if (method == 'licenses') return {'items': items};
    if (method == 'licenseText') {
      return {'text': items.firstWhere((e) => e['id'] == args['id'])['text']};
    }
    return {};
  }

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final root = Directory('../../.artifacts/flutter-g2/visual-actual');
  final manifest = <Map<String, Object?>>[];
  setUpAll(() async {
    for (final entry in {
      'Roboto': 'Roboto-Regular.ttf',
      'G2CJK': 'NotoSansCJK-Regular.ttc',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      final data = File(
        '../../.artifacts/flutter-g2/fonts/${entry.value}',
      ).readAsBytesSync();
      await (FontLoader(
        entry.key,
      )..addFont(Future.value(ByteData.sublistView(data)))).load();
    }
    root.createSync(recursive: true);
  });
  tearDownAll(
    () => File(
      '${root.path}/manifest.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest)),
  );
  for (final size in [
    const Size(960, 540),
    const Size(800, 360),
    const Size(1280, 800),
  ]) {
    for (final locale in ['en', 'zh-CN']) {
      for (final scale in [1.0, 2.0]) {
        for (final page in [
          'hall',
          'search',
          'sources',
          'display',
          'controls',
          'audio',
          'game',
          'about',
          'licenses',
        ]) {
          final id =
              '$page-${size.width.toInt()}x${size.height.toInt()}-$locale-${(scale * 100).toInt()}';
          testWidgets(id, (tester) async {
            await tester.binding.setSurfaceSize(size);
            addTearDown(() => tester.binding.setSurfaceSize(null));
            final controller = ProductController(HallClient());
            addTearDown(controller.dispose);
            controller.bootstrapData = {'locale': locale};
            controller.total = 6;
            controller.selectedId = 'game-1';
            controller.resumeState = 'available';
            controller.windows[0] = [
              for (var i = 1; i <= 6; i++)
                {
                  'canonicalId': 'game-$i',
                  'titleEn': 'Adventure $i',
                  'titleZhHans': '冒险游戏 $i',
                  'favorite': i == 1,
                  'builtin': true,
                  'available': true,
                  'variantCount': 1,
                },
            ];
            controller.selected = controller.windows[0]!.first;
            final settings = SettingsClient();
            settings.values = {
              ...settings.values,
              'localeTag': locale == 'zh-CN' ? 'zh-Hans' : locale,
              'aspectMode': 1,
              'adaptiveProtection': true,
            };
            final widget = switch (page) {
              'hall' || 'search' => ProductHall(
                controller: controller,
                onSources: () {},
                onSettings: () {},
                onNearby: () {},
              ),
              'sources' => ProductSources(
                client: SourceClient(),
                locale: locale,
              ),
              'licenses' => ProductLicenses(
                client: VisualLicenseClient(),
                locale: locale,
              ),
              _ => ProductSettings(
                client: settings,
                locale: locale,
                onLocaleChanged: (_) {},
                onSources: () {},
                onLicenses: () {},
                version: '3.0.6',
              ),
            };
            final boundary = GlobalKey();
            final semantics = tester.ensureSemantics();
            try {
              final fonts =
                  ThemeData(
                    fontFamily: 'Roboto',
                    fontFamilyFallback: const ['G2CJK'],
                  ).textTheme.apply(
                    bodyColor: AppTheme.text,
                    displayColor: AppTheme.text,
                  );
              await tester.pumpWidget(
                MaterialApp(
                  theme: AppTheme.dark().copyWith(textTheme: fonts),
                  home: MediaQuery(
                    data: MediaQueryData(
                      size: size,
                      textScaler: TextScaler.linear(scale),
                      devicePixelRatio: 1,
                      viewInsets: page == 'search'
                          ? EdgeInsets.only(
                              bottom: size.height <= 360 ? 180 : 240,
                            )
                          : EdgeInsets.zero,
                    ),
                    child: RepaintBoundary(key: boundary, child: widget),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              if (page == 'search') {
                await tester.tap(
                  find.byTooltip(locale == 'en' ? 'Search' : '搜索'),
                );
                await tester.pumpAndSettle();
                expect(
                  find.byKey(const ValueKey('search-field')).hitTestable(),
                  findsOneWidget,
                );
              }
              if (const ['controls', 'audio', 'game', 'about'].contains(page)) {
                await tester.scrollUntilVisible(
                  find.byKey(ValueKey('section-$page')),
                  120,
                  scrollable: find.byType(Scrollable).first,
                );
                await tester.tap(find.byKey(ValueKey('section-$page')));
                await tester.pumpAndSettle();
              }
              expect(tester.takeException(), isNull);
              final geometry = <String, List<double>>{};
              for (final element in tester.allElements) {
                final key = element.widget.key;
                if (key is! ValueKey<String>) continue;
                final render = element.findRenderObject();
                if (render is RenderBox && render.hasSize && render.attached) {
                  final point = render.localToGlobal(Offset.zero);
                  geometry[key.value] = [
                    point.dx,
                    point.dy,
                    render.size.width,
                    render.size.height,
                  ];
                }
              }
              expect(geometry, isNotEmpty);
              final semanticsText = tester
                  .binding
                  .renderViews
                  .first
                  .owner!
                  .semanticsOwner!
                  .rootSemanticsNode!
                  .toStringDeep();
              expect(semanticsText, contains('SemanticsNode'));
              File(
                '${root.path}/$id.geometry.json',
              ).writeAsStringSync(jsonEncode(geometry));
              File(
                '${root.path}/$id.semantics.txt',
              ).writeAsStringSync(semanticsText);
              await tester.runAsync(() async {
                final image =
                    await (boundary.currentContext!.findRenderObject()!
                            as RenderRepaintBoundary)
                        .toImage(pixelRatio: 1);
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await File(
                  '${root.path}/$id.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
              manifest.add({
                'id': id,
                'ux': switch (page) {
                  'hall' => 'U02',
                  'search' => 'U05',
                  'sources' => 'U09',
                  'display' => 'U15',
                  'controls' => 'U16',
                  'audio' => 'U17',
                  'game' => 'U18',
                  'about' => 'U19',
                  _ => 'U20',
                },
                'fixture': 'synthetic-no-rom',
                'width': size.width,
                'height': size.height,
                'locale': locale,
                'textScale': scale,
                'image': '$id.png',
                'geometry': '$id.geometry.json',
                'semantics': '$id.semantics.txt',
                'keyboard': page == 'search'
                    ? 'simulated IME insets; system keyboard verified separately'
                    : null,
                'review': 'pending',
              });
              await tester.pumpWidget(const SizedBox());
              await tester.pump();
            } finally {
              semantics.dispose();
            }
          });
        }
      }
    }
  }
}
