/// Smart Poll Widget for AUTO_RUN lifecycle.
///
/// State flow:
/// 1. ACTIVE - User votes
/// 2. CLOSING_COUNTDOWN - 10 sec before poll closes
/// 3. SHOWING_RESULTS - Winning text + media only (no vote counts)
/// 4. RESTART_COUNTDOWN - 5 sec "Next poll starts in X" before next poll
/// 5. RESET - Fetch new session → ACTIVE

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:vibration/vibration.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/engagement_provider.dart';
import '../providers/point_provider.dart';
import '../services/engagement_service.dart';
import '../services/canonical_point_balance_sync.dart';
import '../services/point_service.dart';
import '../utils/logger.dart';
import 'package:flutter/foundation.dart';

/// One deferred `PointProvider.refreshPointState` reconcile per poll+session (retry-safe).
final Set<String> _autoRunPollBalanceServerFetchOnceKeys = <String>{};

enum PollDisplayState {
  active,
  closingCountdown,
  showingResults,
  restartCountdown,
  loading,
}

/// State machine for Auto-Run Poll lifecycle.
enum AutoPollState {
  loading,
  activeVoting,
  closingCountdown,
  calculatingResult,
  showingResult,
  restartCountdown,
}

/// API response for poll state
class PollStateData {
  final String state;
  final String currentSessionId;
  final String? endsAt;
  final int pollDurationMinutes;

  /// Server-driven length of the result phase (total seconds). Legacy APIs sent minutes as [result_display_duration].
  final int resultDisplayDurationSeconds;
  final String mode;
  final int pollBaseCost;

  /// User Amount mode step (PNP per unit k=1).
  /// If server doesn't provide it, we derive from [pollBaseCost] (legacy: when poll_base_cost < 1000, treat it as a "unit" => multiply by 1000).
  final int? betAmountStep;
  final double rewardMultiplier;
  final bool requireConfirmation;
  final bool allowUserAmount;

  PollStateData({
    required this.state,
    required this.currentSessionId,
    this.endsAt,
    required this.pollDurationMinutes,
    required this.resultDisplayDurationSeconds,
    required this.mode,
    this.pollBaseCost = 0,
    this.betAmountStep,
    this.rewardMultiplier = 4,
    this.requireConfirmation = true,
    this.allowUserAmount = true,
  });

  factory PollStateData.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? json;
    return PollStateData(
      state: (data['state'] ?? 'ACTIVE').toString(),
      currentSessionId: (data['current_session_id'] ?? '').toString(),
      endsAt: data['ends_at']?.toString(),
      /*
      Old Code:
      pollDuration: (data['poll_duration'] as num?)?.toInt() ?? 15,
      */
      // New Code: canonical unit is MINUTES across codebase.
      pollDurationMinutes: (data['poll_duration'] as num?)?.toInt() ?? 15,
      resultDisplayDurationSeconds: _parseResultDisplayDurationSeconds(data),
      mode: (data['mode'] ?? 'MANUAL').toString(),
      pollBaseCost: (data['poll_base_cost'] as num?)?.toInt() ?? 0,
      betAmountStep: (data['bet_amount_step'] as num?)?.toInt(),
      rewardMultiplier: (data['reward_multiplier'] as num?)?.toDouble() ?? 4,
      requireConfirmation:
          data['require_confirmation'] == true ||
          data['require_confirmation'] == 1 ||
          data['require_confirmation'] == '1',
      allowUserAmount:
          data['allow_user_amount'] == null ||
          data['allow_user_amount'] == true ||
          data['allow_user_amount'] == 1 ||
          data['allow_user_amount'] == '1',
    );
  }

  /// Prefers [result_display_duration_seconds]; legacy payloads used [result_display_duration] as **minutes**.
  static int _parseResultDisplayDurationSeconds(Map<String, dynamic> data) {
    final direct = data['result_display_duration_seconds'];
    if (direct is num) return direct.toInt().clamp(0, 86400);
    final legacyMin = data['result_display_duration'];
    if (legacyMin is num) {
      return (legacyMin.toInt() * 60).clamp(0, 86400);
    }
    return 60;
  }
}

/// Winning option from poll results (minimalist media-focused, no vote counts)
class WinningOption {
  final String text;
  final String? mediaUrl;
  final String? mediaType;

  WinningOption({required this.text, this.mediaUrl, this.mediaType});

  factory WinningOption.fromJson(Map<String, dynamic>? json) {
    if (json == null) return WinningOption(text: '');
    return WinningOption(
      text: (json['text'] ?? '').toString(),
      mediaUrl: json['media_url']?.toString(),
      mediaType: json['media_type']?.toString(),
    );
  }
}

/// API response for poll results (winning option + optional user win info for popup + sync)
class PollResultData {
  final String sessionId;
  final WinningOption winningOption;

  /// From API `winning_index`; negative means server has not resolved the winner yet.
  final int winningIndex;
  final bool userWon;
  final int pointsEarned;
  final int currentBalance;
  final int userBetPnp; // NEW FIELD
  final Map<String, int?>? userDetailedBets; // NEW FIELD

  PollResultData({
    required this.sessionId,
    required this.winningOption,
    this.winningIndex = -1,
    this.userWon = false,
    this.pointsEarned = 0,
    this.currentBalance = 0,
    this.userBetPnp = 0, // DEFAULT
    this.userDetailedBets, // NEW FIELD
  });

  factory PollResultData.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? json;
    final winning = data['winning_option'];
    final winningMap = winning is Map
        ? Map<String, dynamic>.from(winning)
        : null;
    int wi = (data['winning_index'] as num?)?.toInt() ?? -1;
    if (!data.containsKey('winning_index') && winningMap != null) {
      final text = (winningMap['text'] ?? '').toString().trim();
      final media = (winningMap['media_url'] ?? '').toString().trim();
      if (text.isNotEmpty || media.isNotEmpty) {
        wi = 0;
      }
    }

    // Parse the exact map sent from the backend
    Map<String, int?>? parsedDetailedBets;
    if (data['user_detailed_bets'] != null &&
        data['user_detailed_bets'] is Map) {
      parsedDetailedBets = {};
      final rawMap = data['user_detailed_bets'] as Map;
      for (final key in rawMap.keys) {
        parsedDetailedBets[key.toString()] = (rawMap[key] as num?)?.toInt();
      }
    }

    return PollResultData(
      sessionId: (data['session_id'] ?? '').toString(),
      winningOption: WinningOption.fromJson(winningMap),
      winningIndex: wi,
      userWon: data['user_won'] == true || data['user_won'] == 1,
      pointsEarned: (data['points_earned'] as num?)?.toInt() ?? 0,
      currentBalance: (data['current_balance'] as num?)?.toInt() ?? 0,
      userBetPnp:
          (data['user_bet_pnp'] as num?)?.toInt() ?? 0, // PARSED FROM API
      userDetailedBets: parsedDetailedBets, // ADDED
    );
  }
}

class AutoRunPollWidget extends StatefulWidget {
  final int pollId;
  final String question;
  final List<String> options;
  final int rewardPoints;
  final String? title;
  final bool hasInteracted;
  final String? userAnswer;
  final int userId;
  final VoidCallback? onVoteSubmitted;
  final VoidCallback? onPointsEarned;

  const AutoRunPollWidget({
    super.key,
    required this.pollId,
    required this.question,
    required this.options,
    this.rewardPoints = 0,
    this.title,
    this.hasInteracted = false,
    this.userAnswer,
    required this.userId,
    this.onVoteSubmitted,
    this.onPointsEarned,
  });

  @override
  State<AutoRunPollWidget> createState() => _AutoRunPollWidgetState();
}

class _AutoRunPollWidgetState extends State<AutoRunPollWidget>
    with WidgetsBindingObserver {
  /// Global cache: 'pollId_sessionId' -> { option label: value } (last successful vote).
  // Old Code:
  // static final Map<String, Map<String, int?>> _sessionReceiptCache = {};
  //
  // New Code:
  // Migrated to EngagementProvider + SharedPreferences persistence.

  /// Throttle app-resume calls to GET /poll/state (server runs throttled process_auto_run_poll).
  DateTime? _lastAppResumeServerTick;

  AutoPollState _state = AutoPollState.loading;
  PollStateData? _stateData;
  PollResultData? _resultData;

  /// Guards against external refresh/rebuild killing the result or restart countdown.
  bool _isLifecycleRunning = false;
  DateTime? _phaseEndsAtUtc;
  int _countdownSeconds = 0;

  /// Session id for which we've already fetched **final** results — prevents duplicate win handling.
  String? _resultFetchedForSession;

  // Old Code:
  // /// Per-option PNP for the last successful submit (option label → amount).
  // Map<String, int?>? _lastVoteDetailedBets;
  //
  // New Code:
  // Provider persistent state is the single source of truth.

  /// Stops [_fetchResultsWithRetry] when the widget is disposed.
  bool _abortResultsPoll = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Old Code:
    // unawaited(_engagementProvider.ensureInteractionCacheHydrated());
    // _fetchPollState().then((state) {
    // New Code:
    // Hydrate provider cache first to avoid first-frame receipt flicker.
    unawaited(_initializeAfterHydration());
  }

  Future<void> _initializeAfterHydration() async {
    await _engagementProvider.ensureInteractionCacheHydrated();
    if (!mounted) return;
    _fetchPollState().then((state) {
      if (!mounted || state == null) return;
      _isLifecycleRunning = true;
      if (state == 'ACTIVE') {
        _runVotingPhase();
      } else if (state == 'SHOWING_RESULTS') {
        if (_state == AutoPollState.showingResult) {
          _runResultAndCountdownPhase();
        } else if (_state == AutoPollState.activeVoting) {
          _runVotingPhase();
        } else {
          _isLifecycleRunning = false;
        }
      } else {
        _isLifecycleRunning = false;
      }
    });
  }

  @override
  void didUpdateWidget(covariant AutoRunPollWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // CRITICAL: While showing results or in restart countdown,
    // ignore any external data/prop changes from parent refreshes.
    if (_state == AutoPollState.showingResult ||
        _state == AutoPollState.calculatingResult ||
        _state == AutoPollState.restartCountdown) {
      // Intentionally block any state reset or reload here.
      // This prevents EngagementProvider auto-refresh from
      // killing the 5-second "Next poll" countdown.
      // Old Code:
      // ignore: avoid_print
      // print('--- BLOCKING EXTERNAL REFRESH. Currently in phase: $_state ---');
      // New Code: keep this signal but route through structured logger.
      Logger.info(
        'Blocking external refresh while phase=$_state',
        tag: 'AutoRunPoll',
      );
      return;
    }

    // Outside of result/countdown phases, we currently do not
    // need to react to widget prop changes here.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _abortResultsPoll = true;
    _isLifecycleRunning = false;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed) {
      return;
    }
    final now = DateTime.now();
    if (_lastAppResumeServerTick != null &&
        now.difference(_lastAppResumeServerTick!) <
            const Duration(seconds: 30)) {
      return;
    }
    _lastAppResumeServerTick = now;
    _onAppResumedThrottled();
  }

  /// After backgrounding, one GET /poll/state lets PHP run throttled `process_auto_run_poll`
  /// (catch-up award + safe reset) even if the local polling loop was suspended.
  void _onAppResumedThrottled() {
    unawaited(
      Future<void>.microtask(() async {
        try {
          if (!mounted) return;
          // internalCall: ignore _isLifecycleRunning so resume triggers GET /poll/state
          // (PHP throttles twork_rewards_throttled_auto_run_process).
          await _fetchPollState(internalCall: true);
        } catch (e, st) {
          debugPrint('[AutoRunPoll] app resume server tick: $e\n$st');
        }
      }),
    );
  }

  EngagementProvider get _engagementProvider =>
      Provider.of<EngagementProvider>(context, listen: false);

  void _transitionTo(
    AutoPollState newState, {
    int? countdown,
    bool clearVoteReceipt = false,
  }) {
    if (!mounted) return;
    setState(() {
      _state = newState;
      if (countdown != null) _countdownSeconds = countdown;
      if (clearVoteReceipt) {
        // Old Code:
        // _lastVoteDetailedBets = null;
        // final sessionId = _stateData?.currentSessionId ?? '';
        // _engagementProvider.clearPollSessionReceiptCache(widget.pollId, sessionId);
        //
        // New Code:
        // State retention policy: do NOT purge persistent receipt history
        // during rollover countdown. Keep until new vote/session truly replaces it.
      }
    });
  }

  /// Linear async lifecycle — immune to external rebuilds. Call only from within lifecycle or init.
  Future<void> _runVotingPhase() async {
    while (mounted && _phaseEndsAtUtc != null) {
      final now = DateTime.now().toUtc();
      final remaining = _phaseEndsAtUtc!.difference(now).inSeconds;
      if (remaining <= 0) break;
      if (remaining <= 10) {
        _transitionTo(AutoPollState.closingCountdown, countdown: remaining);
      }
      await Future.delayed(const Duration(seconds: 1));
    }
    if (!mounted) return;
    final nextState = await _fetchPollState(internalCall: true);
    if (!mounted) return;
    if (nextState == 'SHOWING_RESULTS') {
      if (_state == AutoPollState.showingResult) {
        _runResultAndCountdownPhase();
      } else if (_state == AutoPollState.activeVoting) {
        _runVotingPhase();
      } else {
        _isLifecycleRunning = false;
      }
    } else if (nextState == 'ACTIVE') {
      _runVotingPhase();
    } else {
      _isLifecycleRunning = false;
    }
  }

  /// Result display then strict 5-second "Next poll" countdown. Uses only Future.delayed.
  Future<void> _runResultAndCountdownPhase() async {
    // Result phase is measured in seconds server-side; reserve 5s for "next poll" strip.
    final resultDisplaySec = _stateData?.resultDisplayDurationSeconds ?? 60;
    final resultWaitTime = (resultDisplaySec - 5).clamp(0, 999999);

    for (int i = 0; i < resultWaitTime; i++) {
      if (!mounted) return;
      await Future.delayed(const Duration(seconds: 1));
    }
    if (!mounted) return;

    _transitionTo(AutoPollState.restartCountdown, countdown: 5);
    await _triggerRestartVibration();

    for (int i = 4; i >= 1; i--) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      setState(() => _countdownSeconds = i);
    }
    await Future.delayed(const Duration(seconds: 1));

    if (!mounted) return;
    _transitionTo(AutoPollState.loading, clearVoteReceipt: true);

    // Countdown finished: resume global engagement auto-polling
    // and trigger an immediate feed refresh for the next poll.
    try {
      await context.read<EngagementProvider>().resumeAndFetchFeed();
    } catch (_) {
      // If provider is not available, just stop lifecycle gracefully.
    }

    // PROFESSIONAL FIX: Loop to next cycle — Auto Poll runs continuously.
    // Without this, the widget would stay in loading and never restart.
    _resultFetchedForSession =
        null; // Allow next session's results to be fetched
    final nextState = await _fetchPollState(internalCall: true);
    if (!mounted) return;
    if (nextState == 'ACTIVE') {
      _isLifecycleRunning = true;
      _runVotingPhase();
    } else if (nextState == 'SHOWING_RESULTS') {
      _isLifecycleRunning = true;
      if (_state == AutoPollState.showingResult) {
        _runResultAndCountdownPhase();
      } else if (_state == AutoPollState.activeVoting) {
        _runVotingPhase();
      } else {
        _isLifecycleRunning = false;
      }
    } else {
      _isLifecycleRunning = false;
    }
  }

  /// Fetch poll state. When [internalCall] is false, no-op if lifecycle is running (ignore external refresh).
  Future<String?> _fetchPollState({bool internalCall = false}) async {
    if (!internalCall && _isLifecycleRunning) return null;
    if (!mounted) return null;
    if (!internalCall) {
      setState(() => _state = AutoPollState.loading);
    }

    try {
      final Map<String, dynamic>? json = await EngagementService.fetchPollState(
        pollId: widget.pollId,
      );
      if (json == null || json['success'] != true) {
        if (mounted) setState(() => _state = AutoPollState.activeVoting);
        return null;
      }

      final data = PollStateData.fromJson(json);
      final parsedEndsAt = data.endsAt != null && data.endsAt!.isNotEmpty
          ? DateTime.tryParse(data.endsAt!)
          : null;

      if (!mounted) return null;
      _stateData = data;

      // Decide local state + timestamps based on backend state.
      if (data.state == 'SHOWING_RESULTS') {
        _phaseEndsAtUtc = null;
        if (mounted) {
          setState(() => _state = AutoPollState.calculatingResult);
        }
        // Pause global engagement auto-polling so the feed
        // does NOT replace this poll while we show result/countdown.
        try {
          context.read<EngagementProvider>().pauseAutoPoll();
        } catch (_) {
          // Provider not found – fail silently; core poll logic still works.
        }
        await _fetchResultsWithRetry();
        if (!mounted) {
          return 'SHOWING_RESULTS';
        }
        // Empty session or aborted poll: avoid infinite "Calculating…" shell.
        if (_state == AutoPollState.calculatingResult) {
          setState(() => _state = AutoPollState.activeVoting);
        }
        return 'SHOWING_RESULTS';
      } else if (data.state == 'ACTIVE') {
        final nowUtc = DateTime.now().toUtc();
        if (parsedEndsAt != null) {
          _phaseEndsAtUtc = parsedEndsAt.toUtc();
        } else {
          /*
          Old Code:
          final pollSeconds = data.pollDuration > 0 ? data.pollDuration : 15;
          _phaseEndsAtUtc = nowUtc.add(Duration(seconds: pollSeconds));
          */
          final pollMinutes = data.pollDurationMinutes > 0
              ? data.pollDurationMinutes
              : 15;
          _phaseEndsAtUtc = nowUtc.add(Duration(minutes: pollMinutes));
        }
        _transitionTo(AutoPollState.activeVoting);
        return 'ACTIVE';
      } else {
        final nowUtc = DateTime.now().toUtc();
        if (parsedEndsAt != null) {
          _phaseEndsAtUtc = parsedEndsAt.toUtc();
        } else {
          /*
          Old Code:
          final pollSeconds = data.pollDuration > 0 ? data.pollDuration : 15;
          _phaseEndsAtUtc = nowUtc.add(Duration(seconds: pollSeconds));
          */
          final pollMinutes = data.pollDurationMinutes > 0
              ? data.pollDurationMinutes
              : 15;
          _phaseEndsAtUtc = nowUtc.add(Duration(minutes: pollMinutes));
        }
        _transitionTo(AutoPollState.activeVoting);
        return 'ACTIVE';
      }
    } catch (e) {
      if (mounted) setState(() => _state = AutoPollState.activeVoting);
      return null;
    }
  }

  /// Parses [winning_index] from API; if absent, infers readiness from [winning_option] (older servers).
  static int _resolvedWinningIndexFromPayload(dynamic data) {
    if (data is! Map) {
      return -1;
    }
    final m = Map<String, dynamic>.from(data);
    if (m.containsKey('winning_index')) {
      return (m['winning_index'] as num?)?.toInt() ?? -1;
    }
    final wo = m['winning_option'];
    if (wo is Map) {
      final text = (wo['text'] ?? '').toString().trim();
      final media = (wo['media_url'] ?? '').toString().trim();
      if (text.isNotEmpty || media.isNotEmpty) {
        return 0;
      }
    }
    return -1;
  }

  /// Polls `/poll/results` every 2s until `winning_index >= 0` (or legacy winning_option present).
  Future<void> _fetchResultsWithRetry() async {
    final sessionId = _stateData?.currentSessionId ?? '';
    if (sessionId.isEmpty) {
      return;
    }

    while (mounted && !_abortResultsPoll) {
      try {
        final Map<String, dynamic>? json =
            await EngagementService.fetchPollResults(
              pollId: widget.pollId,
              sessionId: sessionId,
              userId: widget.userId,
            );

        if (!mounted || _abortResultsPoll) {
          return;
        }

        if (json != null && json['success'] == true) {
          final data = json['data'];
          final wi = _resolvedWinningIndexFromPayload(data);
          if (wi >= 0) {
            final result = PollResultData.fromJson(json);
            if (!mounted || _abortResultsPoll) {
              return;
            }
            setState(() {
              _resultData = result;
              _state = AutoPollState.showingResult;
              _resultFetchedForSession = sessionId;
            });
            if (result.userWon && result.pointsEarned > 0) {
              _handlePollWinPopupAndSync(result);
            }
            return;
          }
        }
      } catch (_) {
        // Network blip — keep retrying.
      }

      if (!mounted || _abortResultsPoll) {
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  /// When user wins: **silent** point sync only (no winner popup / modal / notification UI).
  /// [CanonicalPointBalanceSync.apply] + [PointProvider.refreshPointState] keep balance correct in background.
  Future<void> _handlePollWinPopupAndSync(PollResultData result) async {
    if (!mounted) return;
    try {
      // ============================================================================
      // 1. Capture the EXACT provider instances FIRST to avoid Singleton scope mismatches.
      // ============================================================================
      AuthProvider? authProvider;
      PointProvider? pointProvider;
      if (mounted) {
        try {
          authProvider = context.read<AuthProvider>();
          pointProvider = context.read<PointProvider>();
        } catch (_) {}
      }
      final finalPointProvider = pointProvider ?? PointProvider.instance;

      // Baseline before optimistic bump (avoids double-counting earn twice).
      final int authBal =
          authProvider?.userPointsBalance ?? AuthProvider().userPointsBalance;
      final int baseline = math.max(finalPointProvider.currentBalance, authBal);
      final int localWithEarned = baseline + result.pointsEarned;
      final int effectiveBalance = result.currentBalance > 0
          ? result.currentBalance
          : localWithEarned;

      final optimisticRefId =
          'poll_win_${widget.pollId}_${result.sessionId.isNotEmpty ? result.sessionId : DateTime.now().millisecondsSinceEpoch}';

      Logger.info(
        'DEBUG_SYNC: optimisticAddPoints called userId=${widget.userId} '
        'pointsToAdd=${result.pointsEarned} source=poll_win_auto_run',
        tag: 'AutoRunPoll',
      );
      Logger.info(
        'DEBUG_SYNC: optimisticAddPoints refId=$optimisticRefId',
        tag: 'AutoRunPoll',
      );
      finalPointProvider.optimisticAddPoints(
        result.pointsEarned,
        refId: optimisticRefId,
      );

      debugPrint(
        '[AutoRunPoll] ✓ WINNER REWARD SYNC — Poll: ${widget.pollId}, Session: ${result.sessionId}, '
        'Earned: +${result.pointsEarned}, baseline=$baseline → effective=$effectiveBalance '
        '(API: ${result.currentBalance}, local+earn: $localWithEarned)',
      );

      Logger.info(
        'DEBUG_SYNC: Canonical balance sync userId=${widget.userId} '
        'balance=$effectiveBalance source=poll_win_auto_run',
        tag: 'AutoRunPoll',
      );
      await CanonicalPointBalanceSync.apply(
        userId: widget.userId.toString(),
        currentBalance: effectiveBalance,
        source: 'poll_win_auto_run',
        emitBroadcast: true,
        authProvider: authProvider,
        pointProvider: finalPointProvider,
      );
      Logger.info('DEBUG_SYNC: Canonical sync completed', tag: 'AutoRunPoll');

      if (kDebugMode) {
        debugPrint(
          '🚀 [PNP DEBUG] [${DateTime.now()}] Poll Win Detected! | PollID: ${widget.pollId} | Triggering Immediate Refresh...',
        );
      }
      unawaited(
        PointProvider.instance
            .refreshPointState(
              userId: widget.userId.toString(),
              forceRefresh: true,
              refreshBalance: true,
              refreshTransactions: true,
              refreshUserCallback: authProvider == null
                  ? null
                  : () => authProvider!.refreshUser(),
            )
            .catchError((Object error) {
              debugPrint('[AutoRunPoll] immediate refreshPointState: $error');
            }),
      );

      final String serverFetchKey = 'srv_${widget.pollId}_${result.sessionId}';
      if (_autoRunPollBalanceServerFetchOnceKeys.add(serverFetchKey)) {
        if (_autoRunPollBalanceServerFetchOnceKeys.length > 300) {
          _autoRunPollBalanceServerFetchOnceKeys.clear();
        }
        unawaited(
          Future<void>.delayed(const Duration(seconds: 3)).then((_) async {
            await PointProvider.instance
                .refreshPointState(
                  userId: widget.userId.toString(),
                  forceRefresh: true,
                  refreshBalance: true,
                  refreshTransactions: true,
                  refreshUserCallback: authProvider == null
                      ? null
                      : () => authProvider!.refreshUser(),
                )
                .catchError((Object error) {
                  debugPrint('[AutoRunPoll] delayed refreshPointState: $error');
                });
          }),
        );
      }

      /*
       * POPUP KILL-SWITCH (SILENT MODE) — UI celebration disabled:
       *   // showDialog(...);
       *   // showModalBottomSheet(...);
       *
       * In-app poll-win point notification / modal (PointNotificationManager) — kept off so only balance updates.
       *
      final eventId = 'poll_stable_${widget.pollId}_${result.sessionId}';
      final pollLabel = (widget.title != null && widget.title!.isNotEmpty)
          ? '${widget.title} — '
          : '';
      await PointNotificationManager().notifyPointEvent(
        type: PointNotificationType.engagementEarned,
        points: result.pointsEarned,
        currentBalance: effectiveBalance,
        description:
            '${pollLabel}Your selection matched the winning result. Well done! '
            '+${result.pointsEarned} PNP has been credited to your balance.',
        showPushNotification: false,
        showInAppNotification: true,
        showModalPopup: false,
        orderId: eventId,
        additionalData: {
          'itemType': 'poll',
          'itemTitle': widget.title ?? 'Poll',
          'pollId': widget.pollId,
          'sessionId': result.sessionId,
        },
      );
      */
      widget.onPointsEarned?.call();

      /*
      // 3. Defer server reconcile with AGGRESSIVE ANTI-STALE LOOP.
      unawaited(
        Future<void>.microtask(() async {
          final userIdStr = widget.userId.toString();
          for (int i = 1; i <= 3; i++) {
            await Future<void>.delayed(const Duration(seconds: 2));

            // OLD CODE:
            // authProvider?.applyPointsBalanceSnapshot(effectiveBalance);
            // finalPointProvider.applyRemoteBalanceSnapshot(
            //   userId: userIdStr,
            //   currentBalance: effectiveBalance,
            // );

            // NEW FIX: Re-apply canonical state without extra broadcasts (loop runs 3×).
            await CanonicalPointBalanceSync.apply(
              userId: userIdStr,
              currentBalance: effectiveBalance,
              source: 'poll_win_auto_run_resync',
              emitBroadcast: false,
              authProvider: authProvider,
              pointProvider: finalPointProvider,
            );

            // Old Code:
            try {
              await finalPointProvider.loadBalance(userIdStr,
                  forceRefresh: true);
              await finalPointProvider.loadTransactions(userIdStr,
                  forceRefresh: true);
            } catch (e) {
              debugPrint('[AutoRunPoll] sync loop $i error: $e');
            }

            // New Code:
            try {
              await finalPointProvider.refreshPointState(
                userId: userIdStr,
                forceRefresh: true,
                refreshBalance: true,
                refreshTransactions: true,
                refreshUserCallback: authProvider == null
                    ? null
                    : () => authProvider!.refreshUser(),
              );
            } catch (e) {
              debugPrint('[AutoRunPoll] sync loop $i refreshPointState error: $e');
            }
          }
        }),
      );
      */
    } catch (e, st) {
      debugPrint('Poll win popup/sync error: $e\n$st');
    }
  }

  Future<void> _triggerRestartVibration() async {
    try {
      final hasVibrator = (await Vibration.hasVibrator()) == true;
      if (hasVibrator) {
        await Vibration.vibrate(duration: 50, amplitude: 128);
      } else {
        HapticFeedback.lightImpact();
      }
    } catch (_) {
      HapticFeedback.lightImpact();
    }
  }

  Map<String, int?> _computeVoteDetailedBets(
    String answer, {
    List<int>? selectedOptionIds,
    int? betAmount,
    Map<int, int>? betAmountPerOption,
  }) {
    // Receipt stores the same unit value the user selected (Amount/Count input).
    final allow = _stateData?.allowUserAmount ?? true;
    final acc = <String, int>{};

    var ordered = <int>[];
    if (selectedOptionIds != null && selectedOptionIds.isNotEmpty) {
      // PROFESSIONAL FIX: Deduplicate indices to prevent ghost accumulation
      ordered = selectedOptionIds.toSet().toList()..sort();
    } else {
      for (final p
          in answer
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)) {
        final i = int.tryParse(p);
        if (i != null && i >= 0 && i < widget.options.length) {
          ordered.add(i);
        }
      }
      // PROFESSIONAL FIX: Deduplicate indices from backend string ("0,0,0,0" -> "0")
      ordered = ordered.toSet().toList()..sort();
    }

    if (betAmountPerOption != null && betAmountPerOption.isNotEmpty) {
      for (final idx in ordered) {
        if (idx < 0 || idx >= widget.options.length) continue;
        final label = widget.options[idx].trim();
        if (label.isEmpty) continue;
        final units = (betAmountPerOption[idx] ?? 1) > 0
            ? (betAmountPerOption[idx] ?? 1)
            : 1;
        // PROFESSIONAL FIX: Overwrite instead of accumulate
        acc[label] = units;
      }
      return Map<String, int?>.from(acc);
    }

    for (final idx in ordered) {
      if (idx < 0 || idx >= widget.options.length) continue;
      final label = widget.options[idx].trim();
      if (label.isEmpty) continue;
      // Amount alignment fix: single global amount (betAmount) or default 1 unit per line.
      final int units;
      if (!allow) {
        units = 1;
      } else if (betAmount != null && betAmount > 0) {
        units = betAmount;
      } else {
        units = 1; // null / non-positive => same as legacy base bet (one unit)
      }
      // PROFESSIONAL FIX: Overwrite instead of accumulate
      acc[label] = units;
    }
    return Map<String, int?>.from(acc);
  }

  Map<String, int?>? _fallbackVoteDetailedBets() {
    final ua = widget.userAnswer?.trim();
    if (ua == null || ua.isEmpty) return null;
    final m = _computeVoteDetailedBets(ua);
    return m.isEmpty ? null : m;
  }

  Map<String, int?>? _getEffectiveDetailedBets() {
    final providerLastVote = _engagementProvider.getPollLastVoteDetailedBets(
      widget.pollId,
    );
    Logger.info(
      '[AutoRunPoll] receipt debug provider=$providerLastVote backend=${_resultData?.userDetailedBets}',
      tag: 'AutoRunPoll',
    );

    /*
    // Legacy normalization (kept for reference)
    final int baseCost = _perUnitPnpForState(_stateData);
    final int safePerUnit = baseCost > 0 ? baseCost : 1000;
    final int rewardMult = _stateData?.rewardMultiplier.toInt() ?? 4;

    int normalizeToUnits(int val) {
      if (val <= 0) return 1;
      if (val >= 100) {
        int units = val ~/ safePerUnit;
        if (units <= 0) units = 1;
        if (units > 1 && units == rewardMult) return 1;
        return units;
      }
      if (val > 1 && val == rewardMult) return 1;
      return val;
    }
    */

    /*
    // Previous fix version (kept for reference)
    final int baseCost = _perUnitPnpForState(_stateData);
    final int safePerUnit = baseCost > 0 ? baseCost : 1000;
    final int rewardMult = _stateData?.rewardMultiplier.toInt() ?? 4;
    // Old Code:
    // final cacheKey =
    //     '${widget.pollId}_${sessionId.isEmpty ? 'default' : sessionId}';
    // final cached = _sessionReceiptCache[cacheKey];
    //
    // New Code:
    // cached values are now served from provider persistence layer.
    final trustedMap = (providerLastVote != null && providerLastVote.isNotEmpty)
        ? providerLastVote
        : ((cached != null && cached.isNotEmpty) ? cached : null);

    int? resolveTrustedUnit(String label) { ... }
    bool isSuspiciousMultiplier(int raw, int normalizedUnits) { ... }
    int normalizeToUnitsForLabel(String label, int val) { ... }
    */

    final int baseCost = _perUnitPnpForState(_stateData);
    final int safePerUnit = baseCost > 0 ? baseCost : 1000;
    /*
    Old Code — `rewardMultiplier.toInt()` silently truncated non-whole values server sends (eg 9.5x):
      final int rewardMult = _stateData?.rewardMultiplier.toInt() ?? 4;
    */

    /// Full precision from `/poll/state` ([PollStateData.rewardMultiplier] is server float).
    final double rewardMultEffective = _stateData?.rewardMultiplier ?? 4;

    final sessionId = _stateData?.currentSessionId ?? '';
    // Old Code:
    // final cacheKey =
    //    '${widget.pollId}_${sessionId.isEmpty ? 'default' : sessionId}';
    // final cached = _sessionReceiptCache[cacheKey];
    //
    // New Code:
    final cached = _engagementProvider.getPollSessionReceiptCache(
      widget.pollId,
      sessionId,
    );

    // UI lane source-of-truth: what user actually selected in the vote dialog.
    final trustedMap = (providerLastVote != null && providerLastVote.isNotEmpty)
        ? providerLastVote
        : ((cached != null && cached.isNotEmpty) ? cached : null);
    final fallbackMap = _fallbackVoteDetailedBets();

    int? resolveDisplayUnit(String label) {
      final localUnit = trustedMap?[label];
      if (localUnit != null && localUnit > 0) return localUnit;
      final fallbackUnit = fallbackMap?[label];
      if (fallbackUnit != null && fallbackUnit > 0) return fallbackUnit;
      return null;
    }

    bool sameApproxMultiplier(num a, num b) =>
        ((a.toDouble()) - (b.toDouble())).abs() < 1e-9;

    bool isSuspiciousMultiplierValue(int raw, int normalizedUnits) {
      if (rewardMultEffective <= 1) return false;
      if (sameApproxMultiplier(raw, rewardMultEffective) ||
          sameApproxMultiplier(normalizedUnits, rewardMultEffective)) {
        return true;
      }
      return false;
    }

    int normalizeBackendForCalcOnly(int raw) {
      if (raw <= 0) return 1;
      if (raw >= 100) {
        final units = raw ~/ safePerUnit;
        return units > 0 ? units : 1;
      }
      return raw;
    }

    int resolveUiUnitForLabel(String label, int rawBackendValue) {
      // UI must prefer user's raw selected unit (1,2,...) whenever available.
      final displayUnit = resolveDisplayUnit(label);
      if (displayUnit != null) return displayUnit;

      // No trusted UI source available -> use backend as a fallback-only source.
      final calcUnits = normalizeBackendForCalcOnly(rawBackendValue);
      if (isSuspiciousMultiplierValue(rawBackendValue, calcUnits)) return 1;
      return calcUnits;
    }

    Map<String, int?> processMap(Map<String, int?> rawMap) {
      return rawMap.map((key, value) {
        if (value == null) return MapEntry(key, null);
        return MapEntry(key, resolveUiUnitForLabel(key, value));
      });
    }

    if (providerLastVote != null && providerLastVote.isNotEmpty) {
      return processMap(providerLastVote);
    }

    if (cached != null && cached.isNotEmpty) {
      return processMap(cached);
    }

    if (_resultData?.userDetailedBets != null &&
        _resultData!.userDetailedBets!.isNotEmpty) {
      return processMap(_resultData!.userDetailedBets!);
    }

    // Only [user_bet_pnp] total from API — no per-option map; show placeholder 1 per line.
    final serverTotalBet = _resultData?.userBetPnp ?? 0;
    if (serverTotalBet > 0) {
      final ua = widget.userAnswer?.trim();
      if (ua != null && ua.isNotEmpty) {
        final optionsIndices = ua
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .map((s) => int.tryParse(s))
            .where((i) => i != null && i >= 0 && i < widget.options.length)
            .map((i) => i!)
            .toSet()
            .toList();

        if (optionsIndices.isNotEmpty) {
          final map = <String, int?>{};
          for (final idx in optionsIndices) {
            final label = widget.options[idx].trim();
            if (label.isNotEmpty) {
              map[label] = 1;
            }
          }
          if (map.isNotEmpty) return processMap(map);
        }
      }
      return processMap({'Your Bet': 1});
    }

    final fallback = _fallbackVoteDetailedBets();
    if (fallback == null || fallback.isEmpty) return null;
    return processMap(fallback);
  }

  void _recordSuccessfulVoteMetadata(
    String answer, {
    List<int>? selectedOptionIds,
    int? betAmount,
    Map<int, int>? betAmountPerOption,
  }) {
    if (!mounted) return;
    // Session cache: same map shape as the receipt (raw backend/client units).
    final map = _computeVoteDetailedBets(
      answer,
      selectedOptionIds: selectedOptionIds,
      betAmount: betAmount,
      betAmountPerOption: betAmountPerOption,
    );
    // Old Code:
    // setState(() {
    //   _lastVoteDetailedBets = map.isEmpty ? null : map;
    // });
    //
    // New Code:
    // Keep only provider persistent copy as single source-of-truth.

    // Write to static session cache (handles empty sessionId safely)
    if (map.isNotEmpty) {
      final sessionId = _stateData?.currentSessionId ?? '';
      unawaited(
        _engagementProvider.setPollLastVoteDetailedBets(widget.pollId, map),
      );
      unawaited(
        _engagementProvider.setPollSessionReceiptCache(
          widget.pollId,
          sessionId,
          map,
        ),
      );
    }
  }

  int? _safeParseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    final normalized = value.toString().trim().replaceAll(
      RegExp(r'[^0-9-]'),
      '',
    );
    if (normalized.isEmpty || normalized == '-') return null;
    return int.tryParse(normalized);
  }

  Future<void> _submitVote(
    String answer, {
    List<int>? selectedOptionIds,
    int? betAmount,
    Map<int, int>? betAmountPerOption,
  }) async {
    try {
      final sessionId = _stateData?.currentSessionId ?? '';
      final result = await EngagementService.submitInteraction(
        userId: widget.userId,
        itemId: widget.pollId,
        answer: answer,
        sessionId: sessionId.isEmpty ? null : sessionId,
        selectedOptionIds: selectedOptionIds,
        betAmount: betAmount,
        betAmountPerOption: betAmountPerOption,
      );

      if (result['success'] == true) {
        _recordSuccessfulVoteMetadata(
          answer,
          selectedOptionIds: selectedOptionIds,
          betAmount: betAmount,
          betAmountPerOption: betAmountPerOption,
        );
        // Old Code: no local poll transaction enrichment payload.
        // New Code: normalize selected option labels + per-option spend for history.
        final normalizedSelectedOptions = <Map<String, dynamic>>[];
        final sortedSelectedIds = (selectedOptionIds ?? <int>[])..sort();
        final unitPnp = _perUnitPnpForState(_stateData);
        final int selectionCount = sortedSelectedIds.length;
        int normalizedTotalBetPnp = 0;
        for (final idx in sortedSelectedIds) {
          if (idx < 0 || idx >= widget.options.length) continue;
          final label = widget.options[idx].trim();
          int betPnp;
          int units;
          if (betAmountPerOption != null &&
              betAmountPerOption.containsKey(idx)) {
            // Old Code: averaged or ambiguous fallbacks when per-option missing.
            //
            // New Code: exact per line — units from map, PNP = perUnit * units.
            final u = betAmountPerOption[idx] ?? 1;
            units = u > 0 ? u : 1;
            betPnp = unitPnp > 0 ? (unitPnp * units) : 0;
          } else if (betAmount != null && betAmount > 0) {
            if (selectionCount == 1) {
              // Single selection: betAmount is the exact PNP stake (no unit multiply).
              betPnp = betAmount;
              units = betAmount;
            } else {
              // Multi selection, shared amount field: same units applied to each
              // selected option (matches vote receipt / no averaging).
              units = betAmount;
              betPnp = unitPnp > 0 ? (unitPnp * betAmount) : 0;
            }
          } else {
            units = 1;
            betPnp = unitPnp > 0 ? unitPnp : 0;
          }
          normalizedTotalBetPnp += betPnp;
          normalizedSelectedOptions.add({
            'index': idx,
            'label': label,
            'betPnp': betPnp,
            'betUnits': units,
          });
        }
        // Old Code: recordPollTransaction was called only inside new_balance branch.
        // New Code: decouple success-path history recording from balance payload availability.
        if (normalizedSelectedOptions.isNotEmpty) {
          final parsedBalance = result['data'] != null
              ? _safeParseInt(result['data']['new_balance'])
              : null;
          unawaited(
            PointService.recordPollTransaction(
              userId: widget.userId.toString(),
              pollId: widget.pollId,
              pollTitle: widget.title,
              sessionId: sessionId,
              selectedOptions: normalizedSelectedOptions,
              totalBetPnp: normalizedTotalBetPnp,
              // Keep signature unchanged: use -1 sentinel when server balance is missing.
              newBalance: parsedBalance ?? -1,
              // Old Code:
              // orderId:
              //     'engagement:poll:${widget.pollId}:${sessionId.isEmpty ? DateTime.now().millisecondsSinceEpoch : sessionId}',
              //
              // New Code: let service generate deterministic id for retry-safe dedupe.
              description: 'Poll vote submitted',
            ),
          );
        }
        // INSTANT BALANCE DEDUCTION FIX
        // Immediately sync the deducted balance to the EXACT UI providers.
        if (result['data'] != null && result['data']['new_balance'] != null) {
          // Old Code:
          // final newBalance = result['data']['new_balance'] as int;
          //
          // New Code:
          // Normalize numeric payload from backend (can be int/num/string).
          final newBalance = _safeParseInt(result['data']['new_balance']);
          if (newBalance == null) {
            widget.onVoteSubmitted?.call();
            final points = result['points_earned'] as int? ?? 0;
            if (points > 0) widget.onPointsEarned?.call();
            return;
          }
          AuthProvider? authProvider;
          PointProvider? pointProvider;
          if (mounted) {
            try {
              authProvider = context.read<AuthProvider>();
              pointProvider = context.read<PointProvider>();
            } catch (_) {}
          }

          /*
          // OLD CODE:
          // authProvider?.applyPointsBalanceSnapshot(newBalance);
          // (pointProvider ?? PointProvider.instance).applyRemoteBalanceSnapshot(
          //   userId: widget.userId.toString(),
          //   currentBalance: newBalance,
          // );
          */

          // NEW FIX: Vote deduction — canonical memory + meta + disk (no duplicate broadcast).
          await CanonicalPointBalanceSync.apply(
            userId: widget.userId.toString(),
            currentBalance: newBalance,
            source: 'poll_vote_deduct_auto_run',
            emitBroadcast: false,
            authProvider: authProvider,
            pointProvider: pointProvider ?? PointProvider.instance,
          );
        }

        widget.onVoteSubmitted?.call();
        final points = result['points_earned'] as int? ?? 0;
        if (points > 0) widget.onPointsEarned?.call();
      } else if (mounted) {
        final code = result['code']?.toString().toLowerCase();
        final message =
            result['message']?.toString() ?? 'Failed to submit vote';
        // Old Code: ScaffoldMessenger.of(context).showSnackBar(
        // Old Code:   SnackBar(
        // Old Code:     content: Text(message),
        // Old Code:     backgroundColor:
        // Old Code:         (code == 'insufficient_balance' || code == 'insufficient_funds')
        // Old Code:             ? Colors.red
        // Old Code:             : Colors.orange,
        // Old Code:   ),
        // Old Code: );
        final isInsufficient =
            code == 'insufficient_balance' || code == 'insufficient_funds';
        final safeBalance = _safeParseInt(result['balance']);
        final safeRequired = _safeParseInt(result['required']);
        final displayMessage =
            isInsufficient && safeBalance != null && safeRequired != null
            ? 'Point မလောက်ပါ။ လက်ကျန်: $safeBalance, လိုအပ်ချက်: $safeRequired'
            : message;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(displayMessage),
            backgroundColor: isInsufficient ? Colors.red : Colors.orange,
          ),
        );

        // Old Code: (no immediate re-sync after insufficient response)
        //
        // New Code:
        // Force-refresh provider balance so UI state converges immediately with server.
        if (isInsufficient) {
          try {
            final pointProvider = context.read<PointProvider>();
            await pointProvider.loadBalance(
              widget.userId.toString(),
              forceRefresh: true,
            );
          } catch (_) {}
        }
      }
    } catch (e, _) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Old Code:
    // debugPrint('👉👉👉 APP IS RUNNING NEW CODE! State: $_state 👈👈👈');
    // New Code: removed noisy debug print.

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: _buildChild(),
    );
  }

  /// PNP per one betting unit; aligned with [QuizData.spentPerUnitPnpForPoll] (incl. reward misfit).
  int _perUnitPnpForState(PollStateData? sd) {
    // Old Code:
    // if (sd == null) return 1000;
    // final b = sd.pollBaseCost;
    // final allow = sd.allowUserAmount;
    // if (allow) {
    //   final step = sd.betAmountStep;
    //   if (step != null && step > 0) return step;
    // }
    // if (b > 0 && b < 1000) {
    //   return b * 1000;
    // }
    // if (b > 0) {
    //   final rp = widget.rewardPoints;
    //   if (rp > 0 && b == rp) {
    //     return 1000;
    //   }
    //   return b;
    // }
    // return 1000;

    // New Code:
    // Mirror backend interact formula source/fallback order to avoid client/server cost drift.
    if (sd == null) return 1000;
    final baseCost = sd.pollBaseCost;
    final allowUserAmount = sd.allowUserAmount;

    if (allowUserAmount) {
      final step = sd.betAmountStep;
      if (step != null && step > 0) return step;
      if (baseCost > 0 && baseCost < 1000) return baseCost * 1000;
      if (baseCost > 0) return baseCost;
      return 1000;
    }

    // Base Cost mode: backend uses poll_base_cost and falls back to item reward points, then 1000.
    if (baseCost > 0) return baseCost;
    if (widget.rewardPoints > 0) return widget.rewardPoints;
    return 1000;
  }

  Widget _buildChild() {
    switch (_state) {
      case AutoPollState.loading:
        return _LoadingUI(key: const ValueKey('loading'));
      case AutoPollState.activeVoting:
        return _VotingUI(
          key: const ValueKey('voting'),
          pollId: widget.pollId,
          question: widget.question,
          options: widget.options,
          rewardPoints: widget.rewardPoints,
          title: widget.title,
          hasInteracted: false,
          userAnswer: null,
          userId: widget.userId,
          perUnitPnp: _perUnitPnpForState(_stateData),
          requireConfirmation: _stateData?.requireConfirmation ?? true,
          allowUserAmount: _stateData?.allowUserAmount ?? true,
          onSubmitVote: _submitVote,
        );
      case AutoPollState.closingCountdown:
        return _CountdownUI(
          key: ValueKey('closing_$_countdownSeconds'),
          seconds: _countdownSeconds,
          label: 'Closing in...',
        );
      case AutoPollState.calculatingResult:
        return const _CalculatingResultUI(key: ValueKey('calculating_result'));
      case AutoPollState.showingResult:
        final detailed = _getEffectiveDetailedBets();
        return WinningResultWidget(
          key: ValueKey('result_${_stateData?.currentSessionId ?? ""}'),
          winningOption: _resultData?.winningOption ?? WinningOption(text: ''),
          userDetailedBets: detailed,
          perUnitPnp: _perUnitPnpForState(_stateData),
        );
      case AutoPollState.restartCountdown:
        return _RestartCountdownUI(
          key: ValueKey('restart_$_countdownSeconds'),
          seconds: _countdownSeconds,
        );
    }
  }
}

class _LoadingUI extends StatelessWidget {
  const _LoadingUI({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.orange[400]!, Colors.deepOrange[600]!],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}

class _VotingUI extends StatefulWidget {
  final int pollId;
  final String question;
  final List<String> options;
  final int rewardPoints;
  final String? title;
  final bool hasInteracted;
  final String? userAnswer;
  final int userId;

  /// PNP per selected option for k=1 (matches WordPress deduction formula).
  final int perUnitPnp;
  final bool requireConfirmation;
  final Future<void> Function(
    String answer, {
    List<int>? selectedOptionIds,
    int? betAmount,
    Map<int, int>? betAmountPerOption,
  })
  onSubmitVote;
  final bool allowUserAmount;

  const _VotingUI({
    super.key,
    required this.pollId,
    required this.question,
    required this.options,
    required this.rewardPoints,
    this.title,
    required this.hasInteracted,
    this.userAnswer,
    required this.userId,
    required this.perUnitPnp,
    required this.requireConfirmation,
    required this.onSubmitVote,
    this.allowUserAmount = true,
  });

  @override
  State<_VotingUI> createState() => _VotingUIState();
}

class _VotingUIState extends State<_VotingUI> {
  final Set<int> _selectedIndices = {};
  bool _isSubmitting = false;

  static String _optionText(dynamic opt) {
    if (opt is String) return opt;
    if (opt is Map && opt['text'] != null) return opt['text'].toString();
    return opt.toString();
  }

  @override
  void initState() {
    super.initState();
  }

  Future<void> _submitWithAmount(int amount) async {
    if (_selectedIndices.isEmpty || _isSubmitting || amount <= 0) return;
    try {
      final baseSelected = _selectedIndices.toList()..sort();
      final answerStr = baseSelected.join(',');

      if (!mounted) return;
      setState(() => _isSubmitting = true);
      await widget.onSubmitVote(
        answerStr,
        selectedOptionIds: baseSelected,
        betAmount: amount,
      );
    } catch (e, stacktrace) {
      debugPrint('Submit error: $e\n$stacktrace');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _submitWithAmountPerOption(Map<int, int> amountPerOption) async {
    if (_selectedIndices.isEmpty || _isSubmitting || amountPerOption.isEmpty)
      return;
    try {
      final baseSelected = _selectedIndices.toList()..sort();
      final answerStr = baseSelected.join(',');
      // Freeze the dialog values so "Your Choice" uses exactly what user confirmed.
      final submittedAmounts = Map<int, int>.from(amountPerOption);

      if (!mounted) return;
      setState(() => _isSubmitting = true);
      await widget.onSubmitVote(
        answerStr,
        selectedOptionIds: baseSelected,
        betAmountPerOption: submittedAmounts,
      );
    } catch (e, stacktrace) {
      debugPrint('Submit error: $e\n$stacktrace');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final formattedUserChoices = _formatUserChoices(
      widget.userAnswer,
      widget.options,
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.orange[400]!, Colors.deepOrange[600]!],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.poll, color: Colors.white, size: 24),
              const SizedBox(width: 8),
              Text(
                widget.title ?? 'Poll',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (widget.rewardPoints > 0) ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '+${widget.rewardPoints} PTS',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Text(
            widget.question,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 16),
          if (widget.hasInteracted && formattedUserChoices != null)
            Text(
              'Your choice: $formattedUserChoices',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 14,
              ),
            )
          else ...[
            ...widget.options.asMap().entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      if (_selectedIndices.contains(e.key)) {
                        _selectedIndices.remove(e.key);
                      } else {
                        _selectedIndices.add(e.key);
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(
                        _selectedIndices.contains(e.key) ? 0.35 : 0.2,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: _selectedIndices.contains(e.key)
                          ? Border.all(color: Colors.white, width: 2)
                          : null,
                    ),
                    child: Row(
                      children: [
                        Checkbox(
                          value: _selectedIndices.contains(e.key),
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _selectedIndices.add(e.key);
                              } else {
                                _selectedIndices.remove(e.key);
                              }
                            });
                          },
                          activeColor: Colors.white,
                          checkColor: Colors.deepOrange,
                          fillColor: WidgetStateProperty.resolveWith(
                            (_) => Colors.white.withOpacity(0.5),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _optionText(e.value),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_selectedIndices.isEmpty || _isSubmitting)
                    ? null
                    : () async {
                        final selectedOptionIds = _selectedIndices;
                        final selectedCount = selectedOptionIds.length;
                        if (selectedCount == 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'ကျေးဇူးပြု၍ အနည်းဆုံး တစ်ခု ရွေးချယ်ပါ။',
                              ),
                            ),
                          );
                          return;
                        }

                        final int perUnit = widget.perUnitPnp;

                        // 3. Fetch latest balance from API (PointProvider)
                        if (!mounted) return;
                        setState(() => _isSubmitting = true);
                        final pointProvider = context.read<PointProvider>();
                        await pointProvider.loadBalance(
                          widget.userId.toString(),
                          forceRefresh: true,
                        );
                        if (!mounted) return;
                        setState(() => _isSubmitting = false);

                        final apiBalance = pointProvider.currentBalance;
                        // PROFESSIONAL FIX: Strictly trust the freshly fetched API balance (Single Source of Truth).
                        // Using an outdated local cache (customBalance) causes insufficient balance errors on the server.
                        final int userBalance = apiBalance;

                        // 4. Calculate cost for Amount multiplier k = 1
                        final int requiredPerAmount = perUnit * selectedCount;
                        if (requiredPerAmount <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Poll cost မမှန်ကန်သဖြင့် ကစား၍မရပါ။',
                              ),
                            ),
                          );
                          return;
                        }

                        // If admin has disabled user Amount selection, treat Amount as always 1.
                        if (!widget.allowUserAmount) {
                          final totalCost = requiredPerAmount;
                          if (totalCost > userBalance) {
                            showDialog<void>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text(
                                  'Point မလောက်ပါ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red,
                                  ),
                                ),
                                content: Text(
                                  'ဤ Poll သည် checkbox တစ်ခုလျှင် $perUnit points ကုန်ကျပါသည်။\n\n'
                                  'သင်ရွေးချယ်ထားသော checkbox $selectedCount ခုအတွက် စုစုပေါင်း $totalCost points လိုအပ်ပါသည်။\n\n'
                                  'သင့်လက်ကျန်: $userBalance points ဖြစ်သဖြင့် ယခုအချိန်တွင် ကစား၍ မရနိုင်ပါ။',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text('ပိတ်မည်'),
                                  ),
                                ],
                              ),
                            );
                            return;
                          }

                          // Single-amount confirm flow
                          await _submitWithAmount(1);
                          return;
                        }

                        // 5. User must afford at least base cost (1 per option)
                        if (userBalance < requiredPerAmount) {
                          showDialog<void>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text(
                                'Point မလောက်ပါ',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
                              ),
                              content: Text(
                                'ဤ Poll သည် checkbox တစ်ခုလျှင် $perUnit points ကုန်ကျပါသည်။\n\n'
                                'သင်ရွေးချယ်ထားသော checkbox $selectedCount ခုအတွက် အနည်းဆုံး '
                                '$requiredPerAmount points လိုအပ်ပါသည်။\n\n'
                                'သင့်လက်ကျန်: $userBalance points ဖြစ်သဖြင့် ယခုအချိန်တွင် ကစား၍ မရနိုင်ပါ။',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('ပိတ်မည်'),
                                ),
                              ],
                            ),
                          );
                          return;
                        }

                        // 6. Per-option amount dialog (each selected option gets its own amount)
                        final selectedList = selectedOptionIds.toList()..sort();
                        final Map<int, int> amountPerOption = {
                          for (final i in selectedList) i: 1,
                        };
                        final options = widget.options;

                        // Old Code: per-option amount `showDialog<void>` — both actions used `Navigator.pop(dialogCtx)` only (no result).
                        /*
                        // Old Code:
                        await showDialog<void>(
                          context: context,
                          barrierDismissible: false,
                          builder: (ctx) {
                            return StatefulBuilder(
                              builder: (dialogCtx, setDialogState) {
                                int totalCost = 0;
                                for (final idx in selectedList) {
                                  totalCost +=
                                      perUnit * (amountPerOption[idx] ?? 1);
                                }
                                final canAfford = totalCost <= userBalance;
                                return AlertDialog(
                                  title: const Text(
                                    'Option တစ်ခုချင်းစီအတွက် Amount သတ်မှတ်ပါ',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16),
                                  ),
                                  content: SingleChildScrollView(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'သင့်လက်ရှိ Point: $userBalance',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600),
                                        ),
                                        Text(
                                          'အဆင့် တစ်ခုလျှင်: $perUnit PNP',
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey[700]),
                                        ),
                                        const SizedBox(height: 16),
                                        ...selectedList.map((idx) {
                                          final amt = amountPerOption[idx] ?? 1;
                                          final optLabel = idx < options.length
                                              ? options[idx]
                                              : 'Option ${idx + 1}';
                                          final maxForThis =
                                              userBalance ~/ perUnit;
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 12),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  flex: 2,
                                                  child: Text(
                                                    _optionText(optLabel),
                                                    style: const TextStyle(
                                                        fontSize: 14),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    maxLines: 2,
                                                  ),
                                                ),
                                                Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                      icon: const Icon(
                                                          Icons
                                                              .remove_circle_outline,
                                                          size: 22),
                                                      onPressed: amt > 1
                                                          ? () => setDialogState(
                                                              () =>
                                                                  amountPerOption[
                                                                          idx] =
                                                                      amt - 1)
                                                          : null,
                                                      padding: EdgeInsets.zero,
                                                      constraints:
                                                          const BoxConstraints(
                                                              minWidth: 36,
                                                              minHeight: 36),
                                                    ),
                                                    SizedBox(
                                                      width: 36,
                                                      child: Text(
                                                        '$amt',
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: const TextStyle(
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            fontSize: 16),
                                                      ),
                                                    ),
                                                    IconButton(
                                                      icon: const Icon(
                                                          Icons
                                                              .add_circle_outline,
                                                          size: 22),
                                                      onPressed: amt <
                                                              maxForThis
                                                          ? () => setDialogState(
                                                              () =>
                                                                  amountPerOption[
                                                                          idx] =
                                                                      amt + 1)
                                                          : null,
                                                      padding: EdgeInsets.zero,
                                                      constraints:
                                                          const BoxConstraints(
                                                              minWidth: 36,
                                                              minHeight: 36),
                                                    ),
                                                  ],
                                                ),
                                                Text(
                                                  '${perUnit * amt}',
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey[600]),
                                                ),
                                              ],
                                            ),
                                          );
                                        }),
                                        const Divider(),
                                        Text(
                                          'စုစုပေါင်း ကုန်ကျမည်: $totalCost PNP',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: canAfford
                                                  ? null
                                                  : Colors.red),
                                        ),
                                        if (!canAfford)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 6),
                                            child: Text(
                                              'Point မလောက်ပါ (လိုအပ်ချက်: $totalCost)',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.red[700]),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(dialogCtx),
                                      child: const Text(
                                        'မလုပ်တော့ပါ',
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    ),
                                    ElevatedButton(
                                      onPressed: canAfford
                                          ? () => Navigator.pop(dialogCtx)
                                          : null,
                                      child: const Text('ကစားမည်'),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        );
                        */

                        final bool? isConfirmed = await showDialog<bool>(
                          context: context,
                          barrierDismissible: false,
                          builder: (ctx) {
                            return StatefulBuilder(
                              builder: (dialogCtx, setDialogState) {
                                int totalCost = 0;
                                for (final idx in selectedList) {
                                  totalCost +=
                                      perUnit * (amountPerOption[idx] ?? 1);
                                }
                                final canAfford = totalCost <= userBalance;
                                return AlertDialog(
                                  title: const Text(
                                    'Option တစ်ခုချင်းစီအတွက် Amount သတ်မှတ်ပါ',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  content: SingleChildScrollView(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'သင့်လက်ရှိ Point: $userBalance',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          'အဆင့် တစ်ခုလျှင်: $perUnit PNP',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey[700],
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        ...selectedList.map((idx) {
                                          final amt = amountPerOption[idx] ?? 1;
                                          final optLabel = idx < options.length
                                              ? options[idx]
                                              : 'Option ${idx + 1}';
                                          final maxForThis =
                                              userBalance ~/ perUnit;
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 12,
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  flex: 2,
                                                  child: Text(
                                                    _optionText(optLabel),
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    maxLines: 2,
                                                  ),
                                                ),
                                                Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                      icon: const Icon(
                                                        Icons
                                                            .remove_circle_outline,
                                                        size: 22,
                                                      ),
                                                      onPressed: amt > 1
                                                          ? () => setDialogState(
                                                              () =>
                                                                  amountPerOption[idx] =
                                                                      amt - 1,
                                                            )
                                                          : null,
                                                      padding: EdgeInsets.zero,
                                                      constraints:
                                                          const BoxConstraints(
                                                            minWidth: 36,
                                                            minHeight: 36,
                                                          ),
                                                    ),
                                                    SizedBox(
                                                      width: 36,
                                                      child: Text(
                                                        '$amt',
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 16,
                                                        ),
                                                      ),
                                                    ),
                                                    IconButton(
                                                      icon: const Icon(
                                                        Icons
                                                            .add_circle_outline,
                                                        size: 22,
                                                      ),
                                                      onPressed:
                                                          amt < maxForThis
                                                          ? () => setDialogState(
                                                              () =>
                                                                  amountPerOption[idx] =
                                                                      amt + 1,
                                                            )
                                                          : null,
                                                      padding: EdgeInsets.zero,
                                                      constraints:
                                                          const BoxConstraints(
                                                            minWidth: 36,
                                                            minHeight: 36,
                                                          ),
                                                    ),
                                                  ],
                                                ),
                                                Text(
                                                  '${perUnit * amt}',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey[600],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }),
                                        const Divider(),
                                        Text(
                                          'စုစုပေါင်း ကုန်ကျမည်: $totalCost PNP',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: canAfford
                                                ? null
                                                : Colors.red,
                                          ),
                                        ),
                                        if (!canAfford)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 6,
                                            ),
                                            child: Text(
                                              'Point မလောက်ပါ (လိုအပ်ချက်: $totalCost)',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.red[700],
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(dialogCtx, false),
                                      child: const Text(
                                        'မလုပ်တော့ပါ',
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    ),
                                    ElevatedButton(
                                      onPressed: canAfford
                                          ? () => Navigator.pop(dialogCtx, true)
                                          : null,
                                      child: const Text('ကစားမည်'),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        );
                        if (isConfirmed != true) return;
                        if (!mounted) return;

                        // 7. Final safety check before submit
                        int finalTotalCost = 0;
                        for (final idx in selectedList) {
                          finalTotalCost +=
                              perUnit * (amountPerOption[idx] ?? 1);
                        }
                        if (finalTotalCost > userBalance) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'သတ်မှတ်ထားသော Amount အတွက် Point မလောက်တော့ပါ။ ပြန်လည် ကြိုးစားကြည့်ပါ။',
                              ),
                            ),
                          );
                          return;
                        }

                        // 8. Proceed with per-option amounts
                        await _submitWithAmountPerOption(amountPerOption);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.3),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 44),
                  disabledBackgroundColor: Colors.white.withOpacity(0.15),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('ကစားမည်'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CountdownUI extends StatelessWidget {
  final int seconds;
  final String label;

  const _CountdownUI({super.key, required this.seconds, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.orange[400]!, Colors.deepOrange[600]!],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$seconds',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 72,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown while the server resolves the random winner (`winning_index == -1`).
class _CalculatingResultUI extends StatelessWidget {
  const _CalculatingResultUI({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.orange[400]!, Colors.deepOrange[600]!],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 20),
            Text(
              'Calculating Result...',
              style: TextStyle(
                color: Colors.white.withOpacity(0.95),
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact receipt line: `Option A : 2` (omits value segment if null).
String _formatOptionLabel(String rawLabel) {
  final match = RegExp(r'-\s*([^+]+?)\s*\+').firstMatch(rawLabel);
  if (match == null) return rawLabel;
  final extracted = match.group(1)?.trim();
  if (extracted == null || extracted.isEmpty) return rawLabel;
  return extracted;
}

/// Converts a comma-separated answer string (e.g. "0,1") into display labels.
/// Invalid and out-of-range indices are ignored safely.
String? _formatUserChoices(String? rawAnswer, List<String> options) {
  final answer = rawAnswer?.trim();
  if (answer == null || answer.isEmpty) return null;

  final formattedChoices = <String>[];
  for (final part in answer.split(',')) {
    final index = int.tryParse(part.trim());
    if (index == null || index < 0 || index >= options.length) {
      continue;
    }
    final rawOption = options[index].trim();
    if (rawOption.isEmpty) continue;
    formattedChoices.add(_formatOptionLabel(rawOption));
  }

  if (formattedChoices.isEmpty) return null;
  return formattedChoices.join(', ');
}

List<InlineSpan> _winningPollReceiptInlineSpans(
  Map<String, int?> detailedBets,
  Color amountColor, {
  int perUnitPnp = 1000,
  Color? labelColor,
  Color? separatorColor,
}) {
  final sepColor = separatorColor ?? Colors.grey[600]!;
  final label = labelColor ?? Colors.grey[900]!;
  final spans = <InlineSpan>[];
  var i = 0;
  for (final e in detailedBets.entries) {
    if (i > 0) {
      spans.add(
        TextSpan(
          text: ', ',
          style: TextStyle(
            color: sepColor,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.35,
          ),
        ),
      );
    }
    spans.add(
      TextSpan(
        text: _formatOptionLabel(e.key),
        style: TextStyle(
          color: label,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          height: 1.35,
        ),
      ),
    );
    if (e.value != null) {
      final raw = e.value!;
      // Legacy conversion logic intentionally disabled.
      // final safePerUnit = perUnitPnp > 0 ? perUnitPnp : 1000;
      // final normalized =
      //     raw >= 100 ? ((raw ~/ safePerUnit) > 0 ? raw ~/ safePerUnit : 1) : raw;
      spans.add(
        TextSpan(
          text: ' : $raw',
          style: TextStyle(
            color: amountColor,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ),
      );
    }
    i++;
  }
  return spans;
}

/// Displays ONLY the winning option in a compact card matching the voting grid option style.
class WinningResultWidget extends StatefulWidget {
  final WinningOption winningOption;

  /// Selected options with per-option amount (raw from API/cache); null or empty hides receipt.
  final Map<String, int?>? userDetailedBets;
  final int perUnitPnp;

  const WinningResultWidget({
    super.key,
    required this.winningOption,
    this.userDetailedBets,
    this.perUnitPnp = 1000,
  });

  @override
  State<WinningResultWidget> createState() => _WinningResultWidgetState();
}

class _WinningResultWidgetState extends State<WinningResultWidget> {
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    _initMedia();
  }

  void _initMedia() {
    final mt = (widget.winningOption.mediaType ?? '').toLowerCase();
    final url = widget.winningOption.mediaUrl;
    if (url == null || url.isEmpty) return;
    if (mt == 'video') {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(url))
        ..setVolume(0.3)
        ..initialize().then((_) {
          if (mounted) {
            setState(() {});
            _videoController?.play();
            _videoController?.setLooping(true);
          }
        });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final opt = widget.winningOption;
    final mediaUrl = opt.mediaUrl;
    final mediaType = (opt.mediaType ?? '').toLowerCase();

    Widget mediaContent;
    if (mediaUrl != null && mediaUrl.isNotEmpty) {
      if (mediaType == 'video' &&
          _videoController != null &&
          _videoController!.value.isInitialized) {
        mediaContent = AspectRatio(
          aspectRatio: _videoController!.value.aspectRatio,
          child: VideoPlayer(_videoController!),
        );
      } else if (mediaType == 'video') {
        mediaContent = const Center(child: CircularProgressIndicator());
      } else {
        mediaContent = CachedNetworkImage(
          imageUrl: mediaUrl,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          placeholder: (_, __) =>
              const Center(child: CircularProgressIndicator()),
          errorWidget: (_, __, ___) => Center(
            child: Icon(Icons.broken_image, size: 40, color: Colors.grey[400]),
          ),
        );
      }
    } else {
      mediaContent = Center(
        child: Icon(Icons.emoji_events, size: 48, color: Colors.grey[400]),
      );
    }

    const radius = 20.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          mediaContent,
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            top: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      opt.text,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.userDetailedBets != null &&
                        widget.userDetailedBets!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.32),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.receipt_long_rounded,
                                  size: 18,
                                  color: Colors.white.withOpacity(0.95),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Your choice',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.9,
                                    color: Colors.white.withOpacity(0.9),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            RichText(
                              text: TextSpan(
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.35,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                                children: _winningPollReceiptInlineSpans(
                                  widget.userDetailedBets!,
                                  Colors.amber.shade100,
                                  perUnitPnp: widget.perUnitPnp,
                                  labelColor: Colors.white.withOpacity(0.92),
                                  separatorColor: Colors.white.withOpacity(
                                    0.75,
                                  ),
                                ),
                              ),
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Next poll starts in X seconds" countdown with haptic feedback.
class _RestartCountdownUI extends StatelessWidget {
  final int seconds;

  const _RestartCountdownUI({super.key, required this.seconds});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Next Poll Starts In...',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '$seconds',
            style: const TextStyle(
              fontSize: 60,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
        ],
      ),
    );
  }
}
