import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:ecommerce_int2/providers/auth_provider.dart';
import 'package:ecommerce_int2/providers/point_provider.dart';
import 'package:ecommerce_int2/services/engagement_service.dart';
import 'package:ecommerce_int2/services/canonical_point_balance_sync.dart';
import 'package:ecommerce_int2/utils/logger.dart';

/// Feed-based polls: `GET poll/state` → `GET poll/results/{id}/{session}` then
/// **silent** [PointProvider] balance sync.
///
/// **POPUP KILL-SWITCH (SILENT MODE):** No modal/dialog/bottom sheet or in-app
/// winner celebration UI is shown from this service — only point sync
/// (`optimisticAddPoints`, [CanonicalPointBalanceSync.apply], [PointProvider.refreshPointState]).
class PollWinnerPopupService {
  PollWinnerPopupService._();

  static final Set<String> _shownKeys = <String>{};
  static final Set<String> _inFlightSyncKeys = <String>{};

  /// One deferred `refreshPointState` reconcile per poll+session (avoids duplicate `/points/*` traffic).
  static final Set<String> _serverBalanceFetchOnceKeys = <String>{};

  /// When the feed shows poll results and the user may have won: runs **silent**
  /// balance sync only. Does **not** display any winner popup (see class doc).
  ///
  /// [feedSessionId] / [feedPollResult]: from engagement feed — skips slow `/poll/state`
  /// polling so `/poll/results` runs immediately. If [feedPollResult] includes
  /// `user_won` + `points_earned`, applies [PointProvider.optimisticAddPoints] before network.
  static Future<void> checkAndShowPollWinnerPopup({
    required BuildContext context,
    required int pollId,
    required int userId,
    String? itemTitle,
    String? feedSessionId,
    Map<String, dynamic>? feedPollResult,
  }) async {
    if (userId <= 0 || pollId <= 0) return;
    if (!context.mounted) return;

    try {
      Map<String, dynamic>? data;
      String sessionId = '';
      String state = '';

      // Instant optimistic if backend embeds win info in feed poll_result (optional).
      if (feedPollResult != null) {
        final uw = feedPollResult['user_won'];
        final feedPts = (feedPollResult['points_earned'] as num?)?.toInt() ?? 0;
        final fs = (feedSessionId ?? '').trim();
        if ((uw == true || uw == 1) && feedPts > 0 && fs.isNotEmpty) {
          final refId = 'poll_win_${pollId}_$fs';
          PointProvider.instance.optimisticAddPoints(feedPts, refId: refId);
        }
      }

      if (feedSessionId != null && feedSessionId.trim().isNotEmpty) {
        // Trust engagement feed (already showing result card) — hit /poll/results immediately.
        data = <String, dynamic>{};
        sessionId = feedSessionId.trim();
        state = 'SHOWING_RESULTS';
      } else {
        // Feed can show results a moment before /poll/state flips — retry briefly.
        for (var attempt = 0; attempt < 4; attempt++) {
          if (attempt > 0) {
            await Future<void>.delayed(const Duration(milliseconds: 350));
          }
          if (!context.mounted) return;

          final Map<String, dynamic>? stateJson =
              await EngagementService.fetchPollState(pollId: pollId);
          if (stateJson == null) {
            debugPrint(
              '[PollWinnerPopup] poll/state failed pollId=$pollId err=${EngagementService.lastError}',
            );
            return;
          }
          if (stateJson['success'] != true) return;

          data = stateJson['data'] as Map<String, dynamic>?;
          if (data == null) return;

          sessionId = (data['current_session_id'] ?? '').toString().trim();
          state = (data['state'] ?? '').toString();

          if (sessionId.isEmpty && state == 'SHOWING_RESULTS') {
            sessionId = 'default';
          }

          if (sessionId.isEmpty) {
            debugPrint(
                '[PollWinnerPopup] empty session and not showing results pollId=$pollId state=$state');
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
      }

      if (state != 'SHOWING_RESULTS') {
        debugPrint(
          '[PollWinnerPopup] state never reached SHOWING_RESULTS pollId=$pollId',
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

      final Map<String, dynamic>? resJson =
          await EngagementService.fetchPollResults(
        pollId: pollId,
        sessionId: sessionId,
        userId: userId,
      );
      if (resJson == null) {
        debugPrint(
          '[PollWinnerPopup] poll/results failed pollId=$pollId session=$sessionId err=${EngagementService.lastError}',
        );
        // Old Code:
        // return;
        // New Code:
        _scheduleResilientSync(
          userId: userId.toString(),
          syncKey: 'poll_sync_${pollId}_$sessionId',
        );
        return;
      }
      if (resJson['success'] != true) {
        _scheduleResilientSync(
          userId: userId.toString(),
          syncKey: 'poll_sync_${pollId}_$sessionId',
        );
        return;
      }

      final rd = resJson['data'] as Map<String, dynamic>?;
      if (rd == null) return;

      final userWon = rd['user_won'] == true || rd['user_won'] == 1;
      final pointsEarned = (rd['points_earned'] as num?)?.toInt() ?? 0;
      final currentBalance = (rd['current_balance'] as num?)?.toInt() ?? 0;
      final backendSessionId =
          (rd['session_id'] ?? sessionId).toString().trim();
      final stableSessionId =
          backendSessionId.isNotEmpty ? backendSessionId : sessionId;
      final backendRequestId =
          (rd['request_id'] ?? 'poll_stable_${pollId}_$stableSessionId')
              .toString();

      if (!userWon || pointsEarned <= 0) {
        return;
      }

      final optimisticRefId = 'poll_win_${pollId}_${stableSessionId}';

      // Capture baseline before optimistic UI bump (avoids double-counting earn twice).
      final int baseline = math.max(
        PointProvider.instance.currentBalance,
        AuthProvider().userPointsBalance,
      );
      final int localWithEarned = baseline + pointsEarned;
      final int effectiveBalance =
          currentBalance > 0 ? currentBalance : localWithEarned;

      Logger.info(
        'DEBUG_SYNC: optimisticAddPoints called userId=$userId '
        'pointsToAdd=$pointsEarned source=poll_win_carousel_feed',
        tag: 'PollWinnerPopup',
      );
      Logger.info(
        'DEBUG_SYNC: optimisticAddPoints refId=$optimisticRefId',
        tag: 'PollWinnerPopup',
      );
      PointProvider.instance.optimisticAddPoints(
        pointsEarned,
        refId: optimisticRefId,
      );

      /*
       * POPUP KILL-SWITCH — UI examples kept commented (silent mode):
       *   // showDialog(context: context, builder: (_) => PollWinnerDialog(...));
       *   // showModalBottomSheet(context: context, builder: (_) => ...);
       * Point/in-app celebration is intentionally not shown here.
       */

      _shownKeys.add(dedupeKey);
      if (_shownKeys.length > 250) {
        _shownKeys.clear();
      }

      if (!context.mounted) return;

      debugPrint(
        '[PollWinnerPopup] user won pollId=$pollId session=$sessionId +$pointsEarned PNP — silent sync (no popup)',
      );

      // Winner points are credited server-side; prefer API balance when present, else baseline+earn.
      debugPrint(
        '[PollWinnerPopup] ✓ WINNER REWARD SYNC — User: $userId, Poll: $pollId, Session: $sessionId, '
        'requestId=$backendRequestId, Earned: +$pointsEarned, '
        'baseline=$baseline → effective=$effectiveBalance (API current_balance: $currentBalance, local+earn: $localWithEarned)',
      );

      await CanonicalPointBalanceSync.apply(
        userId: userId.toString(),
        currentBalance: effectiveBalance,
        source: 'poll_win_carousel_feed',
        emitBroadcast: true,
      );

      if (kDebugMode) {
        debugPrint(
          '🚀 [PNP DEBUG] [${DateTime.now()}] Poll Win Detected! | PollID: $pollId | Triggering Immediate Refresh...',
        );
      }
      unawaited(
        PointProvider.instance
            .refreshPointState(
          userId: userId.toString(),
          forceRefresh: true,
          refreshBalance: true,
          refreshTransactions: true,
          refreshUserCallback: () => AuthProvider().refreshUser(),
        )
            .catchError((Object error) {
          debugPrint('[PollWinnerPopup] immediate refreshPointState: $error');
        }),
      );

      final String serverFetchKey = 'srv_${pollId}_$stableSessionId';
      if (_serverBalanceFetchOnceKeys.add(serverFetchKey)) {
        if (_serverBalanceFetchOnceKeys.length > 250) {
          _serverBalanceFetchOnceKeys.clear();
        }
        unawaited(
          Future<void>.delayed(const Duration(seconds: 3)).then((_) async {
            await PointProvider.instance
                .refreshPointState(
              userId: userId.toString(),
              forceRefresh: true,
              refreshBalance: true,
              refreshTransactions: true,
              refreshUserCallback: () => AuthProvider().refreshUser(),
            )
                .catchError((Object error) {
              debugPrint('[PollWinnerPopup] delayed refreshPointState: $error');
            });
          }),
        );
      }

      // In-app point notification disabled for poll wins — Home My PNP updates via PointProvider only.
      // final eventId = backendRequestId;
      // final pollLabel = (itemTitle != null && itemTitle.isNotEmpty)
      //     ? '$itemTitle — '
      //     : '';
      // await PointNotificationManager().notifyPointEvent(
      //   type: PointNotificationType.engagementEarned,
      //   points: pointsEarned,
      //   currentBalance: effectiveBalance,
      //   description:
      //       '${pollLabel}Your selection matched the winning result. Well done! '
      //       '+$pointsEarned PNP has been credited to your balance.',
      //   showPushNotification: false,
      //   showInAppNotification: true,
      //   showModalPopup: false,
      //   orderId: eventId,
      //   additionalData: {
      //     'itemType': 'poll',
      //     'itemTitle': itemTitle ?? 'Poll',
      //     'pollId': pollId,
      //     'sessionId': stableSessionId,
      //     'requestId': backendRequestId,
      //     'awardedTxnId': rd['awarded_txn_id'],
      //   },
      // );

      /*
      // Old Code:
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
      */

      /*
      // New Code:
      // Reconcile using the same flow as Point History refresh so Home/Profile/History
      // converge to one consistent state graph after a poll win.
      unawaited(
        Future<void>.delayed(const Duration(seconds: 4)).then((_) async {
          try {
            await PointProvider.instance.refreshPointState(
              userId: userId.toString(),
              forceRefresh: true,
              refreshBalance: true,
              refreshTransactions: true,
              refreshUserCallback: () => AuthProvider().refreshUser(),
            );
          } catch (e) {
            debugPrint('[PollWinnerPopup] deferred refreshPointState: $e');
            _scheduleResilientSync(
              userId: userId.toString(),
              syncKey: 'poll_sync_${pollId}_$stableSessionId',
            );
          }
        }),
      );
      */
    } catch (e, st) {
      debugPrint('[PollWinnerPopup] error: $e\n$st');
    }
  }

  static void _scheduleResilientSync({
    required String userId,
    required String syncKey,
  }) {
    if (userId.isEmpty) return;
    if (_inFlightSyncKeys.contains(syncKey)) return;
    _inFlightSyncKeys.add(syncKey);

    unawaited(() async {
      const delays = <Duration>[
        Duration(seconds: 1),
        Duration(seconds: 3),
        Duration(seconds: 7),
      ];
      for (final delay in delays) {
        await Future<void>.delayed(delay);
        try {
          await PointProvider.instance.refreshPointState(
            userId: userId,
            forceRefresh: true,
            refreshBalance: true,
            refreshTransactions: true,
            refreshUserCallback: () => AuthProvider().refreshUser(),
          );
          _inFlightSyncKeys.remove(syncKey);
          return;
        } catch (e) {
          debugPrint('[PollWinnerPopup] resilient sync retry failed: $e');
        }
      }
      _inFlightSyncKeys.remove(syncKey);
    }());
  }
}
