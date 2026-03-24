import 'dart:ui';
import 'dart:math' as math;

import 'package:ecommerce_int2/app_properties.dart';
import 'package:ecommerce_int2/theme/app_theme.dart';
import 'package:ecommerce_int2/providers/spin_wheel_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class LuckyBoxRequestSheet extends StatefulWidget {
  final Future<bool> Function()? submit;
  final VoidCallback? onSuccess;
  final bool showPendingOnly;
  final bool showApprovedOnly;

  const LuckyBoxRequestSheet({
    super.key,
    required this.submit,
    this.onSuccess,
    this.showPendingOnly = false,
    this.showApprovedOnly = false,
  });

  static Future<void> show(
    BuildContext context, {
    required Future<bool> Function() submit,
    VoidCallback? onSuccess,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LuckyBoxRequestSheet(
        submit: submit,
        onSuccess: onSuccess,
      ),
    );
  }

  static Future<void> showPendingStatus(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const LuckyBoxRequestSheet(
        submit: null,
        showPendingOnly: true,
      ),
    );
  }

  static Future<void> showApprovedStatus(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const LuckyBoxRequestSheet(
        submit: null,
        showApprovedOnly: true,
      ),
    );
  }

  static Future<void> showBeforeClick(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const LuckyBoxRequestSheet(
        submit: null,
        showPendingOnly: false,
        showApprovedOnly: false,
      ),
    );
  }

  @override
  State<LuckyBoxRequestSheet> createState() => _LuckyBoxRequestSheetState();
}

class _LuckyBoxRequestSheetState extends State<LuckyBoxRequestSheet>
    with TickerProviderStateMixin {
  bool _isSubmitting = true;
  bool? _success;
  bool _playEntry = false;

  // Animation controllers for approved message
  late AnimationController _pulseController;
  late AnimationController _bounceController;
  late AnimationController _shimmerController;

  late Animation<double> _pulseAnimation;
  late Animation<double> _bounceAnimation;
  late Animation<double> _shimmerAnimation;

  @override
  void initState() {
    super.initState();

    // Initialize animation controllers for approved message
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _bounceController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _bounceAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.elasticOut),
    );

    _shimmerAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _playEntry = true);

      // Start animations if showing approved status
      if (widget.showApprovedOnly) {
        _bounceController.forward();
      }

      // Also trigger animation if success becomes true (approval after submission)
      // This will be handled in _run() method
    });

    if (widget.showPendingOnly || widget.showApprovedOnly) {
      _isSubmitting = false;
      _success = true;
      return;
    }
    // Auto-submit when sheet opens - no confirmation needed
    // User clicked Lucky Box button, so directly submit the request
    // Use addPostFrameCallback to avoid setState during build
    if (widget.submit != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _run();
        }
      });
    } else {
      _isSubmitting = false;
      _success = null;
    }
  }

  Future<void> _run() async {
    final submit = widget.submit;
    if (submit == null) return;

    setState(() {
      _isSubmitting = true;
      _success = null;
    });

    try {
      final ok = await submit();
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _success = ok;
      });
      if (ok) {
        widget.onSuccess?.call();
      } else {
        // Log error for debugging
        print('Lucky Box submission failed - check logs for details');
      }
    } catch (e, stackTrace) {
      // Log error for debugging
      print('Lucky Box submission error: $e');
      print('Stack trace: $stackTrace');
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _success = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final safeBottom = media.padding.bottom;
    final spinWheelProvider =
        Provider.of<SpinWheelProvider>(context, listen: false);

    // Determine message state
    final isBeforeClick = !widget.showPendingOnly &&
        !widget.showApprovedOnly &&
        !_isSubmitting &&
        _success == null;
    final isPending = widget.showPendingOnly ||
        (!widget.showApprovedOnly && _success == true && !_isSubmitting);
    final isApproved = widget.showApprovedOnly;

    final title = isApproved
        ? '🎉 ကံကောင်းပါတယ်!'
        : (isPending
            ? '⏳ တောင်းဆိုမှု ဆောင်ရွက်နေပါတယ်'
            : (isBeforeClick
                ? '🎁 Lucky Box ကို ဖွင့်ကြည့်ပါ'
                : (_isSubmitting
                    ? '🔄 တောင်းဆိုနေပါတယ်...'
                    : (_success == true
                        ? '✅ တောင်းဆိုမှု အောင်မြင်ပါပြီ'
                        : '❌ တောင်းဆိုမှု မအောင်မြင်ပါ'))));

    final subtitle = isApproved
        ? 'Admin က သင့်ရဲ့ Lucky Box Request ကို Approve လုပ်ပြီးပါပြီ။\nPoint ကို သင့်အကောင့်ထဲကို ထည့်ပေးပြီးပါပြီ။'
        : (isPending
            ? 'သင့်ရဲ့ Lucky Box Request ကို Admin က စစ်ဆေးနေပါတယ်။\nမကြာခင် Point ထည့်ပေးပါမယ်။\nခဏစောင့်ပေးပါနော်။'
            : (isBeforeClick
                ? 'Lucky Box ကို ဖွင့်လိုက်ရင် သင့်အတွက် အထူးဆုလာဘ်တွေ ရရှိနိုင်ပါတယ်။\nAdmin က သင့်ရဲ့ Request ကို Review လုပ်ပြီး Point ထည့်ပေးပါမယ်။\nကံကောင်းပါစေ! 🍀'
                : (_isSubmitting
                    ? 'Lucky Box Request ကို ပို့နေပါတယ်...\nခဏစောင့်ပေးပါနော်။'
                    : (_success == true
                        ? 'Lucky Box Request ကို အောင်မြင်စွာ ပို့ပြီးပါပြီ။\nPending အနေနဲ့ ဝင်သွားပါပြီ။ Admin က Review လုပ်ပြီး Point ထည့်ပေးပါမယ်။'
                        : (spinWheelProvider.error != null &&
                                spinWheelProvider.error!.isNotEmpty
                            ? '${spinWheelProvider.error}\nနောက်ထပ် တစ်ခါ စမ်းကြည့်ပါ။'
                            : 'Network မကောင်းတာ ဒါမှမဟုတ် Server error ဖြစ်နိုင်ပါတယ်။\nနောက်ထပ် တစ်ခါ စမ်းကြည့်ပါ။')))));

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: safeBottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.transparent,
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 24,
                      offset: const Offset(0, -8),
                    )
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          TweenAnimationBuilder<double>(
                            tween: Tween<double>(
                              begin: 0,
                              end: _playEntry ? 1 : 0,
                            ),
                            duration: const Duration(milliseconds: 650),
                            curve: Curves.easeOutBack,
                            builder: (context, t, child) {
                              return Transform.rotate(
                                angle: (1 - t) * 0.35,
                                child: Transform.scale(
                                  scale: 0.85 + (t * 0.15),
                                  child: child,
                                ),
                              );
                            },
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.20),
                                ),
                              ),
                              child: Center(
                                child: _isSubmitting
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                  Colors.white),
                                        ),
                                      )
                                    : Icon(
                                        _success == true
                                            ? Icons.auto_awesome_rounded
                                            : Icons.close_rounded,
                                        color: Colors.white,
                                        size: 24,
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Show loading state when submitting - only loading indicator, no text
                                if (_isSubmitting) ...[
                                  Row(
                                    children: [
                                      const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                  Colors.white),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    subtitle,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.90),
                                      fontSize: 13,
                                      height: 1.25,
                                    ),
                                  ),
                                ] else ...[
                                  // Animated title for approved status
                                  isApproved
                                      ? _buildAnimatedApprovedTitle(title)
                                      : Text(
                                          title,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                  const SizedBox(height: 6),
                                  Text(
                                    subtitle,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.90),
                                      fontSize: 13,
                                      height: 1.25,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _isSubmitting
                            ? null
                            : () async {
                                // If success or showing status, just close
                                if (_success == true && mounted) {
                                  Navigator.of(context).pop();
                                  return;
                                }
                                // Try again if failed
                                if (_success == false &&
                                    widget.submit != null) {
                                  setState(() {
                                    _isSubmitting = true;
                                    _success = null;
                                  });
                                  await _run();
                                  return;
                                }
                                // Close if no action needed
                                Navigator.of(context).pop();
                              },
                        style: FilledButton.styleFrom(
                          backgroundColor: mediumYellow,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Text(
                                widget.showApprovedOnly
                                    ? 'Thank you'
                                    : (widget.showPendingOnly
                                        ? 'OK'
                                        : (_success == true
                                            ? 'Done'
                                            : (_success == false
                                                ? 'Try Again'
                                                : 'OK'))),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Creative animated title for approved message
  /// Includes: bounce entrance, pulsing effect, and glowing effect
  Widget _buildAnimatedApprovedTitle(String text) {
    return AnimatedBuilder(
      animation: Listenable.merge(
          [_bounceAnimation, _pulseAnimation, _shimmerAnimation]),
      builder: (context, child) {
        // Combine bounce and pulse animations for scale - make it more visible
        final bounceScale =
            0.7 + (_bounceAnimation.value * 0.3); // 0.7 to 1.0 (more dramatic)
        final pulseScale =
            _pulseAnimation.value; // 1.0 to 1.15 (more visible pulse)
        final finalScale = bounceScale * pulseScale;

        // Create pulsing glow effect based on shimmer animation
        final glowIntensity = 0.6 +
            (0.4 *
                (0.5 + 0.5 * math.sin(_shimmerAnimation.value * 2 * math.pi)));

        return Transform.scale(
          scale: finalScale,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.yellow.shade400
                      .withValues(alpha: 0.7 * glowIntensity),
                  blurRadius: 15 * finalScale,
                  spreadRadius: 3 * finalScale,
                ),
                BoxShadow(
                  color: Colors.amber.shade400
                      .withValues(alpha: 0.5 * glowIntensity),
                  blurRadius: 25 * finalScale,
                  spreadRadius: 2 * finalScale,
                ),
              ],
            ),
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                shadows: [
                  // Main shadow for depth
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                  // Yellow glow shadow
                  Shadow(
                    color: Colors.yellow.shade400
                        .withValues(alpha: 0.9 * glowIntensity),
                    blurRadius: 10,
                    offset: const Offset(0, 0),
                  ),
                  // Amber glow shadow
                  Shadow(
                    color: Colors.amber.shade400
                        .withValues(alpha: 0.7 * glowIntensity),
                    blurRadius: 15,
                    offset: const Offset(0, 0),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
