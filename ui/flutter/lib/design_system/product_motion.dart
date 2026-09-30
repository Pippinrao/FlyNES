import 'dart:async';
import 'package:flutter/material.dart';

abstract final class ProductMotion {
  static Duration duration(BuildContext context, int milliseconds) =>
      MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : Duration(milliseconds: milliseconds);
  static const curve = Curves.easeOutCubic;
}

/// Only decoration changes; child layout, focus and hit targets stay attached.
class ProductDecoration extends StatelessWidget {
  const ProductDecoration({
    super.key,
    required this.duration,
    required this.decoration,
    required this.child,
    this.curve = Curves.linear,
  });
  final Duration duration;
  final Decoration decoration;
  final Widget child;
  final Curve curve;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<Decoration>(
    tween: DecorationTween(begin: decoration, end: decoration),
    duration: duration,
    curve: curve,
    child: child,
    builder: (context, painted, child) => DecoratedBox(
      decoration: MediaQuery.disableAnimationsOf(context)
          ? decoration
          : painted,
      child: child,
    ),
  );
}

class ProductFadeSwitcher extends StatelessWidget {
  const ProductFadeSwitcher({
    super.key,
    required this.duration,
    required this.child,
    this.layoutBuilder,
    this.resize = false,
    this.curve = Curves.linear,
  });
  final Duration duration;
  final Widget child;
  final AnimatedSwitcherLayoutBuilder? layoutBuilder;
  final bool resize;
  final Curve curve;
  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: duration,
    switchInCurve: curve,
    switchOutCurve: curve,
    layoutBuilder: (current, previous) =>
        (layoutBuilder ?? AnimatedSwitcher.defaultLayoutBuilder)(
          current,
          MediaQuery.disableAnimationsOf(context) ? [] : previous,
        ),
    transitionBuilder: (child, animation) => AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final retiring =
            animation.status == AnimationStatus.reverse ||
            animation.status == AnimationStatus.dismissed;
        final progress = MediaQuery.disableAnimationsOf(context)
            ? AlwaysStoppedAnimation<double>(retiring ? 0 : 1)
            : animation;
        final faded = FadeTransition(
          opacity: progress,
          child: IgnorePointer(
            ignoring: retiring,
            child: ExcludeFocus(
              excluding: retiring,
              child: ExcludeSemantics(excluding: retiring, child: child),
            ),
          ),
        );
        return resize
            ? SizeTransition(
                sizeFactor: progress,
                axisAlignment: -1,
                child: faded,
              )
            : faded;
      },
    ),
    child: child,
  );
}

class ProductProgress extends StatelessWidget {
  const ProductProgress({super.key, required this.value});
  final double value;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: value, end: value),
    duration: ProductMotion.duration(context, 120),
    builder: (context, displayed, _) => LinearProgressIndicator(
      value: MediaQuery.disableAnimationsOf(context) ? value : displayed,
    ),
  );
}

/// A13: brief work never flashes a spinner and is never delayed to show one.
class DeferredProgress extends StatefulWidget {
  const DeferredProgress({super.key, required this.label});
  final String label;
  @override
  State<DeferredProgress> createState() => _DeferredProgressState();
}

class _DeferredProgressState extends State<DeferredProgress> {
  bool show = false;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => show = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (show && !MediaQuery.disableAnimationsOf(context))
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        Flexible(child: Text(widget.label)),
      ],
    ),
  );
}
