import 'product_button.dart';
import 'package:flutter/material.dart';
import 'product_motion.dart';
import 'product_strings.dart';

class _ProductDialogRoute<T> extends RawDialogRoute<T> {
  _ProductDialogRoute(BuildContext context, Widget child)
    : _reverseDuration = ProductMotion.duration(context, 120),
      super(
        barrierDismissible: true,
        barrierLabel: MaterialLocalizations.of(
          context,
        ).modalBarrierDismissLabel,
        transitionDuration: ProductMotion.duration(context, 180),
        pageBuilder: (context, a, b) => SafeArea(child: child),
        transitionBuilder: (context, a, b, child) => FadeTransition(
          opacity: MediaQuery.disableAnimationsOf(context)
              ? AlwaysStoppedAnimation(
                  a.status == AnimationStatus.reverse ? 0 : 1,
                )
              : a,
          child: ScaleTransition(
            scale: MediaQuery.disableAnimationsOf(context)
                ? const AlwaysStoppedAnimation(1)
                : Tween<double>(begin: .96, end: 1).animate(
                    CurvedAnimation(parent: a, curve: Curves.easeOutCubic),
                  ),
            child: child,
          ),
        ),
      );
  final Duration _reverseDuration;
  @override
  Duration get reverseTransitionDuration => _reverseDuration;
}

Future<T?> productDialog<T>(BuildContext context, Widget child) => Navigator.of(
  context,
  rootNavigator: true,
).push<T>(_ProductDialogRoute<T>(context, child));

Future<bool> productConfirm(
  BuildContext context,
  ProductStrings s,
  String title,
  String message,
) async =>
    await productDialog<bool>(
      context,
      AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          ProductButton.text(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.text('Cancel', '取消')),
          ),
          ProductButton.filled(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.text('Confirm', '确认')),
          ),
        ],
      ),
    ) ??
    false;
