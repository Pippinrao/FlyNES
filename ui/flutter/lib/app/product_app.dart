import 'dart:async';
import 'dart:ui' show FrameTiming;
import 'product_presentation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../native_client/product_client.dart';
import '../design_system/app_theme.dart';
import '../features/product/product_controller.dart';
import '../features/product/product_hall.dart';
import '../features/product/product_settings.dart';
import '../features/product/product_sources.dart';
import '../features/product/product_licenses.dart';

class ProductApp extends StatefulWidget {
  const ProductApp({super.key, this.client});
  final ProductClient? client;
  @override
  State<ProductApp> createState() => _ProductAppState();
}

class _ProductRouteObserver extends NavigatorObserver {
  final routes = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.add(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.remove(route);
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.remove(route);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        routes.removeAt(index);
      } else {
        routes[index] = newRoute;
      }
    }
  }
}

class _ProductAppState extends State<ProductApp> with WidgetsBindingObserver {
  late final ProductClient client = widget.client ?? ChannelProductClient();
  late final ProductController controller = ProductController(client);
  final navigator = GlobalKey<NavigatorState>();
  final routeObserver = _ProductRouteObserver();
  StreamSubscription<ProductMap>? subscription;
  String hostRoute = 'hall';
  String? hostContextKey;
  int routeRequest = 0;
  final presentation = ProductPresentation();
  String? presentationToken, requestedPresentation;
  bool routeMutationPending = false;
  ProductMap safePresentationContext = const {};
  bool contextResolving = true, presentationError = false;
  Timer? acknowledgementRetry;
  bool hidden = false;
  int contextRequest = 0;
  final _dirtyDomains = <String>{};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addTimingsCallback(_rasterized);
    PaintingBinding.instance.imageCache.maximumSizeBytes = 32 * 1024 * 1024;
    PaintingBinding.instance.imageCache.maximumSize = 160;
    controller.addListener(_changed);
    if (client is ProductEventSource) {
      subscription = (client as ProductEventSource).events.listen(_event);
    }
    unawaited(_initialize());
  }

  void _changed() {
    if (mounted) {
      setState(() {});
      if (!contextResolving &&
          !presentationError &&
          controller.bootstrapData.isNotEmpty) {
        _routeHost(controller.bootstrapData);
      }
      _refreshDirty();
    }
  }

  Future<void> _initialize() async {
    final request = ++contextRequest;
    contextResolving = true;
    try {
      final safe = await client.call('presentationContext');
      if (!mounted || request != contextRequest) return;
      if (safe['context'] is Map) safePresentationContext = safe;
    } on ProductFailure catch (_) {
      /* Bootstrap can still supply the context. */
    }
    final previous = controller.bootstrapData;
    await controller.initialize();
    if (!mounted || request != contextRequest) return;
    contextResolving = false;
    if (controller.error.isNotEmpty &&
        identical(previous, controller.bootstrapData)) {
      _showPresentationError();
    } else {
      _routeHost(controller.bootstrapData);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    hidden = state != AppLifecycleState.resumed;
    if (mounted) setState(() {});
    if (!hidden) {
      _refreshDirty();
      // A scheduled frame may have been dropped with the old Android surface.
      if (presentation.token != null) WidgetsBinding.instance.scheduleFrame();
    }
  }

  void _refreshDirty() {
    if (!mounted ||
        hidden ||
        controller.busy ||
        hostRoute != 'hall' ||
        _dirtyDomains.isEmpty) {
      return;
    }
    final catalog = _dirtyDomains.contains('catalog');
    final resume = _dirtyDomains.contains('resume');
    _dirtyDomains.clear();
    if (catalog) {
      unawaited(controller.refresh());
    } else if (resume && controller.selectedId.isNotEmpty) {
      unawaited(
        controller.choose(controller.selectedId, persistSelection: false),
      );
    }
  }

  @override
  void didHaveMemoryPressure() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }

  Future<void> _event(ProductMap event) async {
    if (event['event'] == 'contextChanged') {
      final request = ++contextRequest;
      contextResolving = true;
      if (event['context'] is Map) {
        safePresentationContext = {'locale': controller.locale, ...event};
      }
      try {
        final data = await client.bootstrap();
        if (!mounted || request != contextRequest) return;
        // Reattachment below refreshes the authoritative hall once; do not let
        // adoptHost's synchronous notification drain an older invalidation too.
        _dirtyDomains.clear();
        contextResolving = false;
        controller.adoptHost(data);
        _routeHost(data);
        if (hostRoute == 'hall') await controller.refresh();
      } on ProductFailure catch (error) {
        if (mounted &&
            request == contextRequest &&
            error.code != 'stale_response') {
          controller.error = error.code;
          contextResolving = false;
          _showPresentationError();
        }
      }
    } else {
      final domains = event['domains'];
      if (domains is! List || domains.contains('catalog')) {
        _dirtyDomains.add('catalog');
      } else if (domains.contains('resume')) {
        _dirtyDomains.add('resume');
      }
      _refreshDirty();
    }
  }

  void _routeHost(ProductMap data) {
    final context = data['context'];
    final route = context is Map
        ? context['route'] as String? ?? 'hall'
        : 'hall';
    if (!const {'hall', 'settings', 'sources', 'licenses'}.contains(route)) {
      return;
    }
    final contextKey = context is Map
        ? '$route:${context['purpose']}:${context['returnToken']}'
        : route;
    presentationToken = context is Map
        ? context['presentationToken'] as String?
        : null;
    if (contextKey == hostContextKey) {
      if (presentationError) setState(() => presentationError = false);
      if (!routeMutationPending) _preparePresentation();
      return;
    }
    hostContextKey = contextKey;
    hostRoute = route;
    final request = ++routeRequest;
    routeMutationPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || request != routeRequest) return;
      // Native host restoration must never animate the previous host's page.
      final nav = navigator.currentState;
      for (final previous in routeObserver.routes.skip(1).toList().reversed) {
        nav?.removeRoute(previous);
      }
      if (route != 'hall') unawaited(_open(route, hostRoot: true));
      if (presentationError) setState(() => presentationError = false);
      routeMutationPending = false;
      _preparePresentation();
    });
  }

  void _preparePresentation() {
    final token = presentationToken;
    if (token == null || token == requestedPresentation) return;
    acknowledgementRetry?.cancel();
    requestedPresentation = token;
    presentation.request(token);
    // This begins the first frame AFTER the route mutation. endOfFrame and a
    // cached renderer's onUiDisplayed do not prove this route was rasterized.
    WidgetsBinding.instance.scheduleFrameCallback((_) {
      if (!mounted) return;
      presentation.frameStarted(
        token,
        WidgetsBinding.instance.platformDispatcher.frameData.frameNumber,
      );
    });
  }

  void _rasterized(List<FrameTiming> timings) {
    final token = presentation.rasterized(timings.map((t) => t.frameNumber));
    if (!mounted || token == null) return;
    unawaited(_acknowledgePresentation(token, presentation.rasterFrame!));
  }

  Future<void> _acknowledgePresentation(String token, int frame) async {
    if (!mounted || requestedPresentation != token) return;
    try {
      await client.call('presentationReady', {
        'token': token,
        'frameNumber': frame,
      });
    } on ProductFailure catch (error) {
      if (!mounted ||
          requestedPresentation != token ||
          const {
            'stale_host',
            'stale_response',
            'disposed',
          }.contains(error.code)) {
        return;
      }
      acknowledgementRetry?.cancel();
      acknowledgementRetry = Timer(
        const Duration(milliseconds: 200),
        () => unawaited(_acknowledgePresentation(token, frame)),
      );
    }
  }

  void _showPresentationError() {
    final context = safePresentationContext['context'];
    if (context is! Map || context['presentationToken'] is! String) {
      setState(() {}); // Older/test hosts have no native presentation gate.
      return;
    }
    ++routeRequest;
    routeMutationPending = false;
    presentationToken = context['presentationToken'] as String;
    requestedPresentation = null;
    setState(() => presentationError = true);
    _preparePresentation();
  }

  Future<void> _closeHost() async {
    try {
      await client.call('closeHost');
    } on ProductFailure catch (error) {
      if (mounted) {
        controller.error = error.code;
        _changed();
      }
    }
  }

  Future<void> _open(String page, {bool hostRoot = false}) async {
    final nav = navigator.currentState;
    if (nav == null) return;
    void back() {
      if (hostRoot) {
        unawaited(_closeHost());
      } else {
        nav.pop();
      }
    }

    Widget content() => switch (page) {
      'settings' => ProductSettings(
        hostRoot: hostRoot,
        client: client,
        locale: controller.locale,
        onLocaleChanged: (value) {
          controller.settings = {...controller.settings, 'localeTag': value};
          _changed();
        },
        onSources: () => _open('sources'),
        onLicenses: () => _open('licenses'),
        version: controller.bootstrapData['version'] as String? ?? '',
        buildRevision:
            controller.bootstrapData['buildRevision'] as String? ?? '',
        onBack: back,
      ),
      'sources' => ProductSources(
        client: client,
        locale: controller.locale,
        onBack: back,
      ),
      _ => ProductLicenses(
        hostRoot: hostRoot,
        client: client,
        locale: controller.locale,
        onBack: back,
      ),
    };
    final reduce = MediaQuery.maybeOf(nav.context)?.disableAnimations ?? false;
    await nav.push(
      PageRouteBuilder<void>(
        settings: RouteSettings(name: page),
        transitionDuration: (reduce || hostRoot)
            ? Duration.zero
            : const Duration(milliseconds: 220),
        reverseTransitionDuration: (reduce || hostRoot)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        pageBuilder: (context, a, b) => page != 'sources'
            ? content()
            : PopScope(
                canPop: !hostRoot,
                onPopInvokedWithResult: (didPop, result) {
                  if (!didPop && hostRoot) unawaited(_closeHost());
                },
                child: content(),
              ),
        transitionsBuilder: (context, a, b, child) => FadeTransition(
          opacity: MediaQuery.disableAnimationsOf(context)
              ? AlwaysStoppedAnimation(
                  a.status == AnimationStatus.reverse ? 0 : 1,
                )
              : a,
          child: AnimatedBuilder(
            animation: a,
            child: child,
            builder: (context, child) => Transform.translate(
              offset: Offset(
                MediaQuery.disableAnimationsOf(context)
                    ? 0
                    : (1 - Curves.easeOutCubic.transform(a.value)) * 24,
                0,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
    if (mounted && !hostRoot && (page == 'sources' || page == 'settings')) {
      await controller.refresh();
    }
  }

  Future<void> _nearby() async {
    if (controller.busy) return;
    try {
      await client.call('openNative', {'page': 'nearby'});
      if (mounted) await controller.refresh();
    } on ProductFailure catch (error) {
      if (mounted && error.code != 'stale_response') {
        controller.error = error.code;
        _changed();
      }
    }
  }

  @override
  void dispose() {
    ++contextRequest;
    acknowledgementRetry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.removeTimingsCallback(_rasterized);
    unawaited(subscription?.cancel());
    controller.removeListener(_changed);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    builder: (context, child) {
      final chinese =
          (safePresentationContext['locale'] as String? ?? controller.locale)
              .startsWith('zh');
      return Stack(
        fit: StackFit.expand,
        children: [
          ExcludeSemantics(
            excluding: presentationError,
            child: IgnorePointer(ignoring: presentationError, child: child!),
          ),
          if (presentationError)
            Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(chinese ? '暂时无法载入页面' : 'Unable to load this page'),
                    const SizedBox(height: 16),
                    FilledButton(
                      key: const ValueKey('presentation-retry'),
                      onPressed: contextResolving
                          ? null
                          : () => unawaited(_initialize()),
                      child: Text(chinese ? '重试' : 'Retry'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
    title: 'FlyNES',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.dark(),
    supportedLocales: const [
      Locale('en'),
      Locale('zh', 'CN'),
      if (kDebugMode) Locale('en', 'XA'),
    ],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    locale: controller.locale == 'system'
        ? null
        : controller.locale.startsWith('zh')
        ? const Locale('zh', 'CN')
        : const Locale('en'),
    navigatorKey: navigator,
    navigatorObservers: [routeObserver],
    home: TickerMode(
      enabled: !hidden && hostRoute == 'hall',
      child: ProductHall(
        controller: controller,
        onSources: () => _open('sources'),
        onSettings: () => _open('settings'),
        onNearby: controller.purpose == 'nearby' ? _closeHost : _nearby,
      ),
    ),
  );
}
