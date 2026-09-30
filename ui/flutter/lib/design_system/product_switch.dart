import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'product_button.dart';
import 'product_motion.dart';

/// A11: value is the acknowledged owner state, never a local optimistic value.
class ProductSwitch extends StatelessWidget {
  const ProductSwitch({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
  });
  final bool value;
  final String label;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: label,
    toggled: value,
    enabled: onChanged != null,
    onTap: onChanged == null ? null : () => onChanged!(!value),
    excludeSemantics: true,
    child: ProductButton.text(
      onPressed: onChanged == null ? null : () => onChanged!(!value),
      style: TextButton.styleFrom(padding: const EdgeInsets.all(8)),
      child: AnimatedContainer(
        key: ValueKey(MediaQuery.disableAnimationsOf(context)),
        duration: ProductMotion.duration(context, 150),
        width: 52,
        height: 32,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: value ? AppTheme.accent : AppTheme.surface,
          border: Border.all(
            color: onChanged == null ? AppTheme.muted : AppTheme.text,
            width: 2,
          ),
        ),
        child: AnimatedAlign(
          duration: ProductMotion.duration(context, 150),
          curve: Curves.easeInOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            key: const ValueKey('product-switch-thumb'),
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value ? AppTheme.background : AppTheme.text,
            ),
          ),
        ),
      ),
    ),
  );
}

class ProductSwitchTile extends StatelessWidget {
  const ProductSwitchTile({
    super.key,
    required this.value,
    required this.title,
    required this.onChanged,
  });
  final bool value;
  final String title;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: ListTile(
      title: Text(title),
      onTap: onChanged == null ? null : () => onChanged!(!value),
      trailing: ProductSwitch(value: value, label: title, onChanged: onChanged),
    ),
  );
}
