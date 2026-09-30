import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flynes_ui/features/product/product_controller.dart';
import 'package:flynes_ui/native_client/product_client.dart';

class FakeProduct implements ProductClient {
  Future<ProductMap> Function(String, ProductMap)? handler;
  Future<ProductMap> Function()? bootstrapHandler;
  final calls = <String>[];
  @override
  Future<ProductMap> bootstrap() async =>
      bootstrapHandler != null ? bootstrapHandler!() : {'protocolVersion': 1};
  @override
  Future<ProductMap> call(String method, [ProductMap args = const {}]) async {
    calls.add(method);
    if (handler != null) return handler!(method, args);
    return {};
  }

  @override
  void dispose() {}
}

ProductMap window(int revision, {int offset = 0, String id = 'a'}) => {
  'catalogGeneration': 7,
  'viewRevision': revision,
  'total': 600,
  'offset': offset,
  'selectedId': id,
  'items': [
    {'canonicalId': id, 'favorite': false},
  ],
};

void main() {
  late FakeProduct client;
  late ProductController controller;
  setUp(() {
    client = FakeProduct();
    controller = ProductController(client);
  });
  tearDown(() => controller.dispose());
  testWidgets(
    'U05 search merges at exactly 150ms and clear/category cancel pending work',
    (tester) async {
      final queries = <ProductMap>[];
      client.handler = (method, args) async {
        if (method == 'catalogQuery') {
          queries.add(Map.of(args));
          return window(queries.length);
        }
        if (method == 'catalogItem') return {'canonicalId': 'a'};
        return {'state': 'none'};
      };
      controller.search('g');
      expect(controller.query, 'g');
      await tester.pump(const Duration(milliseconds: 149));
      expect(queries, isEmpty);
      controller.search('game');
      await tester.pump(const Duration(milliseconds: 149));
      expect(queries, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(queries.single['query'], 'game');
      controller.search('pending-clear');
      await tester.pump(const Duration(milliseconds: 50));
      controller.search('', immediate: true);
      await tester.pump();
      expect(queries.length, 2);
      expect(queries.last['query'], '');
      await tester.pump(const Duration(milliseconds: 150));
      expect(queries.length, 2);
      controller.search('pending-category');
      final changing = controller.changeCategory('builtin');
      await tester.pump();
      await changing;
      expect(queries.length, 3);
      expect(queries.last['category'], 'builtin');
      await tester.pump(const Duration(milliseconds: 150));
      expect(queries.length, 3);
    },
  );
  testWidgets('U05 disposal before debounce fires performs no catalog call', (
    tester,
  ) async {
    final pending = ProductController(client);
    pending.search('discarded');
    await tester.pump(const Duration(milliseconds: 149));
    pending.dispose();
    await tester.pump(const Duration(milliseconds: 500));
    expect(client.calls, isNot(contains('catalogQuery')));
  });
  test(
    'U02 explicit selection survives an overlapping observational refresh',
    () async {
      final oldDetail = Completer<ProductMap>();
      var reads = 0;
      ProductMap? saved;
      client.handler = (method, args) async {
        if (method == 'catalogItem') {
          if (++reads == 1) return oldDetail.future;
          return {'canonicalId': 'b'};
        }
        if (method == 'catalogQuery') return window(3, id: 'b');
        if (method == 'saveNavigation') saved = args;
        return {'state': 'none'};
      };
      final selection = controller.choose('b');
      await controller.refresh();
      oldDetail.complete({'canonicalId': 'b'});
      await selection;
      expect(saved?['selections'], {'all': 'b'});
    },
  );
  test(
    'U02 selecting a card persists canonical selection without category change',
    () async {
      ProductMap? saved;
      client.handler = (method, args) async {
        if (method == 'catalogItem') {
          return {'canonicalId': args['canonicalId']};
        }
        if (method == 'saveNavigation') saved = args;
        return {'state': 'none'};
      };
      await controller.choose('new-card');
      expect(saved?['selections'], {'all': 'new-card'});
    },
  );

  test(
    'category selection invalidates old actionable detail before querying',
    () async {
      controller.selectedId = 'a';
      controller.selected = {'canonicalId': 'a'};
      controller.resumeState = 'available';
      controller.selections['favorites'] = 'b';
      final query = Completer<ProductMap>();
      client.handler = (method, args) async {
        if (method == 'catalogQuery') return query.future;
        if (method == 'catalogItem') {
          return {'canonicalId': args['canonicalId']};
        }
        return {'state': 'none'};
      };
      final changing = controller.changeCategory('favorites');
      unawaited(controller.launch());
      expect(client.calls, isNot(contains('launch')));
      expect(controller.selected, isNull);
      expect(controller.resumeState, 'querying');
      query.complete(window(2, id: 'b'));
      await changing;
      expect(controller.selected!['canonicalId'], 'b');
    },
  );

  test(
    'committed favorite refreshes the current selection and projection',
    () async {
      final mutation = Completer<ProductMap>();
      controller.category = 'favorites';
      controller.selectedId = 'a';
      controller.selected = {'canonicalId': 'a', 'favorite': true};
      controller.total = 2;
      controller.windows[0] = [
        {'canonicalId': 'a'},
        {'canonicalId': 'b'},
      ];
      client.handler = (method, args) async {
        if (method == 'setFavorite') return mutation.future;
        if (method == 'catalogQuery') {
          expect(args['category'], 'favorites');
          expect(args['selectedId'], 'b');
          return {...window(2, id: 'b'), 'total': 1};
        }
        if (method == 'catalogItem') {
          return {'canonicalId': args['canonicalId']};
        }
        return {'state': 'none'};
      };
      final operation = controller.favorite(false);
      await controller.choose('b');
      mutation.complete({'favorite': false});
      await operation;
      expect(
        client.calls.where((method) => method == 'catalogQuery').length,
        1,
      );
      expect(controller.total, 1);
      expect(controller.itemAt(0)!['canonicalId'], 'b');
      expect(controller.selectedId, 'b');
      expect(controller.selected!['canonicalId'], 'b');
    },
  );

  test(
    'selection clears obsolete detail and error even when the new item fails',
    () async {
      final detail = Completer<ProductMap>();
      controller.selectedId = 'a';
      controller.selected = {'canonicalId': 'a', 'favorite': true};
      controller.error = 'old_failure';
      client.handler = (method, args) async => detail.future;
      final choosing = controller.choose('b');
      expect(controller.selectedId, 'b');
      expect(controller.selected, isNull);
      expect(controller.error, isEmpty);
      detail.completeError(const ProductFailure('not_found'));
      await choosing;
      expect(controller.selected, isNull);
      expect(controller.error, 'not_found');
      expect(controller.resumeState, 'unavailable');
    },
  );

  test(
    'older initialization error cannot clear the current loading state',
    () async {
      final oldBootstrap = Completer<ProductMap>();
      final catalog = Completer<ProductMap>();
      var bootstraps = 0;
      client.bootstrapHandler = () async => ++bootstraps == 1
          ? oldBootstrap.future
          : {'protocolVersion': 1, 'instanceId': 'new'};
      client.handler = (method, args) async {
        if (method == 'catalogQuery') return catalog.future;
        if (method == 'catalogItem') {
          return {'canonicalId': args['canonicalId']};
        }
        return {'state': 'none'};
      };
      final first = controller.initialize();
      final second = controller.initialize();
      await Future<void>.delayed(Duration.zero);
      oldBootstrap.completeError(const ProductFailure('stale_response'));
      await first;
      expect(controller.loading, isTrue);
      expect(controller.error, isEmpty);
      catalog.complete(window(2, id: 'b'));
      await second;
      expect(controller.bootstrapData['instanceId'], 'new');
      expect(controller.selectedId, 'b');
      expect(controller.loading, isFalse);
    },
  );

  test(
    'older successful initialization cannot restore obsolete preferences',
    () async {
      final oldBootstrap = Completer<ProductMap>();
      var bootstraps = 0;
      client.bootstrapHandler = () async => ++bootstraps == 1
          ? oldBootstrap.future
          : {
              'protocolVersion': 1,
              'preferences': {'category': 'favorites'},
            };
      client.handler = (method, args) async {
        if (method == 'catalogQuery') return window(2, id: 'b');
        if (method == 'catalogItem') {
          return {'canonicalId': args['canonicalId']};
        }
        return {'state': 'none'};
      };
      final first = controller.initialize();
      await controller.initialize();
      oldBootstrap.complete({
        'protocolVersion': 1,
        'preferences': {'category': 'all'},
      });
      await first;
      expect(controller.category, 'favorites');
      expect(
        client.calls.where((method) => method == 'catalogQuery').length,
        1,
      );
    },
  );

  test(
    'same catalog generation cannot append a window from an older view revision',
    () async {
      controller.catalogGeneration = 7;
      controller.viewRevision = 1;
      final catalog = Completer<ProductMap>();
      final olderWindow = Completer<ProductMap>();
      client.handler = (method, args) async {
        if (method == 'catalogQuery') return catalog.future;
        if (method == 'catalogWindow') return olderWindow.future;
        if (method == 'catalogItem') {
          return {'canonicalId': args['canonicalId']};
        }
        return {'state': 'none'};
      };
      final refresh = controller.refresh();
      final loadingWindow = controller.loadWindow(128);
      catalog.complete(window(2, id: 'b'));
      await refresh;
      olderWindow.complete(window(1, offset: 128));
      await loadingWindow;
      expect(controller.catalogGeneration, 7);
      expect(controller.viewRevision, 2);
      expect(controller.windows.keys, [0]);
      expect(controller.itemAt(0)!['canonicalId'], 'b');
    },
  );

  test(
    'failed mutation from a previous selection cannot replace its new error',
    () async {
      final mutation = Completer<ProductMap>();
      controller.selectedId = 'a';
      client.handler = (method, args) async {
        if (method == 'setFavorite') return mutation.future;
        if (method == 'catalogItem') return {'canonicalId': 'b'};
        return {'state': 'unavailable', 'reason': 'history_unavailable'};
      };
      final operation = controller.favorite(true);
      await controller.choose('b');
      mutation.completeError(const ProductFailure('storage_failed'));
      await operation;
      expect(controller.error, 'history_unavailable');
    },
  );

  test(
    'expired window starts a new query rather than leaving an unusable list',
    () async {
      controller.catalogGeneration = 7;
      controller.viewRevision = 1;
      client.handler = (method, args) async {
        if (method == 'catalogWindow') {
          throw const ProductFailure('snapshot_expired');
        }
        if (method == 'catalogQuery') {
          return {...window(2), 'catalogGeneration': 8};
        }
        if (method == 'catalogItem') return {'canonicalId': 'a'};
        return {'state': 'none'};
      };
      await controller.loadWindow(128);
      expect(controller.catalogGeneration, 8);
      expect(client.calls.where((e) => e == 'catalogQuery').length, 1);
    },
  );

  test(
    'selecting while refresh is pending preserves the newer selection',
    () async {
      final catalog = Completer<ProductMap>();
      client.handler = (method, args) async {
        if (method == 'catalogQuery') return catalog.future;
        if (method == 'catalogItem') {
          return {'canonicalId': args['canonicalId']};
        }
        return {'state': 'available'};
      };
      final refresh = controller.refresh();
      await controller.choose('b');
      catalog.complete(window(2, id: 'a'));
      await refresh;
      expect(controller.selectedId, 'b');
      expect(controller.selected!['canonicalId'], 'b');
    },
  );

  test(
    'window requested during refresh cannot append an old generation afterwards',
    () async {
      controller.catalogGeneration = 7;
      controller.viewRevision = 1;
      final catalog = Completer<ProductMap>();
      final olderWindow = Completer<ProductMap>();
      client.handler = (method, args) async {
        if (method == 'catalogQuery') return catalog.future;
        if (method == 'catalogWindow') return olderWindow.future;
        if (method == 'catalogItem') {
          return {'canonicalId': args['canonicalId']};
        }
        return {'state': 'none'};
      };
      final refresh = controller.refresh();
      final loadingWindow = controller.loadWindow(128);
      catalog.complete({...window(2), 'catalogGeneration': 8});
      await refresh;
      olderWindow.complete(window(1, offset: 128));
      await loadingWindow;
      expect(controller.catalogGeneration, 8);
      expect(controller.windows.keys, [0]);
    },
  );

  test(
    'older catalog responses never overwrite newer category results',
    () async {
      final old = Completer<ProductMap>();
      client.handler = (m, a) async {
        if (m == 'catalogQuery') {
          return a['category'] == 'all' ? old.future : window(2, id: 'b');
        }
        if (m == 'catalogItem') return {'canonicalId': a['canonicalId']};
        return {'state': 'none'};
      };
      final first = controller.refresh();
      controller.category = 'favorites';
      await controller.refresh();
      old.complete(window(1));
      await first;
      expect(controller.selectedId, 'b');
      expect(controller.viewRevision, 2);
    },
  );

  test(
    'same ID selected twice still rejects the first capability result',
    () async {
      final old = Completer<ProductMap>();
      var requests = 0;
      client.handler = (m, a) async {
        if (m == 'catalogItem') return {'canonicalId': 'a'};
        if (m == 'resumeCapability') {
          return ++requests == 1 ? old.future : {'state': 'available'};
        }
        return {};
      };
      final first = controller.choose('a');
      await Future<void>.delayed(Duration.zero);
      await controller.choose('a');
      old.complete({'state': 'none'});
      await first;
      expect(controller.resumeState, 'available');
    },
  );

  test('paged results retain at most three windows', () async {
    controller.catalogGeneration = 7;
    controller.viewRevision = 1;
    client.handler = (m, a) async =>
        window(1, offset: a['offset'] as int? ?? 0);
    for (final offset in [0, 128, 256, 384]) {
      await controller.loadWindow(offset);
    }
    expect(controller.windows.length, 3);
    expect(controller.windows.containsKey(0), isFalse);
  });

  test(
    'window from another catalog cannot be joined to current snapshot',
    () async {
      controller.catalogGeneration = 7;
      controller.viewRevision = 1;
      client.handler = (m, a) async {
        if (m == 'catalogQuery') throw const ProductFailure('snapshot_expired');
        return {...window(1), 'catalogGeneration': 8};
      };
      await controller.loadWindow(128);
      expect(controller.windows, isEmpty);
      expect(controller.error, 'snapshot_expired');
    },
  );

  test('repeated launch while native owns the route submits once', () async {
    final route = Completer<ProductMap>();
    controller.selectedId = 'a';
    controller.selected = {'canonicalId': 'a'};
    controller.resumeState = 'none';
    client.handler = (m, a) async {
      if (m == 'launch') return route.future;
      if (m == 'catalogQuery') return window(2);
      return {'state': 'available'};
    };
    final first = controller.launch();
    final second = controller.launch();
    route.complete({'status': 'returned'});
    await Future.wait([first, second]);
    expect(client.calls.where((m) => m == 'launch').length, 1);
    expect(client.calls, contains('catalogQuery'));
  });

  test(
    'failed favorite keeps authoritative value and exposes stable error',
    () async {
      controller.selectedId = 'a';
      controller.selected = {'canonicalId': 'a', 'favorite': false};
      client.handler = (m, a) async =>
          throw const ProductFailure('storage_failed');
      await controller.favorite(true);
      expect(controller.selected!['favorite'], false);
      expect(controller.error, 'storage_failed');
    },
  );
}
