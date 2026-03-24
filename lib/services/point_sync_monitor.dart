import 'dart:async';

import 'package:ecommerce_int2/utils/logger.dart';

class PointSyncStats {
  const PointSyncStats({
    this.successCount = 0,
    this.failureCount = 0,
    this.consecutiveFailures = 0,
    this.lastErrorMessage,
    this.lastTransactionId,
  });

  final int successCount;
  final int failureCount;
  final int consecutiveFailures;
  final String? lastErrorMessage;
  final String? lastTransactionId;

  PointSyncStats copyWith({
    int? successCount,
    int? failureCount,
    int? consecutiveFailures,
    String? lastErrorMessage,
    String? lastTransactionId,
  }) {
    return PointSyncStats(
      successCount: successCount ?? this.successCount,
      failureCount: failureCount ?? this.failureCount,
      consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
      lastErrorMessage: lastErrorMessage ?? this.lastErrorMessage,
      lastTransactionId: lastTransactionId ?? this.lastTransactionId,
    );
  }
}

/// Lightweight telemetry helper that keeps track of point sync successes and
/// failures. Consumers can listen through the broadcast stream to surface
/// diagnostics in developer tooling or in-app dashboards.
class PointSyncMonitor {
  PointSyncMonitor._();

  static final StreamController<PointSyncStats> _controller =
      StreamController<PointSyncStats>.broadcast();
  static PointSyncStats _current = const PointSyncStats();

  static Stream<PointSyncStats> get stream => _controller.stream;
  static PointSyncStats get current => _current;

  static void recordSuccess(String transactionId) {
    _updateStats(
      _current.copyWith(
        successCount: _current.successCount + 1,
        consecutiveFailures: 0,
        lastErrorMessage: null,
        lastTransactionId: transactionId,
      ),
    );

    Logger.info(
      'Point transaction synced',
      tag: 'PointSync',
      metadata: {'transactionId': transactionId},
    );
  }

  static void recordFailure({
    required String transactionId,
    required String message,
    int attempt = 0,
    dynamic error,
  }) {
    _updateStats(
      _current.copyWith(
        failureCount: _current.failureCount + 1,
        consecutiveFailures: _current.consecutiveFailures + 1,
        lastErrorMessage: message,
        lastTransactionId: transactionId,
      ),
    );

    Logger.error(
      'Point transaction sync failed: $message',
      tag: 'PointSync',
      error: error,
      metadata: {
        'transactionId': transactionId,
        'attempt': attempt,
        'consecutiveFailures': _current.consecutiveFailures,
      },
    );
  }

  static void _updateStats(PointSyncStats stats) {
    _current = stats;
    if (!_controller.hasListener) {
      return;
    }
    _controller.add(stats);
  }

  static Future<void> dispose() async {
    await _controller.close();
  }
}

