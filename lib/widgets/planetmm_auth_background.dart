import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Shared PlanetMM space artwork + gradient overlay for auth screens.
class PlanetMMAuthBackground extends StatelessWidget {
  final Widget child;

  const PlanetMMAuthBackground({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final bool wideWeb =
        kIsWeb && MediaQuery.sizeOf(context).width >= 1024;
    final BoxFit logoFit = wideWeb ? BoxFit.cover : BoxFit.contain;

    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        Positioned.fill(
          child: Opacity(
            opacity: wideWeb ? 0.65 : 0.85,
            child: Image.asset(
              'assets/icons/planetmm_inapplogo.png',
              fit: logoFit,
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withValues(alpha: 0.75),
                  Colors.black.withValues(alpha: 0.55),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
