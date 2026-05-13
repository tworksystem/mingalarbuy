import 'dart:async';
import 'dart:math';

import 'package:ecommerce_int2/providers/auth_provider.dart';
import 'package:ecommerce_int2/providers/point_provider.dart';
import 'package:ecommerce_int2/utils/logger.dart';

/// FIFO queue so overlapping [reconcileAfterPollResult] calls do not stack
/// balance-sync leases, duplicate ledger polls, or redundant refreshes.
Future<void> _reconcileAfterPollResultTail = Future<void>.value();

extension PointProviderPollReconcileExtension on PointProvider {
  /// After poll results settle: shimmer via [beginBalanceSync]/[endBalanceSync], then **backend-only**
  /// balance sync: first a mandatory [loadBalance](forceRefresh), then up to 15× total attempts with
  /// incremental backoff + jitter until the balance differs from the pre-sync local value (or attempts exhaust).
  /// Does **not** apply client-side authoritative totals.
  ///
  /// [authoritativePollBalance] is retained for API compatibility / logging only (ignored for apply).
  ///
  /// When [pollWinPriorBalanceExclusive] is set, runs [refreshPointStateAfterPollWin] with
  /// no authoritative injection so the ledger response remains the source of truth.
  Future<void> reconcileAfterPollResult({
    required String userId,

    /// Ignored for balance apply — backend GET is the only source of truth here.
    int? authoritativePollBalance,
    String balanceSyncDebugTag = 'poll_result_reconcile',
    AuthProvider? authProvider,
    BigInt? snapshotSequence,
    DateTime? snapshotObservedAt,
    String canonicalSource = 'poll_result_reconcile',
    Future<void> Function()? refreshUserCallback,
    bool Function()? shouldContinue,
    int? pollWinPriorBalanceExclusive,
    bool scheduleDeferredRetryOnPollWin = true,
  }) async {
    if (userId.isEmpty) {
      return;
    }

    final Future<void> previous = _reconcileAfterPollResultTail;
    final Completer<void> gate = Completer<void>();
    _reconcileAfterPollResultTail = gate.future;
    await previous.catchError((Object _, StackTrace __) {});

    String? balanceSyncLeaseId;
    try {
      Logger.info(
        'reconcileAfterPollResult:start userId=$userId '
        'authoritativePollBalance=${authoritativePollBalance ?? 'null'} tag=$balanceSyncDebugTag '
        'pollWinPrior=${pollWinPriorBalanceExclusive != null}',
        tag: 'PointProviderPollReconcile',
      );

      balanceSyncLeaseId = beginBalanceSync(balanceSyncDebugTag);

      if (!_guardShouldContinue(
        shouldContinue,
        'reconcileAfterPollResult(start)',
      )) {
        Logger.info(
          'reconcileAfterPollResult:aborted_early userId=$userId reason=shouldContinue',
          tag: 'PointProviderPollReconcile',
        );
        return;
      }

      /*
      Old balance path (removed — backend GET only; no client-side authoritative totals):
      if (authoritativePollBalance == null) { await loadBalance(...); }
      else { CanonicalPointBalanceSync.apply(authoritativePollBalance, ...); }
      */
      final int priorLocalBalance = currentBalance;

      Logger.info(
        'RECONCILE START: Confirming backend balance for user userId=$userId '
        'priorLocal=$priorLocalBalance',
        tag: 'PointProviderPollReconcile',
      );

      await _forceRefreshBalanceFirstAttempt(this, userId, shouldContinue);

      /*
      Old smart polling (fixed 1s delay, 10 attempts):
      const int maxSmartPollAttempts = 10;
      var attempt = 1;
      Logger.info(
        'Smart Polling retry count=$attempt/$maxSmartPollAttempts userId=$userId '
        'priorLocal=$priorLocalBalance authoritativePollBalance=${authoritativePollBalance ?? 'null'} '
        'balanceAfterFirstFetch=$currentBalance',
        tag: 'PointProviderPollReconcile',
      );
      if (currentBalance != priorLocalBalance) {
        Logger.info(
          'Final balance matched from backend: $currentBalance '
          '(changed from prior local $priorLocalBalance) attempt=$attempt/$maxSmartPollAttempts',
          tag: 'PointProviderPollReconcile',
        );
      } else {
        for (attempt = 2; attempt <= maxSmartPollAttempts; attempt++) {
          Logger.info(
            'Smart Polling retry count=$attempt/$maxSmartPollAttempts userId=$userId '
            'priorLocal=$priorLocalBalance authoritativePollBalance=${authoritativePollBalance ?? 'null'}',
            tag: 'PointProviderPollReconcile',
          );
          await Future<void>.delayed(const Duration(seconds: 1));
          if (!_guardShouldContinue(
            shouldContinue,
            'reconcileAfterPollResult(smart_poll_$attempt)',
          )) {
            Logger.info(
              'reconcileAfterPollResult:aborted_during_smart_poll userId=$userId',
              tag: 'PointProviderPollReconcile',
            );
            return;
          }
          await loadBalance(userId, forceRefresh: true, notifyLoading: false);
          final int afterFetch = currentBalance;
          if (afterFetch != priorLocalBalance) {
            Logger.info(
              'Final balance matched from backend: $afterFetch '
              '(changed from prior local $priorLocalBalance) attempt=$attempt/$maxSmartPollAttempts',
              tag: 'PointProviderPollReconcile',
            );
            break;
          }
        }
        if (currentBalance == priorLocalBalance) {
          Logger.info(
            'Smart Polling: balance still equals prior local=$priorLocalBalance after '
            '$maxSmartPollAttempts attempts (currentBalance=$currentBalance)',
            tag: 'PointProviderPollReconcile',
          );
        }
      }
      */

      const int maxSmartPollAttempts = 15;
      final Random jitterRng = Random();
      var attempt = 1;
      Logger.info(
        'Smart Polling retry count=$attempt/$maxSmartPollAttempts userId=$userId '
        'priorLocal=$priorLocalBalance authoritativePollBalance=${authoritativePollBalance ?? 'null'} '
        'balanceAfterFirstFetch=$currentBalance',
        tag: 'PointProviderPollReconcile',
      );
      if (currentBalance != priorLocalBalance) {
        Logger.info(
          'SUCCESS: Backend balance updated to $currentBalance after $attempt attempts.',
          tag: 'PointProviderPollReconcile',
        );
      } else {
        for (attempt = 2; attempt <= maxSmartPollAttempts; attempt++) {
          if (priorLocalBalance != currentBalance) {
            Logger.info(
              'SUCCESS: Backend balance updated to $currentBalance after ${attempt - 1} attempts.',
              tag: 'PointProviderPollReconcile',
            );
            break;
          }
          Logger.info(
            'RECONCILE: Waiting for backend to credit points (Attempt $attempt)...',
            tag: 'PointProviderPollReconcile',
          );
          await Future<void>.delayed(
            _reconcilePollBackoffDuration(attempt, jitterRng),
          );
          if (!_guardShouldContinue(
            shouldContinue,
            'reconcileAfterPollResult(smart_poll_$attempt)',
          )) {
            Logger.info(
              'reconcileAfterPollResult:aborted_during_smart_poll userId=$userId',
              tag: 'PointProviderPollReconcile',
            );
            return;
          }
          await loadBalance(userId, forceRefresh: true, notifyLoading: false);
          final int afterFetch = currentBalance;
          if (priorLocalBalance != afterFetch) {
            Logger.info(
              'SUCCESS: Backend balance updated to $afterFetch after $attempt attempts.',
              tag: 'PointProviderPollReconcile',
            );
            break;
          }
        }
        if (currentBalance == priorLocalBalance) {
          Logger.info(
            'Smart Polling: balance still equals prior local=$priorLocalBalance after '
            '$maxSmartPollAttempts attempts (currentBalance=$currentBalance)',
            tag: 'PointProviderPollReconcile',
          );
        }
      }

      if (!_guardShouldContinue(
        shouldContinue,
        'reconcileAfterPollResult(after_balance)',
      )) {
        Logger.info(
          'reconcileAfterPollResult:aborted_after_balance userId=$userId '
          'reason=shouldContinue',
          tag: 'PointProviderPollReconcile',
        );
        return;
      }

      if (pollWinPriorBalanceExclusive != null) {
        Logger.info(
          'reconcileAfterPollResult:delegating_refreshPointStateAfterPollWin '
          'userId=$userId priorExclusive=$pollWinPriorBalanceExclusive',
          tag: 'PointProviderPollReconcile',
        );
        await refreshPointStateAfterPollWin(
          userId: userId,
          priorBalanceExclusive: pollWinPriorBalanceExclusive,
          authoritativePollBalance: null,
          authProvider: authProvider,
          snapshotSequence: snapshotSequence,
          snapshotObservedAt: snapshotObservedAt,
          canonicalPollWinSource: '${canonicalSource}_finalize',
          refreshUserCallback: refreshUserCallback,
          shouldContinue: shouldContinue,
          scheduleDeferredRetryOnFailure: scheduleDeferredRetryOnPollWin,
        );
      } else {
        final Future<void> Function()? cb = refreshUserCallback;
        if (cb != null) {
          try {
            await cb();
          } catch (e, st) {
            Logger.error(
              'reconcileAfterPollResult refreshUserCallback failed: $e',
              tag: 'PointProvider',
              error: e,
              stackTrace: st,
            );
          }
        }
        Logger.info(
          'reconcileAfterPollResult:loadTransactions FIRST PAGE ONLY '
          'userId=$userId page=1 perPage=20 rangeDays=90 — '
          '(no PointService.getAllPointTransactions pagination from this hook)',
          tag: 'PointProviderPollReconcile',
        );
        await loadTransactions(
          userId,
          page: 1,
          perPage: 20,
          forceRefresh: true,
          rangeDays: 90,
          notifyLoading: false,
        ).catchError((Object e, StackTrace st) {
          Logger.error(
            'reconcileAfterPollResult loadTransactions failed: $e',
            tag: 'PointProvider',
            error: e,
            stackTrace: st,
          );
        });
      }

      Logger.info(
        'reconcileAfterPollResult:success userId=$userId',
        tag: 'PointProviderPollReconcile',
      );
    } catch (e, st) {
      Logger.error(
        'reconcileAfterPollResult failed for userId=$userId — $e',
        tag: 'PointProvider',
        error: e,
        stackTrace: st,
      );
    } finally {
      final String? lease = balanceSyncLeaseId;
      if (lease != null) {
        endBalanceSync(lease);
      }
      if (!gate.isCompleted) {
        gate.complete();
      }
    }
  }
}

/// First [loadBalance](forceRefresh) must complete; retries on thrown errors only (transient network).
Future<void> _forceRefreshBalanceFirstAttempt(
  PointProvider pointProvider,
  String userId,
  bool Function()? shouldContinue,
) async {
  const int innerMax = 3;
  for (var inner = 0; inner < innerMax; inner++) {
    if (!_guardShouldContinue(
      shouldContinue,
      'reconcileAfterPollResult(force_refresh_$inner)',
    )) {
      return;
    }
    try {
      await pointProvider.loadBalance(
        userId,
        forceRefresh: true,
        notifyLoading: false,
      );
      Logger.info(
        'RECONCILE: First forceRefresh loadBalance completed userId=$userId '
        'balance=${pointProvider.currentBalance} innerTry=${inner + 1}/$innerMax',
        tag: 'PointProviderPollReconcile',
      );
      return;
    } catch (e, st) {
      Logger.warning(
        'RECONCILE: First forceRefresh attempt ${inner + 1}/$innerMax failed: $e',
        tag: 'PointProviderPollReconcile',
        error: e,
        stackTrace: st,
      );
      if (inner < innerMax - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      } else {
        rethrow;
      }
    }
  }
}

bool _guardShouldContinue(bool Function()? fn, String scopeLabel) {
  if (fn == null) return true;
  try {
    return fn();
  } catch (e, st) {
    Logger.error(
      '$scopeLabel: shouldContinue threw: $e',
      tag: 'PointProviderPollReconcile',
      error: e,
      stackTrace: st,
    );
    return false;
  }
}

/// Delay before retry attempt [attempt] (2…15): **3–5s** only (server ledger + firewall-safe).
Duration _reconcilePollBackoffDuration(int attempt, Random rng) {
  assert(
    attempt >= 2 && attempt <= 15,
    'backoff only used for smart_poll attempts 2–15',
  );
  const int minMs = 3000;
  const int maxMs = 5000;
  final int span = maxMs - minMs + 1;
  return Duration(milliseconds: minMs + rng.nextInt(span));
}
