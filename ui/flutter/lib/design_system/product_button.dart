import 'product_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'app_theme.dart';
import 'product_motion.dart';

/// A01 shares press timing across every Flutter product button. The underlying
/// Material control retains keyboard, focus, semantics and minimum hit targets.
class ProductButton extends StatefulWidget {
  const ProductButton.text({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
  }) : kind = 0,
       icon = null,
       tooltip = null;
  const ProductButton.filled({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
    this.icon,
  }) : kind = 1,
       tooltip = null;
  const ProductButton.outlined({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
    this.icon,
  }) : kind = 2,
       tooltip = null;
  const ProductButton.icon({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.tooltip,
    this.style,
  }) : kind = 3,
       child = null;
  final int kind;
  final VoidCallback? onPressed;
  final Widget? child;
  final Widget? icon;
  final String? tooltip;
  final ButtonStyle? style;
  @override
  State<ProductButton> createState() => _ProductButtonState();
}

class _ProductButtonState extends State<ProductButton> {
  final states = WidgetStatesController();
  bool? paintedEnabled;
  @override
  void initState() {
    super.initState();
    states.addListener(_changed);
  }

  void _changed() {
    // Material updates disabled/focus state while reconciling its child. Wait
    // until that build finishes; pointer-driven transitions can rebuild now.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    states.removeListener(_changed);
    states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pressed = states.value.contains(WidgetState.pressed);
    final large = productUsesLargeText(context);
    final original = widget.style ?? const ButtonStyle();
    final style = original.copyWith(
      minimumSize: WidgetStatePropertyAll(
        Size(48, widget.kind == 1 ? (large ? 88 : 56) : 48),
      ),
      animationDuration: ProductMotion.duration(context, pressed ? 80 : 120),
      splashFactory: NoSplash.splashFactory,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      backgroundColor: WidgetStateProperty.resolveWith((value) {
        final base =
            original.backgroundColor?.resolve(value) ??
            (widget.kind == 1
                ? (value.contains(WidgetState.disabled)
                      ? AppTheme.selected
                      : AppTheme.accent)
                : Colors.transparent);
        return value.contains(WidgetState.pressed)
            ? Color.alphaBlend(const Color(0x22FFFFFF), base)
            : base;
      }),
      side: WidgetStateProperty.resolveWith(
        (value) => value.contains(WidgetState.focused)
            ? const BorderSide(color: AppTheme.text, width: 2)
            : original.side?.resolve(value),
      ),
    );
    final child = widget.icon != null && widget.kind != 3
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              widget.icon!,
              const SizedBox(width: 8),
              Flexible(child: widget.child!),
            ],
          )
        : widget.child;
    final effectiveStates = {...states.value};
    if (widget.onPressed == null) {
      effectiveStates.add(WidgetState.disabled);
    } else {
      effectiveStates.remove(WidgetState.disabled);
    }
    final target = style.backgroundColor!.resolve(effectiveStates)!;
    final enabled = widget.onPressed != null;
    final enabledChanged = paintedEnabled != null && paintedEnabled != enabled;
    paintedEnabled = enabled;
    // Material's animationDuration animates elevation, not its fill color.
    // Interpolate the actual painted fill, retaining the Material focus node.
    return TweenAnimationBuilder<Color?>(
      // Enabled state and its foreground must switch together. Only pointer
      // feedback interpolates the fill; otherwise dark enabled text can paint
      // over the previous disabled background during an async completion.
      tween: ColorTween(begin: target, end: target),
      duration: enabledChanged
          ? Duration.zero
          : ProductMotion.duration(context, pressed ? 80 : 120),
      builder: (context, color, _) {
        final painted = style.copyWith(
          backgroundColor: WidgetStatePropertyAll(
            MediaQuery.disableAnimationsOf(context) ? target : color,
          ),
        );
        return switch (widget.kind) {
          1 => FilledButton(
            statesController: states,
            style: painted,
            onPressed: widget.onPressed,
            child: child!,
          ),
          2 => OutlinedButton(
            statesController: states,
            style: painted,
            onPressed: widget.onPressed,
            child: child!,
          ),
          3 => Tooltip(
            message: widget.tooltip!,
            excludeFromSemantics: true,
            child: IconButton(
              statesController: states,
              style: painted,
              onPressed: widget.onPressed,
              icon: Semantics(label: widget.tooltip, child: widget.icon!),
            ),
          ),
          _ => TextButton(
            statesController: states,
            style: painted,
            onPressed: widget.onPressed,
            child: child!,
          ),
        };
      },
    );
  }
}

/// The OH embedding exports labels but drops tooltip-only semantics.
class ProductBackButton extends StatelessWidget {
  const ProductBackButton({super.key, required this.label, this.onPressed});
  final String label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => ProductButton.icon(
    tooltip: label,
    icon: const Icon(Icons.arrow_back),
    onPressed:
        onPressed ??
        () {
          Navigator.maybePop(context);
        },
  );
}
