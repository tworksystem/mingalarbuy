import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Centers content and caps width on large web/desktop viewports.
class ResponsiveShell extends StatelessWidget {
  const ResponsiveShell({
    super.key,
    required this.child,
    this.maxWidth = 1200,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  static bool isWideLayout(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= 1024;
  }

  static bool isTabletLayout(BuildContext context) {
    final double w = MediaQuery.sizeOf(context).width;
    return w >= 600 && w < 1024;
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && MediaQuery.sizeOf(context).width < maxWidth) {
      return child;
    }

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}
