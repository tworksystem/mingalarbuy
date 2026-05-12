import 'dart:async';

/// Global FIFO queue for **all** point-balance mutations that must not race:
/// [CanonicalPointBalanceSync.apply], [PointProvider.loadBalance], [AuthProvider.refreshUser],
/// and poll-win smart polling (which calls the same unlocked loader under this lock).
///
/// My PNP shimmer is refcounted via [PointProvider.beginBalanceSync] / [PointProvider.endBalanceSync]
/// so parallel flows do not clear each other's loading state.
///
/// [run] is **reentrant**: nested `run` from the same outer serialized task does not
/// deadlock (e.g. [CanonicalPointBalanceSync.apply] → [AuthProvider.applyPointsBalanceSnapshot]
/// → [PointBalanceSyncLock.run] while already holding the queue slot).
///
/// Keeping a dedicated file avoids a circular import between
/// `canonical_point_balance_sync.dart` and `point_provider.dart`.
class PointBalanceSyncLock {
  PointBalanceSyncLock._();

  static Future<void> _tail = Future<void>.value();
  static int _depth = 0;

  /// Runs [work] after all prior queued work completes (including failures).
  static Future<T> run<T>(Future<T> Function() work) async {
    if (_depth > 0) {
      _depth++;
      try {
        return await work();
      } finally {
        _depth--;
      }
    }

    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    try {
      await previous.catchError((Object _, StackTrace __) {});
      _depth = 1;
      try {
        return await work();
      } finally {
        _depth = 0;
      }
    } finally {
      if (!done.isCompleted) {
        done.complete();
      }
    }
  }
}
