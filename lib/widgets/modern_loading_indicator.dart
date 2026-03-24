import 'package:flutter/material.dart';
import 'package:ecommerce_int2/theme/app_theme.dart';
import 'dart:math' as math;

/// Modern, creative loading indicator widget
/// Replaces simple CircularProgressIndicator with an animated, beautiful design
class ModernLoadingIndicator extends StatefulWidget {
  final double? size;
  final Color? color;
  final String? message;
  final bool showMessage;

  const ModernLoadingIndicator({
    super.key,
    this.size,
    this.color,
    this.message,
    this.showMessage = false,
  });

  @override
  State<ModernLoadingIndicator> createState() => _ModernLoadingIndicatorState();
}

class _ModernLoadingIndicatorState extends State<ModernLoadingIndicator>
    with TickerProviderStateMixin {
  late AnimationController _rotationController;
  late AnimationController _pulseController;
  late AnimationController _waveController;
  late Animation<double> _rotationAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _waveAnimation;

  @override
  void initState() {
    super.initState();

    // Rotation animation for outer ring
    _rotationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    // Pulse animation for center circle
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);

    // Wave animation for particles
    _waveController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();

    _rotationAnimation = Tween<double>(begin: 0, end: 2 * math.pi)
        .animate(CurvedAnimation(
      parent: _rotationController,
      curve: Curves.linear,
    ));

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    _waveAnimation = Tween<double>(begin: 0, end: 2 * math.pi).animate(
      CurvedAnimation(
        parent: _waveController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _pulseController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size ?? 50.0;
    final color = widget.color ?? AppTheme.brightPurple;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer rotating ring with gradient
              AnimatedBuilder(
                animation: _rotationAnimation,
                builder: (context, child) {
                  return Transform.rotate(
                    angle: _rotationAnimation.value,
                    child: CustomPaint(
                      size: Size(size, size),
                      painter: _RotatingRingPainter(
                        color: color,
                        strokeWidth: size * 0.08,
                      ),
                    ),
                  );
                },
              ),

              // Orbiting particles
              ...List.generate(3, (index) {
                return AnimatedBuilder(
                  animation: _waveAnimation,
                  builder: (context, child) {
                    final angle = (_waveAnimation.value + (index * 2 * math.pi / 3));
                    final radius = size * 0.35;
                    final x = math.cos(angle) * radius;
                    final y = math.sin(angle) * radius;
                    final particleSize = size * 0.12;
                    final opacity = (math.sin(angle) + 1) / 2;

                    return Positioned(
                      left: (size / 2) + x - (particleSize / 2),
                      top: (size / 2) + y - (particleSize / 2),
                      child: Container(
                        width: particleSize,
                        height: particleSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              color.withOpacity(0.9 * opacity),
                              color.withOpacity(0.3 * opacity),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: color.withOpacity(0.5 * opacity),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              }),

              // Pulsing center circle
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _pulseAnimation.value,
                    child: Container(
                      width: size * 0.3,
                      height: size * 0.3,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            color,
                            color.withOpacity(0.3),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: color.withOpacity(0.6),
                            blurRadius: 12,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),

        // Optional message
        if (widget.showMessage && widget.message != null) ...[
          const SizedBox(height: 16),
          Text(
            widget.message!,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

/// Painter for the rotating ring with gradient
class _RotatingRingPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  _RotatingRingPainter({
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - (strokeWidth / 2);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Draw gradient arc
    final rect = Rect.fromCircle(center: center, radius: radius);
    final gradient = SweepGradient(
      colors: [
        color.withOpacity(0.2),
        color.withOpacity(0.8),
        color,
        color.withOpacity(0.8),
        color.withOpacity(0.2),
      ],
      stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
    );

    paint.shader = gradient.createShader(rect);

    // Draw arc (3/4 of the circle)
    canvas.drawArc(
      rect,
      0,
      2.4 * math.pi,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Compact version for inline loading (smaller size)
class ModernLoadingIndicatorSmall extends StatelessWidget {
  final Color? color;

  const ModernLoadingIndicatorSmall({
    super.key,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ModernLoadingIndicator(
      size: 28,
      color: color,
    );
  }
}

/// Large version with message for full-screen loading
class ModernLoadingIndicatorLarge extends StatelessWidget {
  final String? message;
  final Color? color;

  const ModernLoadingIndicatorLarge({
    super.key,
    this.message,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ModernLoadingIndicator(
      size: 80,
      color: color,
      message: message ?? 'Loading...',
      showMessage: true,
    );
  }
}

