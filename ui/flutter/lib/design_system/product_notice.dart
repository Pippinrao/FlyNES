import 'dart:async';
import 'package:flutter/material.dart';
import 'product_button.dart';
import 'product_motion.dart';

/// U21/A14: errors persist; ordinary acknowledgements expire after 3 seconds.
/// Accessible navigation keeps the acknowledgement available until dismissed.
class ProductNotice extends StatefulWidget {
  const ProductNotice({
    super.key,
    required this.message,
    this.error = true,
    this.actionLabel,
    this.onAction,
    this.sequence = 0,
  });
  final String message;
  final bool error;
  final String? actionLabel;
  final VoidCallback? onAction;
  final int sequence;
  @override
  State<ProductNotice> createState() => _ProductNoticeState();
}

class _ProductNoticeState extends State<ProductNotice> {
  Timer? _timer;
  bool _visible = true;
  bool? _accessible;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final accessible = MediaQuery.accessibleNavigationOf(context);
    if (_accessible != accessible) {
      _accessible = accessible;
      _reset();
    }
  }

  @override
  void didUpdateWidget(ProductNotice old) {
    super.didUpdateWidget(old);
    if (old.message != widget.message ||
        old.error != widget.error ||
        old.sequence != widget.sequence) {
      _reset();
    }
  }

  void _reset() {
    _timer?.cancel();
    _visible = true;
    if (widget.message.isNotEmpty && !widget.error && _accessible != true) {
      _timer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _visible = false);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: ProductMotion.duration(context, 160),
    reverseDuration: ProductMotion.duration(context, 160),
    layoutBuilder: (current, previous) => Stack(
      alignment: Alignment.center,
      children: [
        if (!MediaQuery.disableAnimationsOf(context)) ...previous,
        ?current,
      ],
    ),
    transitionBuilder: (child, animation) => AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final retiring =
            animation.status == AnimationStatus.reverse ||
            animation.status == AnimationStatus.dismissed;
        return FadeTransition(
          opacity: MediaQuery.disableAnimationsOf(context)
              ? AlwaysStoppedAnimation(retiring ? 0 : 1)
              : animation,
          child: IgnorePointer(
            ignoring: retiring,
            child: ExcludeFocus(
              excluding: retiring,
              child: ExcludeSemantics(excluding: retiring, child: child),
            ),
          ),
        );
      },
    ),
    child: !_visible || widget.message.isEmpty
        ? const SizedBox.shrink()
        : Semantics(
            key: ValueKey(
              '${widget.error}:${widget.message}:${widget.sequence}',
            ),
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(child: Text(widget.message)),
                  if (widget.onAction != null && widget.actionLabel != null)
                    ProductButton.text(
                      onPressed: widget.onAction,
                      child: Text(widget.actionLabel!),
                    ),
                ],
              ),
            ),
          ),
  );
}
