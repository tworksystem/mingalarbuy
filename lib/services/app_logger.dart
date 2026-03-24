import 'dart:async';

import 'package:ecommerce_int2/utils/logger.dart';
import 'package:flutter/foundation.dart';

/// Centralized application logging bootstrapper.
///
/// Hooks into Flutter's error pipelines and guards the root zone so that
/// uncaught exceptions are captured and routed through the shared [Logger].
class AppLogger {
  static bool _initialized = false;

  /// Initializes framework level error handlers. Idempotent.
  static void initialize() {
    if (_initialized) return;
    _initialized = true;

    FlutterError.onError = (details) {
      Logger.error(
        'FlutterError: ${details.exceptionAsString()}',
        tag: 'AppLogger',
        error: details.exception,
        stackTrace: details.stack,
      );
      // Preserve default behavior in debug to aid developer tooling.
      FlutterError.presentError(details);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      Logger.fatal(
        'Uncaught platform error: $error',
        tag: 'AppLogger',
        error: error,
        stackTrace: stack,
      );
      return true;
    };
  }

  /// Runs the provided asynchronous [body] inside a guarded zone so that any
  /// uncaught errors are logged consistently.
  static Future<void> guard(Future<void> Function() body) async {
    await runZonedGuarded(
      () async {
        await body();
      },
      (error, stackTrace) {
        Logger.fatal(
          'Uncaught zone error: $error',
          tag: 'AppLogger',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );
  }
}
