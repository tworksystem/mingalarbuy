import 'package:flutter/material.dart';

/// A simple, consistent pull-to-refresh wrapper.
///
/// Use this when your screen body is scrollable. For non-scrollable screens,
/// wrap the body with a SingleChildScrollView + AlwaysScrollableScrollPhysics.
class AppPullToRefresh extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final Widget child;

  const AppPullToRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: child,
    );
  }
}


