import 'dart:async';

import 'package:ecommerce_int2/utils/logger.dart';

/// Foreground sync dedupe + in-flight locks (prevents overlapping API storms).
///
/// **Emergency lane:** [SyncCoordinatorPriority.critical] skips time dedupe but
/// still respects in-flight lock unless [force: true].
enum SyncCoordinatorPriority {
  critical,
  high,
  normal,
  low,
}

/// Coordinates periodic / resume / fallback sync without replacing domain logic.
class SyncCoordinator {
  SyncCoordinator._();

  static final SyncCoordinator instance = SyncCoordinator._();

  static const Duration defaultMinInterval = Duration(seconds: 10);
  static const Duration fallbackMinInterval = Duration(seconds: 45);
  static const Duration resumeMinInterval = Duration(seconds: 20);
  static const Duration lockWatchdog = Duration(seconds: 30);

  final Map<String, DateTime> _lastCompletedAt = {};
  final Map<String, DateTime> _lockAcquiredAt = {};
  final Set<String> _inFlight = {};

  String? _sessionUserId;

  /// Call on login/logout/account switch so dedupe keys do not leak across users.
  void resetForSessionChange({String? userId}) {
    if (_sessionUserId == userId) return;
    _sessionUserId = userId;
    _lastCompletedAt.clear();
    _releaseAllLocks();
    Logger.info(
      'SyncCoordinator session reset (userId=${userId ?? "none"})',
      tag: 'SyncCoordinator',
    );
  }

  static String pointsFallbackKey(String userId) => 'points:fallback:$userId';

  static String pointsResumeKey(String userId) => 'points:resume:$userId';

  static String engagementFcmKey(String userId) => 'engagement:fcm:$userId';

  /// App resume poll result / loss reconcile (feed + silent /poll/results sync).
  static String engagementResumePollKey(String userId) =>
      'engagement:resume_poll:$userId';

  /// Periodic engagement feed poll only — not used for [forceRefresh] paths.
  static String engagementPollKey(String userId) => 'engagement:poll:$userId';

  /// Returns true when the caller should run sync work.
  bool tryBegin({
    required String key,
    Duration minInterval = defaultMinInterval,
    SyncCoordinatorPriority priority = SyncCoordinatorPriority.normal,
    bool force = false,
  }) {
    _sweepStaleLocks();

    if (!force && priority != SyncCoordinatorPriority.critical) {
      final last = _lastCompletedAt[key];
      if (last != null && DateTime.now().difference(last) < minInterval) {
        Logger.info(
          'SyncCoordinator skip (dedupe) key=$key',
          tag: 'SyncCoordinator',
        );
        return false;
      }
    }

    if (_inFlight.contains(key)) {
      Logger.info(
        'SyncCoordinator skip (in-flight) key=$key',
        tag: 'SyncCoordinator',
      );
      return false;
    }

    _inFlight.add(key);
    _lockAcquiredAt[key] = DateTime.now();
    return true;
  }

  void complete(String key) {
    _lastCompletedAt[key] = DateTime.now();
    _release(key);
  }

  void cancel(String key) {
    _release(key);
  }

  void _release(String key) {
    _inFlight.remove(key);
    _lockAcquiredAt.remove(key);
  }

  void _releaseAllLocks() {
    _inFlight.clear();
    _lockAcquiredAt.clear();
  }

  void _sweepStaleLocks() {
    final now = DateTime.now();
    for (final entry in Map<String, DateTime>.from(_lockAcquiredAt).entries) {
      if (now.difference(entry.value) > lockWatchdog) {
        Logger.warning(
          'SyncCoordinator releasing stale lock key=${entry.key}',
          tag: 'SyncCoordinator',
        );
        _release(entry.key);
      }
    }
  }
}

/// Runs [action] when [tryBegin] allows; always completes/cancels the lock.
/// Returns `true` if [action] ran, `false` if deduped / already in-flight.
Future<bool> runGuarded({
  required String key,
  required Future<void> Function() action,
  Duration minInterval = SyncCoordinator.defaultMinInterval,
  SyncCoordinatorPriority priority = SyncCoordinatorPriority.normal,
  bool force = false,
}) async {
  final coordinator = SyncCoordinator.instance;
  if (!coordinator.tryBegin(
    key: key,
    minInterval: minInterval,
    priority: priority,
    force: force,
  )) {
    return false;
  }
  try {
    await action();
    return true;
  } catch (e, st) {
    Logger.warning(
      'SyncCoordinator guarded action failed key=$key: $e',
      tag: 'SyncCoordinator',
      error: e,
      stackTrace: st,
    );
    rethrow;
  } finally {
    coordinator.complete(key);
  }
}
