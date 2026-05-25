import '../providers/auth_provider.dart';
import '../providers/point_provider.dart';
import '../utils/logger.dart';
import '../utils/my_pnp_balance_debug.dart';
import 'point_balance_sync_lock.dart';
import 'point_service.dart';

/// Single entry for poll wins, push snapshots, and other authoritative balances:
/// [AuthProvider] customFields + [PointProvider] memory + SharedPreferences disk,
/// optionally [PointService.notifyPointBalanceBroadcast] for listeners without context.
class CanonicalPointBalanceSync {
  CanonicalPointBalanceSync._();

  /*
  // Old Code: private `_mutexTail` duplicated queue logic here only.
  // static Future<void> _mutexTail = Future<void>.value();
  */

  /// NEW FIX: Align memory, user meta patch, disk cache, and optional broadcast.
  /// Serialized with [PointProvider.loadBalance] via [PointBalanceSyncLock].
  static Future<void> apply({
    required String userId,
    required int currentBalance,
    String source = 'canonical_point_balance',
    bool emitBroadcast = false,
    AuthProvider? authProvider,
    PointProvider? pointProvider,
    BigInt? snapshotSequence,
    DateTime? snapshotObservedAt,
  }) async {
    await PointBalanceSyncLock.run(() async {
      final auth = authProvider ?? AuthProvider();
      if (!auth.isAuthenticated || auth.user == null) {
        Logger.warning(
          'CanonicalPointBalanceSync.apply: skipped — not authenticated '
          '(requested userId=$userId, source=$source)',
          tag: 'CanonicalPointBalanceSync',
        );
        return;
      }
      final String sessionUid = auth.user!.id.toString();
      if (sessionUid != userId) {
        Logger.warning(
          'CanonicalPointBalanceSync.apply: skipped — session user does not match '
          '(session=$sessionUid requested=$userId, source=$source)',
          tag: 'CanonicalPointBalanceSync',
        );
        return;
      }

      final PointProvider points = pointProvider ?? PointProvider.instance;
      if (!identical(points, PointProvider.instance)) {
        Logger.warning(
          'CanonicalPointBalanceSync.apply: injected PointProvider is not the '
          'global singleton; snapshot still applies via PointProvider.instance.',
          tag: 'CanonicalPointBalanceSync',
        );
      }

      final ok = await auth.applyPointsBalanceSnapshot(
        currentBalance,
        expectedUserId: userId,
        snapshotSequence: snapshotSequence,
        snapshotObservedAt: snapshotObservedAt,
      );
      if (!ok) {
        MyPnpBalanceDebug.blocked(
          'CanonicalPointBalanceSync REJECTED balance=$currentBalance source=$source — '
          'PointProvider refused snapshot (stale seq/time or downgrade guard). '
          'My PNP keeps memory balance; see 🛑 applyRemoteBalanceSnapshot logs above.',
        );
        Logger.info(
          'CanonicalPointBalanceSync.apply: snapshot rejected (stale); '
          'skipping disk cache + broadcast (userId=$userId)',
          tag: 'CanonicalPointBalanceSync',
        );
        return;
      }
      MyPnpBalanceDebug.ok(
        'CanonicalPointBalanceSync applied balance=$currentBalance source=$source — '
        'My PNP + user meta should match.',
      );
      await PointService.saveCanonicalBalance(
        userId: userId,
        currentBalance: currentBalance,
      );
      if (emitBroadcast) {
        PointService.notifyPointBalanceBroadcast(
          userId: userId,
          newBalance: currentBalance,
          source: source,
        );
      }
    });
  }
}
