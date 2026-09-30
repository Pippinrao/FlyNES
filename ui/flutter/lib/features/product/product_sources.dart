import '../../design_system/product_notice.dart';
import '../../design_system/product_animated_rows.dart';
import '../../design_system/product_button.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../native_client/product_client.dart';
import '../../design_system/app_theme.dart';
import '../../design_system/product_motion.dart';
import '../../design_system/product_strings.dart';
import '../../design_system/product_dialogs.dart';

class ProductSources extends StatefulWidget {
  const ProductSources({
    super.key,
    required this.client,
    required this.locale,
    this.onBack,
  });
  final ProductClient client;
  final String locale;
  final VoidCallback? onBack;
  @override
  State<ProductSources> createState() => _ProductSourcesState();
}

class _ProductSourcesState extends State<ProductSources>
    with WidgetsBindingObserver {
  List<ProductMap> sources = [];
  String error = '';
  bool _operationError = false;
  bool loading = true;
  bool busy = false;
  bool folderSelection = true;
  int _request = 0;
  Timer? _poll;
  StreamSubscription<ProductMap>? _subscription;
  bool _hidden = false;
  static const _activePhases = {
    'queued',
    'enumerating',
    'ingesting',
    'scanning',
    'committing',
    'cancelling',
  };
  ProductStrings get s => ProductStrings(context, widget.locale);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.client is ProductEventSource) {
      _subscription = (widget.client as ProductEventSource).events.listen((
        event,
      ) {
        final domains = event['domains'];
        if (event['event'] == 'projectionChanged' &&
            (domains is! List || domains.contains('sources'))) {
          unawaited(_read());
        }
      });
    }
    _read();
  }

  @override
  void dispose() {
    ++_request;
    _poll?.cancel();
    unawaited(_subscription?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _read() async {
    if (_hidden) return;
    final request = ++_request;
    try {
      final result = await widget.client.call('sources');
      if (!mounted || request != _request) return;
      final rows = (result['items'] as List)
          .map((e) => Map<String, Object?>.from(e as Map))
          .toList();
      final ids = <String>{};
      final folder = result['folderSelection'];
      if (folder != null && (folder is! Map || folder['available'] is! bool)) {
        throw const ProductFailure('invalid_response');
      }
      if (rows.any(
        (e) => e['uuid'] is! String || !ids.add(e['uuid'] as String),
      )) {
        throw const ProductFailure('invalid_response');
      }
      setState(() {
        sources = rows;
        folderSelection =
            folder == null || (folder as Map)['available'] == true;
        if (!_operationError) error = '';
        loading = false;
      });
      _poll?.cancel();
      // This timer observes an application-owned scan; it never starts or cancels it.
      if (rows.any((e) => _activePhases.contains(e['phase']))) {
        _poll = Timer(const Duration(milliseconds: 500), _read);
      }
    } catch (e) {
      if (mounted && request == _request) {
        setState(() {
          if (!_operationError) {
            error = e is ProductFailure ? e.code : 'service_unavailable';
          }
          loading = false;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasHidden = _hidden;
    _hidden = state != AppLifecycleState.resumed;
    if (_hidden) {
      ++_request;
      _poll?.cancel();
    } else if (wasHidden) {
      unawaited(_read());
    }
  }

  Future<void> _operate(String method, ProductMap arguments) async {
    if (busy) return;
    setState(() {
      busy = true;
    });
    try {
      final result = await widget.client.call(method, arguments);
      if (!mounted) return;
      if (result['status'] != 'cancelled') {
        _operationError = false;
        await _read();
      }
    } catch (e) {
      if (mounted && e is ProductFailure && e.code == 'source_cleanup_failed') {
        await _read();
      }
      if (mounted) {
        _operationError = true;
        setState(
          () => error = e is ProductFailure ? e.code : 'service_unavailable',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _remove(ProductMap row) async {
    if (await productConfirm(
          context,
          s,
          s.text('Remove source', '移除来源'),
          s.text(
            'Remove this source and its library entries? Original ROMs, saved progress and game preferences will be kept.',
            '移除此来源登记及关联游戏？原始 ROM、存档和游戏偏好会保留。',
          ),
        ) &&
        mounted) {
      await _operate('removeSource', {'uuid': row['uuid']});
    }
  }

  String _status(ProductMap row) => switch (row['phase'] == null ||
          row['phase'] == '' ||
          row['phase'] == 'idle'
      ? row['status']
      : row['phase']) {
    'queued' => s.text('Waiting to scan…', '等待扫描…'),
    'enumerating' => s.text('Reading files…', '正在读取文件…'),
    'ingesting' => s.text('Importing…', '正在导入…'),
    'scanning' => s.text('Scanning…', '正在扫描…'),
    'committing' => s.text('Finishing…', '正在完成…'),
    'cancelling' => s.text('Cancelling…', '正在取消…'),
    'cancelled' => s.text(
      'Scan cancelled. Previous library retained.',
      '扫描已取消，已保留原游戏库。',
    ),
    'partial' => s.text('Some files could not be imported', '部分文件未能导入'),
    'failed' when row['reason'] == 'scan_committed_refresh_failed' => s.text(
      'Saved · refresh incomplete',
      '已保存 · 刷新未完成',
    ),
    'failed' => s.text(
      'Scan failed. Previous library retained.',
      '扫描失败，已保留原游戏库。',
    ),
    'unavailable' || 'permission_lost' => s.text('Source unavailable', '来源不可用'),
    _ => s.text('${row['count'] ?? 0} games', '${row['count'] ?? 0} 个游戏'),
  };
  Widget _intro() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        s.text('Your game sources', '游戏来源'),
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 16),
      Text(
        s.text(
          'Add your own NES games. Removing a source keeps your original files and saved progress.',
          '添加自己的 NES 游戏。移除来源不会删除原文件和游戏进度。',
        ),
      ),
      const SizedBox(height: 24),
      ProductButton.filled(
        onPressed: busy ? null : () => _operate('pickSource', {'kind': 'file'}),
        icon: const Icon(Icons.note_add_outlined),
        child: Text(s.text('Add file', '添加文件')),
      ),
      const SizedBox(height: 12),
      ProductButton.outlined(
        style: OutlinedButton.styleFrom(minimumSize: const Size(48, 56)),
        onPressed: busy || loading || !folderSelection
            ? null
            : () => _operate('pickSource', {'kind': 'folder'}),
        icon: const Icon(Icons.create_new_folder_outlined),
        child: Text(s.text('Add folder', '添加文件夹')),
      ),
      if (!folderSelection) ...[
        const SizedBox(height: 12),
        Text(s.error('folder_selection_unsupported')),
      ],
    ],
  );
  Widget _row(ProductMap row) => Card(
    key: ValueKey('source-${row['uuid']}'),
    color: AppTheme.surface,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            row['builtin'] == true
                ? s.text('Built-in', '内置')
                : (row['name'] as String? ?? '').isNotEmpty
                ? row['name'] as String
                : s.text('Game source', '游戏来源'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            row['builtin'] == true
                ? s.text('Built-in · cannot be removed', '内置 · 不可移除')
                : row['type'] == 'file'
                ? s.text('File', '文件')
                : s.text('Folder', '文件夹'),
            style: const TextStyle(color: AppTheme.muted),
          ),
          const SizedBox(height: 8),
          Text(_status(row)),
          if (row['reason'] is String && (row['reason'] as String).isNotEmpty)
            Text(s.error(row['reason'] as String)),
          if (const {
            'scanning',
            'enumerating',
            'ingesting',
          }.contains(row['phase']))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: row['total'] is num && (row['total'] as num) > 0
                  ? ProductProgress(
                      value:
                          ((row['completed'] as num? ?? 0) /
                                  (row['total'] as num))
                              .clamp(0, 1),
                    )
                  : DeferredProgress(
                      label: s.text('Reading files…', '正在读取文件…'),
                    ),
            ),
          if (row['builtin'] != true)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ProductButton.text(
                  onPressed: busy || _activePhases.contains(row['phase'])
                      ? null
                      : () => _operate('scanSource', {'uuid': row['uuid']}),
                  child: Text(s.text('Scan', '扫描')),
                ),
                if (row['canReauthorize'] == true)
                  ProductButton.text(
                    onPressed: busy
                        ? null
                        : () => _operate('pickSource', {
                            'kind': row['type'] == 'file' ? 'file' : 'folder',
                            'sourceUuid': row['uuid'],
                          }),
                    child: Text(s.text('Reauthorize', '重新授权')),
                  ),
                if (row['canCancel'] == true && row['phase'] != 'committing')
                  ProductButton.text(
                    onPressed: () => _operate('cancelScan', {
                      'uuid': row['uuid'],
                      'operationId': row['operationId'],
                    }),
                    child: Text(s.text('Cancel scan', '取消扫描')),
                  ),
                ProductButton.text(
                  key: ValueKey('remove-${row['uuid']}'),
                  onPressed: busy ? null : () => _remove(row),
                  child: Semantics(
                    identifier: 'source-remove-${row['uuid']}',
                    child: Text(s.text('Remove', '移除')),
                  ),
                ),
              ],
            ),
        ],
      ),
    ),
  );
  Widget _list() => loading
      ? Center(
          child: DeferredProgress(label: s.text('Loading sources…', '正在读取来源…')),
        )
      : ProductAnimatedRows<ProductMap>(
          key: const ValueKey('sources-list'),
          items: sources,
          identity: (row) => row['uuid'] as String,
          builder: _row,
        );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(s.text('Sources', '来源')),
      leading: widget.onBack == null
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
              message: error.isNotEmpty ? s.error(error) : '',
              actionLabel: s.retry,
              onAction: () {
                _operationError = false;
                _read();
              },
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, bounds) => bounds.maxWidth >= 720
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: (bounds.maxWidth - 24) * .34,
                            child: SingleChildScrollView(child: _intro()),
                          ),
                          const SizedBox(width: 24),
                          Expanded(child: _list()),
                        ],
                      )
                    : ListView(
                        children: [
                          _intro(),
                          const SizedBox(height: 24),
                          if (loading)
                            DeferredProgress(
                              label: s.text('Loading sources…', '正在读取来源…'),
                            )
                          else
                            ProductAnimatedRows<ProductMap>(
                              items: sources,
                              identity: (row) => row['uuid'] as String,
                              builder: _row,
                              shrinkWrap: true,
                            ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
