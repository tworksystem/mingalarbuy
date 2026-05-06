// Hard-kill modal UI: legacy helpers kept for future re-enable; analyzer may warn on unused.
// ignore_for_file: unused_element, unused_field

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ecommerce_int2/services/point_notification_manager.dart';
import 'dart:math' as math;

/// Point celebration UI for **[showDialog]** routes only.
///
/// In-feed **poll results** (percentages / winner option) are rendered by
/// the carousel poll result card, **not** by this widget.
///
/// When [suppressAsDialogOverlay] is true (default), the dialog shows no
/// celebration surface (poll win popups stay off; carousel results unaffected).
class PointNotificationModal extends StatefulWidget {
  final PointNotificationEvent event;

  /// `true` = silence popup chrome when this widget is used as a dialog overlay.
  /// Does not affect carousel poll result widgets (they never construct this class).
  final bool suppressAsDialogOverlay;

  const PointNotificationModal({
    super.key,
    required this.event,
    this.suppressAsDialogOverlay = true,
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

    if (widget.suppressAsDialogOverlay) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return;
    }

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
    if (!widget.suppressAsDialogOverlay) {
      _scaleController.dispose();
      _fadeController.dispose();
      _rotationController.dispose();
      _pulseController.dispose();
      _confettiController.dispose();
    }
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
    // Empty surface; [suppressAsDialogOverlay] gates [initState] pop + future full UI.
    return const SizedBox.shrink();
  }
}
