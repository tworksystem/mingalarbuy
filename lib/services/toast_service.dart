import 'package:ecommerce_int2/services/global_keys.dart';
import 'package:flutter/material.dart';

/// Lightweight helper for showing snackbars from non-UI layers.
class ToastService {
  ToastService._();

  static void showInfo(String message, {Duration duration = const Duration(seconds: 3)}) {
    _showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static void showError(String message, {Duration duration = const Duration(seconds: 4)}) {
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

