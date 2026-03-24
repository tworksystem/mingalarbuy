import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/app_config.dart';
import '../utils/logger.dart' as app_logger;
import '../utils/network_utils.dart';

/// PROFESSIONAL: Point balance verification service for debugging and health checks.
/// 
/// This service provides detailed insights into point transactions and balance consistency.
/// Use for:
/// - Verifying deduction and reward flows work correctly
/// - Debugging balance inconsistencies
/// - Monitoring poll transaction history
/// - Health checks in production
class PointVerificationService {
  static String? _lastError;
  static String? get lastError => _lastError;

  /// Get WooCommerce authentication query parameters
  static Map<String, String> _getWooCommerceAuthQueryParams() {
    return {
      'consumer_key': AppConfig.consumerKey,
      'consumer_secret': AppConfig.consumerSecret,
    };
  }

  /// Verify user's point balance and get detailed breakdown.
  /// 
  /// Returns comprehensive verification data including:
  /// - Ledger balance (from wp_twork_point_transactions - PRIMARY source)
  /// - Meta cache balance (from user meta)
  /// - Poll-specific transaction counts
  /// - Recent poll transaction history
  /// - Consistency status
  /// 
  /// GET /wp-json/twork/v1/points/verify-balance/{user_id}
  static Future<BalanceVerification?> verifyBalance({
    required String userId,
  }) async {
    _lastError = null;

    try {
      final uri = Uri.parse(
        '${AppConfig.backendUrl}/wp-json/twork/v1/points/verify-balance/$userId',
      ).replace(queryParameters: _getWooCommerceAuthQueryParams());

      app_logger.Logger.info(
        'Verifying balance for user: $userId',
        tag: 'PointVerification',
      );

      final response = await NetworkUtils.executeRequest(
        () => http.get(
          uri,
          headers: const {'Content-Type': 'application/json'},
        ),
        context: 'verifyBalance',
      );

      if (NetworkUtils.isValidResponse(response)) {
        try {
          final data = jsonDecode(response!.body) as Map<String, dynamic>;

          if (data['success'] == true) {
            final verification = BalanceVerification.fromJson(data);
            
            app_logger.Logger.info(
              'Balance verification complete — User: $userId, Ledger: ${verification.ledgerBalance}, '
              'Meta: ${verification.metaBalance}, Consistent: ${verification.isConsistent}',
              tag: 'PointVerification',
            );

            // Log warning if inconsistent
            if (!verification.isConsistent) {
              app_logger.Logger.warning(
                'BALANCE INCONSISTENCY! User: $userId, Ledger: ${verification.ledgerBalance}, '
                'Meta: ${verification.metaBalance}, Diff: ${verification.difference}',
                tag: 'PointVerification',
              );
            }

            // Log poll transaction summary
            app_logger.Logger.info(
              'Poll transactions — Plays: ${verification.pollDeductionCount} (${verification.pollDeductionTotal} PNP), '
              'Wins: ${verification.pollRewardCount} (${verification.pollRewardTotal} PNP), '
              'Net: ${verification.netPollImpact} PNP',
              tag: 'PointVerification',
            );

            return verification;
          } else {
            _lastError = data['message']?.toString() ?? 'Verification failed';
            app_logger.Logger.error(
              'Balance verification failed: $_lastError',
              tag: 'PointVerification',
            );
            return null;
          }
        } catch (e, stackTrace) {
          _lastError = 'Failed to parse verification response: ${NetworkUtils.getErrorMessage(e)}';
          app_logger.Logger.error(
            'Balance verification parse error: $_lastError',
            tag: 'PointVerification',
            error: e,
            stackTrace: stackTrace,
          );
          return null;
        }
      } else {
        _lastError = 'Invalid response from server. Status: ${response?.statusCode}';
        app_logger.Logger.error(
          'Balance verification invalid response: $_lastError',
          tag: 'PointVerification',
        );
        return null;
      }
    } catch (e) {
      _lastError = 'Verification exception: ${e.toString()}';
      app_logger.Logger.error(
        'Balance verification exception: $_lastError',
        tag: 'PointVerification',
        error: e,
      );
      return null;
    }
  }

  /// Print detailed verification report to console (for debugging)
  static Future<void> printVerificationReport(String userId) async {
    final verification = await verifyBalance(userId: userId);
    
    if (verification == null) {
      print('❌ Verification failed: $_lastError');
      return;
    }

    print('\n╔═══════════════════════════════════════════════════════════════╗');
    print('║       POLL POINTS SYSTEM - BALANCE VERIFICATION REPORT       ║');
    print('╚═══════════════════════════════════════════════════════════════╝\n');
    
    print('User ID: $userId');
    print('Timestamp: ${verification.timestamp}\n');
    
    print('┌─────────────────────────────────────────────────────────────┐');
    print('│ BALANCE STATUS                                              │');
    print('├─────────────────────────────────────────────────────────────┤');
    print('│ Ledger Balance (PRIMARY):  ${verification.ledgerBalance.toString().padLeft(10)} PNP      │');
    print('│ Meta Cache Balance:        ${verification.metaBalance.toString().padLeft(10)} PNP      │');
    print('│ Consistency Status:        ${verification.isConsistent ? "✅ CONSISTENT" : "❌ INCONSISTENT"}           │');
    if (!verification.isConsistent) {
      print('│ Difference:                ${verification.difference.toString().padLeft(10)} PNP      │');
    }
    print('└─────────────────────────────────────────────────────────────┘\n');

    print('┌─────────────────────────────────────────────────────────────┐');
    print('│ POLL TRANSACTIONS                                           │');
    print('├─────────────────────────────────────────────────────────────┤');
    print('│ Poll Plays (Deductions):   ${verification.pollDeductionCount.toString().padLeft(4)} plays │ ${verification.pollDeductionTotal.toString().padLeft(10)} PNP │');
    print('│ Poll Wins (Rewards):       ${verification.pollRewardCount.toString().padLeft(4)} wins  │ ${verification.pollRewardTotal.toString().padLeft(10)} PNP │');
    print('│ Net Poll Impact:                        │ ${verification.netPollImpact.toString().padLeft(10)} PNP │');
    print('└─────────────────────────────────────────────────────────────┘\n');

    print('┌─────────────────────────────────────────────────────────────┐');
    print('│ OVERALL TRANSACTION BREAKDOWN                               │');
    print('├─────────────────────────────────────────────────────────────┤');
    print('│ Total Earned:              ${verification.totalEarned.toString().padLeft(10)} PNP      │');
    print('│ Total Redeemed (Approved): ${verification.totalRedeemedApproved.toString().padLeft(10)} PNP      │');
    print('│ Total Redeemed (Pending):  ${verification.totalRedeemedPending.toString().padLeft(10)} PNP      │');
    print('│ Total Refunded:            ${verification.totalRefunded.toString().padLeft(10)} PNP      │');
    print('│ Total Transactions:        ${verification.totalTransactions.toString().padLeft(10)}          │');
    print('└─────────────────────────────────────────────────────────────┘\n');

    if (verification.recentPollTransactions.isNotEmpty) {
      print('┌─────────────────────────────────────────────────────────────┐');
      print('│ RECENT POLL TRANSACTIONS (Last 20)                         │');
      print('├─────────────────────────────────────────────────────────────┤');
      for (final txn in verification.recentPollTransactions.take(10)) {
        final typeIcon = txn.type == 'earn' ? '✓' : '✗';
        final deltaStr = txn.delta >= 0 ? '+${txn.delta}' : '${txn.delta}';
        print('│ $typeIcon ${txn.id.toString().padLeft(6)} | ${deltaStr.padLeft(7)} PNP | ${txn.description?.substring(0, 30) ?? ""}');
      }
      if (verification.recentPollTransactions.length > 10) {
        print('│ ... (${verification.recentPollTransactions.length - 10} more transactions)');
      }
      print('└─────────────────────────────────────────────────────────────┘\n');
    }

    if (!verification.isConsistent) {
      print('⚠️  WARNING: Balance inconsistency detected!');
      print('   Ledger (primary): ${verification.ledgerBalance} PNP');
      print('   Meta (cache):     ${verification.metaBalance} PNP');
      print('   Difference:       ${verification.difference} PNP');
      print('   → Meta cache should be refreshed from ledger.\n');
    } else {
      print('✅ Balance is consistent between ledger and meta cache.\n');
    }

    print('═══════════════════════════════════════════════════════════════\n');
  }
}

/// Balance verification data model
class BalanceVerification {
  final int userId;
  final String tableName;
  final int ledgerBalance;
  final int metaBalance;
  final bool isConsistent;
  final int difference;
  final int pollDeductionCount;
  final int pollDeductionTotal;
  final int pollRewardCount;
  final int pollRewardTotal;
  final int netPollImpact;
  final int totalEarned;
  final int totalRefunded;
  final int totalRedeemedApproved;
  final int totalRedeemedPending;
  final int totalTransactions;
  final List<PollTransaction> recentPollTransactions;
  final String timestamp;
  final String? warning;

  const BalanceVerification({
    required this.userId,
    required this.tableName,
    required this.ledgerBalance,
    required this.metaBalance,
    required this.isConsistent,
    required this.difference,
    required this.pollDeductionCount,
    required this.pollDeductionTotal,
    required this.pollRewardCount,
    required this.pollRewardTotal,
    required this.netPollImpact,
    required this.totalEarned,
    required this.totalRefunded,
    required this.totalRedeemedApproved,
    required this.totalRedeemedPending,
    required this.totalTransactions,
    required this.recentPollTransactions,
    required this.timestamp,
    this.warning,
  });

  factory BalanceVerification.fromJson(Map<String, dynamic> json) {
    final balance = json['balance'] as Map<String, dynamic>? ?? {};
    final pollTxns = json['poll_transactions'] as Map<String, dynamic>? ?? {};
    final deductions = pollTxns['deductions'] as Map<String, dynamic>? ?? {};
    final rewards = pollTxns['winner_rewards'] as Map<String, dynamic>? ?? {};
    final breakdown = json['overall_breakdown'] as Map<String, dynamic>? ?? {};
    final recentRaw = json['recent_poll_transactions'] as List? ?? [];

    final recentTxns = recentRaw.map((e) {
      if (e is Map<String, dynamic>) {
        return PollTransaction.fromJson(e);
      }
      return null;
    }).whereType<PollTransaction>().toList();

    return BalanceVerification(
      userId: json['user_id'] as int? ?? 0,
      tableName: json['table_name'] as String? ?? '',
      ledgerBalance: balance['ledger'] as int? ?? 0,
      metaBalance: balance['meta_points_balance'] as int? ?? 0,
      isConsistent: balance['is_consistent'] as bool? ?? true,
      difference: balance['difference'] as int? ?? 0,
      pollDeductionCount: deductions['count'] as int? ?? 0,
      pollDeductionTotal: deductions['total_points'] as int? ?? 0,
      pollRewardCount: rewards['count'] as int? ?? 0,
      pollRewardTotal: rewards['total_points'] as int? ?? 0,
      netPollImpact: pollTxns['net_poll_impact'] as int? ?? 0,
      totalEarned: breakdown['total_earned'] as int? ?? 0,
      totalRefunded: breakdown['total_refunded'] as int? ?? 0,
      totalRedeemedApproved: breakdown['total_redeemed_approved'] as int? ?? 0,
      totalRedeemedPending: breakdown['total_redeemed_pending'] as int? ?? 0,
      totalTransactions: breakdown['total_transactions'] as int? ?? 0,
      recentPollTransactions: recentTxns,
      timestamp: json['timestamp'] as String? ?? '',
      warning: json['warning'] as String?,
    );
  }
}

/// Poll transaction model
class PollTransaction {
  final int id;
  final String type;
  final int points;
  final int delta;
  final String? description;
  final String? orderIdPreview;
  final String? createdAt;

  const PollTransaction({
    required this.id,
    required this.type,
    required this.points,
    required this.delta,
    this.description,
    this.orderIdPreview,
    this.createdAt,
  });

  factory PollTransaction.fromJson(Map<String, dynamic> json) {
    return PollTransaction(
      id: json['id'] as int? ?? 0,
      type: json['type'] as String? ?? '',
      points: json['points'] as int? ?? 0,
      delta: json['delta'] as int? ?? 0,
      description: json['description'] as String?,
      orderIdPreview: json['order_id_preview'] as String?,
      createdAt: json['created_at'] as String?,
    );
  }
}
