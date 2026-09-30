import '../../design_system/product_typography.dart';
import '../../design_system/product_notice.dart';
import '../../design_system/product_button.dart';
import '../../design_system/product_switch.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../design_system/app_theme.dart';
import '../../design_system/product_motion.dart';
import '../../design_system/product_strings.dart';
import '../../native_client/product_client.dart';
import 'product_controller.dart';

class ProductHall extends StatefulWidget {
  const ProductHall({
    super.key,
    required this.controller,
    required this.onSources,
    required this.onSettings,
    required this.onNearby,
  });
  final ProductController controller;
  final VoidCallback onSources;
  final VoidCallback onSettings;
  final VoidCallback onNearby;
  @override
  State<ProductHall> createState() => _ProductHallState();
}

class _ProductHallState extends State<ProductHall> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _scrolls = <String, ScrollController>{};
  final _pendingWindows = <int>{};
  bool searchOpen = false;
  ProductMap? _paintedDetail;
  ProductController get c => widget.controller;
  ProductStrings get s => ProductStrings(context, c.locale);
  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    for (final scroll in _scrolls.values) {
      scroll.dispose();
    }
    super.dispose();
  }

  void _closeSearch() {
    _searchFocus.unfocus();
    _search.clear();
    c.search('', immediate: true);
    setState(() => searchOpen = false);
  }

  String _title(ProductMap item) {
    final first = item[s.chinese ? 'titleZhHans' : 'titleEn'] as String? ?? '';
    final second = item[s.chinese ? 'titleEn' : 'titleZhHans'] as String? ?? '';
    return first.isNotEmpty
        ? first
        : second.isNotEmpty
        ? second
        : s.text('Untitled game', '未命名游戏');
  }

  Widget _icon(IconData icon, String label, VoidCallback callback) =>
      ProductButton.icon(tooltip: label, onPressed: callback, icon: Icon(icon));
  Widget _categories() => Wrap(
    spacing: 4,
    runSpacing: 4,
    children: [
      for (final category in ['recent', 'favorites', 'all', 'builtin'])
        Semantics(
          selected: c.category == category,
          child: ProductDecoration(
            duration: ProductMotion.duration(context, 150),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: c.category == category
                  ? AppTheme.accent
                  : AppTheme.surface,
            ),
            child: ProductButton.text(
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                foregroundColor: c.category == category
                    ? AppTheme.background
                    : AppTheme.text,
              ),
              onPressed: () => c.changeCategory(category),
              child: Text(s.category(category)),
            ),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final large = productUsesLargeText(context);
      final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
      return PopScope(
        canPop: !searchOpen && c.purpose != 'nearby',
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && searchOpen) {
            if (_searchFocus.hasFocus &&
                MediaQuery.viewInsetsOf(context).bottom > 0) {
              _searchFocus.unfocus();
            } else {
              _closeSearch();
            }
          } else if (!didPop && c.purpose == 'nearby') {
            widget.onNearby();
          }
        },
        child: Scaffold(
          backgroundColor: AppTheme.background,
          resizeToAvoidBottomInset: true,
          body: SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: keyboard ? 8 : 16,
              ),
              child: LayoutBuilder(
                builder: (context, bounds) {
                  final compact = large || bounds.maxWidth < 1000;
                  final editingShortWindow = keyboard && bounds.maxHeight < 360;
                  final tools = Wrap(
                    spacing: 4,
                    children: [
                      _icon(Icons.search, s.text('Search', '搜索'), () {
                        setState(() => searchOpen = !searchOpen);
                        if (searchOpen) {
                          _searchFocus.requestFocus();
                        } else {
                          _closeSearch();
                        }
                      }),
                      _icon(
                        Icons.folder_outlined,
                        s.text('Sources', '来源'),
                        widget.onSources,
                      ),
                      _icon(
                        Icons.settings_outlined,
                        s.text('Settings', '设置'),
                        widget.onSettings,
                      ),
                      _icon(
                        c.purpose == 'nearby' ? Icons.arrow_back : Icons.wifi,
                        c.purpose == 'nearby'
                            ? s.text('Return to room', '返回房间')
                            : s.text('Nearby', '附近联机'),
                        widget.onNearby,
                      ),
                    ],
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (compact)
                        Row(
                          children: [
                            Expanded(
                              child:
                                  (editingShortWindow ||
                                      (large && bounds.maxHeight < 400))
                                  ? SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: _categories(),
                                    )
                                  : _categories(),
                            ),
                            tools,
                          ],
                        )
                      else
                        Row(
                          children: [
                            Text(
                              s.text('GAME CENTER', '游戏中心'),
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(width: 24),
                            Expanded(child: _categories()),
                            tools,
                          ],
                        ),
                      ProductFadeSwitcher(
                        resize: true,
                        duration: ProductMotion.duration(context, 160),
                        curve: Curves.easeInOut,
                        child: searchOpen
                            ? Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Semantics(
                                        container: true,
                                        child: TextField(
                                          key: const ValueKey('search-field'),
                                          controller: _search,
                                          focusNode: _searchFocus,
                                          onChanged: c.search,
                                          decoration: InputDecoration(
                                            labelText: s.text(
                                              'Search games',
                                              '搜索游戏',
                                            ),
                                            prefixIcon: const Icon(
                                              Icons.search,
                                            ),
                                            suffixIcon: _icon(
                                              Icons.clear,
                                              s.text('Clear search', '清除搜索'),
                                              () {
                                                _search.clear();
                                                c.search('', immediate: true);
                                              },
                                            ),
                                            border: const OutlineInputBorder(),
                                          ),
                                        ),
                                      ),
                                    ),
                                    _icon(
                                      Icons.close,
                                      s.text('Close search', '关闭搜索'),
                                      _closeSearch,
                                    ),
                                  ],
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      if (!editingShortWindow) const SizedBox(height: 12),
                      if (!editingShortWindow)
                        ProductNotice(
                          message: c.error.isNotEmpty ? s.error(c.error) : '',
                          actionLabel: s.retry,
                          onAction: c.retry,
                        ),
                      if (!editingShortWindow)
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                width: (bounds.maxWidth - 16) * .3,
                                child: _detail(large),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        if (!large)
                                          Expanded(
                                            child: Text(
                                              s.text(
                                                '${c.total} games · swipe to browse',
                                                '${c.total} 个游戏 · 横滑浏览',
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          )
                                        else
                                          const Spacer(),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            s.text('Two-player', '双人支持'),
                                            maxLines: 2,
                                          ),
                                        ),
                                        ProductSwitch(
                                          label: s.text('Two-player', '双人支持'),
                                          value: c.multiplayerOnly,
                                          onChanged: (_) =>
                                              c.toggleMultiplayer(),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Expanded(
                                      child: TweenAnimationBuilder<double>(
                                        key: ValueKey(
                                          'results-${c.category}-${c.multiplayerOnly}',
                                        ),
                                        tween: Tween(begin: 0, end: 1),
                                        duration: ProductMotion.duration(
                                          context,
                                          120,
                                        ),
                                        builder: (context, value, child) =>
                                            Opacity(
                                              opacity:
                                                  MediaQuery.disableAnimationsOf(
                                                    context,
                                                  )
                                                  ? 1
                                                  : value,
                                              child: child,
                                            ),
                                        child: c.loading && c.total == 0
                                            ? Center(
                                                child: DeferredProgress(
                                                  label: s.text(
                                                    'Loading library…',
                                                    '正在读取游戏库…',
                                                  ),
                                                ),
                                              )
                                            : c.total == 0
                                            ? _empty()
                                            : _grid(large),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _empty() {
    if (c.error.isNotEmpty) {
      return Center(
        child: Text(
          s.text('Library unavailable', '无法读取游戏库'),
          textAlign: TextAlign.center,
        ),
      );
    }
    final text = c.query.isNotEmpty
        ? s.text('No matching games', '没有匹配的游戏')
        : c.multiplayerOnly
        ? s.text('No supported two-player games', '没有支持双人的游戏')
        : c.category == 'recent'
        ? s.text('No recently played games', '尚未玩过游戏')
        : c.category == 'favorites'
        ? s.text('No favorite games yet', '尚未收藏游戏')
        : s.text('Your library is empty', '游戏库为空');
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sports_esports_outlined, size: 48),
          const SizedBox(height: 16),
          Text(text, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          ProductButton.text(
            onPressed: () {
              if (c.query.isNotEmpty) {
                _search.clear();
                c.search('', immediate: true);
              } else if (c.multiplayerOnly) {
                c.toggleMultiplayer();
              } else if (c.category != 'all') {
                c.changeCategory('all');
              } else {
                widget.onSources();
              }
            },
            child: Text(
              c.query.isNotEmpty
                  ? s.text('Clear search', '清除搜索')
                  : c.multiplayerOnly
                  ? s.text('Turn off filter', '关闭筛选')
                  : c.category != 'all'
                  ? s.text('Show all', '查看全部')
                  : s.text('Manage sources', '管理来源'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detail(bool large) {
    final item = c.selected;
    if (item != null) _paintedDetail = item;
    // Keep the last complete visual while reading; all actions still use the
    // current controller selection, so old content can never launch or mutate.
    final displayed =
        item ?? (c.resumeState == 'querying' ? _paintedDetail : null);
    final title = displayed == null
        ? s.text('Select a game', '选择游戏')
        : _title(displayed);
    final subtitle =
        item?[s.chinese ? 'titleEn' : 'titleZhHans'] as String? ?? '';
    final action = c.purpose == 'nearby'
        ? s.text('Choose game', '选择游戏')
        : c.resumeState == 'querying'
        ? s.text('Reading…', '正在读取')
        : c.resumeState == 'unavailable'
        ? s.retry
        : c.resumeState == 'available'
        ? s.text('Continue', '继续')
        : s.text('Start', '开始');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.selected),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!large)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: ProductFadeSwitcher(
                    key: const ValueKey('detail-cover'),
                    duration: ProductMotion.duration(context, 120),
                    layoutBuilder: (current, previous) => Stack(
                      fit: StackFit.expand,
                      children: [...previous, ?current],
                    ),
                    child: ProductCover(
                      key: ValueKey(displayed?['canonicalId']),
                      item: displayed,
                      title: title,
                    ),
                  ),
                ),
              ),
            Flexible(
              flex: large ? 1 : 0,
              child: SingleChildScrollView(
                child: Row(
                  children: [
                    Expanded(
                      child: ProductFadeSwitcher(
                        duration: ProductMotion.duration(context, 120),
                        child: Text(
                          title,
                          key: ValueKey(title),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ),
                    if (item != null)
                      ProductButton.icon(
                        tooltip: s.text('Favorite', '收藏'),
                        onPressed: c.busy
                            ? null
                            : () => c.favorite(item['favorite'] != true),
                        icon: Icon(
                          item['favorite'] == true
                              ? Icons.star
                              : Icons.star_outline,
                          color: AppTheme.accent,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (!large) ...[
              const SizedBox(height: 8),
              if (subtitle.isNotEmpty && subtitle != title)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.muted),
                ),
              if (item != null)
                Text(
                  s.text(
                    '${item['variantCount'] ?? 1} version(s)',
                    '${item['variantCount'] ?? 1} 个版本',
                  ),
                  style: const TextStyle(color: AppTheme.muted),
                ),
              const SizedBox(height: 16),
            ],
            if (item?['available'] == false)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  s.text('Source unavailable', '来源不可用'),
                  style: const TextStyle(color: Color(0xFFFF6B6B)),
                ),
              ),
            SizedBox(
              height: large ? 88 : 56,
              child: ProductButton.filled(
                key: const ValueKey('launch-button'),
                onPressed:
                    item == null ||
                        c.busy ||
                        c.resumeState == 'querying' ||
                        item['available'] == false
                    ? null
                    : c.resumeState == 'unavailable'
                    ? () => c.choose(c.selectedId)
                    : c.launch,
                child: Text(action, textAlign: TextAlign.center, maxLines: 2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _grid(bool large) => KeyedSubtree(
    key: PageStorageKey('category-${c.category}'),
    child: GridView.builder(
      key: const ValueKey('catalog-grid'),
      controller: _scrolls.putIfAbsent(c.category, () => ScrollController()),
      scrollDirection: Axis.horizontal,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: large ? 1 : 2,
        mainAxisExtent: large ? 250 : 220,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemCount: c.total,
      itemBuilder: (context, index) {
        final item = c.itemAt(index);
        if (item == null) {
          final offset = (index ~/ 128) * 128;
          if (_pendingWindows.add(offset)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                unawaited(
                  c
                      .loadWindow(offset)
                      .whenComplete(() => _pendingWindows.remove(offset)),
                );
              }
            });
          }
          return const ColoredBox(color: AppTheme.surface);
        }
        final id = item['canonicalId'] as String;
        final chosen = id == c.selectedId;
        return Semantics(
          selected: chosen,
          button: true,
          label: _title(item),
          child: ProductDecoration(
            duration: ProductMotion.duration(context, 160),
            curve: ProductMotion.curve,
            decoration: BoxDecoration(
              color: chosen ? AppTheme.selected : AppTheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: chosen ? AppTheme.accent : AppTheme.selected,
                width: 2,
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                key: ValueKey('game-$id'),
                borderRadius: BorderRadius.circular(20),
                onTap: () => c.choose(id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: LayoutBuilder(
                    builder: (context, bounds) => Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!large || bounds.maxHeight > 100)
                          Expanded(
                            flex: 4,
                            child: ProductCover(
                              item: item,
                              title: _title(item),
                            ),
                          ),
                        if (!large || bounds.maxHeight > 100)
                          const SizedBox(width: 8),
                        Expanded(
                          flex: 6,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _title(item),
                              maxLines: bounds.maxHeight > 100 ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// FileImage normally keys only by path; game screenshots overwrite that path.
/// Include the owner's revision so a new head cannot reuse stale decoded pixels.
class _RevisionFileImage extends FileImage {
  const _RevisionFileImage(super.file, this.revision);
  final Object? revision;
  @override
  bool operator ==(Object other) =>
      other is _RevisionFileImage &&
      other.file.path == file.path &&
      other.scale == scale &&
      other.revision == revision;
  @override
  int get hashCode => Object.hash(file.path, scale, revision);
}

class ProductCover extends StatefulWidget {
  const ProductCover({super.key, required this.item, required this.title});
  final ProductMap? item;
  final String title;
  @override
  State<ProductCover> createState() => _ProductCoverState();
}

class _ProductCoverState extends State<ProductCover> {
  ImageProvider? _decoded;
  @override
  void didUpdateWidget(ProductCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item?['coverPath'] != widget.item?['coverPath'] ||
        oldWidget.item?['coverRevision'] != widget.item?['coverRevision']) {
      // Evict just this old size/revision; unrelated library images stay warm.
      unawaited(_decoded?.evict());
      _decoded = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.item?['coverPath'] as String? ?? '';
    Widget placeholder() => ColoredBox(
      color: AppTheme.selected,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            widget.title,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.muted),
          ),
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: LayoutBuilder(
        builder: (context, bounds) {
          if (path.isEmpty) return placeholder();
          final ratio = MediaQuery.devicePixelRatioOf(context);
          final provider = ResizeImage(
            _RevisionFileImage(File(path), widget.item?['coverRevision']),
            width: (bounds.maxWidth * ratio).ceil().clamp(1, 2048),
            height: (bounds.maxHeight * ratio).ceil().clamp(1, 2048),
            policy: ResizeImagePolicy.fit,
          );
          _decoded = provider;
          return Image(
            image: provider,
            key: ValueKey('$path:${widget.item?['coverRevision']}'),
            fit: BoxFit.contain,
            width: bounds.maxWidth,
            height: bounds.maxHeight,
            errorBuilder: (context, error, stack) => placeholder(),
            frameBuilder: (context, child, frame, synchronous) =>
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: frame == null ? 0 : 1),
                  duration: ProductMotion.duration(context, 120),
                  child: child,
                  builder: (context, opacity, child) {
                    final visible = MediaQuery.disableAnimationsOf(context)
                        ? (frame == null ? 0.0 : 1.0)
                        : opacity;
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        if (visible < 1) placeholder(),
                        Opacity(opacity: visible, child: child),
                      ],
                    );
                  },
                ),
          );
        },
      ),
    );
  }
}
