import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:ecommerce_int2/providers/auth_provider.dart';
import 'package:ecommerce_int2/providers/point_provider.dart';
import 'package:ecommerce_int2/services/point_notification_manager.dart';
import 'package:ecommerce_int2/utils/app_config.dart';

/// Surfaces poll winner credit as an **in-app notification** (not a blocking modal)
/// for **feed-based** polls (Engagement Carousel).
///
/// [AutoRunPollWidget] already calls [PointNotificationManager.notifyPointEvent] directly;
/// this service mirrors that flow for carousel cards:
/// `GET poll/state` → `GET poll/results/{id}/{session}` → notify + balance sync.
class PollWinnerPopupService {
  PollWinnerPopupService._();

  static final Set<String> _shownKeys = <String>{};

  /// Call when the engagement card is showing poll results and the user has voted.
  static Future<void> checkAndShowPollWinnerPopup({
    required BuildContext context,
    required int pollId,
    required int userId,
    String? itemTitle,
  }) async {
    if (userId <= 0 || pollId <= 0) return;
    if (!context.mounted) return;

    try {
      final base = AppConfig.backendUrl.replaceAll(RegExp(r'/$'), '');
      final ck = AppConfig.consumerKey;
      final cs = AppConfig.consumerSecret;

      Map<String, dynamic>? data;
      String sessionId = '';
      String state = '';

      // Feed can show results a moment before /poll/state flips to SHOWING_RESULTS — retry briefly.
      for (var attempt = 0; attempt < 4; attempt++) {
        if (attempt > 0) {
          await Future<void>.delayed(const Duration(milliseconds: 350));
        }
        if (!context.mounted) return;

        final stateUri =
            Uri.parse('$base/wp-json/twork/v1/poll/state/$pollId').replace(
          queryParameters: {
            'consumer_key': ck,
            'consumer_secret': cs,
          },
        );

        final stateResp = await http.get(
          stateUri,
          headers: const {'Content-Type': 'application/json'},
        );
        if (stateResp.statusCode != 200) {
          debugPrint(
            '[PollWinnerPopup] poll/state HTTP ${stateResp.statusCode} pollId=$pollId',
          );
          return;
        }

        final stateJson = jsonDecode(stateResp.body) as Map<String, dynamic>;
        if (stateJson['success'] != true) return;

        data = stateJson['data'] as Map<String, dynamic>?;
        if (data == null) return;

        sessionId = (data['current_session_id'] ?? '').toString().trim();
        state = (data['state'] ?? '').toString();

        // Manual/schedule: poll/state returns SHOWING_RESULTS but empty session;
        // DB stores votes with session_id ''. Backend accepts "default" → ''.
        if (sessionId.isEmpty && state == 'SHOWING_RESULTS') {
          sessionId = 'default';
        }

        if (sessionId.isEmpty) {
          debugPrint(
            '[PollWinnerPopup] empty session and not showing results pollId=$pollId state=$state',
          );
          return;
        }

        if (state == 'SHOWING_RESULTS') break;
      }

      if (state != 'SHOWING_RESULTS') {
        debugPrint(
          '[PollWinnerPopup] state never reached SHOWING_RESULTS (got $state) pollId=$pollId',
        );
        return;
      }

      // For manual/schedule polls, backend can use empty session (mapped to "default").
      // If we dedupe only by pollId_default, future rounds would be blocked forever.
      final bool isDefaultSession = sessionId == 'default';
      final String roundMarker =
          (data?['ends_at'] ?? data?['result_display_ends_at'] ?? '')
          .toString()
          .trim();
      final String dedupeSessionKey = isDefaultSession
          ? (roundMarker.isNotEmpty
              ? 'default_$roundMarker'
              : 'default_${DateTime.now().toUtc().millisecondsSinceEpoch ~/ 60000}')
          : sessionId;
      final dedupeKey = '${pollId}_$dedupeSessionKey';
      if (_shownKeys.contains(dedupeKey)) return;

      final resultsUri =
          Uri.parse('$base/wp-json/twork/v1/poll/results/$pollId/$sessionId')
              .replace(
        queryParameters: {
          'consumer_key': ck,
          'consumer_secret': cs,
          'user_id': userId.toString(),
        },
      );

      final resResp = await http.get(
        resultsUri,
        headers: const {'Content-Type': 'application/json'},
      );
      if (resResp.statusCode != 200) {
        debugPrint(
          '[PollWinnerPopup] poll/results HTTP ${resResp.statusCode} pollId=$pollId session=$sessionId',
        );
        return;
      }

      final resJson = jsonDecode(resResp.body) as Map<String, dynamic>;
      if (resJson['success'] != true) return;

      final rd = resJson['data'] as Map<String, dynamic>?;
      if (rd == null) return;

      final userWon = rd['user_won'] == true || rd['user_won'] == 1;
      final pointsEarned = (rd['points_earned'] as num?)?.toInt() ?? 0;
      final currentBalance = (rd['current_balance'] as num?)?.toInt() ?? 0;

      if (!userWon || pointsEarned <= 0) {
        return;
      }

      _shownKeys.add(dedupeKey);
      if (_shownKeys.length > 250) {
        _shownKeys.clear();
      }

      if (!context.mounted) return;

      debugPrint(
        '[PollWinnerPopup] user won pollId=$pollId session=$sessionId +$pointsEarned PNP — showing modal',
      );

      // ============================================================================
      // CRITICAL: Winner points already credited in wp_twork_point_transactions (backend)
      // SAME TABLE used for deduction when user played
      // Balance = SUM(type='earn') - SUM(type='redeem') from wp_twork_point_transactions
      // ============================================================================
      
      // PROFESSIONAL FIX: Always ensure balance reflects the win.
      // API current_balance can be stale (read replica lag, race before DB commit).
      // Use max(API value, prev + earned) so we never show less than what user just won.
      final fromPointProvider = PointProvider.instance.currentBalance;
      final fromAuth = AuthProvider().userPointsBalance;
      final prev = fromPointProvider > fromAuth ? fromPointProvider : fromAuth;
      final localWithEarned = prev + pointsEarned;
      final effectiveBalance = (currentBalance > 0 && currentBalance >= localWithEarned)
          ? currentBalance
          : localWithEarned;

      debugPrint(
        '[PollWinnerPopup] ✓ WINNER REWARD SYNC — User: $userId, Poll: $pollId, Session: $sessionId, '
        'Earned: +$pointsEarned, Balance: $prev → $effectiveBalance (API: $currentBalance)',
      );

      // Winner points are already credited in backend /poll/results flow.
      // Do not call points/earn again from app (causes duplicate/dedup races).
      AuthProvider().applyPointsBalanceSnapshot(effectiveBalance);
      PointProvider.instance.applyRemoteBalanceSnapshot(
        userId: userId.toString(),
        currentBalance: effectiveBalance,
      );

      final eventId =
          'poll_${pollId}_${sessionId}_${DateTime.now().millisecondsSinceEpoch}';

      // In-app notification (one per round; duplicate key still blocked in manager)
      final pollLabel = (itemTitle != null && itemTitle.isNotEmpty)
          ? '$itemTitle — '
          : '';
      await PointNotificationManager().notifyPointEvent(
        type: PointNotificationType.engagementEarned,
        points: pointsEarned,
        currentBalance: effectiveBalance,
        description:
            '${pollLabel}Your selection matched the winning result. Well done! '
            '+$pointsEarned PNP has been credited to your balance.',
        showPushNotification: false,
        showInAppNotification: true,
        showModalPopup: false,
        orderId: eventId,
        additionalData: {
          'itemType': 'poll',
          'itemTitle': itemTitle ?? 'Poll',
          'pollId': pollId,
          'sessionId': sessionId,
        },
      );

      // PROFESSIONAL FIX: Defer balance/transactions refresh by 4 seconds.
      // Immediate loadBalance/refreshUser can overwrite the applied balance with
      // stale API responses (backend may not have propagated to all endpoints yet).
      // Skip refreshUser — we already patched points in AuthProvider; no user
      // profile data changes from a poll win.
      unawaited(
        Future<void>.delayed(const Duration(seconds: 4)).then((_) async {
          try {
            await PointProvider.instance.loadBalance(
              userId.toString(),
              forceRefresh: true,
            );
          } catch (e) {
            debugPrint('[PollWinnerPopup] deferred loadBalance: $e');
          }
        }),
      );
    } catch (e, st) {
      debugPrint('[PollWinnerPopup] error: $e\n$st');
    }
  }
}
