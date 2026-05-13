import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:ecommerce_int2/providers/auth_provider.dart';
import 'package:ecommerce_int2/providers/point_provider.dart';
import 'package:ecommerce_int2/providers/point_provider_poll_reconcile.dart';
import 'package:ecommerce_int2/services/engagement_service.dart';
/*
import 'package:ecommerce_int2/services/canonical_point_balance_sync.dart';
*/
import 'package:ecommerce_int2/utils/logger.dart';
import 'package:ecommerce_int2/utils/poll_result_snapshot_meta.dart';

/// Feed-based polls: `GET poll/state` → `GET poll/results/{id}/{session}` then
/// **silent** [PointProvider] balance sync.
///
/// **POPUP KILL-SWITCH (SILENT MODE):** No modal/dialog/bottom sheet or in-app
/// winner celebration UI is shown from this service — only point sync:
/// [PointProvider.reconcileAfterPollResult] bundles [PointProvider.beginBalanceSync],
/// optional [CanonicalPointBalanceSync.apply] when local ≠ poll balance, and
/// [PointProvider.refreshPointStateAfterPollWin] for wins (optimistic bumps removed).
class PollWinnerPopupService {
  PollWinnerPopupService._();

  /*
  // Old Code: win-only duplicate tracking (replaced by [_pollBalanceReconcileKeys] for win + loss).
  // static final Set<String> _shownKeys = <String>{};
  */
  /// Win + loss: one balance reconcile pass per `[pollId]_[sessionKey]` outcome.
  static final Set<String> _pollBalanceReconcileKeys = <String>{};
  static final Set<String> _inFlightSyncKeys = <String>{};

  static BigInt? snapshotSequenceFromPollResultMap(Map<String, dynamic> rd) =>
      pollResultSnapshotSequenceFromMap(rd);

  static DateTime? snapshotObservedAtFromPollResultMap(
    Map<String, dynamic> rd,
  ) => pollResultSnapshotObservedAtFromMap(rd);

  /*
  // Old Code: deferred duplicate points REST refresh dedupe set.
  // static final Set<String> _serverBalanceFetchOnceKeys = <String>{};
  */

  /// When the feed shows poll results and the user may have won: runs **silent**
  /// balance sync only. Does **not** display any winner popup (see class doc).
  ///
  /// [feedSessionId] / [feedPollResult]: from engagement feed — skips slow `/poll/state`
  /// polling so `/poll/results` runs immediately.
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

      /*
      Old Code: feed-embedded win triggered optimisticAddPoints (second bump after /poll/results).
      if (feedPollResult != null) {
        final uw = feedPollResult['user_won'];
        final feedPts = (feedPollResult['points_earned'] as num?)?.toInt() ?? 0;
        final fs = (feedSessionId ?? '').trim();
        if ((uw == true || uw == 1) && feedPts > 0 && fs.isNotEmpty) {
          final refId = 'poll_win_${pollId}_$fs';
          PointProvider.instance.optimisticAddPoints(feedPts, refId: refId);
        }
      }
      */

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
      /*
      // Old Code: if (_shownKeys.contains(dedupeKey)) return;
      */
      if (_pollBalanceReconcileKeys.contains(dedupeKey)) return;

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
      final backendSessionId = (rd['session_id'] ?? sessionId)
          .toString()
          .trim();
      final stableSessionId = backendSessionId.isNotEmpty
          ? backendSessionId
          : sessionId;
      final backendRequestId =
          (rd['request_id'] ?? 'poll_stable_${pollId}_$stableSessionId')
              .toString();

      /*
      Old Code: required pointsEarned > 0 — same Cron race as AutoRunPollWidget;
      winners with points_awarded not yet written never synced.
      if (!userWon || pointsEarned <= 0) {
        return;
      }
      */
      if (!userWon) {
        if (!context.mounted) return;
        /*
        // Old Code: loss path did not reconcile engagement feed polls.
        // return;
        */
        try {
          await PointProvider.instance.reconcileAfterPollResult(
            userId: userId.toString(),
            authoritativePollBalance: currentBalance > 0
                ? currentBalance
                : null,
            balanceSyncDebugTag:
                'carousel_feed_loss_${pollId}_$stableSessionId',
            canonicalSource: 'poll_result_reconcile_carousel_loss',
            shouldContinue: () => context.mounted,
          );
          _pollBalanceReconcileKeys.add(dedupeKey);
          if (_pollBalanceReconcileKeys.length > 250) {
            _pollBalanceReconcileKeys.clear();
          }
        } catch (e, st) {
          debugPrint('[PollWinnerPopup] loss reconcile: $e\n$st');
        }
        return;
      }

      if (!context.mounted) return;

      /*
      Old Code: wrapped win path in an extra try { } (flattened — single outer try handles errors).
      */

      // Single dedupe id per poll for logging / future extension (session-free).
      final String pollWinSyncRefId = 'poll_win_sync_$pollId';
      Logger.info(
        'DEBUG_SYNC: poll win sync refId=$pollWinSyncRefId userId=$userId session=$stableSessionId',
        tag: 'PollWinnerPopup',
      );

      // Baseline (My PNP SSOT): [PointProvider.currentBalance] only — pre-reconcile snapshot.
      final int baseline = PointProvider.instance.currentBalance;
      final int localWithEarned = baseline + pointsEarned;
      final int effectiveBalance = currentBalance > 0
          ? currentBalance
          : localWithEarned;

      debugPrint(
        '[PollWinnerPopup] user won pollId=$pollId session=$sessionId +$pointsEarned PNP — silent sync (no popup)',
      );

      debugPrint(
        '[PollWinnerPopup] ✓ WINNER REWARD SYNC — User: $userId, Poll: $pollId, Session: $sessionId, '
        'requestId=$backendRequestId, Earned: +$pointsEarned, '
        'baseline=$baseline → effective=$effectiveBalance (API current_balance: $currentBalance, local+earn: $localWithEarned)',
      );

      await PointProvider.instance.reconcileAfterPollResult(
        userId: userId.toString(),
        authoritativePollBalance: effectiveBalance,
        balanceSyncDebugTag: 'carousel_feed_win_${pollId}_$stableSessionId',
        authProvider: AuthProvider(),
        snapshotSequence: snapshotSequenceFromPollResultMap(rd),
        snapshotObservedAt: snapshotObservedAtFromPollResultMap(rd),
        canonicalSource: 'poll_win_instant_carousel_feed',
        refreshUserCallback: () => AuthProvider().refreshUser(),
        shouldContinue: () => context.mounted,
        pollWinPriorBalanceExclusive: baseline,
      );

      if (kDebugMode) {
        debugPrint(
          '🚀 [PNP DEBUG] [${DateTime.now()}] Poll Win Detected! | PollID: $pollId | Triggering Immediate Refresh...',
        );
      }

      /*
      _shownKeys.add(dedupeKey);
      if (_shownKeys.length > 250) _shownKeys.clear();
      */

      _pollBalanceReconcileKeys.add(dedupeKey);
      if (_pollBalanceReconcileKeys.length > 250) {
        _pollBalanceReconcileKeys.clear();
      }

      /*
      ... prior notification / deferred refresh snippets kept above in history ...
      */

      // Old Code closing inner try } catch — removed after flatten.
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
      try {
        await PointProvider.instance.refreshPointState(
          userId: userId,
          forceRefresh: true,
          refreshBalance: true,
          refreshTransactions: true,
          notifyBalanceLoading: false,
          refreshUserCallback: () => AuthProvider().refreshUser(),
        );
      } catch (e) {
        debugPrint(
          '[PollWinnerPopup] resilient sync refreshPointState failed: $e',
        );
      } finally {
        _inFlightSyncKeys.remove(syncKey);
      }
    }());
  }
}
