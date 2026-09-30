import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flynes_ui/app/product_app.dart';
import 'package:flynes_ui/design_system/product_strings.dart';
import 'package:flynes_ui/features/product/product_hall.dart';
import 'package:flynes_ui/native_client/product_client.dart';
import 'product_app_test.dart' show AppClient;

class PseudoAppClient extends AppClient {
  PseudoAppClient(this.language, {this.preference});
  final String? preference;
  final String language;
  final requests = <ProductMap>[];
  @override
  Future<ProductMap> bootstrap() async => {
    ...await super.bootstrap(),
    'locale': language,
    if (preference != null) 'localePreference': preference,
  };
  @override
  Future<ProductMap> call(String method, [ProductMap args = const {}]) async {
    requests.add(args);
    return super.call(method, args);
  }
}

void main() {
  testWidgets('resolved native bootstrap retains raw system preference', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localesTestValue = const [
      Locale('en', 'XA'),
    ];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    final client = PseudoAppClient('en-XA', preference: 'system');
    await tester.pumpWidget(ProductApp(client: client));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(ProductHall));
    expect(
      tester.widget<ProductHall>(find.byType(ProductHall)).controller.locale,
      'system',
    );
    expect(Localizations.localeOf(context), const Locale('en', 'XA'));
    expect(ProductStrings(context, 'system').category('all'), startsWith('['));
    await tester.pumpWidget(const SizedBox());
  });

  Future<ProductStrings> strings(WidgetTester tester, String preference) async {
    late ProductStrings result;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en', 'XA'),
        supportedLocales: const [Locale('en', 'XA')],
        home: Builder(
          builder: (context) {
            result = ProductStrings(context, preference);
            return const SizedBox();
          },
        ),
      ),
    );
    return result;
  }

  testWidgets(
    'debug en-XA accents, expands and marks English product strings',
    (tester) async {
      final s = await strings(tester, 'system');
      const english = 'Audio focus policy';
      final value = s.text(english, '音频焦点');
      expect(value, startsWith('['));
      expect(value, endsWith(']'));
      expect(value, contains('Áúdíó'));
      expect(value.length, greaterThanOrEqualTo((english.length * 1.3).ceil()));
      expect(s.text('', ''), isEmpty);
      expect(s.category('all'), isNot('All'));
      expect(s.error('storage_failed'), startsWith('['));
    },
  );

  for (final preference in ['en', 'zh-Hans', 'zh-CN']) {
    testWidgets('explicit $preference overrides en-XA system locale', (
      tester,
    ) async {
      final s = await strings(tester, preference);
      expect(s.text('Sound', '声音'), preference == 'en' ? 'Sound' : '声音');
    });
  }

  for (final preference in ['system', 'en', 'zh-Hans']) {
    testWidgets(
      'ProductApp resolves en-XA only for system preference $preference',
      (tester) async {
        tester.binding.platformDispatcher.localesTestValue = const [
          Locale('en', 'XA'),
        ];
        addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
        final client = PseudoAppClient(preference);
        await tester.pumpWidget(ProductApp(client: client));
        await tester.pumpAndSettle();
        final hall = tester.widget<ProductHall>(find.byType(ProductHall));
        final locale = Localizations.localeOf(
          tester.element(find.byType(ProductHall)),
        );
        expect(
          locale,
          preference == 'system'
              ? const Locale('en', 'XA')
              : preference == 'en'
              ? const Locale('en')
              : const Locale('zh', 'CN'),
        );
        expect(hall.controller.locale, preference);
        await hall.controller.saveNavigation();
        expect(
          client.requests.any((args) => args.values.contains('en-XA')),
          isFalse,
        );
        final labels = tester
            .widgetList<Tooltip>(find.byType(Tooltip))
            .map((w) => w.message ?? '')
            .join();
        expect(labels.contains('['), preference == 'system');
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
