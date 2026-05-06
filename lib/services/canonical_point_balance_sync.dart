import '../providers/auth_provider.dart';
import '../providers/point_provider.dart';
import 'point_service.dart';

/// Single entry for poll wins, push snapshots, and other authoritative balances:
/// [AuthProvider] customFields + [PointProvider] memory + SharedPreferences disk,
/// optionally [PointService.notifyPointBalanceBroadcast] for listeners without context.
class CanonicalPointBalanceSync {
  CanonicalPointBalanceSync._();

  /// NEW FIX: Align memory, user meta patch, disk cache, and optional broadcast.
  static Future<void> apply({
    required String userId,
    required int currentBalance,
    String source = 'canonical_point_balance',
    bool emitBroadcast = false,
    AuthProvider? authProvider,
    PointProvider? pointProvider,
  }) async {
    final auth = authProvider ?? AuthProvider();
    final points = pointProvider ?? PointProvider.instance;

    auth.applyPointsBalanceSnapshot(currentBalance);
    points.applyRemoteBalanceSnapshot(
      userId: userId,
      currentBalance: currentBalance,
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
  }
}
