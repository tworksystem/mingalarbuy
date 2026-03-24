import 'dart:async';

import 'package:ecommerce_int2/models/point_transaction.dart';
import 'package:ecommerce_int2/services/point_sync_monitor.dart';
import 'package:ecommerce_int2/utils/logger.dart';

/// Telemetry event emitted whenever a point sync attempt finishes.
class PointSyncEvent {
  final bool success;
  final PointTransaction transaction;
  final int attempt;
  final Duration? backoff;
  final String context;
  final String? userMessage;
  final bool userFacing;

  const PointSyncEvent.success({
    required this.transaction,
    required this.attempt,
    this.context = '',
  })  : success = true,
        backoff = null,
        userMessage = null,
        userFacing = false;

  const PointSyncEvent.failure({
    required this.transaction,
    required this.attempt,
    required this.backoff,
    required this.context,
    this.userMessage,
    this.userFacing = false,
  }) : success = false;
}

/// Centralized instrumentation for point sync operations.
class PointSyncTelemetry {
  PointSyncTelemetry._();

  static final StreamController<PointSyncEvent> _controller =
      StreamController<PointSyncEvent>.broadcast();

  static Stream<PointSyncEvent> get events => _controller.stream;

  static void recordSuccess({
    required PointTransaction transaction,
    required int attempt,
    String context = '',
  }) {
    final event = PointSyncEvent.success(
      transaction: transaction,
      attempt: attempt,
      context: context,
    );
    PointSyncMonitor.recordSuccess(transaction.id);
    Logger.info(
      'Point sync succeeded on attempt $attempt (${transaction.type.toValue()})',
      tag: 'PointSync',
      stackTrace: null,
    );
    _controller.add(event);
  }

  static Future<void> recordFailure({
    required PointTransaction transaction,
    required int attempt,
    required Duration backoff,
    required String context,
    Object? error,
    bool finalAttempt = false,
  }) async {
    // We still track failures internally, but we no longer want to show
    // user-facing errors for background point sync. Points are now managed
    // primarily from the WordPress dashboard, so hiccups should be silent.
    Logger.error(
      'Point sync attempt $attempt failed (${transaction.type.toValue()})',
      tag: 'PointSync',
      error: error,
    );

    PointSyncMonitor.recordFailure(
      transactionId: transaction.id,
      message: 'Attempt $attempt failed',
      attempt: attempt,
      error: error,
    );

    final event = PointSyncEvent.failure(
      transaction: transaction,
      attempt: attempt,
      backoff: backoff,
      context: context,
      userMessage: null,
      userFacing: false,
    );
    _controller.add(event);
  }
}
