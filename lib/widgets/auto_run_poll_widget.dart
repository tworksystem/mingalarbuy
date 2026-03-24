/// Smart Poll Widget for AUTO_RUN lifecycle.
///
/// State flow:
/// 1. ACTIVE - User votes
/// 2. CLOSING_COUNTDOWN - 10 sec before poll closes
/// 3. SHOWING_RESULTS - Winning text + media only (no vote counts)
/// 4. RESTART_COUNTDOWN - 5 sec "Next poll starts in X" before next poll
/// 5. RESET - Fetch new session → ACTIVE

import 'dart:async';
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
import '../services/point_notification_manager.dart';
import '../utils/app_config.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

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
  showingResult,
  restartCountdown,
}

/// API response for poll state
class PollStateData {
  final String state;
  final String currentSessionId;
  final String? endsAt;
  final int pollDuration;
  final int resultDisplayDuration;
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
    required this.pollDuration,
    required this.resultDisplayDuration,
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
      pollDuration: (data['poll_duration'] as num?)?.toInt() ?? 15,
      resultDisplayDuration:
          (data['result_display_duration'] as num?)?.toInt() ?? 1,
      mode: (data['mode'] ?? 'MANUAL').toString(),
      pollBaseCost: (data['poll_base_cost'] as num?)?.toInt() ?? 0,
      betAmountStep: (data['bet_amount_step'] as num?)?.toInt(),
      rewardMultiplier: (data['reward_multiplier'] as num?)?.toDouble() ?? 4,
      requireConfirmation: data['require_confirmation'] == true ||
          data['require_confirmation'] == 1 ||
          data['require_confirmation'] == '1',
      allowUserAmount: data['allow_user_amount'] == null ||
          data['allow_user_amount'] == true ||
          data['allow_user_amount'] == 1 ||
          data['allow_user_amount'] == '1',
    );
  }
}

/// Winning option from poll results (minimalist media-focused, no vote counts)
class WinningOption {
  final String text;
  final String? mediaUrl;
  final String? mediaType;

  WinningOption({
    required this.text,
    this.mediaUrl,
    this.mediaType,
  });

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
  final bool userWon;
  final int pointsEarned;
  final int currentBalance;

  PollResultData({
    required this.sessionId,
    required this.winningOption,
    this.userWon = false,
    this.pointsEarned = 0,
    this.currentBalance = 0,
  });

  factory PollResultData.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? json;
    final winning = data['winning_option'];
    final winningMap = winning is Map
        ? Map<String, dynamic>.from(winning)
        : null;
    return PollResultData(
      sessionId: (data['session_id'] ?? '').toString(),
      winningOption: WinningOption.fromJson(winningMap),
      userWon: data['user_won'] == true || data['user_won'] == 1,
      pointsEarned: (data['points_earned'] as num?)?.toInt() ?? 0,
      currentBalance: (data['current_balance'] as num?)?.toInt() ?? 0,
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

class _AutoRunPollWidgetState extends State<AutoRunPollWidget> {
  AutoPollState _state = AutoPollState.loading;
  PollStateData? _stateData;
  PollResultData? _resultData;
  /// Guards against external refresh/rebuild killing the result or restart countdown.
  bool _isLifecycleRunning = false;
  DateTime? _phaseEndsAtUtc;
  int _countdownSeconds = 0;
  /// Session id for which we've already fetched results — prevents re-fetch and flicker.
  String? _resultFetchedForSession;

  @override
  void initState() {
    super.initState();
    _fetchPollState().then((state) {
      if (!mounted || state == null) return;
      _isLifecycleRunning = true;
      if (state == 'ACTIVE') {
        _runVotingPhase();
      } else if (state == 'SHOWING_RESULTS') {
        _runResultAndCountdownPhase();
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
        _state == AutoPollState.restartCountdown) {
      // Intentionally block any state reset or reload here.
      // This prevents EngagementProvider auto-refresh from
      // killing the 5-second "Next poll" countdown.
      // Use print to make sure this is visible in release logs too.
      // (Can be swapped to debugPrint if preferred.)
      // ignore: avoid_print
      print(
        '--- BLOCKING EXTERNAL REFRESH. Currently in phase: $_state ---',
      );
      return;
    }

    // Outside of result/countdown phases, we currently do not
    // need to react to widget prop changes here.
  }

  @override
  void dispose() {
    _isLifecycleRunning = false;
    super.dispose();
  }

  void _transitionTo(AutoPollState newState, {int? countdown}) {
    if (!mounted) return;
    setState(() {
      _state = newState;
      if (countdown != null) _countdownSeconds = countdown;
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
      _runResultAndCountdownPhase();
    } else if (nextState == 'ACTIVE') {
      _runVotingPhase();
    } else {
      _isLifecycleRunning = false;
    }
  }

  /// Result display then strict 5-second "Next poll" countdown. Uses only Future.delayed.
  Future<void> _runResultAndCountdownPhase() async {
    final resultDisplayDuration =
        _stateData?.resultDisplayDuration ?? 60;
    final resultWaitTime = (resultDisplayDuration - 5).clamp(0, 999);

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
    _transitionTo(AutoPollState.loading);

    // Countdown finished: resume global engagement auto-polling
    // and trigger an immediate feed refresh for the next poll.
    try {
      await context.read<EngagementProvider>().resumeAndFetchFeed();
    } catch (_) {
      // If provider is not available, just stop lifecycle gracefully.
    }

    // PROFESSIONAL FIX: Loop to next cycle — Auto Poll runs continuously.
    // Without this, the widget would stay in loading and never restart.
    _resultFetchedForSession = null; // Allow next session's results to be fetched
    final nextState = await _fetchPollState(internalCall: true);
    if (!mounted) return;
    if (nextState == 'ACTIVE') {
      _isLifecycleRunning = true;
      _runVotingPhase();
    } else if (nextState == 'SHOWING_RESULTS') {
      _isLifecycleRunning = true;
      _runResultAndCountdownPhase();
    } else {
      _isLifecycleRunning = false;
    }
  }

  /// Fetch poll state. When [internalCall] is false, no-op if lifecycle is running (ignore external refresh).
  Future<String?> _fetchPollState({bool internalCall = false}) async {
    if (!internalCall && _isLifecycleRunning) return null;
    if (!mounted) return null;
    setState(() => _state = AutoPollState.loading);

    try {
      final uri = Uri.parse(
        '${AppConfig.backendUrl}/wp-json/twork/v1/poll/state/${widget.pollId}',
      ).replace(queryParameters: {
        'consumer_key': AppConfig.consumerKey,
        'consumer_secret': AppConfig.consumerSecret,
      });

      final response = await http
          .get(uri, headers: const {'Content-Type': 'application/json'});

      if (response.statusCode != 200) {
        if (mounted) setState(() => _state = AutoPollState.activeVoting);
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['success'] != true) {
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
        _resultData ??= PollResultData(
          sessionId: data.currentSessionId,
          winningOption: WinningOption(text: ''),
        );
        _fetchResultsAndShow();
        _phaseEndsAtUtc = null;
        _transitionTo(AutoPollState.showingResult);
        // Pause global engagement auto-polling so the feed
        // does NOT replace this poll while we show result/countdown.
        try {
          context.read<EngagementProvider>().pauseAutoPoll();
        } catch (_) {
          // Provider not found – fail silently; core poll logic still works.
        }
        return 'SHOWING_RESULTS';
      } else if (data.state == 'ACTIVE') {
        final nowUtc = DateTime.now().toUtc();
        if (parsedEndsAt != null) {
          _phaseEndsAtUtc = parsedEndsAt.toUtc();
        } else {
          final pollSeconds =
              data.pollDuration > 0 ? data.pollDuration : 15;
          _phaseEndsAtUtc = nowUtc.add(Duration(seconds: pollSeconds));
        }
        _transitionTo(AutoPollState.activeVoting);
        return 'ACTIVE';
      } else {
        final nowUtc = DateTime.now().toUtc();
        if (parsedEndsAt != null) {
          _phaseEndsAtUtc = parsedEndsAt.toUtc();
        } else {
          final pollSeconds =
              data.pollDuration > 0 ? data.pollDuration : 15;
          _phaseEndsAtUtc = nowUtc.add(Duration(seconds: pollSeconds));
        }
        _transitionTo(AutoPollState.activeVoting);
        return 'ACTIVE';
      }
    } catch (e) {
      if (mounted) setState(() => _state = AutoPollState.activeVoting);
      return null;
    }
  }

  Future<void> _fetchResultsAndShow() async {
    final sessionId = _stateData?.currentSessionId ?? '';
    if (sessionId.isEmpty) return;

    // Single fetch per session: avoid multiple API calls causing result to change.
    if (_resultFetchedForSession == sessionId) return;
    _resultFetchedForSession = sessionId;

    try {
      final queryParams = <String, String>{
        'consumer_key': AppConfig.consumerKey,
        'consumer_secret': AppConfig.consumerSecret,
        if (widget.userId > 0) 'user_id': widget.userId.toString(),
      };
      final uri = Uri.parse(
        '${AppConfig.backendUrl}/wp-json/twork/v1/poll/results/${widget.pollId}/$sessionId',
      ).replace(queryParameters: queryParams);

      final response = await http
          .get(uri, headers: const {'Content-Type': 'application/json'});

      if (response.statusCode == 200 && mounted) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        if (json['success'] == true) {
          final result = PollResultData.fromJson(json);
          if (!mounted) return;
          // Update once — do not overwrite if we already have valid data for this session.
          setState(() => _resultData = result);
          if (result.userWon && result.pointsEarned > 0) {
            _handlePollWinPopupAndSync(result);
          }
        }
      }
    } catch (_) {}
    // Placeholder already set in _fetchPollState; avoid extra setState to prevent flicker.
  }

  /// When user wins: show point popup immediately (same time as result) + sync balance in background.
  Future<void> _handlePollWinPopupAndSync(PollResultData result) async {
    if (!mounted) return;
    try {
      // ============================================================================
      // CRITICAL: Winner points already credited in wp_twork_point_transactions (backend)
      // SAME TABLE used for deduction when user played
      // Balance = SUM(type='earn') - SUM(type='redeem') from wp_twork_point_transactions
      // ============================================================================
      
      // PROFESSIONAL FIX: Always ensure balance reflects the win.
      // API current_balance can be stale. Use max(API, prev + earned) so we never
      // show less than what user just won in popup and My PNP card.
      final fromPointProvider = PointProvider.instance.currentBalance;
      final fromAuth = AuthProvider().userPointsBalance;
      final prev = fromPointProvider > fromAuth ? fromPointProvider : fromAuth;
      final localWithEarned = prev + result.pointsEarned;
      final effectiveBalance = (result.currentBalance > 0 &&
              result.currentBalance >= localWithEarned)
          ? result.currentBalance
          : localWithEarned;

      debugPrint(
        '[AutoRunPoll] ✓ WINNER REWARD SYNC — Poll: ${widget.pollId}, Session: ${result.sessionId}, '
        'Earned: +${result.pointsEarned}, Balance: $prev → $effectiveBalance (API: ${result.currentBalance})',
      );

      // Winner points are already credited by /poll/results backend flow.
      // Do NOT call points/earn here (it creates duplicate/dedup races and can
      // prevent UI update when backend returns "duplicate").
      AuthProvider().applyPointsBalanceSnapshot(effectiveBalance);
      PointProvider.instance.applyRemoteBalanceSnapshot(
        userId: widget.userId.toString(),
        currentBalance: effectiveBalance,
      );

      // 3. In-app notification only (no blocking winner modal)
      final eventId =
          'poll_${widget.pollId}_${result.sessionId}_${DateTime.now().millisecondsSinceEpoch}';
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
      widget.onPointsEarned?.call();

      // 3. Defer server reconcile — immediate loadBalance/refreshUser races the DB and
      // often overwrites the poll snapshot with stale balance (popup shows, points "vanish").
      unawaited(
        Future<void>.delayed(const Duration(seconds: 4)).then((_) async {
          try {
            await PointProvider.instance.loadBalance(
              widget.userId.toString(),
              forceRefresh: true,
            );
          } catch (e) {
            debugPrint('[AutoRunPoll] deferred loadBalance: $e');
          }
        }),
      );
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
        widget.onVoteSubmitted?.call();
        final points = result['points_earned'] as int? ?? 0;
        if (points > 0) widget.onPointsEarned?.call();
      } else if (mounted) {
        final code = result['code']?.toString().toLowerCase();
        final message =
            result['message']?.toString() ?? 'Failed to submit vote';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor:
                (code == 'insufficient_balance' || code == 'insufficient_funds')
                    ? Colors.red
                    : Colors.orange,
          ),
        );
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
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: _buildChild(),
    );
  }

  /// Per-checkbox PNP matching server (Base Cost vs User Amount + step).
  int _perUnitPnpForState(PollStateData? sd) {
    if (sd == null) return 1000;
    if (!sd.allowUserAmount) {
      final b = sd.pollBaseCost;
      return b > 0 ? b : 1000;
    }
    final step = sd.betAmountStep;
    if (step != null && step > 0) return step;
    final b = sd.pollBaseCost;
    if (b <= 0) return 1000;
    // Back-compat: if server didn't provide bet_amount_step, poll_base_cost may be stored as unit number.
    // Example: poll_base_cost=1..5 => step=1000..5000 PNP.
    if (b < 1000) return b * 1000;
    return b;
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
      case AutoPollState.showingResult:
        return WinningResultWidget(
          key: ValueKey('result_${_stateData?.currentSessionId ?? ""}'),
          winningOption: _resultData?.winningOption ?? WinningOption(text: ''),
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
  }) onSubmitVote;
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
    if (_selectedIndices.isEmpty || _isSubmitting || amountPerOption.isEmpty) return;
    try {
      final baseSelected = _selectedIndices.toList()..sort();
      final answerStr = baseSelected.join(',');

      if (!mounted) return;
      setState(() => _isSubmitting = true);
      await widget.onSubmitVote(
        answerStr,
        selectedOptionIds: baseSelected,
        betAmountPerOption: amountPerOption,
      );
    } catch (e, stacktrace) {
      debugPrint('Submit error: $e\n$stacktrace');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('+${widget.rewardPoints} PTS',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
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
          if (widget.hasInteracted && widget.userAnswer != null)
            Text(
              'Your choice: ${widget.userAnswer}',
              style:
                  TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14),
            )
          else ...[
            ...widget.options.asMap().entries.map((e) => Padding(
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
                          horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(
                            _selectedIndices.contains(e.key) ? 0.35 : 0.2),
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
                                (_) => Colors.white.withOpacity(0.5)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(_optionText(e.value),
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 15))),
                        ],
                      ),
                    ),
                  ),
                )),
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
                                  'ကျေးဇူးပြု၍ အနည်းဆုံး တစ်ခု ရွေးချယ်ပါ။'),
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

                        // 3b. Combine API balance with AuthProvider custom fields (my_point / points_balance)
                        final authProvider =
                            context.read<AuthProvider>();
                        int customBalance = 0;
                        final user = authProvider.user;
                        if (user != null) {
                          final myPointValue = user.customFields['my_point'] ??
                              user.customFields['my_points'] ??
                              user.customFields['My Point Value'] ??
                              user.customFields['points_balance'];
                          if (myPointValue != null &&
                              myPointValue.trim().isNotEmpty) {
                            final parsed =
                                int.tryParse(myPointValue.trim()) ??
                                    int.tryParse(RegExp(r'\d+')
                                            .firstMatch(myPointValue)
                                            ?.group(0) ??
                                        '');
                            if (parsed != null) {
                              customBalance = parsed;
                            }
                          }
                        }

                        final apiBalance = pointProvider.currentBalance;
                        final int userBalance = customBalance > apiBalance
                            ? customBalance
                            : apiBalance;

                        // 4. Calculate cost for Amount multiplier k = 1
                        final int requiredPerAmount = perUnit * selectedCount;
                        if (requiredPerAmount <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content:
                                  Text('Poll cost မမှန်ကန်သဖြင့် ကစား၍မရပါ။'),
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
                          for (final i in selectedList) i: 1
                        };
                        final options = widget.options;

                        await showDialog<void>(
                          context: context,
                          barrierDismissible: false,
                          builder: (ctx) {
                            return StatefulBuilder(
                              builder: (dialogCtx, setDialogState) {
                                int totalCost = 0;
                                for (final idx in selectedList) {
                                  totalCost += perUnit *
                                      (amountPerOption[idx] ?? 1);
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
                                          final amt =
                                              amountPerOption[idx] ?? 1;
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
                                                      onPressed: amt < maxForThis
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
                                                      color: Colors
                                                          .grey[600]),
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
                                            padding: const EdgeInsets.only(
                                                top: 6),
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
                                      onPressed: () =>
                                          Navigator.pop(dialogCtx),
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

                        // If dialog was closed without selecting (e.g. back), do nothing.
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
                                  'သတ်မှတ်ထားသော Amount အတွက် Point မလောက်တော့ပါ။ ပြန်လည် ကြိုးစားကြည့်ပါ။'),
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
                            color: Colors.white, strokeWidth: 2))
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
              style:
                  TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays ONLY the winning option in a compact card matching the voting grid option style.
class WinningResultWidget extends StatefulWidget {
  final WinningOption winningOption;

  const WinningResultWidget({super.key, required this.winningOption});

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
          placeholder: (_, __) => const Center(
            child: CircularProgressIndicator(),
          ),
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

    const radius = 20.0; // Match Engagement Hub card
    return Center(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Same as Engagement Hub: availableWidth = width - 40 (16+16+4+4 padding)
          final availableWidth = constraints.maxWidth - 40;
          final cardHeight = availableWidth * 1.15; // Hub card aspect ratio
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 20.0), // 20 each side = 40 total
            width: double.infinity,
            child: Card(
              elevation: 2,
              shadowColor: Colors.black26,
              color: Theme.of(context).cardColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(radius),
              ),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: double.infinity,
                height: cardHeight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(radius),
                        ),
                        child: mediaContent,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Text(
                        opt.text,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
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
