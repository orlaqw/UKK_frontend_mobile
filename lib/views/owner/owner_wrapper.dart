import 'package:flutter/material.dart';

class OwnerWrapper extends StatelessWidget {
  final Widget child;

  const OwnerWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: Navigator.of(context).canPop()
              ? () => Navigator.of(context).pop()
              : null,
        ),
        title: const Text('Owner Panel'),
      ),
      body: child,
    );
  }
}
