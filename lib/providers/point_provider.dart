import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/point_transaction.dart';
import '../services/point_service.dart';
import '../services/point_notification_manager.dart';
import '../utils/logger.dart';
import '../services/connectivity_service.dart';
import '../services/point_sync_telemetry.dart';

/// Point provider for managing point state
/// Handles point balance, transactions, and UI updates
/// Uses singleton pattern to ensure same instance across the app
class PointProvider with ChangeNotifier {
  // Singleton instance
  static PointProvider? _instance;
  static PointProvider get instance {
    _instance ??= PointProvider._internal();
    return _instance!;
  }

  PointProvider._internal() {
    _initialize();
    _syncSubscription = PointSyncTelemetry.events.listen(_handleSyncEvent);
    // Context-free earn/cache updates still reach Home My PNP.
    _pointBroadcastSubscription =
        PointService.pointSyncBroadcast.listen(_onPointSyncBroadcast);
  }

  /// Applies balance from [PointService.pointSyncBroadcast] (e.g. poll win emit).
  /// [applyOptimisticBalanceUpdate] ends with [notifyListeners] so Home My PNP
  /// (Consumer2) rebuilds without a separate StreamBuilder.
  void _onPointSyncBroadcast(PointSyncBroadcast event) {
    Logger.info(
      'DEBUG_SYNC: _onPointSyncBroadcast received userId=${event.userId} '
      'newBalance=${event.newBalance} source=${event.source} '
      '_currentUserId=$_currentUserId',
      tag: 'PointProvider',
    );
    if (event.userId.isEmpty) {
      Logger.info(
        'DEBUG_SYNC: _onPointSyncBroadcast skipped (empty userId)',
        tag: 'PointProvider',
      );
      return;
    }
    if (_currentUserId != null && _currentUserId != event.userId) {
      Logger.info(
        'DEBUG_SYNC: _onPointSyncBroadcast skipped (user mismatch '
        'event=${event.userId} current=$_currentUserId)',
        tag: 'PointProvider',
      );
      return;
    }
    applyOptimisticBalanceUpdate(
      userId: event.userId,
      currentBalance: event.newBalance,
    );
  }

  // Factory constructor for Provider compatibility
  factory PointProvider() => instance;

  PointBalance? _balance;
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

  /// After poll win / push snapshot, do not let [loadBalance] overwrite with a
  /// lower API value until this time (server read replicas / meta lag).
  DateTime? _balanceNonDowngradeUntil;

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
  bool get hasPoints => currentBalance > 0;
  String get formattedBalance => _balance?.formattedBalance ?? '0 points';
  DateTime? get lastPushBalanceSnapshotAt => _lastPushBalanceSnapshotAt;
  String? get syncNoticeMessage => _syncNoticeMessage;

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
      Logger.error('Error initializing point provider: $e',
          tag: 'PointProvider', error: e);
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
            tag: 'PointProvider');
        // Clear old user's data immediately
        _balance = null;
        _transactions = [];
        _currentTransactionsPage = 1;
        _transactionsPerPage = 20;
        _totalTransactionPages = 1;
        _hasLoadedForCurrentUser = false;
        _lastTransactionsHash = null;
        _lastPushBalanceSnapshotAt = null;
        _balanceNonDowngradeUntil = null;
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
            tag: 'PointProvider');
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
            tag: 'PointProvider');
      }
    } else {
      // User logged out - clear state
      final previousUserId = _currentUserId;
      _currentUserId = null;
      _hasLoadedForCurrentUser = false;
      _balance = null;
      _transactions = [];
      _currentTransactionsPage = 1;
      _transactionsPerPage = 20;
      _totalTransactionPages = 1;
      _lastTransactionsHash = null;
      _lastPushBalanceSnapshotAt = null;
      _balanceNonDowngradeUntil = null;
      _sessionInitialBalanceLoadComplete = false;
      notifyListeners();
      Logger.info(
          'User logged out (previous user: $previousUserId), cleared point data',
          tag: 'PointProvider');
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

  /// Load point balance for user
  /// If forceRefresh is true, will reload even if already loaded for this user
  /// PROFESSIONAL FIX: Validates user ID and clears old data on user change
  Future<void> loadBalance(
    String userId, {
    bool forceRefresh = false,
    bool notifyLoading = true,
  }) async {
    // First successful hydrate for this session (startup / login sync), not an in-session earn.
    final bool isInitialLoad = !_sessionInitialBalanceLoadComplete;
    Logger.info(
      'PointProvider.loadBalance start: userId=$userId, forceRefresh=$forceRefresh, '
      'isConnected=${_connectivityService.isConnected}, currentUserId=$_currentUserId, '
      'localBalance=${_balance?.currentBalance}',
      tag: 'PointProvider',
    );
    if (forceRefresh) {
      Logger.debug(
        'Forcing balance refresh due to user switch or explicit request '
        '(loadBalance forceRefresh=true, userId=$userId)',
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
        Logger.info('Balance already loaded for user $userId, skipping',
            tag: 'PointProvider');
        if (isInitialLoad) {
          _sessionInitialBalanceLoadComplete = true;
        }
        return;
      } else if (_currentUserId != null && _currentUserId != userId) {
        // User ID mismatch - this should not happen if handleAuthStateChange is called correctly
        // But handle it gracefully by clearing and reloading
        Logger.warning(
            'User ID mismatch detected: current=$_currentUserId, requested=$userId. Clearing and reloading.',
            tag: 'PointProvider');
        _balance = null;
        _hasLoadedForCurrentUser = false;
      }
    }

    // If userId changed, clear old data first (defensive check)
    if (_currentUserId != null && _currentUserId != userId) {
      Logger.info(
          'User changed from $_currentUserId to $userId, clearing old point balance',
          tag: 'PointProvider');
      _balance = null;
      _hasLoadedForCurrentUser = false;
    }

    _setLoading(true, notify: notifyLoading);
    _clearError();
    _currentUserId = userId;

    try {
      // Try to load from API if online
      // OPTIMIZED: Use cached connectivity service
      if (_connectivityService.isConnected) {
        // Load balance from API first (source of truth)
        final balance = await PointService.getPointBalance(
          userId,
          cacheBypassTimestampMs: DateTime.now().millisecondsSinceEpoch,
        );
        if (balance != null) {
          // PROFESSIONAL FIX: Don't overwrite with a LOWER balance when we recently
          // applied a poll/push snapshot. Prevents stale API from undoing a poll win.
          final now = DateTime.now();
          final lastSnapshot = _lastPushBalanceSnapshotAt;
          final isRecentSnapshot = lastSnapshot != null &&
              now.difference(lastSnapshot).inSeconds < 8;
          final guardUntil = _balanceNonDowngradeUntil;
          final guardActive = guardUntil != null && !now.isAfter(guardUntil);
          final currentFromSnapshot = _balance?.currentBalance ?? 0;
          final bool snapshotWouldPreferLocal =
              (isRecentSnapshot || guardActive) &&
                  currentFromSnapshot > 0 &&
                  balance.currentBalance < currentFromSnapshot;
          // Safety check: even during forceRefresh, do not downgrade to a lower API
          // value while snapshot guard window is active (likely stale read).
          final bool keepLocalSnapshotBecauseStaleApi =
              snapshotWouldPreferLocal;

          if (keepLocalSnapshotBecauseStaleApi) {
            Logger.info(
              'Keeping applied snapshot balance $currentFromSnapshot '
              '(API returned ${balance.currentBalance}, forceRefresh=$forceRefresh)',
              tag: 'PointProvider',
            );
          } else {
            if (forceRefresh && snapshotWouldPreferLocal) {
              Logger.info(
                'Forcing balance refresh due to user switch or explicit request — '
                'applying API balance ${balance.currentBalance} '
                '(snapshot guard bypassed; local snapshot was $currentFromSnapshot)',
                tag: 'PointProvider',
              );
            }
            _balance = balance;
            Logger.info(
              'Point balance loaded from API: ${balance.currentBalance} points',
              tag: 'PointProvider',
            );
          }
          _hasLoadedForCurrentUser = true;
          // Balance must hit My PNP immediately after API read (do not wait for transactions
          // or debounce — poll-win UX depends on this).
          _debounceTimer?.cancel();
          notifyListeners();
        } else {
          if (forceRefresh) {
            // Force refresh must trust server as source of truth; do not reuse stale cache.
            Logger.error(
              'PointProvider.loadBalance forceRefresh API returned null. '
              'Clearing in-memory balance and skipping cache fallback for userId=$userId',
              tag: 'PointProvider',
            );
            _balance = null;
            _hasLoadedForCurrentUser = false;
            _setError(_buildBalanceSyncErrorMessage());
            _debounceTimer?.cancel();
            notifyListeners();
          } else {
            Logger.warning(
              'PointProvider.loadBalance API returned null, entering cache fallback '
              'for userId=$userId',
              tag: 'PointProvider',
            );
            await _loadCachedBalance(
              userId: userId,
              preferImmediateNotify: isInitialLoad,
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
      Logger.error('Error loading point balance: $e',
          tag: 'PointProvider', error: e, stackTrace: stackTrace);
      if (forceRefresh) {
        Logger.error(
          'PointProvider.loadBalance forceRefresh threw error, skipping cache fallback '
          'and clearing balance for userId=$userId',
          tag: 'PointProvider',
        );
        _balance = null;
        _hasLoadedForCurrentUser = false;
        _setError(_buildBalanceSyncErrorMessage(error: e));
        _debounceTimer?.cancel();
        notifyListeners();
      } else {
        _setError('Failed to load point balance');
        Logger.warning(
          'PointProvider.loadBalance catch branch entering cache fallback '
          'for userId=$userId',
          tag: 'PointProvider',
        );
        await _loadCachedBalance(
          userId: userId,
          preferImmediateNotify: isInitialLoad,
        );
      }
    } finally {
      _setLoading(false, notify: notifyLoading);
      if (_balance != null && isInitialLoad) {
        _sessionInitialBalanceLoadComplete = true;
      }
    }
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
      await loadBalance(userId, forceRefresh: forceRefresh);
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
      _balance = PointBalance(
        userId: previous.userId,
        currentBalance: previous.currentBalance + pointsToAdd,
        lifetimeEarned: previous.lifetimeEarned,
        lifetimeRedeemed: previous.lifetimeRedeemed,
        lifetimeExpired: previous.lifetimeExpired,
        lastUpdated: DateTime.now(),
        pointsExpireAt: previous.pointsExpireAt,
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
    _balance = PointBalance(
      userId: previous.userId,
      currentBalance: latest.previousBalance,
      lifetimeEarned: previous.lifetimeEarned,
      lifetimeRedeemed: previous.lifetimeRedeemed,
      lifetimeExpired: previous.lifetimeExpired,
      lastUpdated: DateTime.now(),
      pointsExpireAt: previous.pointsExpireAt,
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
      _balance = null;
      _transactions = [];
      _lastTransactionsHash = null;
      _hasLoadedForCurrentUser = false;
    }
    _currentUserId = userId;
    final previous = _balance;
    _balance = PointBalance(
      userId: userId,
      currentBalance: currentBalance,
      lifetimeEarned: previous?.lifetimeEarned ?? 0,
      lifetimeRedeemed: previous?.lifetimeRedeemed ?? 0,
      lifetimeExpired: previous?.lifetimeExpired ?? 0,
      lastUpdated: DateTime.now(),
      pointsExpireAt: previous?.pointsExpireAt,
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

  /// Apply point balance snapshot coming from push notification payload.
  ///
  /// This provides instant UI updates (no manual refresh) while the app later
  /// reconciles via `loadBalance()` / `loadTransactions()` as needed.
  void applyRemoteBalanceSnapshot({
    required String userId,
    required int currentBalance,
  }) {
    // Defensive: handle user switching.
    if (_currentUserId != null && _currentUserId != userId) {
      _balance = null;
      _transactions = [];
      _lastTransactionsHash = null;
      _hasLoadedForCurrentUser = false;
    }

    _currentUserId = userId;

    final previous = _balance;
    _balance = PointBalance(
      userId: userId,
      currentBalance: currentBalance,
      lifetimeEarned: previous?.lifetimeEarned ?? 0,
      lifetimeRedeemed: previous?.lifetimeRedeemed ?? 0,
      lifetimeExpired: previous?.lifetimeExpired ?? 0,
      lastUpdated: DateTime.now(),
      pointsExpireAt: previous?.pointsExpireAt,
    );

    // Prevent stale API overwrite: extend non-downgrade window on every remote snapshot.
    final DateTime snapshotClock = DateTime.now();
    _lastPushBalanceSnapshotAt = snapshotClock;
    _balanceNonDowngradeUntil = snapshotClock.add(const Duration(seconds: 35));
    _hasLoadedForCurrentUser = true;
    // Server-confirmed snapshot supersedes pending optimistic deltas.
    _optimisticSnapshots.removeWhere((_, s) => s.userId == userId);
    // PROFESSIONAL FIX: Notify immediately so My PNP card and popup show same balance.
    // Poll/push snapshots are user-critical; 300ms debounce caused balance to lag behind popup.
    notifyListeners();
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
      List<PointTransaction> a, List<PointTransaction> b) {
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
  Future<void> loadTransactions(String userId,
      {int page = 1,
      int perPage = 20,
      bool forceRefresh = false,
      int rangeDays = 90,
      DateTime? dateFrom,
      DateTime? dateTo,
      bool notifyLoading = true}) async {
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
        tag: 'PointProvider');

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
        Logger.info('Transactions already loaded for user $userId, skipping',
            tag: 'PointProvider');
        return;
      } else if (_currentUserId != null && _currentUserId != userId) {
        // User ID mismatch - clear old data
        Logger.warning(
            'User ID mismatch detected: current=$_currentUserId, requested=$userId. Clearing and reloading.',
            tag: 'PointProvider');
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
          tag: 'PointProvider');
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
            tag: 'PointProvider');
        // Clear local transaction cache first to rebuild with latest schema/data.
        await PointService.clearTransactionsCache(userId);
      } else if (_transactions.isEmpty && !isLoadMoreRequest) {
        // Only load cached transactions if we don't have any AND not forcing refresh
        try {
          final cachedTransactions =
              await PointService.getCachedTransactions(userId);
          if (cachedTransactions.isNotEmpty) {
            // BEST PRACTICE: show cached transactions as-is (including pending)
            // so users don't see an empty history while approvals are pending.
            cachedFilteredTransactions =
                List<PointTransaction>.from(cachedTransactions);

            // CRITICAL FIX: Ensure cached transactions are sorted by date (newest first)
            cachedFilteredTransactions
                .sort((a, b) => b.createdAt.compareTo(a.createdAt));

            // Only update if data is different
            if (!_areTransactionsEqual(
                _transactions, cachedFilteredTransactions)) {
              _transactions = cachedFilteredTransactions;
              _currentUserId = userId;
              _notifyListenersDebounced(
                  force: true); // Force immediate update for cached data
              Logger.info(
                  'Loaded ${_transactions.length} cached transactions for immediate display (newest: ${_transactions.isNotEmpty ? _transactions.first.createdAt.toString() : "N/A"})',
                  tag: 'PointProvider');
            }
          }
        } catch (e) {
          Logger.warning('Error loading cached transactions: $e',
              tag: 'PointProvider', error: e);
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
          tag: 'PointProvider');

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
            tag: 'PointProvider');
        final now = DateTime.now();
        final newestDiff = newest.createdAt.difference(now).inDays;
        Logger.info(
            'PointProvider - Newest transaction is $newestDiff days ${newestDiff > 0 ? "in the future" : newestDiff < 0 ? "ago" : "today"}',
            tag: 'PointProvider');
      }

      // BEST PRACTICE: show ALL transactions (including pending) in history.
      // Pending transactions are informational and do not affect balance.
      var filteredTransactions = sortedTransactions;

      // Preserve already-known poll details if API row is temporarily missing them.
      filteredTransactions = _mergeTransactionsPreservingPollDetails(
        current: _transactions,
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
          tag: 'PointProvider');

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
            tag: 'PointProvider');
        if (_transactions.isNotEmpty) {
          Logger.info(
              'PointProvider - Newest transaction: ${_transactions.first.createdAt.toString()} (ID: ${_transactions.first.id}), Oldest: ${_transactions.last.createdAt.toString()} (ID: ${_transactions.last.id})',
              tag: 'PointProvider');
        }
      } else {
        Logger.info(
            'PointProvider - Transactions unchanged, skipping UI update',
            tag: 'PointProvider');
      }
    } catch (e, stackTrace) {
      Logger.error('Error loading point transactions: $e',
          tag: 'PointProvider', error: e, stackTrace: stackTrace);
      // Surface actionable error to UI when available (e.g., 401/403/500),
      // so the page doesn't look like a "silent empty history".
      final message = e.toString().replaceFirst('Exception: ', '').trim();
      _setError(
          message.isNotEmpty ? message : 'Failed to load point transactions');
      // If API fails but we have cached transactions, keep showing them
      if (_transactions.isEmpty) {
        try {
          final cachedTransactions =
              await PointService.getCachedTransactions(userId);
          if (cachedTransactions.isNotEmpty) {
            final fallbackTransactions =
                List<PointTransaction>.from(cachedTransactions);

            // Only update if different
            if (!_areTransactionsEqual(_transactions, fallbackTransactions)) {
              _transactions = fallbackTransactions;
              _currentUserId = userId;
              _notifyListenersDebounced(force: true);
              Logger.info(
                  'Loaded ${_transactions.length} cached transactions as fallback after API error',
                  tag: 'PointProvider');
            }
          } else {
            // No cached transactions either - ensure UI is notified of empty state
            Logger.warning(
                'No transactions found: API failed and no cached transactions available',
                tag: 'PointProvider');
            _transactions = [];
            _currentUserId = userId;
            _notifyListenersDebounced(force: true);
          }
        } catch (cacheError) {
          Logger.error(
              'Error loading cached transactions as fallback: $cacheError',
              tag: 'PointProvider',
              error: cacheError);
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

  List<PointTransaction> _mergeTransactionsPreservingPollDetails({
    required List<PointTransaction> current,
    required List<PointTransaction> incoming,
  }) {
    final currentById = <String, PointTransaction>{
      for (final tx in current) tx.id: tx,
    };

    return incoming.map((tx) {
      final old = currentById[tx.id];
      if (old == null) return tx;
      if (tx.pollDetails != null) return tx;
      if (old.pollDetails == null) return tx;
      return tx.copyWith(pollDetails: old.pollDetails);
    }).toList();
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
          loadBalance(
            userId,
            forceRefresh: true,
            notifyLoading: false,
          ),
        );
        unawaited(
          loadTransactions(
            userId,
            notifyLoading: false,
          ),
        );
        Logger.info('Points earned successfully: $points points',
            tag: 'PointProvider');

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
      Logger.error('Error earning points: $e',
          tag: 'PointProvider', error: e, stackTrace: stackTrace);
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
        Logger.info('Points redeemed successfully: $points points',
            tag: 'PointProvider');

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
      Logger.error('Error redeeming points: $e',
          tag: 'PointProvider', error: e, stackTrace: stackTrace);
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
      Logger.warning('Error extracting engagement data from orderId: $e',
          tag: 'PointProvider');
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
        _balance = cached;
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
      Logger.error('Error loading cached balance: $e',
          tag: 'PointProvider', error: e);
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
