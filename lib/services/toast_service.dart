import 'package:ecommerce_int2/services/global_keys.dart';
import 'package:flutter/material.dart';

/// Lightweight helper for showing snackbars from non-UI layers.
class ToastService {
  ToastService._();

  /// Shown when ledger verification (poll win / vote reconcile) exhausts retries.
  static const String pointsVerificationTimeoutMessage =
      'Points update may take a few moments.';

  /// UX for [PointProvider] verification loops that fail after repeated GETs.
  /// Returns `true` if a snackbar was shown; `false` if no [ScaffoldMessenger] (caller may fallback).
  static bool showPointsVerificationTimeout({
    Duration duration = const Duration(seconds: 4),
  }) {
    final messenger = AppKeys.scaffoldMessengerKey.currentState;
    if (messenger == null) {
      return false;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text(pointsVerificationTimeoutMessage),
          duration: duration,
          behavior: SnackBarBehavior.floating,
        ),
      );
    return true;
  }

  static void showInfo(
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    _showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static void showError(
    String message, {
    Duration duration = const Duration(seconds: 4),
  }) {
    _showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static void _showSnackBar(SnackBar snackBar) {
    final messenger = AppKeys.scaffoldMessengerKey.currentState;
    if (messenger != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(snackBar);
    }
  }
}
