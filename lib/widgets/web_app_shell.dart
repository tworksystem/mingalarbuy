import 'package:ecommerce_int2/theme/app_theme.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Global Flutter Web shell — text selection, scrollbar theme, loading chrome.
class WebAppShell extends StatelessWidget {
  const WebAppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return child;

    return SelectionArea(
      child: Theme(
        data: Theme.of(context).copyWith(
          scrollbarTheme: ScrollbarThemeData(
            thumbVisibility: WidgetStateProperty.all(true),
            radius: const Radius.circular(4),
            thickness: WidgetStateProperty.all(6),
            thumbColor: WidgetStateProperty.all(
              AppTheme.brightPurple.withValues(alpha: 0.45),
            ),
          ),
        ),
        child: child,
      ),
    );
  }
}

/// Centers form/content on wide web viewports (auth, settings, checkout).
class WebFormFrame extends StatelessWidget {
  const WebFormFrame({
    super.key,
    required this.child,
    this.maxWidth = 480,
    this.padding = const EdgeInsets.symmetric(horizontal: 24),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  static bool shouldCenter(BuildContext context) {
    return kIsWeb && MediaQuery.sizeOf(context).width >= 600;
  }

  @override
  Widget build(BuildContext context) {
    if (!shouldCenter(context)) {
      return Padding(padding: padding, child: child);
    }

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Centers page body on wide web (lists, detail pages).
class WebPageFrame extends StatelessWidget {
  const WebPageFrame({
    super.key,
    required this.child,
    this.maxWidth = 960,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return child;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
