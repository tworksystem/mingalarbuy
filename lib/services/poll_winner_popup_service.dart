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
import 'package:ecommerce_int2/utils/my_pnp_balance_debug.dart';
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
  /// Win + loss: one balance reconcile per poll **round** (not per calendar minute).
  static final Set<String> _pollBalanceReconcileKeys = <String>{};
  static final List<String> _pollBalanceReconcileKeyOrder = <String>[];
  static const int _pollBalanceReconcileKeyCap = 4096;
  static const int _pollBalanceReconcileEvictBatch = 1024;

  static final Set<String> _inFlightSyncKeys = <String>{};
  static final Map<String, _PendingPollPnpSync> _queuedPollPnpSync =
      <String, _PendingPollPnpSync>{};

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
  /// [feedSessionId] / [feedPollResult] / [feedVotingStatus]: from engagement feed —
  /// skips slow `/poll/state` when the feed is already in a result phase (auto_run often
  /// has empty `current_session_id` while `/poll/state` still says ACTIVE).
  static Future<void> checkAndShowPollWinnerPopup({
    required BuildContext context,
    required int pollId,
    required int userId,
    String? itemTitle,
    String? feedSessionId,
    Map<String, dynamic>? feedPollResult,
    String? feedVotingStatus,
    Map<String, dynamic>? feedPollVotingSchedule,
  }) async {
    if (userId <= 0 || pollId <= 0) return;
    if (!context.mounted) return;
    await syncBalanceWhenShowingResult(
      pollId: pollId,
      userId: userId,
      feedSessionId: feedSessionId,
      feedPollResult: feedPollResult,
      feedVotingStatus: feedVotingStatus,
      feedPollVotingSchedule: feedPollVotingSchedule,
      shouldContinue: () => context.mounted,
    );
  }

  static bool _isFeedResultLikeVotingStatus(String? status) {
    if (status == null || status.trim().isEmpty) return false;
    switch (status.trim().toLowerCase()) {
      case 'showing_result':
      case 'showing_results':
      case 'ended':
      case 'result':
      case 'results':
        return true;
      default:
        return false;
    }
  }

  /// Feed [poll_result] with a resolved winner — safe to call `/poll/results` even when
  /// `/poll/state` still reports ACTIVE (common on auto_run).
  static bool _feedPollResultImpliesResultPhase(Map<String, dynamic>? pollResult) {
    if (pollResult == null || pollResult.isEmpty) return false;
    if (pollResult['winning_option'] is Map) return true;
    final wi = pollResult['winning_index'];
    if (wi is int && wi >= 0) return true;
    if (wi is num && wi.toInt() >= 0) return true;
    final votes = pollResult['vote_counts'];
    if (votes is List && votes.isNotEmpty) return true;
    if (votes is Map && votes.isNotEmpty) return true;
    final total = pollResult['total_votes'];
    if (total is num && total > 0) return true;
    return false;
  }

  static String _resolveSessionIdForResults({
    String? feedSessionId,
    Map<String, dynamic>? feedPollResult,
    Map<String, dynamic>? feedPollVotingSchedule,
  }) {
    final fromFeed = (feedSessionId ?? '').trim();
    if (fromFeed.isNotEmpty) return fromFeed;
    final fromResult = (feedPollResult?['session_id'] ?? '').toString().trim();
    if (fromResult.isNotEmpty) return fromResult;
    final fromSchedule =
        (feedPollVotingSchedule?['current_session_id'] ?? '').toString().trim();
    if (fromSchedule.isNotEmpty) return fromSchedule;
    return 'default';
  }

  static bool _isPollResultsWin(Map<String, dynamic> rd) {
    if (rd['user_won'] == true || rd['user_won'] == 1) return true;
    if (rd['winner_pending_award'] == true || rd['winner_pending_award'] == 1) {
      return true;
    }
    final pointsEarned = (rd['points_earned'] as num?)?.toInt() ?? 0;
    return pointsEarned > 0;
  }

  /// Server has picked a winning option — safe to treat `user_won=false` as a true loss.
  static bool _pollResultsWinningIndexResolved(Map<String, dynamic> rd) {
    final wi = rd['winning_index'];
    if (wi is num && wi.toInt() >= 0) return true;
    final winningOption = rd['winning_option'];
    if (winningOption is Map && winningOption.isNotEmpty) return true;
    return false;
  }

  static int? _winningIndexFromPollResults(Map<String, dynamic> rd) {
    final wi = rd['winning_index'];
    if (wi is num) return wi.toInt();
    return null;
  }

  /// Resolved winner + no win signals → user genuinely lost; do not wait for win credit.
  static bool _isPollResultsConfirmedLoss(Map<String, dynamic> rd) {
    if (_isPollResultsWin(rd)) return false;
    return _pollResultsWinningIndexResolved(rd);
  }

  /// Feed is in result phase but WP-Cron has not set [winning_index] yet — may still win.
  static bool _isPollResultsWinCreditPending(
    Map<String, dynamic> rd,
    bool trustFeedResultPhase,
  ) {
    if (!trustFeedResultPhase) return false;
    if (_isPollResultsWin(rd)) return false;
    return _pollResultsOutcomeStillPending(rd, trustFeedResultPhase);
  }

  static String _inFlightSlotKey(int pollId, int userId) =>
      'poll_pnp_sync_${pollId}_$userId';

  /// Stable per-round id for marathon auto_run (500+ consecutive plays).
  ///
  /// Priority: [awarded_txn_id] → schedule/result timestamps → outcome fingerprint.
  static String buildPollRoundDedupeKey({
    required int pollId,
    required String stableSessionId,
    Map<String, dynamic>? schedule,
    Map<String, dynamic>? feedPollResult,
    required Map<String, dynamic> pollResultsRd,
  }) {
    final String sessionPart = stableSessionId.isNotEmpty
        ? stableSessionId
        : 'default';
    final List<Map<String, dynamic>?> sources = <Map<String, dynamic>?>[
      pollResultsRd,
      schedule,
      feedPollResult,
    ];

    final int txnId = (pollResultsRd['awarded_txn_id'] as num?)?.toInt() ?? 0;
    if (txnId > 0) {
      return '${pollId}_${sessionPart}_txn_$txnId';
    }

    final String? roundTimeToken = _firstNonEmptyPollRoundField(
      sources,
      const <String>[
        'result_display_ends_at',
        'ends_at',
        'voting_ends_at',
        'started_at',
        'poll_resolved_at',
      ],
    );
    if (roundTimeToken != null) {
      final int? wi = _winningIndexFromPollResults(pollResultsRd);
      final int pe = (pollResultsRd['points_earned'] as num?)?.toInt() ?? 0;
      final dynamic uw = pollResultsRd['user_won'];
      return '${pollId}_${sessionPart}_${roundTimeToken}_wi${wi ?? 'x'}_uw${uw}_pe$pe';
    }

    final String backendSession =
        (pollResultsRd['session_id'] ?? '').toString().trim();
    if (backendSession.isNotEmpty && backendSession != 'default') {
      final int? wi = _winningIndexFromPollResults(pollResultsRd);
      final int pe = (pollResultsRd['points_earned'] as num?)?.toInt() ?? 0;
      return '${pollId}_sess_${backendSession}_wi${wi ?? 'x'}_pe$pe';
    }

    final int? wi = _winningIndexFromPollResults(pollResultsRd);
    final int pe = (pollResultsRd['points_earned'] as num?)?.toInt() ?? 0;
    final int bet = (pollResultsRd['user_bet_pnp'] as num?)?.toInt() ?? 0;
    final dynamic uw = pollResultsRd['user_won'];
    final dynamic pending = pollResultsRd['winner_pending_award'];
    final dynamic totalVotes =
        pollResultsRd['total_votes'] ?? feedPollResult?['total_votes'];
    return '${pollId}_${sessionPart}_fp'
        '_wi${wi ?? 'x'}_uw${uw}_pe${pe}_bet$bet'
        '_tv${totalVotes}_p$pending';
  }

  static String? _firstNonEmptyPollRoundField(
    List<Map<String, dynamic>?> sources,
    List<String> keys,
  ) {
    for (final Map<String, dynamic>? src in sources) {
      if (src == null) continue;
      for (final String k in keys) {
        final String v = src[k]?.toString().trim() ?? '';
        if (v.isNotEmpty) return '$k:$v';
      }
    }
    return null;
  }

  static bool _pollRoundAlreadyReconciled(String dedupeKey) =>
      _pollBalanceReconcileKeys.contains(dedupeKey);

  static void _rememberPollBalanceReconcileKey(String dedupeKey) {
    if (_pollBalanceReconcileKeys.contains(dedupeKey)) return;
    _pollBalanceReconcileKeys.add(dedupeKey);
    _pollBalanceReconcileKeyOrder.add(dedupeKey);
    while (_pollBalanceReconcileKeyOrder.length > _pollBalanceReconcileKeyCap) {
      for (var i = 0; i < _pollBalanceReconcileEvictBatch; i++) {
        if (_pollBalanceReconcileKeyOrder.isEmpty) break;
        final String evicted = _pollBalanceReconcileKeyOrder.removeAt(0);
        _pollBalanceReconcileKeys.remove(evicted);
      }
    }
  }

  static void _queuePollPnpSyncBehindInFlight({
    required String inFlightKey,
    required int pollId,
    required int userId,
    String? feedSessionId,
    Map<String, dynamic>? feedPollResult,
    String? feedVotingStatus,
    Map<String, dynamic>? feedPollVotingSchedule,
    bool Function()? shouldContinue,
  }) {
    _queuedPollPnpSync[inFlightKey] = _PendingPollPnpSync(
      pollId: pollId,
      userId: userId,
      feedSessionId: feedSessionId,
      feedPollResult: feedPollResult,
      feedVotingStatus: feedVotingStatus,
      feedPollVotingSchedule: feedPollVotingSchedule,
      shouldContinue: shouldContinue,
    );
  }

  static void _flushQueuedPollPnpSync(String inFlightKey) {
    final pending = _queuedPollPnpSync.remove(inFlightKey);
    if (pending == null) return;
    MyPnpBalanceDebug.info(
      'PollWinnerPopup — running queued My PNP sync for pollId=${pending.pollId} '
      'userId=${pending.userId} (follow-up round after in-flight sync).',
    );
    unawaited(
      syncBalanceWhenShowingResult(
        pollId: pending.pollId,
        userId: pending.userId,
        feedSessionId: pending.feedSessionId,
        feedPollResult: pending.feedPollResult,
        feedVotingStatus: pending.feedVotingStatus,
        feedPollVotingSchedule: pending.feedPollVotingSchedule,
        shouldContinue: pending.shouldContinue,
      ),
    );
  }

  /// Cron may not have set [winning_index] yet when the feed already shows results.
  static bool _pollResultsOutcomeStillPending(
    Map<String, dynamic> rd,
    bool trustFeedResultPhase,
  ) {
    if (!trustFeedResultPhase) return false;
    if (_isPollResultsWin(rd)) return false;
    final winningIndex = rd['winning_index'];
    if (winningIndex is num && winningIndex.toInt() < 0) return true;
    return false;
  }

  static Future<Map<String, dynamic>?> _fetchPollResultsForSync({
    required int pollId,
    required String sessionId,
    required int userId,
    required bool trustFeedResultPhase,
    bool Function()? shouldContinue,
  }) async {
    final int maxAttempts = trustFeedResultPhase ? 6 : 1;
    Map<String, dynamic>? lastRd;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(
          Duration(milliseconds: 280 + attempt * 120),
        );
        MyPnpBalanceDebug.waiting(
          'PollWinnerPopup — /poll/results attempt ${attempt + 1}/$maxAttempts '
          'pollId=$pollId session=$sessionId (winner not resolved yet on server).',
        );
      }
      if (shouldContinue != null && !shouldContinue()) return lastRd;

      final Map<String, dynamic>? resJson =
          await EngagementService.fetchPollResults(
            pollId: pollId,
            sessionId: sessionId,
            userId: userId,
          );
      if (resJson == null || resJson['success'] != true) continue;

      final rd = resJson['data'];
      if (rd is! Map<String, dynamic>) continue;
      lastRd = rd;

      if (!_pollResultsOutcomeStillPending(rd, trustFeedResultPhase)) {
        return rd;
      }
    }
    return lastRd;
  }

  /// Silent My PNP sync when poll result is visible (feed or carousel).
  /// Fetches `/poll/results`, then [reconcileAfterPollResult] — server GET only, no popup.
  static Future<void> syncBalanceWhenShowingResult({
    required int pollId,
    required int userId,
    String? feedSessionId,
    Map<String, dynamic>? feedPollResult,
    String? feedVotingStatus,
    Map<String, dynamic>? feedPollVotingSchedule,
    bool Function()? shouldContinue,
  }) async {
    if (userId <= 0 || pollId <= 0) return;
    if (shouldContinue != null && !shouldContinue()) return;

    final String inFlightKey = _inFlightSlotKey(pollId, userId);
    if (_inFlightSyncKeys.contains(inFlightKey)) {
      _queuePollPnpSyncBehindInFlight(
        inFlightKey: inFlightKey,
        pollId: pollId,
        userId: userId,
        feedSessionId: feedSessionId,
        feedPollResult: feedPollResult,
        feedVotingStatus: feedVotingStatus,
        feedPollVotingSchedule: feedPollVotingSchedule,
        shouldContinue: shouldContinue,
      );
      MyPnpBalanceDebug.waiting(
        'PollWinnerPopup — sync in flight for pollId=$pollId userId=$userId '
        '(queued follow-up — next round will not be dropped).',
      );
      return;
    }
    _inFlightSyncKeys.add(inFlightKey);
    final int syncBaseline = PointProvider.instance.currentBalance;

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

      final bool trustFeedResultPhase =
          _isFeedResultLikeVotingStatus(feedVotingStatus) ||
          _feedPollResultImpliesResultPhase(feedPollResult);

      if (trustFeedResultPhase) {
        sessionId = _resolveSessionIdForResults(
          feedSessionId: feedSessionId,
          feedPollResult: feedPollResult,
          feedPollVotingSchedule: feedPollVotingSchedule,
        );
        state = 'SHOWING_RESULTS';
        data = feedPollVotingSchedule != null
            ? Map<String, dynamic>.from(feedPollVotingSchedule)
            : <String, dynamic>{};
        MyPnpBalanceDebug.info(
          'PollWinnerPopup — feed result phase (voting_status=$feedVotingStatus, '
          'session=$sessionId) → skip /poll/state, call /poll/results immediately.',
        );
      } else if (feedSessionId != null && feedSessionId.trim().isNotEmpty) {
        // Trust engagement feed session — hit /poll/results immediately.
        data = <String, dynamic>{};
        sessionId = feedSessionId.trim();
        state = 'SHOWING_RESULTS';
      } else {
        // Feed can show results a moment before /poll/state flips — retry briefly.
        for (var attempt = 0; attempt < 4; attempt++) {
          if (attempt > 0) {
            await Future<void>.delayed(const Duration(milliseconds: 350));
          }
          if (shouldContinue != null && !shouldContinue()) return;

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
          if (_feedPollResultImpliesResultPhase(feedPollResult) ||
              _isFeedResultLikeVotingStatus(feedVotingStatus)) {
            sessionId = _resolveSessionIdForResults(
              feedSessionId: feedSessionId,
              feedPollResult: feedPollResult,
              feedPollVotingSchedule: feedPollVotingSchedule,
            );
            state = 'SHOWING_RESULTS';
            data = feedPollVotingSchedule != null
                ? Map<String, dynamic>.from(feedPollVotingSchedule)
                : (data ?? <String, dynamic>{});
            MyPnpBalanceDebug.info(
              'PollWinnerPopup — /poll/state=$state but feed is in result phase; '
              'using session=$sessionId for /poll/results.',
            );
          } else {
            MyPnpBalanceDebug.waiting(
              'PollWinnerPopup — poll/state not SHOWING_RESULTS yet (got $state) pollId=$pollId. '
              'My PNP win sync waits for result phase.',
            );
            debugPrint(
              '[PollWinnerPopup] state never reached SHOWING_RESULTS (got $state) pollId=$pollId',
            );
            _scheduleResilientSync(
              userId: userId.toString(),
              syncKey: 'poll_sync_${pollId}_await_result',
            );
            return;
          }
        }
      }

      if (state != 'SHOWING_RESULTS') {
        debugPrint(
          '[PollWinnerPopup] state never reached SHOWING_RESULTS pollId=$pollId',
        );
        return;
      }

      final rd = await _fetchPollResultsForSync(
        pollId: pollId,
        sessionId: sessionId,
        userId: userId,
        trustFeedResultPhase: trustFeedResultPhase,
        shouldContinue: shouldContinue,
      );
      if (rd == null) {
        MyPnpBalanceDebug.fail(
          'PollWinnerPopup — GET /poll/results FAILED pollId=$pollId session=$sessionId. '
          'Cannot read user_won/points_earned/current_balance → My PNP delayed (resilient sync scheduled). '
          'err=${EngagementService.lastError}',
        );
        debugPrint(
          '[PollWinnerPopup] poll/results failed pollId=$pollId session=$sessionId err=${EngagementService.lastError}',
        );
        _scheduleResilientSync(
          userId: userId.toString(),
          syncKey: 'poll_sync_${pollId}_$sessionId',
        );
        return;
      }

      final userWon = _isPollResultsWin(rd);
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

      final String dedupeKey = buildPollRoundDedupeKey(
        pollId: pollId,
        stableSessionId: stableSessionId,
        schedule: data,
        feedPollResult: feedPollResult,
        pollResultsRd: rd,
      );
      if (_pollRoundAlreadyReconciled(dedupeKey)) {
        final bool awardStillPending =
            _isPollResultsWin(rd) &&
            ((rd['points_earned'] as num?)?.toInt() ?? 0) <= 0 &&
            (rd['winner_pending_award'] == true ||
                rd['winner_pending_award'] == 1);
        if (!awardStillPending) {
          MyPnpBalanceDebug.info(
            'PollWinnerPopup — round already reconciled pollId=$pollId '
            'dedupe=$dedupeKey (skip duplicate reconcile for this round).',
          );
          return;
        }
        MyPnpBalanceDebug.waiting(
          'PollWinnerPopup — dedupe=$dedupeKey but winner_pending_award '
          '→ retry win-credit sync for pollId=$pollId.',
        );
      } else {
        MyPnpBalanceDebug.info(
          'PollWinnerPopup — round dedupe pollId=$pollId key=$dedupeKey',
        );
      }

      /*
      Old Code: required pointsEarned > 0 — same Cron race as AutoRunPollWidget;
      winners with points_awarded not yet written never synced.
      if (!userWon || pointsEarned <= 0) {
        return;
      }
      */
      if (!userWon) {
        if (shouldContinue != null && !shouldContinue()) return;

        final bool confirmedLoss = _isPollResultsConfirmedLoss(rd);
        final bool winCreditPending = _isPollResultsWinCreditPending(
          rd,
          trustFeedResultPhase,
        );
        final int? winningIndex = _winningIndexFromPollResults(rd);

        try {
          if (confirmedLoss) {
            MyPnpBalanceDebug.info(
              'PollWinnerPopup — LOSS confirmed pollId=$pollId session=$stableSessionId '
              'winning_index=$winningIndex user_won=false points=$pointsEarned → '
              'short balance refresh (no win-credit poll, balance stays unchanged).',
            );
            await PointProvider.instance.reconcileAfterPollResult(
              userId: userId.toString(),
              authoritativePollBalance: currentBalance > 0
                  ? currentBalance
                  : null,
              balanceSyncDebugTag:
                  'carousel_feed_loss_confirmed_${pollId}_$stableSessionId',
              canonicalSource:
                  'poll_result_reconcile_carousel_loss_confirmed',
              shouldContinue: shouldContinue,
              balancePollMaxAttempts: 1,
            );
          } else if (winCreditPending) {
            MyPnpBalanceDebug.waiting(
              'PollWinnerPopup — outcome pending pollId=$pollId session=$stableSessionId '
              '(winning_index not resolved yet) → wait for possible win credit after WP-Cron.',
            );
            await PointProvider.instance.reconcileAfterPollResult(
              userId: userId.toString(),
              authoritativePollBalance: currentBalance > 0
                  ? currentBalance
                  : null,
              balanceSyncDebugTag:
                  'carousel_feed_result_pending_${pollId}_$stableSessionId',
              canonicalSource:
                  'poll_result_reconcile_carousel_result_pending',
              shouldContinue: shouldContinue,
              pollWinPriorBalanceExclusive: syncBaseline,
            );
          } else {
            MyPnpBalanceDebug.info(
              'PollWinnerPopup — poll loss pollId=$pollId session=$stableSessionId '
              '(no win signals) → single balance refresh.',
            );
            await PointProvider.instance.reconcileAfterPollResult(
              userId: userId.toString(),
              authoritativePollBalance: currentBalance > 0
                  ? currentBalance
                  : null,
              balanceSyncDebugTag:
                  'carousel_feed_loss_${pollId}_$stableSessionId',
              canonicalSource: 'poll_result_reconcile_carousel_loss',
              shouldContinue: shouldContinue,
              balancePollMaxAttempts: 1,
            );
          }
          _rememberPollBalanceReconcileKey(dedupeKey);
        } catch (e, st) {
          debugPrint('[PollWinnerPopup] loss reconcile: $e\n$st');
        }
        return;
      }

      if (shouldContinue != null && !shouldContinue()) return;

      /*
      Old Code: wrapped win path in an extra try { } (flattened — single outer try handles errors).
      */

      // Single dedupe id per poll for logging / future extension (session-free).
      final String pollWinSyncRefId = 'poll_win_sync_$pollId';
      Logger.info(
        'DEBUG_SYNC: poll win sync refId=$pollWinSyncRefId userId=$userId session=$stableSessionId',
        tag: 'PollWinnerPopup',
      );

      // Baseline captured before /poll/results (sync may have started with stale UI balance).
      final int baseline = syncBaseline;
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
      MyPnpBalanceDebug.info(
        'PollWinnerPopup WIN detected pollId=$pollId +$pointsEarned PNP — '
        'starting reconcileAfterPollResult (My PNP shimmer until GET /points/balance changes from $baseline).',
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
        shouldContinue: shouldContinue,
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

      _rememberPollBalanceReconcileKey(dedupeKey);

      /*
      ... prior notification / deferred refresh snippets kept above in history ...
      */

      // Old Code closing inner try } catch — removed after flatten.
    } catch (e, st) {
      debugPrint('[PollWinnerPopup] error: $e\n$st');
    } finally {
      _inFlightSyncKeys.remove(inFlightKey);
      _flushQueuedPollPnpSync(inFlightKey);
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

/// Latest params to run when a poll PNP sync is already in flight (marathon rounds).
class _PendingPollPnpSync {
  const _PendingPollPnpSync({
    required this.pollId,
    required this.userId,
    this.feedSessionId,
    this.feedPollResult,
    this.feedVotingStatus,
    this.feedPollVotingSchedule,
    this.shouldContinue,
  });

  final int pollId;
  final int userId;
  final String? feedSessionId;
  final Map<String, dynamic>? feedPollResult;
  final String? feedVotingStatus;
  final Map<String, dynamic>? feedPollVotingSchedule;
  final bool Function()? shouldContinue;
}
