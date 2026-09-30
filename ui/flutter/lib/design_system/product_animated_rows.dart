import 'package:flutter/material.dart';
import 'product_motion.dart';

/// A12 consumes acknowledged snapshots. Identity updates never become inserts.
class ProductAnimatedRows<T> extends StatefulWidget {
  const ProductAnimatedRows({
    super.key,
    required this.items,
    required this.identity,
    required this.builder,
    this.shrinkWrap = false,
  });
  final List<T> items;
  final String Function(T) identity;
  final Widget Function(T) builder;
  final bool shrinkWrap;
  @override
  State<ProductAnimatedRows<T>> createState() => _ProductAnimatedRowsState<T>();
}

class _ProductAnimatedRowsState<T> extends State<ProductAnimatedRows<T>> {
  final _list = GlobalKey<AnimatedListState>();
  late List<T> _items;
  @override
  void initState() {
    super.initState();
    _items = List.of(widget.items);
  }

  Widget _transition(
    T item,
    Animation<double> animation, {
    bool removing = false,
  }) => SizeTransition(
    sizeFactor: MediaQuery.disableAnimationsOf(context)
        ? AlwaysStoppedAnimation(removing ? 0 : 1)
        : animation,
    child: FadeTransition(
      opacity: MediaQuery.disableAnimationsOf(context)
          ? AlwaysStoppedAnimation(removing ? 0 : 1)
          : animation,
      child: IgnorePointer(
        ignoring: removing,
        child: ExcludeFocus(
          excluding: removing,
          child: ExcludeSemantics(
            excluding: removing,
            child: widget.builder(item),
          ),
        ),
      ),
    ),
  );
  @override
  void didUpdateWidget(covariant ProductAnimatedRows<T> old) {
    super.didUpdateWidget(old);
    final duration = ProductMotion.duration(context, 180);
    final wanted = widget.items.map(widget.identity).toSet();
    for (var i = _items.length - 1; i >= 0; --i) {
      if (!wanted.contains(widget.identity(_items[i]))) _remove(i, duration);
    }
    for (var i = 0; i < widget.items.length; ++i) {
      final current = widget.items[i];
      final index = _items.indexWhere(
        (item) => widget.identity(item) == widget.identity(current),
      );
      if (index == i) {
        _items[i] = current;
        continue;
      }
      if (index >= 0) _remove(index, duration);
      _items.insert(i, current);
      _list.currentState?.insertItem(i, duration: duration);
    }
  }

  void _remove(int index, Duration duration) {
    final removed = _items.removeAt(index);
    _list.currentState?.removeItem(
      index,
      (context, animation) => _transition(removed, animation, removing: true),
      duration: duration,
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedList(
    key: _list,
    initialItemCount: _items.length,
    shrinkWrap: widget.shrinkWrap,
    physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : null,
    itemBuilder: (context, index, animation) =>
        _transition(_items[index], animation),
  );
}
