import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ecommerce_int2/services/point_notification_manager.dart';
import 'dart:math' as math;

/// Professional, Creative Point Notification Modal
///
/// A beautiful modal popup that displays point notifications on the home page
/// - Requires user interaction to close (not dismissible by tapping outside)
/// - Animated entrance and exit
/// - Creative design with gradients and animations
/// - Responsive and accessible
class PointNotificationModal extends StatefulWidget {
  final PointNotificationEvent event;

  const PointNotificationModal({
    super.key,
    required this.event,
  });

  @override
  State<PointNotificationModal> createState() => _PointNotificationModalState();
}

class _PointNotificationModalState extends State<PointNotificationModal>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _fadeController;
  late AnimationController _rotationController;
  late AnimationController _pulseController;
  late AnimationController _confettiController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _rotationAnimation;
  late Animation<double> _pulseAnimation;

  bool _isClosing = false;

  @override
  void initState() {
    super.initState();

    // Scale animation for entrance
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    );

    // Fade animation
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );

    // Rotation animation for decorative elements
    _rotationController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();

    _rotationAnimation = Tween<double>(begin: 0, end: 2 * math.pi).animate(
      CurvedAnimation(
        parent: _rotationController,
        curve: Curves.linear,
      ),
    );

    // Pulse animation for icon
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    // Confetti animation controller
    _confettiController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    // Start animations
    _scaleController.forward();
    _fadeController.forward();

    // PROFESSIONAL FIX: Only show confetti for positive events (not deductions)
    final isPositiveEvent =
        widget.event.type != PointNotificationType.exchangeApproved &&
            (widget.event.type != PointNotificationType.adjusted ||
                (widget.event.additionalData?['isPositive'] as bool? ??
                    widget.event.points > 0));

    if (isPositiveEvent) {
      _confettiController.forward();
    }

    // Haptic feedback - different pattern for deductions vs earnings
    if (widget.event.type == PointNotificationType.exchangeApproved) {
      // Single impact for exchange (deduction)
      HapticFeedback.lightImpact();
    } else {
      // Success pattern for positive events
      HapticFeedback.mediumImpact();
      Future.delayed(const Duration(milliseconds: 100), () {
        HapticFeedback.lightImpact();
      });
    }
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _fadeController.dispose();
    _rotationController.dispose();
    _pulseController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  /// Handle close with animation
  Future<void> _handleClose() async {
    if (_isClosing) return;
    _isClosing = true;

    HapticFeedback.lightImpact();

    // Animate out
    await _fadeController.reverse();
    await _scaleController.reverse();

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// Get icon and colors based on notification type
  Map<String, dynamic> _getNotificationStyle() {
    switch (widget.event.type) {
      case PointNotificationType.earned:
        return {
          'icon': Icons.stars_rounded,
          'primaryColor': const Color(0xFFFFD700), // Gold
          'secondaryColor': const Color(0xFFFFA500), // Orange
          'gradient': const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
          ),
        };

      case PointNotificationType.approved:
        return {
          'icon': Icons.check_circle_rounded,
          'primaryColor': const Color(0xFF4CAF50), // Green
          'secondaryColor': const Color(0xFF81C784), // Light Green
          'gradient': const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4CAF50), Color(0xFF81C784)],
          ),
        };

      case PointNotificationType.engagementEarned:
        return {
          'icon': Icons.emoji_events_rounded,
          'primaryColor': const Color(0xFF9C27B0), // Purple
          'secondaryColor': const Color(0xFFBA68C8), // Light Purple
          'gradient': const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF9C27B0), Color(0xFFBA68C8)],
          ),
        };

      case PointNotificationType.exchangeApproved:
        // PROFESSIONAL FIX: Exchange requests deduct points, so use red/negative styling
        return {
          'icon': Icons.swap_horiz_rounded, // Exchange icon
          'primaryColor': const Color(0xFFF44336), // Red for deduction
          'secondaryColor': const Color(0xFFE57373), // Light Red
          'gradient': const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF44336), Color(0xFFE57373)],
          ),
        };

      case PointNotificationType.adjusted:
        // PROFESSIONAL FIX: Different styling for positive vs negative adjustments
        final isPositive =
            widget.event.additionalData?['isPositive'] as bool? ??
                widget.event.points > 0;
        if (isPositive) {
          return {
            'icon': Icons.add_circle_rounded,
            'primaryColor': const Color(0xFF4CAF50), // Green for positive
            'secondaryColor': const Color(0xFF81C784), // Light Green
            'gradient': const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF4CAF50), Color(0xFF81C784)],
            ),
          };
        } else {
          return {
            'icon': Icons.remove_circle_rounded,
            'primaryColor': const Color(0xFFF44336), // Red for negative
            'secondaryColor': const Color(0xFFE57373), // Light Red
            'gradient': const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF44336), Color(0xFFE57373)],
            ),
          };
        }

      default:
        return {
          'icon': Icons.attach_money_rounded,
          'primaryColor': const Color(0xFF607D8B), // Blue Grey
          'secondaryColor': const Color(0xFF90A4AE), // Light Blue Grey
          'gradient': const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF607D8B), Color(0xFF90A4AE)],
          ),
        };
    }
  }

  /// Get title text based on notification type
  String _getTitle() {
    switch (widget.event.type) {
      case PointNotificationType.earned:
        return 'Points Earned! 🎉';
      case PointNotificationType.approved:
        return 'Points Approved! ✨';
      case PointNotificationType.engagementEarned:
        final isPollWinner =
            widget.event.additionalData?['itemType']?.toString() == 'poll';
        final pollWinCount =
            widget.event.additionalData?['pollWinCount'] as int? ?? 1;
        final itemTitle = widget.event.additionalData?['itemTitle'] as String?;
        final pollName = (itemTitle != null && itemTitle.isNotEmpty)
            ? itemTitle
            : null;
        if (isPollWinner && pollWinCount > 1) {
          return 'Congratulations! You Won in $pollWinCount Polls! 🏆';
        }
        if (isPollWinner && pollName != null) {
          return 'You won: $pollName! 🏆';
        }
        return isPollWinner
            ? "Congratulations! You're the Winner! 🏆"
            : 'Engagement Points! 🎯';
      case PointNotificationType.exchangeApproved:
        return 'Exchange Approved! 💰';
      case PointNotificationType.adjusted:
        // PROFESSIONAL FIX: Different title for positive vs negative adjustments
        final isPositive =
            widget.event.additionalData?['isPositive'] as bool? ??
                widget.event.points > 0;
        // UX requirement: When admin manually ADDS points, show "You Win" in popup.
        return isPositive ? 'You Win! 🏆' : 'Points Adjusted 📊';
      default:
        return 'Points Updated!';
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = _getNotificationStyle();

    return PopScope(
      canPop:
          false, // Prevent back button from closing - user must interact with button
      child: AnimatedBuilder(
        animation: Listenable.merge([_fadeAnimation, _scaleAnimation]),
        builder: (context, child) {
          return Opacity(
            opacity: _fadeAnimation.value,
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: child,
            ),
          );
        },
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(20),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color:
                      (style['primaryColor'] as Color).withValues(alpha: 0.3),
                  blurRadius: 30,
                  spreadRadius: 5,
                  offset: const Offset(0, 10),
                ),
                const BoxShadow(
                  color: Colors.black26,
                  blurRadius: 20,
                  spreadRadius: 2,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Decorative background gradient
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(32),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          (style['primaryColor'] as Color)
                              .withValues(alpha: 0.1),
                          (style['secondaryColor'] as Color)
                              .withValues(alpha: 0.05),
                        ],
                      ),
                    ),
                  ),
                ),

                // Content
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Decorative rotating icon background with pulse animation
                      AnimatedBuilder(
                        animation: Listenable.merge([
                          _rotationAnimation,
                          _pulseAnimation,
                        ]),
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _pulseAnimation.value,
                            child: Transform.rotate(
                              angle: _rotationAnimation.value * 0.1,
                              child: Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: style['gradient'] as LinearGradient,
                                  boxShadow: [
                                    BoxShadow(
                                      color: (style['primaryColor'] as Color)
                                          .withValues(alpha: 0.4),
                                      blurRadius: 25,
                                      spreadRadius: 8,
                                    ),
                                    BoxShadow(
                                      color: (style['primaryColor'] as Color)
                                          .withValues(alpha: 0.2),
                                      blurRadius: 40,
                                      spreadRadius: 15,
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Icon(
                                    style['icon'] as IconData,
                                    size: 60,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 24),

                      // Title
                      Text(
                        _getTitle(),
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: style['primaryColor'] as Color,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 16),

                      // Points display with animation and confetti effect
                      Builder(
                        builder: (context) {
                          // PROFESSIONAL FIX: Determine if this is a positive event (for confetti)
                          final isPositiveEvent = widget.event.type !=
                                  PointNotificationType.exchangeApproved &&
                              (widget.event.type !=
                                      PointNotificationType.adjusted ||
                                  (widget.event.additionalData?['isPositive']
                                          as bool? ??
                                      widget.event.points > 0));

                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              // Confetti particles (decorative) - only for positive events
                              if (isPositiveEvent &&
                                  _confettiController.value > 0)
                                ...List.generate(8, (index) {
                                  final angle = (index * math.pi * 2) / 8;
                                  final progress = _confettiController.value;
                                  final distance = 30 * progress;
                                  return Positioned(
                                    left: math.cos(angle) * distance,
                                    top: math.sin(angle) * distance,
                                    child: Opacity(
                                      opacity: 1 - progress,
                                      child: Icon(
                                        Icons.star,
                                        size: 16,
                                        color: (style['primaryColor'] as Color)
                                            .withValues(alpha: 0.7),
                                      ),
                                    ),
                                  );
                                }),
                              // Points text
                              // PROFESSIONAL FIX: Show negative points for exchange requests
                              TweenAnimationBuilder<double>(
                                tween: Tween<double>(
                                    begin: 0,
                                    end: widget.event.points.toDouble()),
                                duration: const Duration(milliseconds: 1200),
                                curve: Curves.easeOutBack,
                                builder: (context, value, child) {
                                  // Determine if this is a deduction (exchange request or negative adjustment)
                                  final isDeduction = widget.event.type ==
                                          PointNotificationType
                                              .exchangeApproved ||
                                      (widget.event.type ==
                                              PointNotificationType.adjusted &&
                                          (widget.event.additionalData?[
                                                      'isPositive'] as bool? ??
                                                  widget.event.points > 0) ==
                                              false);

                                  // Format points with appropriate sign
                                  final pointsText = isDeduction
                                      ? '-${value.toInt()}'
                                      : '+${value.toInt()}';

                                  return Text(
                                    pointsText,
                                    style: TextStyle(
                                      fontSize: 52,
                                      fontWeight: FontWeight.bold,
                                      color: style['primaryColor'] as Color,
                                      height: 1.2,
                                      shadows: [
                                        Shadow(
                                          color:
                                              (style['primaryColor'] as Color)
                                                  .withValues(alpha: 0.3),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          );
                        },
                      ),

                      Text(
                        'Points',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[700],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Description if available
                      if (widget.event.description != null &&
                          widget.event.description!.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            widget.event.description!,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[800],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),

                      if (widget.event.description != null &&
                          widget.event.description!.isNotEmpty)
                        const SizedBox(height: 16),

                      // Current balance - Professional fix for overflow prevention
                      Container(
                        constraints: const BoxConstraints(
                          maxWidth: double.infinity,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: (style['primaryColor'] as Color)
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: (style['primaryColor'] as Color)
                                .withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Icon - fixed size, always visible
                            Icon(
                              Icons.account_balance_wallet_rounded,
                              color: style['primaryColor'] as Color,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            // Text - flexible to prevent overflow
                            Flexible(
                              child: Text(
                                'New Balance: ${widget.event.currentBalance} points',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: style['primaryColor'] as Color,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Action button with improved styling
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _handleClose,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: style['primaryColor'] as Color,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 6,
                            shadowColor: (style['primaryColor'] as Color)
                                .withValues(alpha: 0.4),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                'Got it!',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.check_circle_outline,
                                size: 20,
                                color: Colors.white,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Decorative corner elements
                Positioned(
                  top: -20,
                  right: -20,
                  child: AnimatedBuilder(
                    animation: _rotationAnimation,
                    builder: (context, child) {
                      return Transform.rotate(
                        angle: _rotationAnimation.value * 0.05,
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: (style['primaryColor'] as Color)
                                .withValues(alpha: 0.1),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
