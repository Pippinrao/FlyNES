import '../../design_system/product_button.dart';
import '../../design_system/product_notice.dart';
import 'package:flutter/material.dart';
import '../../native_client/product_client.dart';
import '../../design_system/app_theme.dart';
import '../../design_system/product_motion.dart';
import '../../design_system/product_strings.dart';

class ProductLicenses extends StatefulWidget {
  const ProductLicenses({
    super.key,
    required this.client,
    required this.locale,
    this.onBack,
    this.hostRoot = false,
  });
  final ProductClient client;
  final String locale;
  final VoidCallback? onBack;
  final bool hostRoot;
  @override
  State<ProductLicenses> createState() => _ProductLicensesState();
}

class _ProductLicensesState extends State<ProductLicenses> {
  List<ProductMap> items = [];
  ProductMap? selected;
  String body = '';
  String error = '';
  String message = '';
  int messageSequence = 0;
  bool loading = true;
  bool bodyLoading = false;
  bool compactDetail = false;
  int _request = 0;
  final _listScroll = ScrollController();
  final _bodyScrolls = <String, ScrollController>{};
  final _bodies = <String, String>{};
  ProductStrings get s => ProductStrings(context, widget.locale);
  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void dispose() {
    ++_request;
    _listScroll.dispose();
    for (final scroll in _bodyScrolls.values) {
      scroll.dispose();
    }
    super.dispose();
  }

  Future<void> _read() async {
    try {
      final result = await widget.client.call('licenses');
      if (!mounted) return;
      setState(() {
        items = (result['items'] as List)
            .map((e) => Map<String, Object?>.from(e as Map))
            .toList();
        loading = false;
        error = '';
      });
      if (items.isNotEmpty) await _select(items.first);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e is ProductFailure ? e.code : 'service_unavailable';
          loading = false;
        });
      }
    }
  }

  Future<void> _select(ProductMap item) async {
    final request = ++_request;
    final id = item['id'] as String;
    final cached = _bodies[id];
    setState(() {
      selected = item;
      body = cached ?? '';
      bodyLoading = cached == null;
      error = '';
    });
    if (cached != null) return;
    try {
      final result = await widget.client.call('licenseText', {
        'id': item['id'],
      });
      if (!mounted || request != _request) return;
      setState(() => body = _bodies[id] = result['text'] as String);
    } catch (e) {
      if (mounted && request == _request) {
        setState(
          () => error = e is ProductFailure ? e.code : 'service_unavailable',
        );
      }
    } finally {
      if (mounted && request == _request) setState(() => bodyLoading = false);
    }
  }

  Future<void> _platform(String method, ProductMap args) async {
    try {
      await widget.client.call(method, args);
      if (mounted) {
        setState(() {
          error = '';
          if (method == 'copyText') {
            message = s.text('License copied', '已复制许可');
            ++messageSequence;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is ProductFailure ? e.code : 'service_unavailable',
        );
      }
    }
  }

  Widget _list() => ListView.builder(
    key: const PageStorageKey('license-list'),
    controller: _listScroll,
    itemCount: items.length,
    itemBuilder: (context, index) => ListTile(
      selected: selected?['id'] == items[index]['id'],
      selectedTileColor: AppTheme.selected,
      title: Text(items[index]['title'] as String),
      onTap: () {
        setState(() => compactDetail = true);
        _select(items[index]);
      },
    ),
  );
  Widget _body() {
    final id = selected?['id'] as String? ?? '';
    final link = Uri.tryParse(selected?['sourceUrl'] as String? ?? '');
    final validLink =
        link != null &&
        (link.scheme == 'https' || link.scheme == 'http') &&
        link.host.isNotEmpty;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                selected?['title'] as String? ?? '',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (validLink)
              ProductButton.icon(
                tooltip: s.text('Source website', '来源网站'),
                onPressed: () =>
                    _platform('openLink', {'url': link.toString()}),
                icon: const Icon(Icons.open_in_new),
              ),
            ProductButton.icon(
              tooltip: s.text('Copy license', '复制许可'),
              onPressed: bodyLoading || body.isEmpty
                  ? null
                  : () => _platform('copyText', {'text': body}),
              icon: const Icon(Icons.copy_outlined),
            ),
          ],
        ),
        Expanded(
          child: ProductFadeSwitcher(
            duration: ProductMotion.duration(context, 120),
            layoutBuilder: (child, previous) => Stack(
              fit: StackFit.expand,
              alignment: Alignment.topLeft,
              children: [...previous, ?child],
            ),
            child: bodyLoading
                ? Center(
                    key: ValueKey('license-loading-$id'),
                    child: DeferredProgress(
                      label: s.text('Loading license…', '正在读取许可…'),
                    ),
                  )
                : SingleChildScrollView(
                    key: PageStorageKey('license-$id'),
                    controller: _bodyScrolls.putIfAbsent(
                      id,
                      () => ScrollController(),
                    ),
                    padding: const EdgeInsets.only(top: 16, bottom: 24),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: SelectableText(body),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final compact = bounds.maxWidth < 720;
      return PopScope(
        canPop: !widget.hostRoot && (!compact || !compactDetail),
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            if (compact && compactDetail) {
              setState(() => compactDetail = false);
            } else if (widget.hostRoot) {
              widget.onBack?.call();
            }
          }
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(s.text('Licenses', '许可')),
            leading: compact && compactDetail
                ? ProductBackButton(
                    label: s.text('Back', '返回'),
                    onPressed: () => setState(() => compactDetail = false),
                  )
                : widget.onBack == null
                ? null
                : ProductBackButton(
                    label: s.text('Back', '返回'),
                    onPressed: widget.onBack,
                  ),
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  ProductNotice(
                    message: error.isNotEmpty ? s.error(error) : message,
                    error: error.isNotEmpty,
                    sequence: messageSequence,
                    actionLabel: error.isNotEmpty ? s.retry : null,
                    onAction: error.isNotEmpty
                        ? (selected == null ? _read : () => _select(selected!))
                        : null,
                  ),
                  Expanded(
                    child: loading
                        ? Center(
                            child: DeferredProgress(
                              label: s.text('Loading licenses…', '正在读取许可列表…'),
                            ),
                          )
                        : compact
                        ? (compactDetail ? _body() : _list())
                        : Row(
                            children: [
                              SizedBox(
                                width: bounds.maxWidth * .28,
                                child: _list(),
                              ),
                              const VerticalDivider(width: 24),
                              Expanded(child: _body()),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
