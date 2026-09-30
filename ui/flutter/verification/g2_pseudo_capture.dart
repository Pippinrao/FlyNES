// Debug-only en-XA evidence. Product/native preference remains "system".
// This independent runner never touches the normal/state captures or goldens.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flynes_ui/design_system/product_strings.dart';
import 'package:flynes_ui/features/product/product_controller.dart';
import 'package:flynes_ui/features/product/product_hall.dart';
import 'package:flynes_ui/features/product/product_settings.dart';
import 'package:flynes_ui/features/product/product_sources.dart';
import 'package:flynes_ui/features/product/product_licenses.dart';
import '../test/product_hall_test.dart' show HallClient;
import '../test/product_settings_test.dart' show SettingsClient;
import '../test/product_sources_test.dart' show SourceClient;
import 'g2_visual_capture.dart' show VisualLicenseClient;
import 'g2_state_capture.dart' show StateCapture;

class PseudoCapture extends StateCapture {
  @override
  Directory get root => Directory('../../.artifacts/flutter-g2/pseudo-actual');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final h = PseudoCapture();
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
      testWidgets('en-XA $page 800x360 ${scale * 100}', (tester) async {
        final c = ProductController(HallClient());
        addTearDown(c.dispose);
        c.bootstrapData = {'locale': 'system'};
        c.total = 6;
        c.selectedId = 'fixture-1';
        c.resumeState = 'available';
        c.windows[0] = [
          for (var i = 1; i <= 6; i++)
            {
              'canonicalId': 'fixture-$i',
              'titleEn': 'Adventure $i',
              'titleZhHans': '冒险游戏 $i',
              'favorite': i == 1,
              'available': true,
              'variantCount': 1,
            },
        ];
        c.selected = c.windows[0]!.first;
        final settings = SettingsClient();
        settings.values = {
          ...settings.values,
          'localeTag': 'system',
          'aspectMode': 1,
          'adaptiveProtection': true,
        };
        final Widget scene = switch (page) {
          'hall' || 'search' => ProductHall(
            controller: c,
            onSources: () {},
            onSettings: () {},
            onNearby: () {},
          ),
          'sources' => ProductSources(client: SourceClient(), locale: 'system'),
          'licenses' => ProductLicenses(
            client: VisualLicenseClient(),
            locale: 'system',
          ),
          _ => ProductSettings(
            client: settings,
            locale: 'system',
            onLocaleChanged: (_) {},
            onSources: () {},
            onLicenses: () {},
            version: '3.0.6',
          ),
        };
        await h.show(
          tester,
          Builder(
            builder: (context) => Localizations.override(
              context: context,
              locale: const Locale('en', 'XA'),
              child: Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    viewInsets: page == 'search'
                        ? const EdgeInsets.only(bottom: 180)
                        : EdgeInsets.zero,
                  ),
                  child: scene,
                ),
              ),
            ),
          ),
          surface: const Size(800, 360),
          textScale: scale,
          safe: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        );
        final sceneFinder = find.byType(scene.runtimeType);
        final strings = ProductStrings(tester.element(sceneFinder), 'system');
        expect(strings.text('Settings', '设置'), startsWith('['));
        final operable = <Finder>[];
        if (page == 'search') {
          await h.tap(tester, find.byTooltip(strings.text('Search', '搜索')));
          operable.add(find.byKey(const ValueKey('search-field')));
          operable.add(find.byTooltip(strings.text('Close search', '关闭搜索')));
        } else if (page == 'hall') {
          final favorite = find.byTooltip(strings.text('Favorite', '收藏'));
          expect(tester.getSemantics(favorite).rect.height, greaterThanOrEqualTo(48),
              reason: 'Favorite visible semantic target must not be clipped');
          final title = find.byKey(const ValueKey('Adventure 1'));
          final viewport = find.ancestor(of: title, matching: find.byType(SingleChildScrollView)).first;
          expect(tester.getRect(viewport).contains(tester.getRect(title).bottomRight - const Offset(.01, .01)), isTrue,
              reason: 'Both selected-title lines must fit without vertical clipping');

          operable.add(find.byKey(const ValueKey('launch-button')));
          operable.add(find.byTooltip(strings.text('Sources', '来源')));
        } else if (page == 'sources') {
          await tester.scrollUntilVisible(
            find.text(strings.text('Add folder', '添加文件夹')),
            80,
            scrollable: find.byType(Scrollable).first,
          );
          await h.settle(tester);
          operable.add(find.text(strings.text('Add file', '添加文件')));
          operable.add(find.text(strings.text('Add folder', '添加文件夹')));
        } else if (page == 'licenses') {
          operable.add(find.byTooltip(strings.text('Copy license', '复制许可')));
        } else {
          final nav = find.byKey(ValueKey('section-$page'));
          await tester.scrollUntilVisible(
            nav,
            80,
            scrollable: find.byType(Scrollable).first,
          );
          await h.settle(tester);
          await h.tap(tester, nav);
          operable.add(nav);
        }
        final expected = switch (page) {
          'hall' => strings.text('Continue', '继续'),
          'search' => strings.text('Search games', '搜索游戏'),
          'sources' => strings.text('Your game sources', '游戏来源'),
          'licenses' => strings.text('Licenses', '许可'),
          _ => strings.text('Settings', '设置'),
        };
        await h.capture(
          tester,
          '$page-800x360-en-XA-${(scale * 100).toInt()}',
          [
            switch (page) {
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
            'U26',
          ],
          [
            'Resolve debug en-XA via system preference',
            'Accent product strings and expand approximately 30%',
            '800x360; safe insets 16/16/16/8; scale $scale',
            if (page == 'sources')
              'Scroll introduction to both add controls; verify independent vertical access',
            if (page == 'search')
              'Simulated 180px IME inset, not system keyboard pixels',
          ],
          [expected],
          operable: operable,
          assertions: [
            'No native/user language enum added',
            'Preference remains system',
          ],
        );
        h.manifest.last['locale'] = 'en-XA';
        h.manifest.last['nativeLocalePreference'] = 'system';
        h.manifest.last['fixture'] =
            'synthetic-no-rom-debug-pseudolocalization';
        await h.close(tester);
      });
    }
  }
}
