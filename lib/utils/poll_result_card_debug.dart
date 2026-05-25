import 'package:flutter/foundation.dart';

/// Console traces for in-feed poll result card visibility (spectators + voters).
class PollResultCardDebug {
  PollResultCardDebug._();

  static const String tag = '🏆 poll_result_card';

  static void ok(String message) => _emit('✅', message);

  static void pending(String message) => _emit('⏳', message);

  static void blocked(String message) => _emit('🚫', message);

  static void fail(String message, {Object? error, StackTrace? stackTrace}) {
    final extra = error != null ? ' | cause: $error' : '';
    _emit('❌', '$message$extra');
    if (stackTrace != null && kDebugMode) {
      debugPrint('$tag 🧵 $stackTrace');
    }
  }

  static void info(String message) => _emit('ℹ️', message);

  static void warn(String message) => _emit('⚠️', message);

  static void gate({
    required int pollId,
    required bool hasInteracted,
    required String votingStatus,
    required bool isResultLikeStatus,
    required bool hasPollResult,
    required bool resultPayloadReady,
    required bool showResultCard,
    required bool forceVotingUi,
    required int secondsUntilClose,
    String? reason,
  }) {
    final emoji = showResultCard
        ? '✅'
        : (forceVotingUi ? '🚫' : (isResultLikeStatus ? '⏳' : 'ℹ️'));
    final detail = reason ?? _defaultReason(
      isResultLikeStatus: isResultLikeStatus,
      hasPollResult: hasPollResult,
      resultPayloadReady: resultPayloadReady,
      showResultCard: showResultCard,
      forceVotingUi: forceVotingUi,
      hasInteracted: hasInteracted,
    );
    _emit(
      emoji,
      'pollId=$pollId status=$votingStatus interacted=$hasInteracted '
      'sec=$secondsUntilClose result=$hasPollResult ready=$resultPayloadReady '
      'card=$showResultCard votingUi=$forceVotingUi — $detail',
    );
  }

  static String _defaultReason({
    required bool isResultLikeStatus,
    required bool hasPollResult,
    required bool resultPayloadReady,
    required bool showResultCard,
    required bool forceVotingUi,
    required bool hasInteracted,
  }) {
    if (showResultCard) return 'showing result card';
    if (forceVotingUi && isResultLikeStatus && !hasInteracted) {
      return 'BUG guard: non-voter forced to voting UI during result phase (fixed if you see this after update)';
    }
    if (forceVotingUi) return 'voting UI preferred over result card';
    if (!isResultLikeStatus) return 'not in result phase yet';
    if (!hasPollResult) return 'awaiting poll_result on feed';
    if (!resultPayloadReady) {
      return 'poll_result missing winning_index / vote_counts / total_votes';
    }
    return 'result card hidden (check engagementItemShouldShowPollVotingUi)';
  }

  static void _emit(String emoji, String message) {
    final line = '$emoji $tag $message';
    print(line);
    debugPrint(line);
  }
}
