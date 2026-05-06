import 'package:shared_preferences/shared_preferences.dart';
import '../models/point_transaction.dart';
import '../providers/auth_provider.dart';
import '../providers/point_provider.dart';
import '../services/in_app_notification_service.dart';
import '../services/point_service.dart';
import '../services/canonical_point_balance_sync.dart';
import '../utils/logger.dart';

/// Service to recover missed notifications for poll wins
/// 
/// PROBLEM:
/// - User votes on poll, then uninstalls app
/// - Poll determines winner → backend credits points
/// - FCM notification fails (app uninstalled)
/// - User reinstalls app → balance correct but no notification
/// 
/// SOLUTION:
/// - On app launch/login, check recent transactions (last 30 days)
/// - Detect poll winner transactions that haven't been "notified"
/// - Recreate in-app notifications for missed wins
class MissedNotificationRecoveryService {
  static const String _lastCheckKey = 'missed_notification_last_check';
  static const String _notifiedTransactionsKey = 'notified_transaction_ids';

  /// Check for missed poll winner notifications and recreate them
  /// 
  /// Should be called:
  /// - On app first launch after installation
  /// - On user login
  /// - When app returns from background after long absence
  /// 
  /// @param userId Current authenticated user ID
  /// @param forceCheck If true, will check even if recently checked
  static Future<int> checkAndRecoverMissedNotifications(
    String userId, {
    bool forceCheck = false,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Rate limiting: Don't check too frequently (once per 6 hours)
      if (!forceCheck) {
        final lastCheckStr = prefs.getString('${_lastCheckKey}_$userId');
        if (lastCheckStr != null) {
          final lastCheck = DateTime.parse(lastCheckStr);
          final hoursSinceLastCheck =
              DateTime.now().difference(lastCheck).inHours;
          if (hoursSinceLastCheck < 6) {
            Logger.info(
                'Skipping missed notification check (last checked $hoursSinceLastCheck hours ago)',
                tag: 'MissedNotificationRecovery');
            return 0;
          }
        }
      }

      Logger.info('Checking for missed poll winner notifications for user: $userId',
          tag: 'MissedNotificationRecovery');

      // Load recent transactions (last 30 days)
      final allTransactions = await PointService.getAllPointTransactions(userId);
      
      // Filter to recent transactions (last 30 days)
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
      final recentTransactions = allTransactions.where((txn) {
        return txn.createdAt.isAfter(thirtyDaysAgo);
      }).toList();

      // Get list of transaction IDs that have already been notified
      final notifiedIds = prefs.getStringList('${_notifiedTransactionsKey}_$userId') ?? [];
      final notifiedIdsSet = Set<String>.from(notifiedIds);

      // Find poll winner transactions that haven't been notified
      final missedWins = <PointTransaction>[];
      for (final txn in recentTransactions) {
        // Check if this is a poll winner transaction
        final isPollWin = _isPollWinnerTransaction(txn);
        if (!isPollWin) continue;

        // Check if already notified
        if (notifiedIdsSet.contains(txn.id)) continue;

        // This is a missed poll win!
        missedWins.add(txn);
      }

      if (missedWins.isEmpty) {
        Logger.info('No missed poll winner notifications found',
            tag: 'MissedNotificationRecovery');
        await prefs.setString(
            '${_lastCheckKey}_$userId', DateTime.now().toIso8601String());
        return 0;
      }

      Logger.info('Found ${missedWins.length} missed poll winner notification(s)',
          tag: 'MissedNotificationRecovery');

      /*
      Old Code:
      // No server balance fetch here; in-app rows used currentBalance: null only.
      */

      // New Code: One live balance read so recreated notifications + Home My PNP match ledger.
      String? balanceLabelForMissedRecovery;
      try {
        final live = await PointService.getPointBalance(userId);
        if (live != null) {
          balanceLabelForMissedRecovery = live.currentBalance.toString();
          /*
          // OLD CODE:
          // AuthProvider().applyPointsBalanceSnapshot(live.currentBalance);
          // PointProvider.instance.applyRemoteBalanceSnapshot(
          //   userId: userId,
          //   currentBalance: live.currentBalance,
          // );
          */

          // NEW FIX: Missed poll recovery UI matches ledger + disk.
          await CanonicalPointBalanceSync.apply(
            userId: userId,
            currentBalance: live.currentBalance,
            source: 'missed_poll_recovery',
            emitBroadcast: false,
          );
        }
      } catch (e, stackTrace) {
        Logger.warning(
          'Missed recovery: could not fetch live balance for UI sync: $e',
          tag: 'MissedNotificationRecovery',
          error: e,
          stackTrace: stackTrace,
        );
      }

      // Recreate in-app notifications for missed wins
      int recreatedCount = 0;
      for (final txn in missedWins) {
        try {
          // Extract poll title from description
          // Format: "Poll winner reward: Poll Title (+8000 points)"
          final pollTitle = _extractPollTitle(txn.description ?? '');

          // Generate notification title and body
          final notificationTitle = "Congratulations! You're the Winner! 🏆";
          final notificationBody = txn.description ??
              'Your selection matched the winning result. ${txn.points} PNP has been credited to your balance. Keep playing to win more!';

          // Create in-app notification with transaction ID
          // This ensures duplicate prevention works correctly
          /*
          Old Code:
          final wasCreated = await InAppNotificationService().createPointNotification(
            type: 'engagement_points',
            title: notificationTitle,
            body: notificationBody,
            points: txn.points.toString(),
            currentBalance: null, // Will use cached balance
            transactionId: txn.id,
            eventOccurredAt: txn.createdAt,
            additionalData: {
              'itemType': 'poll',
              'itemTitle': pollTitle,
            },
          );
          */

          // New Code: Pass live balance label when available so notification payload matches My PNP.
          final wasCreated = await InAppNotificationService().createPointNotification(
            type: 'engagement_points',
            title: notificationTitle,
            body: notificationBody,
            points: txn.points.toString(),
            currentBalance: balanceLabelForMissedRecovery,
            transactionId: txn.id,
            eventOccurredAt: txn.createdAt,
            additionalData: {
              'itemType': 'poll',
              'itemTitle': pollTitle,
            },
          );

          // PROFESSIONAL FIX: Mark as notified regardless of whether notification was created
          // This prevents infinite recreation attempts for the same transaction
          // Even if duplicate prevention blocked it, we still mark it to avoid rechecking
          notifiedIdsSet.add(txn.id);
          
          if (wasCreated) {
            recreatedCount++;
            Logger.info(
                'Recreated notification for missed poll win: ${txn.id} (${txn.points} points)',
                tag: 'MissedNotificationRecovery');
          } else {
            Logger.info(
                'Notification already exists for transaction: ${txn.id}, marked as notified',
                tag: 'MissedNotificationRecovery');
          }
        } catch (e, stackTrace) {
          Logger.error('Error recreating notification for transaction ${txn.id}: $e',
              tag: 'MissedNotificationRecovery',
              error: e,
              stackTrace: stackTrace);
          // Still mark as notified to avoid infinite retry
          notifiedIdsSet.add(txn.id);
        }
      }

      /*
      Old Code:
      // No PointProvider.refreshPointState / loadBalance after recovery loop.
      */

      // New Code: Reconcile balance, transactions, and user meta with server after recovery.
      try {
        await PointProvider.instance.refreshPointState(
          userId: userId,
          forceRefresh: true,
          refreshBalance: true,
          refreshTransactions: true,
          refreshUserCallback: () => AuthProvider().refreshUser(),
        );
      } catch (e, stackTrace) {
        Logger.warning(
          'Missed recovery: refreshPointState after loop failed: $e',
          tag: 'MissedNotificationRecovery',
          error: e,
          stackTrace: stackTrace,
        );
      }

      // Save updated notified transaction IDs
      // Keep only recent IDs (last 100) to prevent list from growing indefinitely
      final updatedNotifiedIds = notifiedIdsSet.toList();
      if (updatedNotifiedIds.length > 100) {
        updatedNotifiedIds.removeRange(0, updatedNotifiedIds.length - 100);
      }
      await prefs.setStringList(
          '${_notifiedTransactionsKey}_$userId', updatedNotifiedIds);

      // Update last check timestamp
      await prefs.setString(
          '${_lastCheckKey}_$userId', DateTime.now().toIso8601String());

      Logger.info(
          'Missed notification recovery completed: $recreatedCount notification(s) recreated',
          tag: 'MissedNotificationRecovery');

      return recreatedCount;
    } catch (e, stackTrace) {
      Logger.error('Error in missed notification recovery: $e',
          tag: 'MissedNotificationRecovery',
          error: e,
          stackTrace: stackTrace);
      return 0;
    }
  }

  /// Check if transaction is a poll winner transaction
  /// 
  /// Criteria:
  /// - Type is 'earn' (winner gets points)
  /// - Status is 'approved'
  /// - Order ID starts with "engagement:poll:" (poll-related)
  /// - Description contains "winner" or "Poll winner reward"
  static bool _isPollWinnerTransaction(PointTransaction txn) {
    // Must be earn type (winners earn points)
    if (txn.type != PointTransactionType.earn) return false;

    // Must be approved
    if (txn.status != PointTransactionStatus.approved) return false;

    // Check order ID pattern
    final orderId = txn.orderId?.toLowerCase() ?? '';
    if (!orderId.startsWith('engagement:poll:')) return false;

    // Check description for winner keywords
    final description = txn.description?.toLowerCase() ?? '';
    if (!description.contains('winner') && 
        !description.contains('poll winner reward')) return false;

    return true;
  }

  /// Extract poll title from transaction description
  /// 
  /// Format examples:
  /// - "Poll winner reward: Myanmar Premier League Champion 2025 (+8000 points)"
  /// - "Poll winner reward (+5000 points)"
  /// 
  /// @param description Transaction description
  /// @return Extracted poll title or "Poll"
  static String _extractPollTitle(String description) {
    if (description.isEmpty) return 'Poll';

    // Try to extract from "Poll winner reward: TITLE (+XXX points)"
    final match = RegExp(r'Poll winner reward:\s*(.+?)\s*\(').firstMatch(description);
    if (match != null && match.group(1) != null) {
      return match.group(1)!.trim();
    }

    // Try simpler pattern "TITLE (+XXX points)"
    final simpleMatch = RegExp(r'(.+?)\s*\(\+\d+\s*points?\)').firstMatch(description);
    if (simpleMatch != null && simpleMatch.group(1) != null) {
      final title = simpleMatch.group(1)!.trim();
      if (title.toLowerCase() != 'poll winner reward') {
        return title;
      }
    }

    return 'Poll';
  }

  /// Mark a transaction as notified (called by other services)
  /// 
  /// This should be called when:
  /// - FCM notification is successfully received
  /// - In-app notification is created from poll winner popup
  /// - Modal popup is shown
  static Future<void> markTransactionAsNotified(
      String userId, String transactionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final notifiedIds =
          prefs.getStringList('${_notifiedTransactionsKey}_$userId') ?? [];
      
      if (!notifiedIds.contains(transactionId)) {
        notifiedIds.add(transactionId);
        
        // Keep only recent IDs (last 100)
        if (notifiedIds.length > 100) {
          notifiedIds.removeRange(0, notifiedIds.length - 100);
        }
        
        await prefs.setStringList(
            '${_notifiedTransactionsKey}_$userId', notifiedIds);
        
        Logger.info('Transaction marked as notified: $transactionId',
            tag: 'MissedNotificationRecovery');
      }
    } catch (e, stackTrace) {
      Logger.error('Error marking transaction as notified: $e',
          tag: 'MissedNotificationRecovery',
          error: e,
          stackTrace: stackTrace);
    }
  }

  /// Clear notification tracking for user (e.g., on logout)
  static Future<void> clearTrackingForUser(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('${_lastCheckKey}_$userId');
      await prefs.remove('${_notifiedTransactionsKey}_$userId');
      Logger.info('Cleared notification tracking for user: $userId',
          tag: 'MissedNotificationRecovery');
    } catch (e, stackTrace) {
      Logger.error('Error clearing notification tracking: $e',
          tag: 'MissedNotificationRecovery',
          error: e,
          stackTrace: stackTrace);
    }
  }

  /// Force check for missed notifications (for testing/debugging)
  static Future<int> forceCheck(String userId) async {
    return await checkAndRecoverMissedNotifications(userId, forceCheck: true);
  }
}
