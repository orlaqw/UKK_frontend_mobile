import 'package:flutter/material.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.margin = EdgeInsets.zero,
    this.onTap,
    this.color,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(16);

    Widget content = Card(
      elevation: 0,
      color: color ?? cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: borderColor ?? cs.outlineVariant.withAlpha(153),
        ),
      ),
      child: Padding(padding: padding, child: child),
    );

    if (onTap != null) {
      content = InkWell(borderRadius: radius, onTap: onTap, child: content);
    }

    return Padding(padding: margin, child: content);
  }
}
