import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'logger.dart';

/// Professional error handling utility for the e-commerce app
class ErrorHandler {
  static void handleError(dynamic error, StackTrace? stackTrace,
      {String? context}) {
    Logger.error(
      'ERROR${context != null ? ' in $context' : ''}: $error',
      tag: context ?? 'ErrorHandler',
      error: error,
      stackTrace: stackTrace,
    );

    // Log to crash analytics in production
    if (kReleaseMode) {
      // TODO: Integrate with crash analytics service (Firebase Crashlytics, Sentry, etc.)
      _logToAnalytics(error, stackTrace, context);
    }
  }

  static void _logToAnalytics(
      dynamic error, StackTrace? stackTrace, String? context) {
    // Implementation for production error logging
    // This would integrate with your chosen analytics service
  }

  static void showErrorSnackBar(BuildContext context, String message,
      {Duration? duration}) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[600],
        duration: duration ?? const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  static void showSuccessSnackBar(BuildContext context, String message,
      {Duration? duration}) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green[600],
        duration: duration ?? const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  static void showWarningSnackBar(BuildContext context, String message,
      {Duration? duration}) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange[600],
        duration: duration ?? const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

/// Safe async operation wrapper
class SafeAsync {
  static Future<T?> execute<T>(
    Future<T> Function() operation, {
    String? context,
    T? fallbackValue,
    bool logErrors = true,
  }) async {
    try {
      return await operation();
    } catch (error, stackTrace) {
      if (logErrors) {
        ErrorHandler.handleError(error, stackTrace, context: context);
      }
      return fallbackValue;
    }
  }

  static Future<void> executeVoid(
    Future<void> Function() operation, {
    String? context,
    bool logErrors = true,
  }) async {
    try {
      await operation();
    } catch (error, stackTrace) {
      if (logErrors) {
        ErrorHandler.handleError(error, stackTrace, context: context);
      }
    }
  }
}

/// Widget lifecycle management utilities
class LifecycleManager {
  static bool isWidgetMounted(BuildContext context) {
    return context.mounted;
  }
}

/// Performance monitoring utilities
class PerformanceMonitor {
  static Future<T> measureAsync<T>(
    Future<T> Function() operation,
    String operationName,
  ) async {
    final stopwatch = Stopwatch()..start();

    try {
      final result = await operation();
      stopwatch.stop();

      Logger.debug('$operationName took ${stopwatch.elapsedMilliseconds}ms',
          tag: 'PerformanceMonitor');

      return result;
    } catch (error) {
      stopwatch.stop();
      ErrorHandler.handleError(error, null, context: operationName);
      rethrow;
    }
  }

  static T measureSync<T>(
    T Function() operation,
    String operationName,
  ) {
    final stopwatch = Stopwatch()..start();

    try {
      final result = operation();
      stopwatch.stop();

      Logger.debug('$operationName took ${stopwatch.elapsedMilliseconds}ms',
          tag: 'PerformanceMonitor');

      return result;
    } catch (error) {
      stopwatch.stop();
      ErrorHandler.handleError(error, null, context: operationName);
      rethrow;
    }
  }
}
