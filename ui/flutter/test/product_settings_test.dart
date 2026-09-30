import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flynes_ui/design_system/app_theme.dart';
import 'package:flynes_ui/design_system/product_switch.dart';
import 'package:flynes_ui/features/product/product_settings.dart';
import 'package:flynes_ui/native_client/product_client.dart';

class SettingsClient implements ProductClient {
  ProductMap values = {
    'audioEnabled': true,
    'audioFocusPolicy': 1,
    'localeTag': 'en',
    'videoQualityPreset': 2,
    'directionMode': 2,
    'hapticLevel': 2,
    'distinctAbHaptics': true,
    'autosaveEnabled': true,
  };
  final calls = <String>[];
  bool fail = false;
  bool resetFails = false;
  bool readFails = false;
  String layoutSummary = 'recommended';
  @override
  Future<ProductMap> bootstrap() async => {};
  @override
  Future<ProductMap> call(String method, [ProductMap args = const {}]) async {
    calls.add(method);
    if (method == 'settings' && readFails) {
      throw const ProductFailure('service_unavailable');
    }
    if (method == 'openNative') layoutSummary = 'custom';
    if (method == 'resetControls') {
      values = {...values, 'directionMode': 2};
      if (resetFails) throw const ProductFailure('storage_failed');
      layoutSummary = 'recommended';
    }
    if (method == 'patchSetting') {
      if (fail) throw const ProductFailure('storage_failed');
      if (args['key'] == 'localeTag' &&
          !const {'system', 'en', 'zh-Hans'}.contains(args['value'])) {
        throw const ProductFailure('invalid_setting');
      }
      values = {...values, args['key'] as String: args['value']};
    }
    return {
      'values': values,
      'capabilities': {},
      'layoutSummary': layoutSummary,
    };
  }

  @override
  void dispose() {}
}

void main() {
  late SettingsClient client;
  setUp(() => client = SettingsClient());
  Future<void> show(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(960, 540));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: ProductSettings(
          client: client,
          locale: 'en',
          onLocaleChanged: (_) {},
          onSources: () {},
          onLicenses: () {},
          version: '3.0.6',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('U14 settings sections restore independent scroll offsets', (
    tester,
  ) async {
    client.values['videoQualityPreset'] = 4;
    await show(tester);
    await tester.binding.setSurfaceSize(const Size(800, 360));
    await tester.pumpAndSettle();
    Finder section(String name) => find.byWidgetPredicate(
      (widget) =>
          widget is ListView &&
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value == 'settings-scroll-$name',
    );
    double offset(String name) =>
        tester.widget<ListView>(section(name)).controller!.offset;
    await tester.drag(section('display'), const Offset(0, -150));
    await tester.pumpAndSettle();
    final displayOffset = offset('display');
    expect(displayOffset, greaterThan(50));
    await tester.tap(find.byKey(const ValueKey('section-controls')));
    await tester.pumpAndSettle();
    await tester.drag(section('controls'), const Offset(0, -100));
    await tester.pumpAndSettle();
    final controlsOffset = offset('controls');
    expect(controlsOffset, greaterThan(20));
    await tester.tap(find.byKey(const ValueKey('section-display')));
    await tester.pumpAndSettle();
    expect(offset('display'), closeTo(displayOffset, 1));
    await tester.tap(find.byKey(const ValueKey('section-controls')));
    await tester.pumpAndSettle();
    expect(offset('controls'), closeTo(controlsOffset, 1));
  });

  testWidgets('U21 single-choice exposes checked state to accessibility', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      await show(tester);
      await tester.tap(
        find.byKey(const ValueKey('setting-videoQualityPreset')),
      );
      await tester.pumpAndSettle();
      final selected = tester
          .getSemantics(
            find.descendant(
              of: find.byType(SimpleDialog),
              matching: find.text('Balanced'),
            ),
          )
          .getSemanticsData();
      final other = tester
          .getSemantics(
            find.descendant(
              of: find.byType(SimpleDialog),
              matching: find.text('Power saver'),
            ),
          )
          .getSemanticsData();
      expect(selected.toString(), contains('isChecked'));
      expect(other.toString(), contains('hasCheckedState'));
      expect(other.toString(), isNot(contains('isChecked')));
    } finally {
      handle.dispose();
    }
  });
  testWidgets('U22 layout summary refreshes after native editor returns', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('section-controls')));
    await tester.pumpAndSettle();
    expect(find.text('Recommended layout'), findsOneWidget);
    await tester.tap(find.text('Edit layout'));
    await tester.pumpAndSettle();
    expect(find.text('Custom layout'), findsOneWidget);
  });
  testWidgets(
    'U16 partial reset rereads authoritative values and reports incomplete reset',
    (tester) async {
      client.values['directionMode'] = 3;
      client.resetFails = true;
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('section-controls')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Reset controls'),
        200,
        scrollable: find.descendant(
          of: find.byKey(const PageStorageKey('settings-scroll-controls')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.text('Reset controls'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(client.calls.where((v) => v == 'settings').length, 2);
      expect(find.textContaining('Reset did not finish'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('setting-directionMode')),
        -200,
        scrollable: find.descendant(
          of: find.byKey(const PageStorageKey('settings-scroll-controls')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('Fixed joystick'), findsOneWidget);
      expect(find.text('D-pad'), findsNothing);
      client.resetFails = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm'), findsOneWidget);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(client.calls.where((v) => v == 'resetControls').length, 2);
      expect(find.textContaining('Reset did not finish'), findsNothing);
    },
  );
  testWidgets(
    'U16 unreadable state after failed reset disables edits until Retry',
    (tester) async {
      client.resetFails = true;
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('section-controls')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Reset controls'),
        200,
        scrollable: find.descendant(
          of: find.byKey(const PageStorageKey('settings-scroll-controls')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.text('Reset controls'));
      await tester.pumpAndSettle();
      client.readFails = true;
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Reload before editing'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('section-audio')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ProductSwitchTile>(
              find.byKey(const ValueKey('setting-audioEnabled')),
            )
            .onChanged,
        isNull,
      );
      client.readFails = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ProductSwitchTile>(
              find.byKey(const ValueKey('setting-audioEnabled')),
            )
            .onChanged,
        isNotNull,
      );
    },
  );
  testWidgets(
    'U18 Chinese uses the native canonical locale and updates current page',
    (tester) async {
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('section-game')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('setting-localeTag')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simplified Chinese'));
      await tester.pumpAndSettle();
      expect(client.values['localeTag'], 'zh-Hans');
      expect(find.text('设置'), findsOneWidget);
      expect(find.text('简体中文'), findsOneWidget);
    },
  );
  testWidgets('U14 five sections remain in approved order', (tester) async {
    await show(tester);
    var previous = -1.0;
    for (final key in ['display', 'controls', 'audio', 'game', 'about']) {
      final position = tester
          .getTopLeft(find.byKey(ValueKey('section-$key')))
          .dy;
      expect(position, greaterThan(previous));
      previous = position;
    }
  });
  testWidgets('U19 missing build metadata is explicitly unavailable', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('section-about')));
    await tester.pumpAndSettle();
    expect(find.text('3.0.6'), findsOneWidget);
    expect(find.text('Build revision'), findsOneWidget);
    expect(find.text('Unavailable'), findsOneWidget);
  });
  testWidgets('U17 failed sound write retains value and persistent error', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('section-audio')));
    await tester.pumpAndSettle();
    client.fail = true;
    await tester.tap(find.byKey(const ValueKey('setting-audioEnabled')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ProductSwitchTile>(
            find.byKey(const ValueKey('setting-audioEnabled')),
          )
          .value,
      isTrue,
    );
    expect(find.textContaining('previous value'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(find.textContaining('previous value'), findsOneWidget);
  });
  testWidgets('U15 Extreme is not silently enabled without device evidence', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('setting-videoQualityPreset')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Extreme'));
    await tester.pumpAndSettle();
    expect(client.calls, isNot(contains('patchSetting')));
    expect(find.textContaining('verified device'), findsWidgets);
  });
  testWidgets(
    'U16 resetting controls requires confirmation and cancel is zero writes',
    (tester) async {
      await show(tester);
      await tester.tap(find.byKey(const ValueKey('section-controls')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Reset controls'),
        200,
        scrollable: find.descendant(
          of: find.byKey(const PageStorageKey('settings-scroll-controls')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.text('Reset controls'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(client.calls, isNot(contains('resetControls')));
    },
  );
}
