// Additional U03/U05/U09-U21 evidence. Never accepts its own golden output.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flynes_ui/features/product/product_controller.dart';
import 'package:flynes_ui/features/product/product_sources.dart';
import 'package:flynes_ui/features/product/product_licenses.dart';
import 'package:flynes_ui/native_client/product_client.dart';
import '../test/product_settings_test.dart' show SettingsClient;
import '../test/product_licenses_test.dart' show LicenseClient;
import 'g2_state_capture.dart';
import 'g2_visual_capture.dart' show VisualLicenseClient;

class ExtendedCapture extends StateCapture {
  @override
  Directory get root =>
      Directory('../../.artifacts/flutter-g2/extended-state-actual');
}

class SourceStates extends StateClient {
  String? failMethod;
  bool? folderAvailable;
  bool readFails = false;
  @override
  Future<ProductMap> call(String method, [ProductMap args = const {}]) async {
    if (method == 'sources' && folderAvailable != null) {
      return {
        ...await super.call(method, args),
        'folderSelection': {
          'available': folderAvailable,
          'reason': 'folder_selection_unsupported',
        },
      };
    }
    if (method == failMethod || (method == 'sources' && readFails)) {
      calls.add(method);
      arguments.add(args);
      throw const ProductFailure('source_unavailable');
    }
    if (method == 'removeSource') {
      sources.removeWhere((r) => r['uuid'] == args['uuid']);
    }
    if (method == 'pickSource' && args.containsKey('sourceUuid')) {
      sources = sources.map((r) => {...r, 'status': 'ready'}).toList();
      calls.add(method);
      arguments.add(args);
      return {'status': 'completed'};
    }
    if (method == 'pickSource') {
      calls.add(method);
      arguments.add(args);
      sources.add({
        'uuid': 'added',
        'name': 'Added game folder',
        'type': 'folder',
        'count': 3,
        'status': 'ready',
        'builtin': false,
      });
      return {'status': 'completed'};
    }
    return super.call(method, args);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final h = ExtendedCapture();
  setUpAll(() async {
    h.root.createSync(recursive: true);
    for (final e in {
      'Roboto': 'Roboto-Regular.ttf',
      'G2CJK': 'NotoSansCJK-Regular.ttc',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      final data = File(
        '../../.artifacts/flutter-g2/fonts/${e.value}',
      ).readAsBytesSync();
      await (FontLoader(
        e.key,
      )..addFont(Future.value(ByteData.sublistView(data)))).load();
    }
  });
  tearDownAll(
    () => File(
      '${h.root.path}/manifest.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(h.manifest)),
  );
  Future<void> capture(
    WidgetTester t,
    String id,
    List<String> ux,
    List<String> text,
  ) => h.capture(t, id, ux, [
    'Interact with real product widget using deterministic owner responses',
  ], text);
  Future<void> field(WidgetTester t, String section, String key) async {
    await h.tap(t, find.byKey(ValueKey('section-$section')));
    await t.scrollUntilVisible(
      find.byKey(ValueKey('setting-$key')),
      120,
      scrollable: find.descendant(
        of: find.byKey(PageStorageKey('settings-scroll-$section')),
        matching: find.byType(Scrollable),
      ),
    );
    await h.settle(t);
    await h.tap(t, find.byKey(ValueKey('setting-$key')));
  }

  for (final locale in ['en', 'zh-Hans']) {
    testWidgets('U10 unsupported folder capability $locale', (t) async {
      final c = SourceStates()..folderAvailable = false;
      await h.show(t, ProductSources(client: c, locale: locale));
      final label = locale == 'en' ? 'Add folder' : '添加文件夹';
      final button = find.ancestor(
        of: find.text(label),
        matching: find.byType(OutlinedButton),
      );
      expect(t.widget<OutlinedButton>(button).onPressed, isNull);
      await capture(
        t,
        'source-folder-unavailable-$locale',
        ['U10', 'U12'],
        [
          locale == 'en'
              ? 'Folder selection is unavailable on this system. Add files or ZIP archives instead.'
              : '当前系统不支持选择文件夹，请添加文件或 ZIP 压缩包。',
        ],
      );
      h.manifest.last['locale'] = locale;
      await h.close(t);
    });
  }

  for (final decoded in [true, false]) {
    testWidgets(
      'U03 cover ${decoded ? 'decoded' : 'failed'} keeps fixed geometry',
      (t) async {
        final file = File('${h.root.path}/cover-fixture.png');
        if (decoded) {
          await t.runAsync(() async {
            final recorder = ui.PictureRecorder();
            final canvas = Canvas(recorder);
            canvas.drawRect(
              const Rect.fromLTWH(0, 0, 320, 160),
              Paint()..color = const Color(0xFF496C83),
            );
            canvas.drawRect(
              const Rect.fromLTWH(80, 40, 160, 80),
              Paint()..color = const Color(0xFFFF6B5E),
            );
            final picture = recorder.endRecording();
            final image = await picture.toImage(320, 160);
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            file.writeAsBytesSync(png!.buffer.asUint8List());
            image.dispose();
            picture.dispose();
          });
        }
        final client = StateClient();
        client.games = [
          {
            ...client.games.first,
            'coverPath': decoded
                ? file.absolute.path
                : '${h.root.path}/missing-cover.png',
            'coverRevision': 1,
          },
        ];
        final c = ProductController(client);
        await c.initialize();
        await h.show(t, hall(c));
        for (var n = 0; n < 80; n++) {
          final ready = find
              .byType(RawImage)
              .evaluate()
              .any((e) => (e.widget as RawImage).image != null);
          if (decoded && ready) break;
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await t.pump();
        }
        await h.settle(t);
        if (decoded) {
          final images = find
              .byType(RawImage)
              .evaluate()
              .map((e) => (e.widget as RawImage).image)
              .whereType<ui.Image>();
          expect(images, isNotEmpty);
          expect(images.first.width / images.first.height, closeTo(2, .02));
        } else {
          expect(find.text('Fixture Adventure'), findsWidgets);
        }
        await capture(
          t,
          decoded ? 'cover-decoded' : 'cover-failed',
          ['U03', 'A04'],
          ['Fixture Adventure'],
        );
        await h.close(t);
        c.dispose();
      },
    );
  }
  testWidgets('U05 populated search clear and close preserve category', (
    t,
  ) async {
    final c = ProductController(StateClient());
    await c.initialize();
    await h.show(t, hall(c));
    await h.tap(t, find.byTooltip('Search'));
    await t.enterText(find.byKey(const ValueKey('search-field')), 'Fixture');
    await t.pump(const Duration(milliseconds: 151));
    await h.settle(t);
    expect(c.query, 'Fixture');
    await capture(
      t,
      'search-populated',
      ['U05'],
      ['Fixture Adventure', 'Fixture'],
    );
    await h.tap(t, find.byTooltip('Clear search'));
    expect(c.query, '');
    await capture(
      t,
      'search-cleared',
      ['U05'],
      ['Search games', 'Fixture Adventure'],
    );
    await h.tap(t, find.byTooltip('Close search'));
    expect(find.byKey(const ValueKey('search-field')), findsNothing);
    await capture(t, 'search-closed', ['U05'], ['Fixture Adventure']);
    await h.close(t);
    c.dispose();
  });

  testWidgets('U09 protected built-in and U11 cancelled scan', (t) async {
    final c = SourceStates();
    c.sources = [
      {
        'uuid': 'builtin',
        'name': 'Built-in',
        'count': 7,
        'builtin': true,
        'status': 'ready',
      },
      {...c.sources.first, 'phase': 'cancelled'},
    ];
    await h.show(t, ProductSources(client: c, locale: 'en'));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('source-builtin')),
        matching: find.text('Remove'),
      ),
      findsNothing,
    );
    await capture(
      t,
      'source-builtin-cancelled',
      ['U09', 'U11'],
      ['Built-in', 'Scan cancelled. Previous library retained.'],
    );
    await h.close(t);
  });
  testWidgets(
    'U12 failed targeted reauthorization retains original row then retries',
    (t) async {
      final c = SourceStates()..failMethod = 'pickSource';
      c.sources = [
        {
          ...c.sources.first,
          'status': 'permission_lost',
          'canReauthorize': true,
        },
      ];
      await h.show(t, ProductSources(client: c, locale: 'en'));
      await h.tap(t, find.text('Reauthorize'));
      expect(c.sources.single['uuid'], 'fixture-source');
      await capture(
        t,
        'source-reauthorize-failed',
        ['U12'],
        ['My game folder', 'Source unavailable'],
      );
      c.failMethod = null;
      await h.tap(t, find.text('Reauthorize'));
      expect(c.sources.length, 1);
      expect(c.sources.single['uuid'], 'fixture-source');
      await capture(
        t,
        'source-reauthorize-restored',
        ['U12'],
        ['My game folder', '12 games'],
      );
      await h.close(t);
    },
  );
  testWidgets(
    'U13 failed removal retains row then success removes only source',
    (t) async {
      final c = SourceStates()..failMethod = 'removeSource';
      await h.show(t, ProductSources(client: c, locale: 'en'));
      await h.tap(t, find.text('Remove'));
      await h.tap(t, find.text('Confirm'));
      expect(c.sources.length, 1);
      await capture(
        t,
        'source-remove-failed',
        ['U13'],
        ['My game folder', 'This source is unavailable'],
      );
      c.failMethod = null;
      await h.tap(t, find.text('Remove'));
      await h.tap(t, find.text('Confirm'));
      expect(c.sources, isEmpty);
      await capture(
        t,
        'source-remove-completed',
        ['U13'],
        ['Add file', 'Add folder'],
      );
      await h.tap(t, find.text('Add folder'));
      await capture(
        t,
        'source-add-completed',
        ['U10', 'U11'],
        ['Added game folder', '3 games'],
      );
      await h.close(t);
    },
  );
  testWidgets('U09 source read error can be retried', (t) async {
    final c = SourceStates()..readFails = true;
    await h.show(t, ProductSources(client: c, locale: 'en'));
    await capture(
      t,
      'source-read-failed',
      ['U09', 'U21'],
      ['This source is unavailable', 'Retry'],
    );
    c.readFails = false;
    await h.tap(t, find.text('Retry'));
    await capture(
      t,
      'source-read-restored',
      ['U09'],
      ['My game folder', '12 games'],
    );
    await h.close(t);
  });
  for (final e in {
    'customRefreshPolicy': 'Refresh policy',
    'customTemporalMode': 'Time processing',
    'customSpatialMode': 'Image scaling',
    'customPostEffect': 'Post-processing',
    'aspectMode': 'Aspect ratio',
  }.entries) {
    testWidgets('U15 expanded ${e.key}', (t) async {
      final c = SettingsClient();
      c.values.addAll({
        'videoQualityPreset': 4,
        'customRefreshPolicy': 3,
        'customTemporalMode': 1,
        'customSpatialMode': 2,
        'customPostEffect': 1,
        'aspectMode': 1,
      });
      await h.show(t, settings(c));
      await field(t, 'display', e.key);
      await capture(t, 'chooser-${e.key}', ['U15', 'U21'], [e.value]);
      await h.close(t);
    });
  }
  testWidgets('U17 audio focus chooser', (t) async {
    await h.show(t, settings(SettingsClient()));
    await field(t, 'audio', 'audioFocusPolicy');
    await capture(
      t,
      'chooser-audio-focus',
      ['U17'],
      ['Pause', 'Lower volume', 'Keep playing'],
    );
    await h.close(t);
  });
  testWidgets('U18 applied language updates visible page', (t) async {
    final c = SettingsClient();
    await h.show(t, settings(c));
    await field(t, 'game', 'localeTag');
    await h.tap(t, find.text('Simplified Chinese'));
    expect(c.values['localeTag'], 'zh-Hans');
    await capture(
      t,
      'language-applied-chinese',
      ['U18'],
      ['设置', '简体中文', '自动保存'],
    );
    await h.close(t);
  });
  testWidgets('U19 real supplied version and unconfigured source', (t) async {
    await h.show(t, settings(SettingsClient()));
    await h.tap(t, find.byKey(const ValueKey('section-about')));
    await capture(
      t,
      'about-unconfigured',
      ['U19'],
      ['3.0.6', 'Unavailable', 'Not configured'],
    );
    await h.close(t);
  });
  testWidgets('U16 narrow reset confirmation and completed summary', (t) async {
    final c = SettingsClient()..layoutSummary = 'custom';
    await h.show(t, settings(c), surface: const Size(420, 600), textScale: 2);
    await h.tap(t, find.byKey(const ValueKey('section-controls')));
    await t.scrollUntilVisible(
      find.text('Reset controls'),
      160,
      scrollable: find.descendant(
        of: find.byKey(const PageStorageKey('settings-scroll-controls')),
        matching: find.byType(Scrollable),
      ),
    );
    await h.settle(t);
    await h.tap(t, find.text('Reset controls'));
    await capture(
      t,
      'reset-narrow-confirm',
      ['U16', 'U21'],
      ['Reset controls', 'Confirm', 'Cancel'],
    );
    await h.tap(t, find.text('Confirm'));
    await t.scrollUntilVisible(
      find.text('Edit layout'),
      -160,
      scrollable: find.descendant(
        of: find.byKey(const PageStorageKey('settings-scroll-controls')),
        matching: find.byType(Scrollable),
      ),
    );
    await h.settle(t);
    await capture(t, 'reset-completed', ['U16', 'U22'], ['Recommended layout']);
    await h.close(t);
  });
  testWidgets('U20 long real packaged license scroll', (t) async {
    final c = VisualLicenseClient();
    await h.show(t, ProductLicenses(client: c, locale: 'en'));
    final body = find.byType(SingleChildScrollView);
    final scroll = t.widget<SingleChildScrollView>(body).controller!;
    await t.drag(body, const Offset(0, -320));
    expect(scroll.offset, greaterThan(0));
    await h.settle(t);
    await capture(t, 'license-long-scrolled', ['U20'], []);
    await h.close(t);
  });
  testWidgets('U20 failed component list retries before reading a body', (
    t,
  ) async {
    final c = LicenseClient()..listFails = true;
    await h.show(t, ProductLicenses(client: c, locale: 'en'));
    expect(c.calls, ['licenses']);
    await capture(
      t,
      'license-list-failed',
      ['U20', 'U21'],
      ['Retry', 'This operation could not be completed. Please retry.'],
    );
    c.listFails = false;
    await h.tap(t, find.text('Retry'));
    expect(c.calls, ['licenses', 'licenses', 'licenseText']);
    await capture(
      t,
      'license-list-recovered',
      ['U20'],
      ['Component A', 'License a'],
    );
    await h.close(t);
  });
  for (final unreadable in [false, true]) {
    testWidgets('U16 reset incomplete state unreadable=$unreadable', (t) async {
      final c = SettingsClient()..resetFails = true;
      await h.show(t, settings(c));
      await h.tap(t, find.byKey(const ValueKey('section-controls')));
      await t.scrollUntilVisible(
        find.text('Reset controls'),
        160,
        scrollable: find.descendant(
          of: find.byKey(const PageStorageKey('settings-scroll-controls')),
          matching: find.byType(Scrollable),
        ),
      );
      await h.settle(t);
      await h.tap(t, find.text('Reset controls'));
      c.readFails = unreadable;
      await h.tap(t, find.text('Confirm'));
      await h.tap(t, find.byKey(const ValueKey('section-audio')));
      await capture(
        t,
        unreadable ? 'reset-state-unreadable' : 'reset-partial-authoritative',
        ['U16', 'U17', 'U21'],
        ['Retry'],
      );
      if (unreadable) {
        c.readFails = false;
        await h.tap(t, find.text('Retry'));
        await capture(t, 'reset-state-recovered', ['U16', 'U17'], ['Sound']);
      }
      await h.close(t);
    });
  }
}
