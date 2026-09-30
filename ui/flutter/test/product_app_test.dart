import 'dart:async';
import 'dart:ui' as ui;
import 'dart:ui' show FrameTiming;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flynes_ui/app/product_app.dart';
import 'package:flynes_ui/features/product/product_settings.dart';
import 'package:flynes_ui/native_client/product_client.dart';

class AppClient implements ProductClient {
  final calls = <String>[];
  @override
  Future<ProductMap> bootstrap() async => {
    'locale': 'en',
    'version': '3.0.6',
    'context': {'route': 'hall', 'purpose': 'single'},
  };
  @override
  Future<ProductMap> call(String method, [ProductMap args = const {}]) async {
    calls.add(method);
    if (method == 'catalogQuery') {
      return {
        'catalogGeneration': 1,
        'viewRevision': 1,
        'total': 1,
        'offset': 0,
        'selectedId': 'a',
        'items': [
          {
            'canonicalId': 'a',
            'titleEn': 'My game',
            'favorite': false,
            'available': true,
          },
        ],
      };
    }
    if (method == 'catalogItem') {
      return {'canonicalId': 'a', 'titleEn': 'My game', 'available': true};
    }
    if (method == 'resumeCapability') return {'state': 'none'};
    if (method == 'settings') {
      return {
        'values': {'localeTag': 'en', 'videoQualityPreset': 2},
        'capabilities': {},
      };
    }
    if (method == 'sources' || method == 'licenses') return {'items': []};
    return {};
  }

  @override
  void dispose() {}
}

class HostClient extends AppClient implements ProductEventSource {
  final changes = StreamController<ProductMap>.broadcast();
  String route = 'settings';
  @override
  Stream<ProductMap> get events => changes.stream;
  @override
  Future<ProductMap> bootstrap() async => {
    ...await super.bootstrap(),
    'context': {
      'route': route,
      'purpose': 'single',
      'returnToken': 'same-native-game',
    },
  };
  @override
  void dispose() {
    unawaited(changes.close());
  }
}

class RetryClient extends AppClient {
  int attempts = 0;
  @override
  Future<ProductMap> bootstrap() async {
    if (++attempts == 1) throw const ProductFailure('service_unavailable');
    return super.bootstrap();
  }
}

class PresentationFailureClient extends HostClient {
  bool failBootstrap = true;
  int failAck = 0;
  final acknowledgements = <ProductMap>[];
  String token = 'host-one';
  @override
  Future<ProductMap> bootstrap() async {
    if (failBootstrap) throw const ProductFailure('native_unavailable');
    return {
      ...await super.bootstrap(),
      'context': {
        'route': route,
        'purpose': 'single',
        'presentationToken': token,
      },
    };
  }

  @override
  Future<ProductMap> call(String method, [ProductMap args = const {}]) async {
    if (method == 'presentationContext') {
      return {
        'locale': 'en',
        'context': {
          'route': route,
          'purpose': 'single',
          'presentationToken': token,
        },
      };
    }
    if (method == 'presentationReady') {
      acknowledgements.add(args);
      if (failAck-- > 0) throw const ProductFailure('native_unavailable');
      return {'accepted': true};
    }
    return super.call(method, args);
  }
}

void reportRaster(WidgetTester tester, int frame) {
  tester.binding.platformDispatcher.onReportTimings!([
    FrameTiming(
      vsyncStart: 1,
      buildStart: 2,
      buildFinish: 3,
      rasterStart: 4,
      rasterFinish: 5,
      rasterFinishWallTime: 6,
      frameNumber: frame,
    ),
  ]);
}

void main() {
  testWidgets(
    'U26 actual image cache is bounded and pressure releases UI without closing the owner',
    (tester) async {
      final client = AppClient();
      await tester.pumpWidget(ProductApp(client: client));
      await tester.pumpAndSettle();
      final cache = PaintingBinding.instance.imageCache;
      expect(cache.maximumSizeBytes, 32 * 1024 * 1024);
      expect(cache.maximumSize, 160);
      cache.clear();
      Future<void> populate(int count, int side, String prefix) async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawPaint(Paint()..color = Colors.red);
        final picture = recorder.endRecording();
        final image = (await tester.runAsync(
          () => picture.toImage(side, side),
        ))!;
        for (var index = 0; index < count; index++) {
          cache.putIfAbsent(
            '$prefix-$index',
            () => OneFrameImageStreamCompleter(
              Future.value(ImageInfo(image: image.clone())),
            ),
          );
        }
        image.dispose();
        picture.dispose();
        await tester.pump();
      }

      await populate(170, 1, 'small');
      expect(cache.currentSize, 160);
      expect(cache.containsKey('small-0'), isFalse);
      cache.clear();
      await populate(3, 2048, 'large');
      expect(cache.currentSize, 2);
      expect(cache.currentSizeBytes, 32 * 1024 * 1024);
      final before = List<String>.of(client.calls);
      tester.binding.handleMemoryPressure();
      await tester.pump();
      expect(cache.currentSize, 0);
      expect(cache.currentSizeBytes, 0);
      expect(cache.liveImageCount, 0);
      expect(
        client.calls,
        before,
        reason: 'UI cache eviction must not send a close or restart command',
      );
      expect(find.byTooltip('Settings').hitTestable(), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'bootstrap failure renders an opaque presentation Retry and recovers',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final client = PresentationFailureClient();
      await tester.pumpWidget(ProductApp(client: client));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('presentation-retry')), findsOneWidget);
      final dynamic state = tester.state(find.byType(ProductApp));
      expect(state.presentation.token, client.token);
      state.presentation.frame = 42;
      reportRaster(tester, 42);
      await tester.pump();
      expect(client.acknowledgements.single['token'], client.token);
      client.failBootstrap = false;
      await tester.tap(find.byKey(const ValueKey('presentation-retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('presentation-retry')), findsNothing);
      expect(find.byType(ProductSettings), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'reattachment failure acknowledges the new error surface not old page',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final client = PresentationFailureClient()..failBootstrap = false;
      await tester.pumpWidget(ProductApp(client: client));
      await tester.pumpAndSettle();
      client.failBootstrap = true;
      client.token = 'host-two';
      client.route = 'hall';
      client.changes.add({
        'event': 'contextChanged',
        'context': {'route': 'hall', 'presentationToken': client.token},
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('presentation-retry')), findsOneWidget);
      final dynamic state = tester.state(find.byType(ProductApp));
      expect(state.presentation.token, client.token);
      state.presentation.frame = 43;
      reportRaster(tester, 44);
      await tester.pump();
      expect(client.acknowledgements.last['token'], 'host-two');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'transient presentationReady failure retries the same valid raster',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final client = PresentationFailureClient()
        ..failBootstrap = false
        ..failAck = 1;
      await tester.pumpWidget(ProductApp(client: client));
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(ProductApp));
      state.presentation.frame = 45;
      reportRaster(tester, 45);
      await tester.pump();
      expect(client.acknowledgements.length, 1);
      await tester.pump(const Duration(milliseconds: 300));
      expect(client.acknowledgements.length, 2);
      expect(client.acknowledgements.last['token'], client.token);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'A16 native context restoration removes old settings without a reverse animation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final client = HostClient();
      await tester.pumpWidget(ProductApp(client: client));
      await tester.pumpAndSettle();
      expect(find.byType(ProductSettings), findsOneWidget);
      client.route = 'hall';
      client.changes.add({'event': 'contextChanged'});
      // Flush async bootstrap and Navigator disposal without advancing time.
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(
        find.byType(ProductSettings),
        findsNothing,
        reason: 'A native return is restoration, not an animated Flutter Back',
      );
      expect(find.text('All'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('U24 dirty domains and host reattachment share one refresh', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(960, 540));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = HostClient();
    await tester.pumpWidget(ProductApp(client: client));
    await tester.pumpAndSettle();
    client.changes.add({
      'event': 'projectionChanged',
      'domains': ['catalog'],
    });
    await tester.pump();
    final before = client.calls.where((m) => m == 'catalogQuery').length;
    client.route = 'hall';
    client.changes.add({'event': 'contextChanged'});
    await tester.pumpAndSettle();
    expect(client.calls.where((m) => m == 'catalogQuery').length, before + 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'U26 background invalidations coalesce into one authoritative resume refresh',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final client = HostClient()..route = 'hall';
      await tester.pumpWidget(ProductApp(client: client));
      await tester.pumpAndSettle();
      final before = client.calls.where((m) => m == 'catalogQuery').length;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      client.changes.add({
        'event': 'projectionChanged',
        'domains': ['catalog', 'resume'],
      });
      await tester.pump();
      expect(client.calls.where((m) => m == 'catalogQuery').length, before);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(client.calls.where((m) => m == 'catalogQuery').length, before + 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'U26 compact paused settings Back closes detail before native host',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final client = HostClient();
      await tester.pumpWidget(ProductApp(client: client));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('section-audio')));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(client.calls, isNot(contains('closeHost')));
      expect(find.byKey(const ValueKey('section-audio')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(client.calls.where((method) => method == 'closeHost').length, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'A17 reducing motion during page entry immediately shows final page',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(
        tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpWidget(ProductApp(client: AppClient()));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      await tester.pump();
      final page = find.byType(ProductSettings);
      final fade = find.ancestor(
        of: page,
        matching: find.byType(FadeTransition),
      );
      expect(tester.widget<FadeTransition>(fade.first).opacity.value, 1);
      final transform = find.ancestor(
        of: page,
        matching: find.byType(Transform),
      );
      expect(
        tester.widget<Transform>(transform.first).transform.getTranslation().x,
        0,
      );
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'source progress invalidation does not rescan the hidden or unrelated hall',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final client = HostClient()..route = 'hall';
      await tester.pumpWidget(ProductApp(client: client));
      await tester.pumpAndSettle();
      final before = client.calls.where((m) => m == 'catalogQuery').length;
      client.changes.add({
        'event': 'projectionChanged',
        'domains': ['sources'],
      });
      await tester.pumpAndSettle();
      expect(client.calls.where((m) => m == 'catalogQuery').length, before);
      client.changes.add({
        'event': 'projectionChanged',
        'domains': ['catalog'],
      });
      await tester.pumpAndSettle();
      expect(client.calls.where((m) => m == 'catalogQuery').length, before + 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('U01 retry reacquires bootstrap after startup failure', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(960, 540));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = RetryClient();
    await tester.pumpWidget(ProductApp(client: client));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry').first);
    await tester.pumpAndSettle();
    expect(client.attempts, 2);
    expect(find.text('Start'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'U22 reacquiring the same host keeps settings section and nested route',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final client = HostClient();
      await tester.pumpWidget(ProductApp(client: client));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('section-game')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manage sources'));
      await tester.pumpAndSettle();
      expect(find.text('Your game sources'), findsOneWidget);
      client.changes.add({'event': 'contextChanged'});
      await tester.pumpAndSettle();
      expect(
        find.text('Your game sources'),
        findsOneWidget,
        reason:
            'Reattaching after a system picker must not replace the nested route.',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Manage sources'), findsOneWidget);
      expect(find.text('Quality preset'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'U01 normal product app begins on Flutter hall and routes settings internally',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final client = AppClient();
      await tester.pumpWidget(ProductApp(client: client));
      await tester.pumpAndSettle();
      expect(find.text('All'), findsOneWidget);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('section-display')), findsOneWidget);
      expect(client.calls, isNot(contains('openNative')));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('All'), findsOneWidget);
    },
  );
}
