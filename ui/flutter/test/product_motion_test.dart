import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flynes_ui/design_system/product_dialogs.dart';
import 'package:flynes_ui/design_system/product_motion.dart';
import 'package:flynes_ui/design_system/product_button.dart';
import 'package:flynes_ui/design_system/app_theme.dart';
import 'package:flynes_ui/design_system/product_switch.dart';
import 'package:flynes_ui/design_system/product_notice.dart';
import 'package:flynes_ui/design_system/product_animated_rows.dart';
import 'package:flynes_ui/app/product_app.dart';
import 'product_app_test.dart' show AppClient;

void main() {
  testWidgets(
    'A01 disabled semantics and keyboard focus update in the same frame',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var enabled = true;
      late StateSetter update;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return Center(
                  child: ProductButton.filled(
                    onPressed: enabled ? () {} : null,
                    child: const Text('Act'),
                  ),
                );
              },
            ),
          ),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        update(() => enabled = false);
        await tester.pump();
        final data = tester
            .getSemantics(find.byType(FilledButton))
            .getSemanticsData();

        expect(data.flagsCollection.isEnabled, ui.Tristate.isFalse);
        expect(data.hasAction(ui.SemanticsAction.tap), isFalse);
        // FocusManager applies focus changes in a microtask, then updates semantics.
        await tester.pump();
        expect(
          tester
              .getSemantics(find.byType(FilledButton))
              .getSemanticsData()
              .flagsCollection
              .isFocused,
          isNot(ui.Tristate.isTrue),
        );
      } finally {
        semantics.dispose();
      }
    },
  );
  for (final target in ['Settings', 'Sources']) {
    for (final interruption in ['return', 'background', 'dispose']) {
      testWidgets(
        'A07 A08 $target $interruption at entry midpoint preserves product ownership',
        (tester) async {
          final client = AppClient();
          await tester.pumpWidget(ProductApp(client: client));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip(target));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 110));

          // Read the real route from its visible page; no synthetic substitute transition.
          final destination = find.text(target).last;
          final route = ModalRoute.of(tester.element(destination))!;
          expect(route.animation!.value, closeTo(.5, .01));
          if (interruption == 'dispose') {
            await tester.pumpWidget(const SizedBox());
            await tester.pump(const Duration(seconds: 1));
            expect(find.text('My game'), findsNothing);
          } else {
            if (interruption == 'background') {
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.paused,
              );
              await tester.pump(const Duration(milliseconds: 110));
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.resumed,
              );
              await tester.pumpAndSettle();
            }
            await tester.binding.handlePopRoute();
            await tester.pumpAndSettle();
            expect(find.byTooltip('Settings').hitTestable(), findsOneWidget);
            expect(find.byTooltip('Sources').hitTestable(), findsOneWidget);
            expect(find.text('My game'), findsWidgets);
          }
          expect(client.calls, isNot(contains('launch')));
          expect(client.calls, isNot(contains('patchSetting')));
          expect(client.calls, isNot(contains('removeSource')));
          expect(client.calls, isNot(contains('closeHost')));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'A01 disabling and disposing during press cannot activate a retired action',
    (tester) async {
      var enabled = true;
      var calls = 0;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Center(
                child: ProductButton.filled(
                  onPressed: enabled ? () => calls++ : null,
                  child: const Text('Act'),
                ),
              );
            },
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Act')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      update(() => enabled = false);
      await tester.pump();
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 120));
      expect(calls, 0);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      update(() => enabled = true);
      await tester.pump();
      final retired = await tester.startGesture(
        tester.getCenter(find.text('Act')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pumpWidget(const SizedBox());
      await retired.up();
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'A10 Escape at entry midpoint cancels without confirmation and returns focus',
    (tester) async {
      final origin = FocusNode();
      addTearDown(origin.dispose);
      late BuildContext host;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              host = context;
              return Scaffold(body: TextField(focusNode: origin));
            },
          ),
        ),
      );
      origin.requestFocus();
      await tester.pump();
      final result = productDialog<bool>(
        host,
        AlertDialog(
          title: const Text('Pending confirmation'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(host).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(host).pop(true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      final route = ModalRoute.of(
        tester.element(find.text('Pending confirmation')),
      )!;
      expect(route.animation!.value, closeTo(.5, .01));
      expect(origin.hasFocus, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        ModalRoute.of(FocusManager.instance.primaryFocus!.context!),
        same(route),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(await result, isNull);
      expect(find.text('Pending confirmation'), findsNothing);
      expect(origin.hasFocus, isTrue);
    },
  );
  testWidgets(
    'A12 a UUID reappearing during removal has one active action and clean final rows',
    (tester) async {
      var rows = ['a', 'b'];
      late StateSetter update;
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return ProductAnimatedRows<String>(
                items: rows,
                identity: (s) => s,
                builder: (s) => TextButton(
                  onPressed: () => taps++,
                  child: Text('Source $s'),
                ),
              );
            },
          ),
        ),
      );
      update(() => rows = ['b']);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(find.text('Source a'), findsOneWidget);
      expect(find.text('Source a').hitTestable(), findsNothing);
      update(() => rows = ['a', 'b']);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(find.text('Source a').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Source a').hitTestable());
      expect(taps, 1);
      await tester.pumpAndSettle();
      expect(find.text('Source a'), findsOneWidget);
      expect(find.text('Source b'), findsOneWidget);
    },
  );
  testWidgets(
    'A13 disposing before delay and replacing work never reuses an old spinner timer',
    (tester) async {
      Widget work(String id) => MaterialApp(
        home: DeferredProgress(key: ValueKey(id), label: id),
      );
      await tester.pumpWidget(work('old work'));
      await tester.pump(const Duration(milliseconds: 90));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(work('first'));
      await tester.pump(const Duration(milliseconds: 90));
      await tester.pumpWidget(work('replacement'));
      await tester.pump(const Duration(milliseconds: 149));
      expect(find.text('first'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'A14 midpoint replacement cancels old expiry and background cannot resurrect it',
    (tester) async {
      var message = '';
      late StateSetter update;
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return ProductNotice(message: message, error: false);
            },
          ),
        ),
      );
      update(() => message = 'First notice');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      update(() => message = 'Replacement notice');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final tree = tester
          .binding
          .renderViews
          .first
          .owner!
          .semanticsOwner!
          .rootSemanticsNode!
          .toStringDeep();
      expect(tree, isNot(contains('First notice')));
      expect(tree, contains('Replacement notice'));
      await tester.pump(const Duration(milliseconds: 2840));
      expect(find.text('Replacement notice'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(milliseconds: 500));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('First notice'), findsNothing);
      expect(find.text('Replacement notice'), findsNothing);
      update(() => message = 'Dispose in entry');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 4));
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
  testWidgets(
    'A01 newly enabled button never paints disabled fill with enabled text',
    (tester) async {
      var enabled = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return ProductButton.filled(
                onPressed: enabled ? () {} : null,
                child: const Text('Start'),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      update(() => enabled = true);
      await tester.pump();
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.style!.backgroundColor!.resolve({}), AppTheme.accent);
    },
  );
  testWidgets(
    'A17 changing accessibility during dialog entry settles its painted transition',
    (tester) async {
      final reduce = ValueNotifier(false);
      addTearDown(reduce.dispose);
      late BuildContext host;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => ValueListenableBuilder<bool>(
            valueListenable: reduce,
            builder: (context, value, _) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: value),
              child: child!,
            ),
          ),
          home: Builder(
            builder: (context) {
              host = context;
              return const SizedBox();
            },
          ),
        ),
      );
      productDialog<void>(
        host,
        const AlertDialog(content: Text('Confirm change')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      reduce.value = true;
      await tester.pump();
      final fade = tester
          .widgetList<FadeTransition>(
            find.ancestor(
              of: find.text('Confirm change'),
              matching: find.byType(FadeTransition),
            ),
          )
          .first;
      expect(fade.opacity.value, 1);
      final scale = tester
          .widgetList<ScaleTransition>(
            find.ancestor(
              of: find.text('Confirm change'),
              matching: find.byType(ScaleTransition),
            ),
          )
          .first;
      expect(scale.scale.value, 1);
      Navigator.of(host).pop();
      await tester.pumpAndSettle();
    },
  );
  test('G2 error and progress colors use the approved dark palette', () {
    final theme = AppTheme.dark();
    expect(theme.colorScheme.error, const Color(0xFFFF6B6B));
    expect(theme.progressIndicatorTheme.linearTrackColor, AppTheme.selected);
    expect(theme.progressIndicatorTheme.color, AppTheme.accent);
  });
  testWidgets(
    'A17 enabling reduced motion during transitions paints final geometry immediately',
    (tester) async {
      var reduce = false;
      var changed = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return MediaQuery(
                data: MediaQueryData(disableAnimations: reduce),
                child: Column(
                  children: [
                    ProductSwitch(
                      value: changed,
                      label: 'Audio',
                      onChanged: (_) {},
                    ),
                    ProductProgress(value: changed ? .9 : .1),
                    ProductNotice(
                      message: changed ? 'New message' : 'Old message',
                    ),
                    Expanded(
                      child: ProductAnimatedRows<String>(
                        items: changed ? ['b'] : ['a', 'b'],
                        identity: (s) => s,
                        builder: (s) => SizedBox(height: 100, child: Text(s)),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      update(() => changed = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final thumb = find.byKey(const ValueKey('product-switch-thumb'));
      final midway = tester.getCenter(thumb);
      update(() => reduce = true);
      await tester.pump();
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .9,
      );
      final terminal = tester.getCenter(thumb);
      expect(terminal.dx, greaterThan(midway.dx));
      expect(find.text('Old message'), findsNothing);
      final retiring = find.ancestor(
        of: find.text('a'),
        matching: find.byType(SizeTransition),
      );
      if (retiring.evaluate().isNotEmpty) {
        expect(tester.getSize(retiring.first).height, 0);
      }
      expect(find.text('a').hitTestable(), findsNothing);
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.getCenter(thumb), terminal);
    },
  );
  testWidgets(
    'A01 rendered press color interpolates, not only configured duration',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Center(
            child: ProductButton.filled(
              onPressed: () {},
              child: const Text('Continue'),
            ),
          ),
        ),
      );
      Color color() => tester
          .widgetList<Material>(
            find.descendant(
              of: find.byType(ProductButton),
              matching: find.byType(Material),
            ),
          )
          .first
          .color!;
      final before = color();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ProductButton)),
      );
      await tester.pump();
      expect(color(), before);
      await tester.pump(const Duration(milliseconds: 40));
      final middle = color();
      expect(middle, isNot(before));
      await tester.pump(const Duration(milliseconds: 40));
      expect(color(), isNot(middle));
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(color(), before);
    },
  );
  testWidgets(
    'A14 outgoing message immediately releases actions and semantics',
    (tester) async {
      var message = 'Old failure';
      var retries = 0;
      late StateSetter update;
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return ProductNotice(
                  message: message,
                  actionLabel: 'Retry',
                  onAction: () => ++retries,
                );
              },
            ),
          ),
        ),
      );
      update(() => message = '');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        find.text('Retry'),
        findsOneWidget,
        reason: 'The old message is still fading visually.',
      );
      await tester.tap(find.text('Retry'), warnIfMissed: false);
      expect(retries, 0);
      expect(
        tester
            .binding
            .renderViews
            .first
            .owner!
            .semanticsOwner!
            .rootSemanticsNode!
            .toStringDeep(),
        isNot(contains('Old failure')),
      );
      semantics.dispose();
    },
  );
  testWidgets('A12 removed row immediately releases keyboard focus', (
    tester,
  ) async {
    var rows = ['a', 'b'];
    var activations = 0;
    final focus = FocusNode();
    addTearDown(focus.dispose);
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return ProductAnimatedRows<String>(
              items: rows,
              identity: (s) => s,
              builder: (s) => TextButton(
                focusNode: s == 'a' ? focus : null,
                onPressed: () => ++activations,
                child: Text(s),
              ),
            );
          },
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    update(() => rows = ['b']);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(activations, 0);
    expect(focus.hasFocus, isFalse);
  });
  testWidgets(
    'A17 reduced motion switches and rows settle immediately; keyboard activation works',
    (tester) async {
      bool value = false;
      var rows = ['a', 'b'];
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return Column(
                  children: [
                    ProductSwitch(
                      value: value,
                      label: 'Audio',
                      onChanged: (next) => setState(() => value = next),
                    ),
                    Expanded(
                      child: ProductAnimatedRows<String>(
                        items: rows,
                        identity: (s) => s,
                        builder: (s) => Text(s),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      final thumb = find.byKey(const ValueKey('product-switch-thumb'));
      final before = tester.getCenter(thumb);
      await tester.tap(find.byType(ProductSwitch));
      await tester.pump();
      expect(value, isTrue);
      expect(tester.getCenter(thumb).dx, greaterThan(before.dx));
      for (final animation in tester.widgetList<AnimatedAlign>(
        find.byType(AnimatedAlign),
      )) {
        expect(animation.duration, Duration.zero);
      }
      for (final button in tester.widgetList<TextButton>(
        find.byType(TextButton),
      )) {
        expect(button.style?.animationDuration, Duration.zero);
      }
      update(() => rows = ['b']);
      await tester.pumpAndSettle();
      expect(find.text('a'), findsNothing);
      expect(find.text('b'), findsOneWidget);
    },
  );
  testWidgets(
    'A12 same identity updates once and detached list cancels transitions',
    (tester) async {
      var rows = ['a:one'];
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return ProductAnimatedRows<String>(
                items: rows,
                identity: (s) => s.split(':').first,
                builder: Text.new,
              );
            },
          ),
        ),
      );
      update(() => rows = ['a:two']);
      await tester.pump();
      expect(find.text('a:one'), findsNothing);
      expect(find.text('a:two'), findsOneWidget);
      update(() => rows = ['a:two', 'b:new']);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'A14 accessible success persists; messages do not move keyboard focus',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      var message = '';
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(accessibleNavigation: true),
            child: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return Column(
                  children: [
                    Material(child: TextField(focusNode: focus)),
                    ProductNotice(message: message, error: false),
                  ],
                );
              },
            ),
          ),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      update(() => message = 'Copied');
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isTrue);
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('Copied'), findsOneWidget);
      expect(focus.hasFocus, isTrue);
    },
  );
  testWidgets('A10 dialog enters in 180 ms and leaves in 120 ms', (
    tester,
  ) async {
    late BuildContext host;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            host = context;
            return const SizedBox();
          },
        ),
      ),
    );
    productDialog<void>(host, const AlertDialog(content: Text('Confirmation')));
    await tester.pump();
    final route = ModalRoute.of(tester.element(find.text('Confirmation')))!;
    expect(route.transitionDuration, const Duration(milliseconds: 180));
    expect(route.reverseTransitionDuration, const Duration(milliseconds: 120));
    expect(route.animation!.value, 0);
    await tester.pump(const Duration(milliseconds: 90));
    expect(route.animation!.value, closeTo(.5, .01));
    await tester.pump(const Duration(milliseconds: 90));
    expect(route.animation!.value, 1);
    Navigator.of(host).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(route.animation!.value, closeTo(.5, .01));
    await tester.pumpAndSettle();
    expect(find.text('Confirmation'), findsNothing);
  });
  testWidgets('A13 fast work does not flash progress; disposal cancels delay', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: DeferredProgress(label: 'Reading')),
    );
    await tester.pump(const Duration(milliseconds: 149));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'A17 reduced motion has static loading and zero dialog transition',
    (tester) async {
      late BuildContext host;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: Builder(
            builder: (context) {
              host = context;
              return const DeferredProgress(label: 'Reading');
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Reading'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      productDialog<void>(
        host,
        const AlertDialog(content: Text('Confirmation')),
      );
      await tester.pumpAndSettle();
      final route = ModalRoute.of(tester.element(find.text('Confirmation')))!;
      expect(route.transitionDuration, Duration.zero);
      expect(route.reverseTransitionDuration, Duration.zero);
    },
  );
}
