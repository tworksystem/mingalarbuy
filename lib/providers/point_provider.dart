import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../models/point_transaction.dart';
import '../services/point_service.dart';
import '../services/point_notification_manager.dart';
import '../utils/logger.dart';
import '../services/connectivity_service.dart';
import '../services/point_balance_sync_lock.dart';
import '../services/point_sync_telemetry.dart';
import '../services/canonical_point_balance_sync.dart';
import '../services/toast_service.dart';
import 'auth_provider.dart';

/// Point provider for managing point state
/// Handles point balance, transactions, and UI updates
/// Uses singleton pattern to ensure same instance across the app
class PointProvider with ChangeNotifier, WidgetsBindingObserver {
  // Singleton instance
  static PointProvider? _instance;
  static PointProvider get instance {
    _instance ??= PointProvider._internal();
    return _instance!;
  }

  PointProvider._internal() {
    WidgetsBinding.instance.addObserver(this);
    _initialize();
    _syncSubscription = PointSyncTelemetry.events.listen(_handleSyncEvent);
    // Context-free earn/cache updates still reach Home My PNP.
    _pointBroadcastSubscription = PointService.pointSyncBroadcast.listen(
      _onPointSyncBroadcast,
    );
  }

  /// Applies balance from [PointService.pointSyncBroadcast] (e.g. poll win emit).
  /// [applyOptimisticBalanceUpdate] ends with [notifyListeners] so Home My PNP
  /// (Consumer2) rebuilds without a separate StreamBuilder.
  void _onPointSyncBroadcast(PointSyncBroadcast event) {
    final authId = AuthProvider().user?.id.toString().trim();
    final rawEventId = event.userId.trim();

    Logger.info(
      'DEBUG_SYNC: _onPointSyncBroadcast received userId=$rawEventId '
      'newBalance=${event.newBalance} source=${event.source} '
      '_currentUserId=$_currentUserId authId=$authId',
      tag: 'PointProvider',
    );

    /*
    Old Code:
    if (event.userId.isEmpty) return;
    if (_currentUserId != null && _currentUserId != event.userId) return;
    applyOptimisticBalanceUpdate(userId: event.userId, ...);
    */

    // Active session id from AuthProvider is authoritative when broadcast / PointProvider drift.
    final String effectiveUserId;
    if (authId != null && authId.isNotEmpty) {
      effectiveUserId = authId;
    } else if (rawEventId.isNotEmpty) {
      effectiveUserId = rawEventId;
    } else {
      Logger.info(
        'DEBUG_SYNC: _onPointSyncBroadcast skipped (no auth or event user id)',
        tag: 'PointProvider',
      );
      return;
    }

    if (rawEventId.isNotEmpty && rawEventId != effectiveUserId) {
      Logger.info(
        'DEBUG_SYNC: _onPointSyncBroadcast skipped '
        '(event user=$rawEventId session=$effectiveUserId)',
        tag: 'PointProvider',
      );
      return;
    }

    if (_currentUserId != null && _currentUserId != effectiveUserId) {
      if (authId != null && authId.isNotEmpty && authId == effectiveUserId) {
        Logger.info(
          'DEBUG_SYNC: _onPointSyncBroadcast applying with auth-aligned userId '
          '(stale _currentUserId=$_currentUserId → $effectiveUserId)',
          tag: 'PointProvider',
        );
      } else {
        Logger.info(
          'DEBUG_SYNC: _onPointSyncBroadcast skipped (provider mismatch '
          'current=$_currentUserId effective=$effectiveUserId)',
          tag: 'PointProvider',
        );
        return;
      }
    }

    // Serialize with canonical / loadBalance so optimistic broadcast does not
    // interleave oddly with FIFO balance work (same global queue as mutations).
    unawaited(
      PointBalanceSyncLock.run(() async {
        applyOptimisticBalanceUpdate(
          userId: effectiveUserId,
          currentBalance: event.newBalance,
        );
      }),
    );
  }

  // Factory constructor for Provider compatibility
  factory PointProvider() => instance;

  PointBalance? _balance;

  /// Bumped on every [_commitBalance] so Home My PNP [Selector] rebuilds even when
  /// API returns the same headline total as in-memory (optimistic/poll-win race).
  int _balanceIdentityEpoch = 0;

  List<PointTransaction> _transactions = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _errorMessage;
  StreamSubscription<PointSyncEvent>? _syncSubscription;
  StreamSubscription<PointSyncBroadcast>? _pointBroadcastSubscription;
  String? _currentUserId;
  bool _hasLoadedForCurrentUser = false;
  final Set<String> _optimisticRefs = {};
  final Map<String, _OptimisticBalanceSnapshot> _optimisticSnapshots = {};
  String? _syncNoticeMessage;

  // OPTIMIZED: Cache ConnectivityService instance to avoid repeated creation
  late final ConnectivityService _connectivityService = ConnectivityService();

  // OPTIMIZED: Debounce timer to prevent excessive notifyListeners calls
  Timer? _debounceTimer;
  static const Duration _debounceDelay = Duration(milliseconds: 300);

  // Track last transaction list hash to prevent unnecessary updates
  int? _lastTransactionsHash;

  // Track when a push notification applied a balance snapshot.
  // Used by UI to avoid showing duplicate "balance change" modals.
  DateTime? _lastPushBalanceSnapshotAt;

  /*
  Old Code: blocked loadBalance from applying a lower API balance for 35s after snapshot.
  DateTime? _balanceNonDowngradeUntil;
  */

  /// Active My PNP balance-sync / shimmer leases (paired with [beginBalanceSync]/[endBalanceSync]).
  final Map<String, bool> _activeSyncLeases = {};

  /// Auto-expires a lease when [endBalanceSync]/`setSyncingBalance(false)` never arrives.
  final Map<String, Timer> _balanceSyncLeaseWatchdogs = {};

  static const Duration _balanceSyncLeaseSafety = Duration(seconds: 30);

  /// Last accepted optional server ordering hints for remote snapshots (FCM/poll payloads).
  BigInt? _lastAcceptedRemoteSnapshotSequence;
  DateTime? _lastAcceptedRemoteSnapshotObservedAt;

  /// Monotonic suffix so every lease id is unique (avoids double-[begin] collisions).
  int _balanceSyncLeaseSeq = 0;

  /// Refcount for any in-flight balance-sync UI (leases + legacy [setSyncingBalance] pairs).
  int _syncActiveCount = 0;

  /// Stack of synthetic lease ids created by [setSyncingBalance](true) for strict LIFO pairing.
  final List<String> _legacyBoolLeaseStack = [];

  /// After the first 3 poll-win ledger polls fail to exceed the floor, My PNP shows a stricter label.
  bool _extendedPollWinSyncLabel = false;

  /// Incremented while poll vote / win / deduct **ledger verification** holds
  /// [PointBalanceSyncLock] (entire smart-poll loop, including delays).
  ///
  /// [PointBalanceSyncLock.run] is **reentrant**: nested callers (e.g. pull-to-refresh
  /// [loadBalance]) would otherwise invoke [_loadBalanceUnlocked] without
  /// [acceptOnlyBalanceEquals] / [rejectFetchedBalanceIfGreaterThan] / [pollWinStaleFloorExclusive]
  /// and could apply a stale GET, breaking verification. When this depth is > 0,
  /// unscoped fetches are skipped (see [_loadBalanceUnlocked]).
  int _strictSerializedBalancePollDepth = 0;

  /// Clears [_extendedPollWinSyncLabel] after verification loops (success, timeout, cancel, or throw).
  void _clearExtendedPollWinSyncLabelIfNeeded() {
    if (!_extendedPollWinSyncLabel) {
      return;
    }
    _extendedPollWinSyncLabel = false;
    notifyListeners();
  }

  /// Returns false if [fn] is non-null and throws or returns false (treat as stop polling).
  bool _pollVerificationShouldProceed(bool Function()? fn, String scope) {
    if (fn == null) {
      return true;
    }
    try {
      return fn();
    } catch (e, st) {
      Logger.error(
        '$scope: shouldContinue threw: $e',
        tag: 'PointProvider',
        error: e,
        stackTrace: st,
      );
      return false;
    }
  }

  /// True after the first successful balance hydrate for this session (API or cache).
  /// Used so UI does not treat "0 → server balance" on cold start as points earned.
  bool _sessionInitialBalanceLoadComplete = false;

  // Getters
  PointBalance? get balance => _balance;
  List<PointTransaction> get transactions => List.unmodifiable(_transactions);
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  String? get errorMessage => _errorMessage;
  int _currentTransactionsPage = 1;
  int _transactionsPerPage = 20;
  int _totalTransactionPages = 1;
  int get currentTransactionsPage => _currentTransactionsPage;
  int get totalTransactionPages => _totalTransactionPages;
  bool get hasMoreTransactions =>
      _currentTransactionsPage < _totalTransactionPages;
  int get currentBalance => _balance?.currentBalance ?? 0;

  /// Identity generation for balance rows — paired with [_commitBalance].
  int get balanceIdentityEpoch => _balanceIdentityEpoch;

  /// Assigns [_balance] and advances [balanceIdentityEpoch]. When the new snapshot
  /// matches the previous headline total, briefly assigns an impossible sentinel
  /// (`currentBalance == -1`) then the real value so equality-based selectors can
  /// still observe a transition when paired with [notifyListeners].
  void _commitBalance(PointBalance? next) {
    if (next != null &&
        _balance != null &&
        _balance!.currentBalance == next.currentBalance) {
      final hold = _balance!;
      _balance = PointBalance(
        userId: hold.userId,
        currentBalance: -1,
        lifetimeEarned: hold.lifetimeEarned,
        lifetimeRedeemed: hold.lifetimeRedeemed,
        lifetimeExpired: hold.lifetimeExpired,
        lastUpdated: hold.lastUpdated,
        pointsExpireAt: hold.pointsExpireAt,
      );
    }
    _balance = next;
    _balanceIdentityEpoch++;
  }

  /// Allows external modules (e.g. engagement carousel after poll `loadBalance`) to trigger the
  /// same rebuild signal as internal balance updates — [notifyListeners] is `@protected`.
  void pingBalanceUiListeners() => notifyListeners();

  bool get hasPoints => currentBalance > 0;
  String get formattedBalance => _balance?.formattedBalance ?? '0 points';
  DateTime? get lastPushBalanceSnapshotAt => _lastPushBalanceSnapshotAt;
  String? get syncNoticeMessage => _syncNoticeMessage;
  bool get isSyncingBalance => _syncActiveCount > 0;

  /// Shimmer caption during [isSyncingBalance]: stricter copy after 3 failed ledger polls.
  String get balanceSyncLoadingSubtitle =>
      _extendedPollWinSyncLabel ? 'Synchronizing Points...' : 'Updating...';

  bool get balanceSyncUsesExtendedPollWinUi => _extendedPollWinSyncLabel;

  void _scheduleBalanceSyncLeaseWatchdog(String leaseId) {
    _balanceSyncLeaseWatchdogs.remove(leaseId)?.cancel();
    _balanceSyncLeaseWatchdogs[leaseId] = Timer(_balanceSyncLeaseSafety, () {
      _expireBalanceSyncLease(
        leaseId,
        reason: 'watchdog ${_balanceSyncLeaseSafety.inSeconds}s',
      );
    });
  }

  /// If [leaseId] is missing or watchdog already tore it down, no-op except timer cleanup.
  void _expireBalanceSyncLease(String leaseId, {required String reason}) {
    final timer = _balanceSyncLeaseWatchdogs.remove(leaseId);
    timer?.cancel();
    if (!_activeSyncLeases.containsKey(leaseId)) {
      return;
    }
    Logger.warning(
      'Balance-sync lease expired ($reason): leaseId=$leaseId '
      '(was count=$_syncActiveCount)',
      tag: 'PointProvider',
    );
    _activeSyncLeases.remove(leaseId);
    _legacyBoolLeaseStack.remove(leaseId);
    _syncActiveCount = (_syncActiveCount - 1).clamp(0, 0x7fffffff);
    if (_syncActiveCount == 0) {
      _extendedPollWinSyncLabel = false;
    }
    notifyListeners();
  }

  /// Starts a balance-sync UI session (My PNP shimmer). Pair with [endBalanceSync] in `finally`.
  /// Prefer this over [setSyncingBalance] for multi-tenant parallel flows (poll + vote, etc.).
  String beginBalanceSync([String? debugTag]) {
    final id = '${debugTag ?? 'sync'}__${_balanceSyncLeaseSeq++}';
    _activeSyncLeases[id] = true;
    _syncActiveCount++;
    _scheduleBalanceSyncLeaseWatchdog(id);
    notifyListeners();
    return id;
  }

  /// Ends a session started by [beginBalanceSync]. Unknown or duplicate [leaseId] is a no-op.
  void endBalanceSync(String leaseId) {
    _balanceSyncLeaseWatchdogs.remove(leaseId)?.cancel();
    if (!_activeSyncLeases.containsKey(leaseId)) {
      Logger.warning(
        'endBalanceSync: unknown or duplicate leaseId=$leaseId '
        '(active=${_activeSyncLeases.length}, count=$_syncActiveCount)',
        tag: 'PointProvider',
      );
      return;
    }
    _activeSyncLeases.remove(leaseId);
    _syncActiveCount = (_syncActiveCount - 1).clamp(0, 0x7fffffff);
    if (_syncActiveCount == 0) {
      _extendedPollWinSyncLabel = false;
    }
    notifyListeners();
  }

  /// Legacy paired shimmer toggle. Prefer [beginBalanceSync]/[endBalanceSync] at call sites.
  /// Each `true` pushes a lease; each `false` pops one — unmatched `false` is ignored (guard).
  void setSyncingBalance(bool value) {
    if (value) {
      final id = '__legacy__${_balanceSyncLeaseSeq++}';
      _activeSyncLeases[id] = true;
      _legacyBoolLeaseStack.add(id);
      _syncActiveCount++;
      _scheduleBalanceSyncLeaseWatchdog(id);
      notifyListeners();
      return;
    }
    if (_legacyBoolLeaseStack.isEmpty) {
      Logger.warning(
        'setSyncingBalance(false) unmatched — ignored '
        '(count=$_syncActiveCount, leases=${_activeSyncLeases.length})',
        tag: 'PointProvider',
      );
      return;
    }
    final id = _legacyBoolLeaseStack.removeLast();
    _balanceSyncLeaseWatchdogs.remove(id)?.cancel();
    _activeSyncLeases.remove(id);
    _syncActiveCount = (_syncActiveCount - 1).clamp(0, 0x7fffffff);
    if (_syncActiveCount == 0) {
      _extendedPollWinSyncLabel = false;
    }
    notifyListeners();
  }

  void _resetBalanceSyncUiState() {
    for (final t in _balanceSyncLeaseWatchdogs.values) {
      t.cancel();
    }
    _balanceSyncLeaseWatchdogs.clear();
    _activeSyncLeases.clear();
    _legacyBoolLeaseStack.clear();
    _syncActiveCount = 0;
    _extendedPollWinSyncLabel = false;
    _strictSerializedBalancePollDepth = 0;
  }

  /// After Doze / deep sleep, Dart timers may fire very late; balance-sync shimmer can
  /// remain stuck. On [AppLifecycleState.resumed], tear down orphaned leases/watchdogs.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }
    if (_syncActiveCount == 0 &&
        _balanceSyncLeaseWatchdogs.isEmpty &&
        _activeSyncLeases.isEmpty) {
      return;
    }
    Logger.info(
      'AppLifecycle resumed: resetting balance-sync leases & watchdogs '
      '(deep sleep / doze recovery; was count=$_syncActiveCount)',
      tag: 'PointProvider',
    );
    _resetBalanceSyncUiState();
    notifyListeners();
  }

  /// Whether the first balance sync for this login session has finished (server or cache).
  bool get hasCompletedSessionInitialBalanceLoad =>
      _sessionInitialBalanceLoadComplete;

  /// Initialize point provider
  Future<void> _initialize() async {
    _setLoading(true);
    try {
      // No user yet; cached balance is loaded on-demand per userId
      _setLoading(false);
    } catch (e) {
      Logger.error(
        'Error initializing point provider: $e',
        tag: 'PointProvider',
        error: e,
      );
      _setLoading(false);
    }
  }

  /// Handle authentication state changes
  /// Automatically loads balance when user becomes authenticated
  /// PROFESSIONAL FIX: Properly handles user account switching by clearing cache
  Future<void> handleAuthStateChange({
    required bool isAuthenticated,
    String? userId,
  }) async {
    if (isAuthenticated && userId != null) {
      // PROFESSIONAL FIX: If user changed, immediately clear old data and reset flags
      if (_currentUserId != null && _currentUserId != userId) {
        Logger.info(
          'User account changed from $_currentUserId to $userId, clearing point cache',
          tag: 'PointProvider',
        );
        // Clear old user's data immediately
        _commitBalance(null);
        _transactions = [];
        _currentTransactionsPage = 1;
        _transactionsPerPage = 20;
        _totalTransactionPages = 1;
        _hasLoadedForCurrentUser = false;
        _lastTransactionsHash = null;
        _lastPushBalanceSnapshotAt = null;
        _lastAcceptedRemoteSnapshotSequence = null;
        _lastAcceptedRemoteSnapshotObservedAt = null;
        // _balanceNonDowngradeUntil = null; // Old Code (field removed)
        _resetBalanceSyncUiState();
        _sessionInitialBalanceLoadComplete = false;
        notifyListeners(); // Notify UI immediately that data is cleared
      }

      // Only load if this is a new user or we haven't loaded for this user yet
      if (_currentUserId != userId || !_hasLoadedForCurrentUser) {
        final bool isUserSwitching =
            _currentUserId != null && _currentUserId != userId;
        _currentUserId = userId;
        Logger.info(
          'User authenticated, loading point balance for user: $userId',
          tag: 'PointProvider',
        );
        final bool forceRefreshOnLoad =
            isUserSwitching || !_hasLoadedForCurrentUser;
        if (forceRefreshOnLoad) {
          Logger.debug(
            'Forcing balance refresh due to user switch or explicit request '
            '(handleAuthStateChange: first hydrate/account switch, '
            'isUserSwitching=$isUserSwitching)',
            tag: 'PointProvider',
          );
        }
        await loadBalance(userId, forceRefresh: forceRefreshOnLoad);
        _hasLoadedForCurrentUser = true;
      } else {
        Logger.info(
          'Point balance already loaded for user $userId, skipping reload',
          tag: 'PointProvider',
        );
      }
    } else {
      // User logged out - clear state
      final previousUserId = _currentUserId;
      _currentUserId = null;
      _hasLoadedForCurrentUser = false;
      _commitBalance(null);
      _transactions = [];
      _currentTransactionsPage = 1;
      _transactionsPerPage = 20;
      _totalTransactionPages = 1;
      _lastTransactionsHash = null;
      _lastPushBalanceSnapshotAt = null;
      _lastAcceptedRemoteSnapshotSequence = null;
      _lastAcceptedRemoteSnapshotObservedAt = null;
      // _balanceNonDowngradeUntil = null; // Old Code (field removed)
      _resetBalanceSyncUiState();
      _sessionInitialBalanceLoadComplete = false;
      notifyListeners();
      Logger.info(
        'User logged out (previous user: $previousUserId), cleared point data',
        tag: 'PointProvider',
      );
    }
  }

  void _handleSyncEvent(PointSyncEvent event) {
    if (event.userFacing && event.userMessage != null) {
      _setError(event.userMessage!);
    }
    if (!event.success) {
      _rollbackLatestOptimisticBalance(
        userId: event.transaction.userId,
        reason: event.userMessage ?? 'Sync failed, balance reverted',
      );
    }
  }

  /// Load point balance for user (serialized with canonical balance applies).
  /// If forceRefresh is true, will reload even if already loaded for this user
  /// PROFESSIONAL FIX: Validates user ID and clears old data on user change
  Future<void> loadBalance(
    String userId, {
    bool forceRefresh = false,
    bool notifyLoading = true,

    /// When set, passed to [PointService.getPointBalance] as `t=` to defeat CDN/proxy caches.
    int? balanceCacheBypassTimestampMs,
  }) async {
    try {
      /*
      Old Code:
      await PointBalanceSyncLock.run(() async {
        await _loadBalanceUnlocked(
          userId,
          forceRefresh: forceRefresh,
          notifyLoading: notifyLoading,
          balanceCacheBypassTimestampMs: balanceCacheBypassTimestampMs,
        );
      });
      */
      final int? resolvedBypass = balanceCacheBypassTimestampMs ??
          (forceRefresh ? DateTime.now().microsecondsSinceEpoch : null);
      await PointBalanceSyncLock.run(() async {
        await _loadBalanceUnlocked(
          userId,
          forceRefresh: forceRefresh,
          notifyLoading: notifyLoading,
          balanceCacheBypassTimestampMs: resolvedBypass,
        );
      });
      notifyListeners();
    } catch (e, stackTrace) {
      Logger.error(
        'PointProvider.loadBalance failed userId=$userId '
        'forceRefresh=$forceRefresh: $e',
        tag: 'PointProvider',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Trimmed poll-win finalize: trusts caller-supplied [authoritativePollBalance] when provided
  /// and applies **[CanonicalPointBalanceSync.apply]** once — no ledger polling loop or 30s retry.
  ///
  /// **[priorBalanceExclusive]** is retained for logging / diagnostics only (legacy callers).
  ///
  /// When [authoritativePollBalance] is null, performs a **single** [loadBalance] instead of the
  /// old ten-attempt poll.
  ///
  /// History: **[loadTransactions] page 1 only** (`perPage`: 20, `notifyLoading`: false).
  ///
  /// [scheduleDeferredRetryOnFailure]: **ignored** (kept only so existing call sites keep compiling).
  Future<void> refreshPointStateAfterPollWin({
    required String userId,
    required int priorBalanceExclusive,
    int? authoritativePollBalance,
    AuthProvider? authProvider,
    BigInt? snapshotSequence,
    DateTime? snapshotObservedAt,
    String canonicalPollWinSource = 'poll_win_refresh_trimmed',
    Future<void> Function()? refreshUserCallback,
    bool Function()? shouldContinue,
    bool scheduleDeferredRetryOnFailure = true,
  }) async {
    Logger.info(
      'PointProvider.refreshPointStateAfterPollWin(trimmed) userId=$userId '
      'priorExclusive=$priorBalanceExclusive authoritativePollBalance=$authoritativePollBalance '
      'source=$canonicalPollWinSource (scheduleDeferredRetryOnFailure ignored)',
      tag: 'PointProvider',
    );

    if (shouldContinue != null && !shouldContinue()) {
      Logger.info(
        'refreshPointStateAfterPollWin: aborted (shouldContinue false before apply)',
        tag: 'PointProvider',
      );
      return;
    }

    if (authoritativePollBalance != null) {
      final int local = currentBalance;
      if (authoritativePollBalance != local) {
        Logger.info(
          'refreshPointStateAfterPollWin: CanonicalPointBalanceSync.apply '
          'local=$local authoritative=$authoritativePollBalance',
          tag: 'PointProvider',
        );
        await CanonicalPointBalanceSync.apply(
          userId: userId,
          currentBalance: authoritativePollBalance,
          source: canonicalPollWinSource,
          emitBroadcast: true,
          authProvider: authProvider,
          pointProvider: this,
          snapshotSequence: snapshotSequence,
          snapshotObservedAt: snapshotObservedAt,
        );
      } else {
        Logger.info(
          'refreshPointStateAfterPollWin: skip apply (already local==authoritative $local)',
          tag: 'PointProvider',
        );
      }
    } else {
      Logger.info(
        'refreshPointStateAfterPollWin: authoritative null → single loadBalance(forceRefresh)',
        tag: 'PointProvider',
      );
      /*
      Old Code:
      await loadBalance(userId, forceRefresh: true, notifyLoading: false);
      */
      // High-resolution cache-bypass nonce + explicit notify so My PNP Selector/C rebuilds
      // after poll-win GET even when ledger filters previously skipped nested fetches.
      await loadBalance(
        userId,
        forceRefresh: true,
        notifyLoading: false,
        balanceCacheBypassTimestampMs: DateTime.now().microsecondsSinceEpoch,
      );
      notifyListeners();
    }

    if (shouldContinue != null && !shouldContinue()) {
      Logger.info(
        'refreshPointStateAfterPollWin: aborted after balance (shouldContinue false)',
        tag: 'PointProvider',
      );
      return;
    }

    final refreshUser = refreshUserCallback;
    if (refreshUser != null) {
      try {
        await refreshUser();
        Logger.info(
          'refreshPointStateAfterPollWin: refreshUser done',
          tag: 'PointProvider',
        );
      } catch (e, st) {
        Logger.error(
          'refreshPointStateAfterPollWin refreshUser failed: $e',
          tag: 'PointProvider',
          error: e,
          stackTrace: st,
        );
      }
    }

    if (shouldContinue != null && !shouldContinue()) {
      Logger.info(
        'refreshPointStateAfterPollWin: skip loadTransactions (shouldContinue false)',
        tag: 'PointProvider',
      );
      return;
    }

    try {
      Logger.info(
        'refreshPointStateAfterPollWin: loadTransactions FIRST PAGE ONLY page=1 perPage=20',
        tag: 'PointProvider',
      );
      await loadTransactions(
        userId,
        page: 1,
        perPage: 20,
        forceRefresh: true,
        rangeDays: 90,
        notifyLoading: false,
      );
      Logger.info(
        'refreshPointStateAfterPollWin: done userId=$userId '
        'currentBalance=$currentBalance',
        tag: 'PointProvider',
      );
    } catch (e, st) {
      Logger.error(
        'refreshPointStateAfterPollWin loadTransactions failed: $e',
        tag: 'PointProvider',
        error: e,
        stackTrace: st,
      );
    }

    /*
    // Old Code (heavy path — removed for latency):
    // - Up to 10× _loadBalanceUnlocked (1s apart) until ledger > priorBalanceExclusive
    // - _extendedPollWinSyncLabel + ToastService timeout on exhaustion
    // - unawaited loadTransactions + 30s deferred retry calling this method again
    */
  }

  /// Engagement submit / ledger paths where POST returns an exact authoritative balance.
  /// Up to **5** GETs (1s apart); only applies snapshots equal to [expectedBalance] so stale
  /// pre-mutation reads cannot overwrite [CanonicalPointBalanceSync] UI.
  ///
  /// Does not decrement balance-sync leases — caller [beginBalanceSync] / [endBalanceSync].
  ///
  /// See [refreshPointStateAfterPollWin] regarding [shouldContinue] and app backgrounding.
  Future<void> refreshPointStateUntilBalanceConfirmed({
    required String userId,
    required int expectedBalance,
    Future<void> Function()? refreshUserCallback,
    bool Function()? shouldContinue,
  }) async {
    final int strictPollDepthBaseline = _strictSerializedBalancePollDepth;
    /*
    Old Code: no outer restore — a leaked [_strictSerializedBalancePollDepth] could persist.
    */
    try {
      Logger.info(
        'PointProvider.refreshPointStateUntilBalanceConfirmed userId=$userId '
        'expected=$expectedBalance',
        tag: 'PointProvider',
      );
      var confirmed = false;
      var pollingCancelled = false;
      await PointBalanceSyncLock.run(() async {
        _strictSerializedBalancePollDepth++;
        try {
          try {
            for (var attempt = 0; attempt < 5; attempt++) {
              if (shouldContinue != null &&
                  !_pollVerificationShouldProceed(
                    shouldContinue,
                    'refreshPointStateUntilBalanceConfirmed',
                  )) {
                pollingCancelled = true;
                _extendedPollWinSyncLabel = false;
                Logger.info(
                  'Balance confirm poll: aborted before attempt ${attempt + 1}',
                  tag: 'PointProvider',
                );
                notifyListeners();
                break;
              }
              if (attempt > 0) {
                await Future<void>.delayed(const Duration(seconds: 1));
              }
              if (shouldContinue != null &&
                  !_pollVerificationShouldProceed(
                    shouldContinue,
                    'refreshPointStateUntilBalanceConfirmed',
                  )) {
                pollingCancelled = true;
                _extendedPollWinSyncLabel = false;
                notifyListeners();
                break;
              }
              if (attempt >= 3) {
                _extendedPollWinSyncLabel = true;
                notifyListeners();
              }
              final applied = await _loadBalanceUnlocked(
                userId,
                forceRefresh: true,
                notifyLoading: false,
                acceptOnlyBalanceEquals: expectedBalance,
              );
              if (shouldContinue != null &&
                  !_pollVerificationShouldProceed(
                    shouldContinue,
                    'refreshPointStateUntilBalanceConfirmed',
                  )) {
                pollingCancelled = true;
                _extendedPollWinSyncLabel = false;
                notifyListeners();
                break;
              }
              if (applied) {
                confirmed = true;
                _extendedPollWinSyncLabel = false;
                Logger.info(
                  'Balance confirm poll: matched expected=$expectedBalance on attempt ${attempt + 1}',
                  tag: 'PointProvider',
                );
                break;
              }
            }
            if (!confirmed && !pollingCancelled) {
              Logger.warning(
                'Balance confirm poll: never matched expected=$expectedBalance after 5 attempts',
                tag: 'PointProvider',
              );
              _extendedPollWinSyncLabel = false;
              if (!ToastService.showPointsVerificationTimeout()) {
                _syncNoticeMessage =
                    ToastService.pointsVerificationTimeoutMessage;
                notifyListeners();
              }
            }

            final refreshUser = refreshUserCallback;
            if (!pollingCancelled && refreshUser != null) {
              try {
                await refreshUser();
              } catch (e, st) {
                Logger.error(
                  'refreshPointStateUntilBalanceConfirmed refreshUser failed: $e',
                  tag: 'PointProvider',
                  error: e,
                  stackTrace: st,
                );
              }
            }
          } finally {
            _clearExtendedPollWinSyncLabelIfNeeded();
          }
        } finally {
          _strictSerializedBalancePollDepth--;
        }
      });

      if (!pollingCancelled) {
        unawaited(
          loadTransactions(
            userId,
            page: 1,
            perPage: 20,
            forceRefresh: true,
            rangeDays: 90,
          ).catchError((Object e, StackTrace st) {
            Logger.error(
              'refreshPointStateUntilBalanceConfirmed loadTransactions failed: $e',
              tag: 'PointProvider',
              error: e,
              stackTrace: st,
            );
          }),
        );
      }
    } finally {
      if (_strictSerializedBalancePollDepth != strictPollDepthBaseline) {
        Logger.warning(
          'refreshPointStateUntilBalanceConfirmed: strict poll depth safety restore '
          '($_strictSerializedBalancePollDepth → $strictPollDepthBaseline)',
          tag: 'PointProvider',
        );
      }
      _strictSerializedBalancePollDepth = strictPollDepthBaseline;
    }
  }

  /// Poll-vote **deduction** path when interact response omits `new_balance`: reject GET
  /// snapshots strictly **greater** than [maxAcceptableFromApi] (typically `balanceBefore - cost`)
  /// until the ledger reflects the spend (or attempts exhaust).
  ///
  /// See [refreshPointStateAfterPollWin] regarding [shouldContinue] and app backgrounding.
  Future<void> refreshPointStateUntilDeductionVisibleOnLedger({
    required String userId,
    required int maxAcceptableFromApi,
    Future<void> Function()? refreshUserCallback,
    bool Function()? shouldContinue,
  }) async {
    final int strictPollDepthBaseline = _strictSerializedBalancePollDepth;
    /*
    Old Code: no outer restore — a leaked [_strictSerializedBalancePollDepth] could persist.
    */
    try {
      Logger.info(
        'PointProvider.refreshPointStateUntilDeductionVisibleOnLedger userId=$userId '
        'maxAcceptable=$maxAcceptableFromApi',
        tag: 'PointProvider',
      );
      var confirmed = false;
      var pollingCancelled = false;
      await PointBalanceSyncLock.run(() async {
        _strictSerializedBalancePollDepth++;
        try {
          try {
            for (var attempt = 0; attempt < 5; attempt++) {
              if (shouldContinue != null &&
                  !_pollVerificationShouldProceed(
                    shouldContinue,
                    'refreshPointStateUntilDeductionVisibleOnLedger',
                  )) {
                pollingCancelled = true;
                _extendedPollWinSyncLabel = false;
                notifyListeners();
                break;
              }
              if (attempt > 0) {
                await Future<void>.delayed(const Duration(seconds: 1));
              }
              if (shouldContinue != null &&
                  !_pollVerificationShouldProceed(
                    shouldContinue,
                    'refreshPointStateUntilDeductionVisibleOnLedger',
                  )) {
                pollingCancelled = true;
                _extendedPollWinSyncLabel = false;
                notifyListeners();
                break;
              }
              if (attempt >= 3) {
                _extendedPollWinSyncLabel = true;
                notifyListeners();
              }
              final applied = await _loadBalanceUnlocked(
                userId,
                forceRefresh: true,
                notifyLoading: false,
                rejectFetchedBalanceIfGreaterThan: maxAcceptableFromApi,
              );
              if (shouldContinue != null &&
                  !_pollVerificationShouldProceed(
                    shouldContinue,
                    'refreshPointStateUntilDeductionVisibleOnLedger',
                  )) {
                pollingCancelled = true;
                _extendedPollWinSyncLabel = false;
                notifyListeners();
                break;
              }
              if (applied) {
                confirmed = true;
                _extendedPollWinSyncLabel = false;
                Logger.info(
                  'Deduction ledger poll: applied snapshot on attempt ${attempt + 1} '
                  '(balance=$currentBalance)',
                  tag: 'PointProvider',
                );
                break;
              }
            }
            if (!confirmed && !pollingCancelled) {
              Logger.warning(
                'Deduction ledger poll: stale-high reads persisted after 5 attempts '
                '(maxAcceptable=$maxAcceptableFromApi, memory=${_balance?.currentBalance})',
                tag: 'PointProvider',
              );
              _extendedPollWinSyncLabel = false;
              if (!ToastService.showPointsVerificationTimeout()) {
                _syncNoticeMessage =
                    ToastService.pointsVerificationTimeoutMessage;
                notifyListeners();
              }
            }

            final refreshUser = refreshUserCallback;
            if (!pollingCancelled && refreshUser != null) {
              try {
                await refreshUser();
              } catch (e, st) {
                Logger.error(
                  'refreshPointStateUntilDeductionVisibleOnLedger refreshUser failed: $e',
                  tag: 'PointProvider',
                  error: e,
                  stackTrace: st,
                );
              }
            }
          } finally {
            _clearExtendedPollWinSyncLabelIfNeeded();
          }
        } finally {
          _strictSerializedBalancePollDepth--;
        }
      });

      if (!pollingCancelled) {
        unawaited(
          loadTransactions(
            userId,
            page: 1,
            perPage: 20,
            forceRefresh: true,
            rangeDays: 90,
          ).catchError((Object e, StackTrace st) {
            Logger.error(
              'refreshPointStateUntilDeductionVisibleOnLedger loadTransactions failed: $e',
              tag: 'PointProvider',
              error: e,
              stackTrace: st,
            );
          }),
        );
      }
    } finally {
      if (_strictSerializedBalancePollDepth != strictPollDepthBaseline) {
        Logger.warning(
          'refreshPointStateUntilDeductionVisibleOnLedger: strict poll depth safety restore '
          '($_strictSerializedBalancePollDepth → $strictPollDepthBaseline)',
          tag: 'PointProvider',
        );
      }
      _strictSerializedBalancePollDepth = strictPollDepthBaseline;
    }
  }

  /// Core balance fetch; must be invoked only from inside [PointBalanceSyncLock.run]
  /// **or** from [loadBalance] / [refreshPointStateAfterPollWin] / ledger verification helpers
  /// (which acquire the lock).
  ///
  /// Returns `true` when a **fresh online** [PointService.getPointBalance] result was applied
  /// to [_balance] (including normal loads). Returns `false` when the poll-win floor rejected
  /// a stale snapshot, [acceptOnlyBalanceEquals] / [rejectFetchedBalanceIfGreaterThan] rejected
  /// the fetch, on cache/offline paths, or on errors.
  Future<bool> _loadBalanceUnlocked(
    String userId, {
    bool forceRefresh = false,
    bool notifyLoading = true,
    int? pollWinStaleFloorExclusive,

    /// When set, only apply API balance if it equals this (authoritative `new_balance` path).
    int? acceptOnlyBalanceEquals,

    /// When set, treat API balance as stale if strictly greater (pre-deduct ghost reads).
    int? rejectFetchedBalanceIfGreaterThan,

    /// Optional stronger cache bypass for [PointService.getPointBalance] (`t=` query).
    int? balanceCacheBypassTimestampMs,
  }) async {
    var appliedServerSnapshot = false;
    final bool unscopedApiBalanceApply = pollWinStaleFloorExclusive == null &&
        acceptOnlyBalanceEquals == null &&
        rejectFetchedBalanceIfGreaterThan == null;
    /*
    Old Code:
    if (_strictSerializedBalancePollDepth > 0 &&
        unscopedApiBalanceApply &&
        !forceRefresh) {
      ...
      return false;
    }
    */
    // Strict-depth throttle applies only to incidental unscoped GETs during verification.
    // [forceRefresh: true] bypasses this gate entirely — avoids sync starvation / deadlock-feel.
    if (!forceRefresh &&
        _strictSerializedBalancePollDepth > 0 &&
        unscopedApiBalanceApply) {
      Logger.info(
        'PointProvider._loadBalanceUnlocked: skip unscoped balance fetch during '
        'ledger verification (nested [loadBalance] would bypass accept/reject/floor filters). '
        'userId=$userId',
        tag: 'PointProvider',
      );
      return false;
    }
    // First successful hydrate for this session (startup / login sync), not an in-session earn.
    final bool isInitialLoad = !_sessionInitialBalanceLoadComplete;
    Logger.info(
      'PointProvider._loadBalanceUnlocked start: userId=$userId, forceRefresh=$forceRefresh, '
      'isConnected=${_connectivityService.isConnected}, currentUserId=$_currentUserId, '
      'localBalance=${_balance?.currentBalance}, pollWinFloor=$pollWinStaleFloorExclusive, '
      'acceptOnly=$acceptOnlyBalanceEquals, rejectIfGt=$rejectFetchedBalanceIfGreaterThan',
      tag: 'PointProvider',
    );
    if (forceRefresh) {
      Logger.debug(
        'Forcing balance refresh due to user switch or explicit request '
        '(_loadBalanceUnlocked forceRefresh=true, userId=$userId)',
        tag: 'PointProvider',
      );
      // Force path must invalidate "already loaded" guard before any fetch.
      _hasLoadedForCurrentUser = false;
    }

    // PROFESSIONAL FIX: Check if userId matches before skipping
    // If userId changed, we need to reload even if balance exists
    // CRITICAL: Always reload if userId doesn't match, even if balance exists
    if (!forceRefresh && _balance != null) {
      if (_currentUserId == userId && _hasLoadedForCurrentUser) {
        Logger.info(
          'Balance already loaded for user $userId, skipping',
          tag: 'PointProvider',
        );
        if (isInitialLoad) {
          _sessionInitialBalanceLoadComplete = true;
        }
        return false;
      } else if (_currentUserId != null && _currentUserId != userId) {
        // User ID mismatch - this should not happen if handleAuthStateChange is called correctly
        // But handle it gracefully by clearing and reloading
        Logger.warning(
          'User ID mismatch detected: current=$_currentUserId, requested=$userId. Clearing and reloading.',
          tag: 'PointProvider',
        );
        _commitBalance(null);
        _hasLoadedForCurrentUser = false;
      }
    }

    // If userId changed, clear old data first (defensive check)
    if (_currentUserId != null && _currentUserId != userId) {
      Logger.info(
        'User changed from $_currentUserId to $userId, clearing old point balance',
        tag: 'PointProvider',
      );
      _commitBalance(null);
      _hasLoadedForCurrentUser = false;
    }

    _setLoading(true, notify: notifyLoading);
    _clearError();
    _currentUserId = userId;

    /*
    Old Code: no session-level shimmer during first online fetch; cache fallback
    could call notifyListeners immediately and cause balance flicker vs API.
    */
    // New Code: first-session online hydrate — My PNP shimmer until API finishes or errors.
    var raisedSessionApiShimmer = false;
    // Prefer debounced cache paint after a failed initial online fetch (avoids digit jump).
    final bool immediateCacheNotifyAfterOnlineAttempt =
        !(isInitialLoad && _connectivityService.isConnected);

    try {
      if (isInitialLoad &&
          _connectivityService.isConnected &&
          pollWinStaleFloorExclusive == null) {
        raisedSessionApiShimmer = true;
        setSyncingBalance(true);
      }

      // Try to load from API if online
      // OPTIMIZED: Use cached connectivity service
      // Embedded transaction rows may lift stale headline totals — see [PointService.getPointBalance].
      if (_connectivityService.isConnected) {
        final balance = await PointService.getPointBalance(
          userId,
          cacheBypassTimestampMs: balanceCacheBypassTimestampMs ??
              DateTime.now().millisecondsSinceEpoch,
          persistToStorage: pollWinStaleFloorExclusive == null &&
              acceptOnlyBalanceEquals == null &&
              rejectFetchedBalanceIfGreaterThan == null,
        );
        if (balance != null) {
          Logger.debug(
            'PointProvider: balance snapshot currentBalance=${balance.currentBalance} '
            '(API headline merged with embedded ledger preview via '
            'PointService.coalesceHeadlineWithEmbeddedLedgerPreview inside getPointBalance)',
            tag: 'PointProvider',
          );
          /*
          Old Code: always trust API balance from getPointBalance (no floor).
          _balance = balance;
          */
          if (pollWinStaleFloorExclusive != null &&
              balance.currentBalance <= pollWinStaleFloorExclusive) {
            Logger.info(
              'PointProvider: poll-win smart poll — API returned ${balance.currentBalance} '
              '(<= floor $pollWinStaleFloorExclusive); not applying stale ledger to memory '
              '(keeping ${_balance?.currentBalance})',
              tag: 'PointProvider',
            );
          } else if (pollWinStaleFloorExclusive != null &&
              _balance != null &&
              _balance!.currentBalance > pollWinStaleFloorExclusive &&
              balance.currentBalance < _balance!.currentBalance) {
            // Canonical / broadcast may already reflect the win; a lagging GET can still be
            // strictly above the pre-win floor yet below SSOT — do not downgrade mid-verify.
            Logger.info(
              'PointProvider: poll-win smart poll — API returned ${balance.currentBalance} '
              '(< in-memory ${_balance!.currentBalance} while > floor '
              '$pollWinStaleFloorExclusive); not applying mid-lag snapshot '
              '(keeping ${_balance?.currentBalance})',
              tag: 'PointProvider',
            );
          } else if (acceptOnlyBalanceEquals != null &&
              balance.currentBalance != acceptOnlyBalanceEquals) {
            Logger.info(
              'PointProvider: ledger confirm poll — API returned ${balance.currentBalance} '
              '(want exact $acceptOnlyBalanceEquals); not applying stale snapshot '
              '(keeping ${_balance?.currentBalance})',
              tag: 'PointProvider',
            );
          } else if (rejectFetchedBalanceIfGreaterThan != null &&
              balance.currentBalance > rejectFetchedBalanceIfGreaterThan) {
            Logger.info(
              'PointProvider: post-deduct poll — API returned ${balance.currentBalance} '
              '(> ceiling $rejectFetchedBalanceIfGreaterThan); not applying stale snapshot '
              '(keeping ${_balance?.currentBalance})',
              tag: 'PointProvider',
            );
          } else {
            _commitBalance(balance);
            appliedServerSnapshot = true;
            AuthProvider().mirrorLedgerBalanceToUserMeta(
              balance.currentBalance,
            );
            if (pollWinStaleFloorExclusive != null ||
                acceptOnlyBalanceEquals != null ||
                rejectFetchedBalanceIfGreaterThan != null) {
              await PointService.persistFetchedBalance(balance);
            }
            Logger.info(
              'Point balance loaded from API: ${balance.currentBalance} points',
              tag: 'PointProvider',
            );
            _hasLoadedForCurrentUser = true;
            _debounceTimer?.cancel();
            notifyListeners();
          }
          /*
          Old Code:
          (no extra notify after guarded branches)
          */
          // Force-refresh: always ping listeners after a successful GET parse so My PNP rebuilds
          // even when ledger guards rejected applying (verification paths).
          if (forceRefresh) {
            notifyListeners();
          }
        } else {
          if (forceRefresh) {
            /*
            Old Code: cleared [_balance] on force-refresh null — engagement bursts
            made My PNP flicker to empty when the API hiccupped.
            Logger.error(
              'PointProvider._loadBalanceUnlocked forceRefresh API returned null. '
              'Clearing in-memory balance and skipping cache fallback for userId=$userId',
              tag: 'PointProvider',
            );
            _balance = null;
            _hasLoadedForCurrentUser = false;
            _setError(_buildBalanceSyncErrorMessage());
            _debounceTimer?.cancel();
            notifyListeners();
            */
            // New Code: keep last known good balance; surface error; try disk cache if memory empty.
            Logger.warning(
              'PointProvider._loadBalanceUnlocked forceRefresh API returned null '
              'for userId=$userId — retaining prior balance when available',
              tag: 'PointProvider',
            );
            _setError(_buildBalanceSyncErrorMessage());
            _debounceTimer?.cancel();
            if (_balance != null) {
              notifyListeners();
            } else {
              await _loadCachedBalance(
                userId: userId,
                preferImmediateNotify: immediateCacheNotifyAfterOnlineAttempt,
              );
            }
          } else {
            Logger.warning(
              'PointProvider._loadBalanceUnlocked API returned null, entering cache fallback '
              'for userId=$userId',
              tag: 'PointProvider',
            );
            await _loadCachedBalance(
              userId: userId,
              preferImmediateNotify: immediateCacheNotifyAfterOnlineAttempt,
            );
          }
        }
      } else {
        // Load from cache if offline
        await _loadCachedBalance(
          userId: userId,
          preferImmediateNotify: isInitialLoad,
        );
      }
    } catch (e, stackTrace) {
      Logger.error(
        'Error loading point balance: $e',
        tag: 'PointProvider',
        error: e,
        stackTrace: stackTrace,
      );
      if (forceRefresh) {
        /*
        Old Code: cleared balance on force-refresh exception.
        Logger.error(
          'PointProvider._loadBalanceUnlocked forceRefresh threw error, skipping cache fallback '
          'and clearing balance for userId=$userId',
          tag: 'PointProvider',
        );
        _balance = null;
        _hasLoadedForCurrentUser = false;
        _setError(_buildBalanceSyncErrorMessage(error: e));
        _debounceTimer?.cancel();
        notifyListeners();
        */
        Logger.warning(
          'PointProvider._loadBalanceUnlocked forceRefresh error for userId=$userId '
          '— retaining prior balance when available: $e',
          tag: 'PointProvider',
          error: e,
          stackTrace: stackTrace,
        );
        _setError(_buildBalanceSyncErrorMessage(error: e));
        _debounceTimer?.cancel();
        if (_balance != null) {
          notifyListeners();
        } else {
          await _loadCachedBalance(
            userId: userId,
            preferImmediateNotify: immediateCacheNotifyAfterOnlineAttempt,
          );
        }
      } else {
        _setError('Failed to load point balance');
        Logger.warning(
          'PointProvider._loadBalanceUnlocked catch branch entering cache fallback '
          'for userId=$userId',
          tag: 'PointProvider',
        );
        await _loadCachedBalance(
          userId: userId,
          preferImmediateNotify: immediateCacheNotifyAfterOnlineAttempt,
        );
      }
    } finally {
      if (raisedSessionApiShimmer) {
        setSyncingBalance(false);
      }
      _setLoading(false, notify: notifyLoading);
      if (_balance != null && isInitialLoad) {
        _sessionInitialBalanceLoadComplete = true;
      }
    }
    return appliedServerSnapshot;
  }

  /// Centralized point-state refresh flow used by Home, point history, and
  /// point mutation events so all screens reconcile with the same logic.
  Future<void> refreshPointState({
    required String userId,
    bool forceRefresh = true,
    bool refreshBalance = true,
    bool refreshTransactions = true,
    int transactionsPage = 1,
    int transactionsPerPage = 20,
    int? transactionsRangeDays,
    DateTime? transactionsDateFrom,
    DateTime? transactionsDateTo,
    Future<void> Function()? refreshUserCallback,

    /// When false, [loadBalance] skips the global points loading spinner — use after
    /// authoritative balance (e.g. poll `new_balance`) so My PNP does not flash stale loading.
    bool notifyBalanceLoading = true,
  }) async {
    if (kDebugMode) {
      debugPrint(
        '📥 [PNP DEBUG] [${DateTime.now()}] PointProvider: refreshPointState called. | UserID: $userId | Force: $forceRefresh',
      );
    }
    Logger.info(
      'PointProvider.refreshPointState called: userId=$userId, '
      'forceRefresh=$forceRefresh, refreshBalance=$refreshBalance, '
      'refreshTransactions=$refreshTransactions',
      tag: 'PointProvider',
    );

    if (refreshBalance) {
      if (forceRefresh) {
        // Ensure next fetch cannot be short-circuited by in-memory "already loaded" state.
        _hasLoadedForCurrentUser = false;
      }
      await loadBalance(
        userId,
        forceRefresh: forceRefresh,
        notifyLoading: notifyBalanceLoading,
      );
    }

    final refreshUser = refreshUserCallback;
    if (refreshUser != null) {
      unawaited(
        refreshUser().catchError((Object e, StackTrace st) {
          Logger.error(
            'refreshUserCallback failed: $e',
            tag: 'PointProvider',
            error: e,
            stackTrace: st,
          );
        }),
      );
    }

    if (refreshTransactions) {
      unawaited(
        loadTransactions(
          userId,
          page: transactionsPage,
          perPage: transactionsPerPage,
          forceRefresh: forceRefresh,
          rangeDays: transactionsRangeDays ?? 90,
          dateFrom: transactionsDateFrom,
          dateTo: transactionsDateTo,
        ).catchError((Object e, StackTrace st) {
          Logger.error(
            'refreshPointState loadTransactions failed: $e',
            tag: 'PointProvider',
            error: e,
            stackTrace: st,
          );
        }),
      );
    }
  }

  /// Compatibility helper for UI/service call sites that only need
  /// "refresh latest points now" semantics after a poll winner event.
  Future<void> fetchPoints({
    String? userId,
    Future<void> Function()? refreshUserCallback,
  }) async {
    final effectiveUserId =
        (userId != null && userId.isNotEmpty) ? userId : _currentUserId;
    if (effectiveUserId == null || effectiveUserId.isEmpty) {
      Logger.warning(
        'PointProvider.fetchPoints skipped: no userId available',
        tag: 'PointProvider',
      );
      return;
    }

    await refreshPointState(
      userId: effectiveUserId,
      forceRefresh: true,
      refreshBalance: true,
      refreshTransactions: true,
      refreshUserCallback: refreshUserCallback,
    );
  }

  /// Optimistically increments current balance for instant UI feedback.
  /// Intended for poll-win paths before server reconciliation finishes.
  void optimisticAddPoints(int pointsToAdd, {required String refId}) {
    if (_optimisticRefs.length > 50) {
      Logger.info(
        'Clearing old optimistic refs to prevent memory leak.',
        tag: 'PointProvider',
      );
      _optimisticRefs.clear();
      _optimisticSnapshots.clear();
    }
    if (_optimisticRefs.contains(refId)) {
      Logger.info(
        'Optimistic points already added for $refId, skipping.',
        tag: 'PointProvider',
      );
      return;
    }
    Logger.info(
      'DEBUG_SYNC: optimisticAddPoints accept refId=$refId pointsToAdd=$pointsToAdd',
      tag: 'PointProvider',
    );
    _optimisticRefs.add(refId);
    if (_balance != null) {
      final previous = _balance!;
      _optimisticSnapshots[refId] = _OptimisticBalanceSnapshot(
        refId: refId,
        userId: previous.userId,
        previousBalance: previous.currentBalance,
        appliedAt: DateTime.now(),
      );
      _commitBalance(
        PointBalance(
          userId: previous.userId,
          currentBalance: previous.currentBalance + pointsToAdd,
          lifetimeEarned: previous.lifetimeEarned,
          lifetimeRedeemed: previous.lifetimeRedeemed,
          lifetimeExpired: previous.lifetimeExpired,
          lastUpdated: DateTime.now(),
          pointsExpireAt: previous.pointsExpireAt,
        ),
      );
      notifyListeners();
    }
  }

  void _rollbackLatestOptimisticBalance({
    required String userId,
    required String reason,
  }) {
    if (_optimisticSnapshots.isEmpty) return;
    final snapshots = _optimisticSnapshots.values
        .where((s) => s.userId == userId)
        .toList()
      ..sort((a, b) => b.appliedAt.compareTo(a.appliedAt));
    if (snapshots.isEmpty) return;

    // Only rollback very recent optimistic mutations tied to sync timeout/failure.
    final latest = snapshots.first;
    final age = DateTime.now().difference(latest.appliedAt);
    if (age.inSeconds > 45) return;
    if (_balance == null) return;
    if (_balance!.currentBalance == latest.previousBalance) return;

    final previous = _balance!;
    _commitBalance(
      PointBalance(
        userId: previous.userId,
        currentBalance: latest.previousBalance,
        lifetimeEarned: previous.lifetimeEarned,
        lifetimeRedeemed: previous.lifetimeRedeemed,
        lifetimeExpired: previous.lifetimeExpired,
        lastUpdated: DateTime.now(),
        pointsExpireAt: previous.pointsExpireAt,
      ),
    );
    _optimisticSnapshots.remove(latest.refId);
    _optimisticRefs.remove(latest.refId);
    _syncNoticeMessage = reason;
    notifyListeners();
  }

  String? consumeSyncNoticeMessage() {
    final current = _syncNoticeMessage;
    _syncNoticeMessage = null;
    return current;
  }

  /// Apply optimistic balance update from in-app events (e.g. poll win).
  /// Does NOT set _lastPushBalanceSnapshotAt, so MainPage can show modal as fallback.
  void applyOptimisticBalanceUpdate({
    required String userId,
    required int currentBalance,
  }) {
    final int previousBalance = _balance?.currentBalance ?? -1;
    if (_currentUserId != null && _currentUserId != userId) {
      _commitBalance(null);
      _transactions = [];
      _lastTransactionsHash = null;
      _hasLoadedForCurrentUser = false;
    }
    _currentUserId = userId;
    final previous = _balance;
    _commitBalance(
      PointBalance(
        userId: userId,
        currentBalance: currentBalance,
        lifetimeEarned: previous?.lifetimeEarned ?? 0,
        lifetimeRedeemed: previous?.lifetimeRedeemed ?? 0,
        lifetimeExpired: previous?.lifetimeExpired ?? 0,
        lastUpdated: DateTime.now(),
        pointsExpireAt: previous?.pointsExpireAt,
      ),
    );
    _hasLoadedForCurrentUser = true;
    final bool balanceChanged =
        previous == null || previous.currentBalance != currentBalance;
    Logger.info(
      'DEBUG_SYNC: applyOptimisticBalanceUpdate userId=$userId '
      'previousBalance=$previousBalance newBalance=$currentBalance '
      'balanceActuallyChanged=$balanceChanged — calling notifyListeners()',
      tag: 'PointProvider',
    );
    // Optimistic updates (e.g. poll win) need immediate UI refresh
    notifyListeners();
    Logger.info(
      'DEBUG_SYNC: applyOptimisticBalanceUpdate notifyListeners() returned '
      '(scheduled listeners; newBalance=$currentBalance)',
      tag: 'PointProvider',
    );
  }

  /// True when [snapshotSequence] or [snapshotObservedAt] is strictly newer than the
  /// last accepted values (OR). Used to accept authoritative downgrades from another device.
  bool _snapshotMetadataStrictlyNewerThanLast({
    required BigInt? snapshotSequence,
    required DateTime? snapshotObservedAt,
    required BigInt? seqLast,
    required DateTime? tsLast,
  }) {
    if (snapshotSequence != null) {
      if (seqLast == null || snapshotSequence > seqLast) {
        return true;
      }
    }
    if (snapshotObservedAt != null) {
      if (tsLast == null || snapshotObservedAt.isAfter(tsLast)) {
        return true;
      }
    }
    return false;
  }

  /// Apply point balance snapshot coming from push / canonical paths.
  ///
  /// Call only while [PointBalanceSyncLock.run] already holds the queue (e.g. from
  /// [AuthProvider.applyPointsBalanceSnapshot] or nested canonical work).
  ///
  /// Returns `false` when the snapshot is stale by sequence/time **for non-upgrades**, or when a balance
  /// **downgrade** would apply but neither [snapshotSequence] nor [snapshotObservedAt]
  /// proves the snapshot is strictly newer than the last accepted metadata (avoids
  /// lagging API ghosts while allowing another device’s spend to sync when metadata is fresh).
  /// Ledger **upgrades** (`currentBalance` strictly greater than memory) bypass stale sequence/time
  /// rejection so poll/push paths cannot be blocked by non-monotonic txn ids.
  bool applyRemoteBalanceSnapshotUnlocked({
    required String userId,
    required int currentBalance,
    BigInt? snapshotSequence,
    DateTime? snapshotObservedAt,
  }) {
    // Defensive: handle user switching.
    if (_currentUserId != null && _currentUserId != userId) {
      _commitBalance(null);
      _transactions = [];
      _lastTransactionsHash = null;
      _hasLoadedForCurrentUser = false;
      _lastAcceptedRemoteSnapshotSequence = null;
      _lastAcceptedRemoteSnapshotObservedAt = null;
    }

    _currentUserId = userId;

    final int? memoryBalance = _balance?.currentBalance;
    final bool isLedgerUpgrade =
        memoryBalance == null || currentBalance > memoryBalance;

    final BigInt? seqLast = _lastAcceptedRemoteSnapshotSequence;
    /*
    Old Code: stale sequence rejected even when remote balance was a strict upgrade
    (e.g. poll used DB txn id as “sequence” vs higher FCM seq).
    if (snapshotSequence != null && seqLast != null) {
      if (snapshotSequence < seqLast) {
        ...
        return false;
      }
    }
    */
    if (!isLedgerUpgrade &&
        snapshotSequence != null &&
        seqLast != null &&
        snapshotSequence < seqLast) {
      Logger.info(
        'PointProvider.applyRemoteBalanceSnapshot: ignore stale sequence '
        'seq=$snapshotSequence < lastSeq=$seqLast (userId=$userId)',
        tag: 'PointProvider',
      );
      return false;
    }

    // Chaos guard: ledger `sequence_id` is authoritative; replica/wall-clock fields
    // can be misordered. When sequence strictly increases, do not reject on time alone.
    final bool sequenceStrictlyAheadOfLast = snapshotSequence != null &&
        seqLast != null &&
        snapshotSequence > seqLast;

    final DateTime? tsLast = _lastAcceptedRemoteSnapshotObservedAt;
    /*
    Old Code: stale observation time rejected even for strict balance upgrades.
    if (!sequenceStrictlyAheadOfLast &&
        snapshotObservedAt != null &&
        tsLast != null) {
      if (snapshotObservedAt.isBefore(tsLast)) {
        return false;
      }
    }
    */
    if (!isLedgerUpgrade &&
        !sequenceStrictlyAheadOfLast &&
        snapshotObservedAt != null &&
        tsLast != null) {
      if (snapshotObservedAt.isBefore(tsLast)) {
        Logger.info(
          'PointProvider.applyRemoteBalanceSnapshot: ignore stale observation '
          'time (${snapshotObservedAt.toIso8601String()} < '
          '${tsLast.toIso8601String()}, userId=$userId)',
          tag: 'PointProvider',
        );
        return false;
      }
    }

    if (memoryBalance != null && currentBalance < memoryBalance) {
      if (!_snapshotMetadataStrictlyNewerThanLast(
        snapshotSequence: snapshotSequence,
        snapshotObservedAt: snapshotObservedAt,
        seqLast: seqLast,
        tsLast: tsLast,
      )) {
        Logger.info(
          'PointProvider.applyRemoteBalanceSnapshot: ignore downgrade '
          'remote=$currentBalance < memory=$memoryBalance without newer metadata '
          '(userId=$userId)',
          tag: 'PointProvider',
        );
        return false;
      }
      Logger.info(
        'PointProvider.applyRemoteBalanceSnapshot: accepting downgrade '
        'remote=$currentBalance < memory=$memoryBalance (newer seq/time, userId=$userId)',
        tag: 'PointProvider',
      );
    }

    final previous = _balance;
    _commitBalance(
      PointBalance(
        userId: userId,
        currentBalance: currentBalance,
        lifetimeEarned: previous?.lifetimeEarned ?? 0,
        lifetimeRedeemed: previous?.lifetimeRedeemed ?? 0,
        lifetimeExpired: previous?.lifetimeExpired ?? 0,
        lastUpdated: DateTime.now(),
        pointsExpireAt: previous?.pointsExpireAt,
      ),
    );

    final DateTime snapshotClock = DateTime.now();
    _lastPushBalanceSnapshotAt = snapshotClock;

    /*
    Old Code: always overwrote last seq/ts from snapshot — could lower seq after upgrade bypass.
    if (snapshotSequence != null) {
      _lastAcceptedRemoteSnapshotSequence = snapshotSequence;
    }
    if (snapshotObservedAt != null) {
      _lastAcceptedRemoteSnapshotObservedAt = snapshotObservedAt;
    }
    */
    // New Code: monotonic metadata only — never regress causal ordering state.
    if (snapshotSequence != null) {
      final BigInt? prevSeq = _lastAcceptedRemoteSnapshotSequence;
      if (prevSeq == null || snapshotSequence >= prevSeq) {
        _lastAcceptedRemoteSnapshotSequence = snapshotSequence;
      }
    }
    if (snapshotObservedAt != null) {
      final DateTime? prevTs = _lastAcceptedRemoteSnapshotObservedAt;
      if (prevTs == null || !snapshotObservedAt.isBefore(prevTs)) {
        _lastAcceptedRemoteSnapshotObservedAt = snapshotObservedAt;
      }
    }

    _hasLoadedForCurrentUser = true;
    _optimisticSnapshots.removeWhere((_, s) => s.userId == userId);
    notifyListeners();
    AuthProvider().mirrorLedgerBalanceToUserMeta(currentBalance);
    return true;
  }

  /// FIFO-serialized snapshot apply (same global queue as [loadBalance]).
  Future<bool> applyRemoteBalanceSnapshot({
    required String userId,
    required int currentBalance,
    BigInt? snapshotSequence,
    DateTime? snapshotObservedAt,
  }) async {
    return PointBalanceSyncLock.run(() async {
      return applyRemoteBalanceSnapshotUnlocked(
        userId: userId,
        currentBalance: currentBalance,
        snapshotSequence: snapshotSequence,
        snapshotObservedAt: snapshotObservedAt,
      );
    });
  }

  /// OPTIMIZED: Debounced notifyListeners to prevent excessive rebuilds
  /// Only notifies if data actually changed
  /// PROFESSIONAL FIX: Include balance AND status in hash to detect all state changes
  void _notifyListenersDebounced({bool force = false}) {
    if (!force) {
      // Calculate hash of current balance AND transactions to detect changes
      final currentHash = (_balance?.currentBalance.hashCode ?? 0) ^
          _transactions.length.hashCode ^
          (_transactions.isNotEmpty ? _transactions.first.id.hashCode : 0) ^
          (_transactions.isNotEmpty ? _transactions.first.status.hashCode : 0) ^
          (_transactions.isNotEmpty ? _transactions.last.id.hashCode : 0) ^
          (_transactions.isNotEmpty ? _transactions.last.status.hashCode : 0);

      // Skip notification if data hasn't changed
      if (_lastTransactionsHash == currentHash && !force) {
        return;
      }
      _lastTransactionsHash = currentHash;
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDelay, () {
      notifyListeners();
    });
  }

  /// Helper to check if two transaction lists are equal
  /// PROFESSIONAL FIX: Also check status to detect when transactions change from pending to approved
  /// This ensures UI updates when transaction status changes (e.g., Lucky Box approval)
  bool _areTransactionsEqual(
    List<PointTransaction> a,
    List<PointTransaction> b,
  ) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      // Check id, points, AND status to detect status changes (e.g., pending -> approved)
      if (a[i].id != b[i].id ||
          a[i].points != b[i].points ||
          a[i].status != b[i].status) {
        return false;
      }
    }
    return true;
  }

  /// Load point transactions for user
  /// IMPORTANT: Pending transactions SHOULD be shown in history (transparency),
  /// but they do NOT affect balance until approved.
  /// Loads cached transactions first for immediate display, then refreshes from API
  /// PROFESSIONAL FIX: Validates user ID and clears old data on user change
  Future<void> loadTransactions(
    String userId, {
    int page = 1,
    int perPage = 20,
    bool forceRefresh = false,
    int rangeDays = 90,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool notifyLoading = true,
  }) async {
    DateTime? effectiveFrom = dateFrom;
    DateTime? effectiveTo = dateTo;
    // Normalize reversed inputs defensively for API reliability.
    if (effectiveFrom != null &&
        effectiveTo != null &&
        effectiveFrom.isAfter(effectiveTo)) {
      final swapped = effectiveFrom;
      effectiveFrom = effectiveTo;
      effectiveTo = swapped;
    }

    Logger.info(
      'PointProvider.loadTransactions called: userId=$userId, page=$page, perPage=$perPage, forceRefresh=$forceRefresh, currentUserId=$_currentUserId, hasTransactions=${_transactions.isNotEmpty}',
      tag: 'PointProvider',
    );

    // PROFESSIONAL FIX: Check if userId matches before skipping
    // If userId changed, we need to reload even if transactions exist
    // CRITICAL: Always reload if userId doesn't match, even if transactions exist
    // CRITICAL FIX: Also check if _currentUserId is null (first load) - don't skip in that case
    final bool isLoadMoreRequest = page > 1 && !forceRefresh;
    if (!forceRefresh &&
        !isLoadMoreRequest &&
        _transactions.isNotEmpty &&
        _currentUserId != null) {
      if (_currentUserId == userId) {
        Logger.info(
          'Transactions already loaded for user $userId, skipping',
          tag: 'PointProvider',
        );
        return;
      } else if (_currentUserId != null && _currentUserId != userId) {
        // User ID mismatch - clear old data
        Logger.warning(
          'User ID mismatch detected: current=$_currentUserId, requested=$userId. Clearing and reloading.',
          tag: 'PointProvider',
        );
        _transactions = [];
        _lastTransactionsHash = null;
        _currentTransactionsPage = 1;
        _totalTransactionPages = 1;
        _hasLoadedForCurrentUser = false;
      }
    }

    // If userId changed, clear old data first (defensive check)
    if (_currentUserId != null && _currentUserId != userId) {
      Logger.info(
        'User changed from $_currentUserId to $userId, clearing old transactions',
        tag: 'PointProvider',
      );
      _transactions = [];
      _currentTransactionsPage = 1;
      _totalTransactionPages = 1;
      _lastTransactionsHash = null;
      _hasLoadedForCurrentUser = false;
    }

    if (isLoadMoreRequest) {
      // Use a dedicated incremental loading flag for pagination UX.
      _isLoadingMore = true;
      if (notifyLoading) {
        notifyListeners();
      }
    } else {
      _setLoading(true, notify: notifyLoading);
    }
    _clearError();

    try {
      List<PointTransaction>? cachedFilteredTransactions;

      // CRITICAL FIX: Clear cache if forceRefresh is true to ensure fresh data
      // This prevents showing stale cached data when user explicitly refreshes
      if (forceRefresh) {
        Logger.info(
          'PointProvider - Force refresh requested, will load fresh data from API',
          tag: 'PointProvider',
        );
        // Clear local transaction cache first to rebuild with latest schema/data.
        await PointService.clearTransactionsCache(userId);
      } else if (_transactions.isEmpty && !isLoadMoreRequest) {
        // Only load cached transactions if we don't have any AND not forcing refresh
        try {
          final cachedTransactions = await PointService.getCachedTransactions(
            userId,
          );
          if (cachedTransactions.isNotEmpty) {
            // BEST PRACTICE: show cached transactions as-is (including pending)
            // so users don't see an empty history while approvals are pending.
            cachedFilteredTransactions = List<PointTransaction>.from(
              cachedTransactions,
            );

            // CRITICAL FIX: Ensure cached transactions are sorted by date (newest first)
            cachedFilteredTransactions.sort(
              (a, b) => b.createdAt.compareTo(a.createdAt),
            );

            // Only update if data is different
            if (!_areTransactionsEqual(
              _transactions,
              cachedFilteredTransactions,
            )) {
              _transactions = cachedFilteredTransactions;
              _currentUserId = userId;
              _notifyListenersDebounced(
                force: true,
              ); // Force immediate update for cached data
              Logger.info(
                'Loaded ${_transactions.length} cached transactions for immediate display (newest: ${_transactions.isNotEmpty ? _transactions.first.createdAt.toString() : "N/A"})',
                tag: 'PointProvider',
              );
            }
          }
        } catch (e) {
          Logger.warning(
            'Error loading cached transactions: $e',
            tag: 'PointProvider',
            error: e,
          );
          // Continue to load from API
        }
      }

      // Load fresh data from API and keep list state in sync.
      final historyResult = await PointService.getPointTransactions(
        userId,
        page: page,
        perPage: perPage,
        rangeDays: rangeDays,
        dateFrom: effectiveFrom,
        dateTo: effectiveTo,
      );
      final transactions = historyResult.transactions;
      _currentTransactionsPage = historyResult.page;
      _transactionsPerPage = historyResult.perPage;
      _totalTransactionPages = historyResult.totalPages;

      Logger.info(
        'PointProvider - API returned ${transactions.length} transactions before filtering',
        tag: 'PointProvider',
      );

      // CRITICAL FIX: Ensure transactions are sorted by date (newest first)
      // API might return transactions in any order, so we must sort them
      final sortedTransactions = List<PointTransaction>.from(transactions)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Log date information for debugging
      if (sortedTransactions.isNotEmpty) {
        final newest = sortedTransactions.first;
        final oldest = sortedTransactions.last;
        Logger.info(
          'PointProvider - Transaction date range: Newest: ${newest.createdAt.toString()} (${newest.id}), Oldest: ${oldest.createdAt.toString()} (${oldest.id})',
          tag: 'PointProvider',
        );
        final now = DateTime.now();
        final newestDiff = newest.createdAt.difference(now).inDays;
        Logger.info(
          'PointProvider - Newest transaction is $newestDiff days ${newestDiff > 0 ? "in the future" : newestDiff < 0 ? "ago" : "today"}',
          tag: 'PointProvider',
        );
      }

      // BEST PRACTICE: show ALL transactions (including pending) in history.
      // Pending transactions are informational and do not affect balance.
      var filteredTransactions = sortedTransactions;

      // Preserve already-known poll details if API row is temporarily missing them.
      filteredTransactions =
          PointService.mergeTransactionsPreservingPollDetails(
        existing: _transactions,
        incoming: filteredTransactions,
      );

      if (isLoadMoreRequest) {
        // Append additional pages while preserving existing enriched rows.
        final existingById = <String, PointTransaction>{
          for (final tx in _transactions) tx.id: tx,
        };
        for (final tx in filteredTransactions) {
          existingById[tx.id] = tx;
        }
        filteredTransactions = existingById.values.toList();
      }

      Logger.info(
        'PointProvider - After filtering: ${filteredTransactions.length} transactions',
        tag: 'PointProvider',
      );

      // CRITICAL FIX: Always update transactions if they're different OR if we got new data from API
      // This ensures UI updates even if the list appears "equal" but came from a fresh API call
      // Also ensure we update if transactions list is empty (to show empty state)
      final shouldUpdate =
          !_areTransactionsEqual(_transactions, filteredTransactions) ||
              forceRefresh ||
              _transactions.isEmpty != filteredTransactions.isEmpty;

      if (shouldUpdate) {
        // CRITICAL FIX: Ensure filtered transactions are sorted by date (newest first)
        // This is a defensive check - they should already be sorted, but ensure it
        final sortedFiltered = List<PointTransaction>.from(filteredTransactions)
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        _transactions = sortedFiltered;
        _currentUserId = userId;
        _notifyListenersDebounced(force: true); // Force immediate update
        Logger.info(
          'PointProvider - Updated transactions list: ${_transactions.length} transactions (${sortedTransactions.length} total from API)',
          tag: 'PointProvider',
        );
        if (_transactions.isNotEmpty) {
          Logger.info(
            'PointProvider - Newest transaction: ${_transactions.first.createdAt.toString()} (ID: ${_transactions.first.id}), Oldest: ${_transactions.last.createdAt.toString()} (ID: ${_transactions.last.id})',
            tag: 'PointProvider',
          );
        }
      } else {
        Logger.info(
          'PointProvider - Transactions unchanged, skipping UI update',
          tag: 'PointProvider',
        );
      }
    } catch (e, stackTrace) {
      Logger.error(
        'Error loading point transactions: $e',
        tag: 'PointProvider',
        error: e,
        stackTrace: stackTrace,
      );
      // Surface actionable error to UI when available (e.g., 401/403/500),
      // so the page doesn't look like a "silent empty history".
      final message = e.toString().replaceFirst('Exception: ', '').trim();
      _setError(
        message.isNotEmpty ? message : 'Failed to load point transactions',
      );
      // If API fails but we have cached transactions, keep showing them
      if (_transactions.isEmpty) {
        try {
          final cachedTransactions = await PointService.getCachedTransactions(
            userId,
          );
          if (cachedTransactions.isNotEmpty) {
            final fallbackTransactions = List<PointTransaction>.from(
              cachedTransactions,
            );

            // Only update if different
            if (!_areTransactionsEqual(_transactions, fallbackTransactions)) {
              _transactions = fallbackTransactions;
              _currentUserId = userId;
              _notifyListenersDebounced(force: true);
              Logger.info(
                'Loaded ${_transactions.length} cached transactions as fallback after API error',
                tag: 'PointProvider',
              );
            }
          } else {
            // No cached transactions either - ensure UI is notified of empty state
            Logger.warning(
              'No transactions found: API failed and no cached transactions available',
              tag: 'PointProvider',
            );
            _transactions = [];
            _currentUserId = userId;
            _notifyListenersDebounced(force: true);
          }
        } catch (cacheError) {
          Logger.error(
            'Error loading cached transactions as fallback: $cacheError',
            tag: 'PointProvider',
            error: cacheError,
          );
          // Even if cache fails, ensure UI is notified
          _transactions = [];
          _currentUserId = userId;
          _notifyListenersDebounced(force: true);
        }
      }
    } finally {
      if (isLoadMoreRequest) {
        _isLoadingMore = false;
        if (notifyLoading) {
          notifyListeners();
        }
      } else {
        _setLoading(false, notify: notifyLoading);
      }
    }
  }

  Future<void> loadMoreTransactions(
    String userId, {
    int rangeDays = 90,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    if (_isLoading || _isLoadingMore || !hasMoreTransactions) {
      return;
    }
    await loadTransactions(
      userId,
      page: _currentTransactionsPage + 1,
      perPage: _transactionsPerPage,
      forceRefresh: false,
      rangeDays: rangeDays,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );
  }

  /// Earn points (e.g., on purchase, signup, review)
  Future<bool> earnPoints({
    required String userId,
    required int points,
    required PointTransactionType type,
    String? description,
    String? orderId,
    DateTime? expiresAt,
  }) async {
    _setLoading(true);
    _clearError();

    try {
      final success = await PointService.earnPoints(
        userId: userId,
        points: points,
        type: type,
        description: description,
        orderId: orderId,
        expiresAt: expiresAt,
      );

      if (success) {
        // Align in-memory balance with local cache immediately (notify inside
        // applyOptimisticBalanceUpdate), then force server reconcile so loadBalance cannot skip.
        final cached = await PointService.getCachedBalance(userId);
        if (cached != null) {
          applyOptimisticBalanceUpdate(
            userId: userId,
            currentBalance: cached.currentBalance,
          );
        } else if (type == PointTransactionType.earn && points > 0) {
          final prior = _balance?.currentBalance ?? 0;
          applyOptimisticBalanceUpdate(
            userId: userId,
            currentBalance: prior + points,
          );
        }

        // Phase 1: Non-blocking reconcile. Optimistic balance update already notified UI.
        unawaited(
          loadBalance(userId, forceRefresh: true, notifyLoading: false),
        );
        unawaited(loadTransactions(userId, notifyLoading: false));
        Logger.info(
          'Points earned successfully: $points points',
          tag: 'PointProvider',
        );

        // Notify user about points earned (explicit API success — not cold-start hydrate).
        if (_balance != null) {
          // PROFESSIONAL FIX: Detect engagement points by checking orderId pattern
          // Engagement points have orderId starting with 'engagement:' (e.g., 'engagement:quiz:123:timestamp')
          final earnOrderId = orderId;
          final isEngagementPoints =
              earnOrderId != null && earnOrderId.startsWith('engagement:');
          // Poll wins: in-app notification only (matches carousel / auto-run poll UX).
          final isPollEngagement =
              earnOrderId != null && earnOrderId.startsWith('engagement:poll:');
          final notificationType = isEngagementPoints
              ? PointNotificationType.engagementEarned
              : PointNotificationType.earned;

          await PointNotificationManager().notifyPointEvent(
            type: notificationType,
            points: points,
            currentBalance: _balance!.currentBalance,
            description: description,
            transactionId: '${DateTime.now().millisecondsSinceEpoch}',
            orderId: earnOrderId,
            userId: userId,
            additionalData: isEngagementPoints
                ? _extractEngagementDataFromOrderId(earnOrderId)
                : null,
            showModalPopup: !isPollEngagement,
            showInAppNotification: true,
            showPushNotification: !isPollEngagement,
          );
        }
      } else {
        _setError('Failed to earn points');
      }

      return success;
    } catch (e, stackTrace) {
      Logger.error(
        'Error earning points: $e',
        tag: 'PointProvider',
        error: e,
        stackTrace: stackTrace,
      );
      _setError('Failed to earn points');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Redeem points (e.g., for discount)
  Future<bool> redeemPoints({
    required String userId,
    required int points,
    String? description,
    String? orderId,
  }) async {
    _setLoading(true);
    _clearError();

    try {
      // Check if user has enough points
      if (currentBalance < points) {
        _setError('Insufficient points. You have $currentBalance points.');
        return false;
      }

      final success = await PointService.redeemPoints(
        userId: userId,
        points: points,
        description: description,
        orderId: orderId,
        waitForSync: orderId != null, // Wait for sync if order ID is provided
      );

      if (success) {
        // Reload balance and transactions
        await loadBalance(userId);
        await loadTransactions(userId);
        Logger.info(
          'Points redeemed successfully: $points points',
          tag: 'PointProvider',
        );

        // Notify user about points redeemed
        if (_balance != null) {
          await PointNotificationManager().notifyPointEvent(
            type: PointNotificationType.redeemed,
            points: points,
            currentBalance: _balance!.currentBalance,
            description: description,
            transactionId: '${DateTime.now().millisecondsSinceEpoch}',
            orderId: orderId,
            userId: userId,
            showModalPopup:
                false, // Don't show modal for redeemed (just notification)
            showInAppNotification: true,
            showPushNotification: true,
          );
        }
      } else {
        _setError('Failed to redeem points');
      }

      return success;
    } catch (e, stackTrace) {
      Logger.error(
        'Error redeeming points: $e',
        tag: 'PointProvider',
        error: e,
        stackTrace: stackTrace,
      );
      _setError('Failed to redeem points');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Extract engagement data from orderId
  /// Engagement orderId format: 'engagement:itemType:itemId:timestamp'
  /// Returns map with itemType and itemId if valid, null otherwise
  Map<String, dynamic>? _extractEngagementDataFromOrderId(String orderId) {
    try {
      if (!orderId.startsWith('engagement:')) {
        return null;
      }

      final parts = orderId.split(':');
      if (parts.length >= 3) {
        return {
          'itemType': parts[1], // e.g., 'quiz', 'poll', 'banner'
          'itemId': parts[2], // Engagement item ID
          if (parts.length >= 4) 'timestamp': parts[3],
        };
      }
      return null;
    } catch (e) {
      Logger.warning(
        'Error extracting engagement data from orderId: $e',
        tag: 'PointProvider',
      );
      return null;
    }
  }

  /// Calculate discount from points
  double calculateDiscountFromPoints(int points) {
    return PointService.calculateDiscountFromPoints(points);
  }

  /// Calculate points needed for discount
  int calculatePointsForDiscount(double discountAmount) {
    return PointService.calculatePointsForDiscount(discountAmount);
  }

  /// Check if user has enough points
  bool hasEnoughPoints(int requiredPoints) {
    return currentBalance >= requiredPoints;
  }

  /// Load cached balance from local storage
  Future<void> _loadCachedBalance({
    String? userId,
    bool preferImmediateNotify = false,
  }) async {
    try {
      final id =
          (userId != null && userId.isNotEmpty) ? userId : _currentUserId;
      if (id == null || id.isEmpty) return;

      final cached = await PointService.getCachedBalance(id);
      if (cached != null) {
        _commitBalance(cached);
        _hasLoadedForCurrentUser = true;
        // Same as API path — initial session hydrate should paint immediately.
        if (preferImmediateNotify && !_sessionInitialBalanceLoadComplete) {
          _debounceTimer?.cancel();
          notifyListeners();
        } else {
          _notifyListenersDebounced();
        }
        Logger.info(
          'Cached point balance loaded: ${_balance?.currentBalance} points',
          tag: 'PointProvider',
        );
      }
    } catch (e) {
      Logger.error(
        'Error loading cached balance: $e',
        tag: 'PointProvider',
        error: e,
      );
    }
  }

  /// Set loading state
  /// OPTIMIZED: Immediate notification for loading state (user feedback)
  void _setLoading(bool loading, {bool notify = true}) {
    _isLoading = loading;
    if (notify) {
      notifyListeners(); // Immediate for loading state
    }
  }

  /// Set error message
  /// OPTIMIZED: Debounced notification for errors
  void _setError(String error) {
    _errorMessage = error;
    _notifyListenersDebounced();
  }

  String _buildBalanceSyncErrorMessage({Object? error}) {
    final status = PointService.lastPointBalanceStatusCode;
    final reason = (PointService.lastPointBalanceFailureMessage ?? '').trim();
    final lowerError = (error?.toString() ?? '').toLowerCase();
    final lowerReason = reason.toLowerCase();

    if (status == 401 || status == 403) {
      return 'Session expired. Please re-login.';
    }
    if (status != null && status >= 500) {
      return 'Server error. Please try again later.';
    }
    final bool timeoutLike = lowerError.contains('timeout') ||
        lowerError.contains('timed out') ||
        lowerReason.contains('timeout') ||
        lowerReason.contains('timed out');
    if (timeoutLike) {
      return 'Connection timeout.';
    }
    if (reason.isNotEmpty) {
      return 'Sync failed: $reason';
    }
    return 'Sync failed: unable to load latest balance';
  }

  /// Clear error message
  void _clearError() {
    _errorMessage = null;
    // No notification needed for clearing error
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounceTimer?.cancel();
    _syncSubscription?.cancel();
    _pointBroadcastSubscription?.cancel();
    super.dispose();
  }
}

class _OptimisticBalanceSnapshot {
  final String refId;
  final String userId;
  final int previousBalance;
  final DateTime appliedAt;

  const _OptimisticBalanceSnapshot({
    required this.refId,
    required this.userId,
    required this.previousBalance,
    required this.appliedAt,
  });
}
