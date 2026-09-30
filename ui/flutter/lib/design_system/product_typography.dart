import 'package:flutter/widgets.dart';

/// Selects the accessible layout from the user preference, independently of
/// Android's non-linear scaling of individual font sizes. Text still uses the
/// unmodified system TextScaler; this value is never used to size text.
bool productUsesLargeText(BuildContext context) {
  // SystemTextScaler documents this value as the user's preference. The base
  // getter is deprecated for font-size arithmetic, which is not performed here.
  // ignore: deprecated_member_use
  return MediaQuery.textScalerOf(context).textScaleFactor >= 1.8;
}
