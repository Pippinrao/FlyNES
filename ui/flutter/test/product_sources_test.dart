import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flynes_ui/design_system/app_theme.dart';
import 'package:flynes_ui/features/product/product_sources.dart';
import 'package:flynes_ui/native_client/product_client.dart';

class SourceClient implements ProductClient, ProductEventSource {
  final changes = StreamController<ProductMap>.broadcast();
  @override
  Stream<ProductMap> get events => changes.stream;
  final calls = <String>[];
  ProductMap? folderSelection;
  bool removeFails = false;
  bool cleanupFails = false;
  Completer<void>? removal;
  final rows = <ProductMap>[
    {
      'uuid': 'builtin',
      'name': 'Built-in',
      'type': 'builtin',
      'count': 7,
      'status': 'ready',
      'builtin': true,
    },
    {
      'uuid': 'local',
      'name': 'My games',
      'type': 'directory',
      'count': 12,
      'status': 'ready',
      'builtin': false,
      'canReauthorize': true,
      'canCancel': false,
    },
  ];
  @override
  Future<ProductMap> bootstrap() async => {};
  @override
  Future<ProductMap> call(String method, [ProductMap args = const {}]) async {
    calls.add(method);
    if (method == 'sources') {
      return {
        'items': rows,
        if (folderSelection != null) 'folderSelection': folderSelection,
      };
    }
    if (method == 'pickSource') return {'status': 'cancelled'};
    if (method == 'removeSource' && removeFails) {
      throw const ProductFailure('storage_failed');
    }
    if (method == 'removeSource' && cleanupFails) {
      rows.removeWhere((row) => row['uuid'] == args['uuid']);
      throw const ProductFailure('source_cleanup_failed');
    }
    if (method == 'removeSource' && removal != null) {
      await removal!.future;
      rows.removeWhere((row) => row['uuid'] == args['uuid']);
    }
    return {};
  }

  @override
  void dispose() {}
}

void main() {
  late SourceClient client;
  setUp(() => client = SourceClient());
  tearDown(() => client.changes.close());
  Future<void> show(WidgetTester tester, {bool scanning = false}) async {
    await tester.binding.setSurfaceSize(const Size(960, 540));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: ProductSources(client: client, locale: 'en'),
      ),
    );
    if (scanning) {
      // An unknown-progress scan keeps scheduling spinner frames by design.
      // Advance beyond its delay/row transition without waiting for it to stop.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
    } else {
      await tester.pumpAndSettle();
    }
  }

  testWidgets(
    'U10 unsupported directory picker explains capability and retains file import',
    (tester) async {
      client.folderSelection = {
        'available': false,
        'reason': 'folder_selection_unsupported',
      };
      await show(tester);
      final folder = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Add folder'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(folder.onPressed, isNull);
      expect(
        find.text(
          'Folder selection is unavailable on this system. Add files or ZIP archives instead.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Add file'));
      await tester.pumpAndSettle();
      expect(
        client.calls.where((method) => method == 'pickSource'),
        hasLength(1),
      );
    },
  );

  for (final entry in {
    'cancelled': 'Scan cancelled. Previous library retained.',
    'partial': 'Some files could not be imported',
    'failed': 'Scan failed. Previous library retained.',
    'unavailable': 'Source unavailable',
  }.entries) {
    testWidgets('U11 empty OH transport phase preserves ${entry.key} status', (
      tester,
    ) async {
      client.rows[1].addAll({'phase': '', 'status': entry.key});
      await show(tester);
      expect(find.text(entry.value), findsOneWidget);
    });
  }
  testWidgets('U09 missing provider name has localized fallback', (
    tester,
  ) async {
    client.rows[1]['name'] = '';
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: ProductSources(client: client, locale: 'zh-CN'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('source-local')),
        matching: find.text('游戏来源'),
      ),
      findsOneWidget,
    );
    expect(find.text('Game source'), findsNothing);
  });
  testWidgets(
    'U09 source projection event updates late provider name and disposes observation',
    (tester) async {
      await show(tester);
      client.rows[1]['name'] = 'Resolved provider name';
      client.changes.add({
        'event': 'projectionChanged',
        'domains': ['sources'],
      });
      await tester.pumpAndSettle();
      expect(find.text('Resolved provider name'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      final count = client.calls.length;
      client.changes.add({
        'event': 'projectionChanged',
        'domains': ['sources'],
      });
      await tester.pump();
      expect(client.calls.length, count);
    },
  );
  for (final phase in [
    'queued',
    'enumerating',
    'ingesting',
    'scanning',
    'cancelling',
    'committing',
  ]) {
    testWidgets(
      'U11 $phase prevents a second scan while retaining observation',
      (tester) async {
        client.rows[1]['phase'] = phase;
        await show(tester, scanning: true);
        final button = tester.widget<TextButton>(
          find.ancestor(
            of: find.text('Scan'),
            matching: find.byType(TextButton),
          ),
        );
        expect(button.onPressed, isNull);
        await tester.tap(find.text('Scan'));
        expect(client.calls, isNot(contains('scanSource')));
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('U10 cancelled picker keeps source list and does not scan', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.text('Add folder'));
    await tester.pumpAndSettle();
    expect(find.text('My games'), findsOneWidget);
    expect(client.calls, isNot(contains('scanSource')));
  });
  testWidgets(
    'U09 short landscape at 200 percent keeps both columns actions reachable',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 360));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(800, 360),
              textScaler: TextScaler.linear(2),
            ),
            child: ProductSources(client: client, locale: 'en'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Add folder'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Add folder').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Add folder'));
      await tester.pumpAndSettle();
      expect(client.calls, contains('pickSource'));
      await tester.scrollUntilVisible(
        find.text('Remove'),
        160,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('Remove').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'U11 background stops observation without cancelling owned scan',
    (tester) async {
      client.rows[1]['phase'] = 'queued';
      await show(tester);
      final before = client.calls.where((m) => m == 'sources').length;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 2));
      expect(client.calls.where((m) => m == 'sources').length, before);
      expect(client.calls, isNot(contains('cancelScan')));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(client.calls.where((m) => m == 'sources').length, before + 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('U11 idle transport phase does not hide failed scan result', (
    tester,
  ) async {
    client.rows[1].addAll({'phase': 'idle', 'status': 'failed'});
    await show(tester);
    expect(
      find.text('Scan failed. Previous library retained.'),
      findsOneWidget,
    );
  });
  testWidgets(
    'U11 committed scan refresh failure never claims old library was retained',
    (tester) async {
      client.rows[1].addAll({
        'phase': 'failed',
        'reason': 'scan_committed_refresh_failed',
      });
      await show(tester);
      expect(find.textContaining('Previous library retained'), findsNothing);
      expect(find.textContaining('The scan was saved'), findsOneWidget);
    },
  );
  testWidgets(
    'U11 queued operation is observed through completion without restarting',
    (tester) async {
      client.rows[1].addAll({
        'phase': 'queued',
        'operationId': 'scan-1',
        'canCancel': true,
      });
      await show(tester);
      expect(find.text('Waiting to scan…'), findsOneWidget);
      final initialReads = client.calls.where((e) => e == 'sources').length;
      client.rows[1] = {
        ...client.rows[1],
        'phase': 'completed',
        'count': 13,
        'canCancel': false,
      };
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(
        client.calls.where((e) => e == 'sources').length,
        greaterThan(initialReads),
      );
      expect(find.text('13 games'), findsOneWidget);
      expect(client.calls, isNot(contains('scanSource')));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('U11 committing cannot cancel even with stale capability flag', (
    tester,
  ) async {
    client.rows[1].addAll({'phase': 'committing', 'canCancel': true});
    await show(tester);
    expect(find.text('Finishing…'), findsOneWidget);
    expect(find.text('Cancel scan'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'A13 known scan progress interpolates for 120 ms without a fake total',
    (tester) async {
      client.rows[1].addAll({
        'phase': 'ingesting',
        'completed': 1,
        'total': 10,
      });
      await show(tester);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .1,
      );
      client.rows[1] = {...client.rows[1], 'completed': 5};
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .1,
      );
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        closeTo(.3, .01),
      );
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .5,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('U13 failed confirmed removal retains source row', (
    tester,
  ) async {
    await show(tester);
    client.removeFails = true;
    await tester.tap(find.byKey(const ValueKey('remove-local')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(find.text('My games'), findsOneWidget);
    expect(find.textContaining('previous value'), findsOneWidget);
    expect(find.byKey(const ValueKey('remove-builtin')), findsNothing);
  });
  testWidgets(
    'U21 background source observation cannot dismiss a failed operation',
    (tester) async {
      client.rows[0]['phase'] = 'queued';
      await show(tester);
      client.removeFails = true;
      await tester.tap(find.byKey(const ValueKey('remove-local')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(find.textContaining('previous value'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.textContaining('previous value'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('U13 cancellation performs no remove write', (tester) async {
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('remove-local')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(client.calls, isNot(contains('removeSource')));
  });
  testWidgets(
    'U13 committed deletion with cleanup failure refreshes authoritative rows and preserves warning',
    (tester) async {
      await show(tester);
      client.cleanupFails = true;
      await tester.tap(find.byKey(const ValueKey('remove-local')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(find.text('My games'), findsNothing);
      expect(find.textContaining('cleanup'), findsOneWidget);
    },
  );
  testWidgets('A12 source removal waits for service then shrinks over 180 ms', (
    tester,
  ) async {
    client.removal = Completer<void>();
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('remove-local')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('source-local'));
    expect(
      row,
      findsOneWidget,
      reason: 'Unacknowledged removals remain visible.',
    );
    client.removal!.complete();
    await tester.pump();
    await tester.pump();
    expect(
      row,
      findsOneWidget,
      reason: 'Acknowledged removal begins a visible exit transition.',
    );
    final transition = find
        .ancestor(of: row, matching: find.byType(SizeTransition))
        .first;
    expect(tester.widget<SizeTransition>(transition).sizeFactor.value, 1);
    await tester.pump(const Duration(milliseconds: 90));
    expect(
      tester.widget<SizeTransition>(transition).sizeFactor.value,
      closeTo(.5, .01),
    );
    await tester.pump(const Duration(milliseconds: 106));
    expect(row, findsNothing);
  });
  testWidgets('U18 built-in source name follows application language', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: ProductSources(client: client, locale: 'zh-CN'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('内置'), findsOneWidget);
    expect(find.text('Built-in'), findsNothing);
    expect(
      find.text('My games'),
      findsOneWidget,
      reason: 'User source names are not translated.',
    );
  });
}
