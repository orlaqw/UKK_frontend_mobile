import 'package:flutter/material.dart';

import 'app_gradient_background.dart';

class AppGradientScaffold extends StatelessWidget {
  final String title;
  final Widget child;
  final bool showBack;
  final List<Widget>? actions;
  final LinearGradient? backgroundGradient;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;

  const AppGradientScaffold({
    super.key,
    required this.title,
    required this.child,
    this.showBack = true,
    this.actions,
    this.backgroundGradient,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: showBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: Navigator.of(context).canPop()
                    ? () => Navigator.of(context).pop()
                    : null,
              )
            : null,
        title: Text(title),
        actions: actions,
      ),
      body: SafeArea(
        child: AppGradientBackground(
          gradient: backgroundGradient,
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
    );
  }
}
