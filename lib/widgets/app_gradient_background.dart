import 'package:flutter/material.dart';

class AppGradientBackground extends StatelessWidget {
  final Widget child;
  final LinearGradient? gradient;

  const AppGradientBackground({super.key, required this.child, this.gradient});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final g =
        gradient ??
        LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primary.withAlpha(36),
            cs.secondary.withAlpha(26),
            cs.surface,
          ],
          stops: const [0.0, 0.45, 1.0],
        );
    return LayoutBuilder(
      builder: (context, constraints) {
        return DecoratedBox(
          decoration: BoxDecoration(gradient: g),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: child,
          ),
        );
      },
    );
  }
}
