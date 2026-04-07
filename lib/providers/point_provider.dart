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
  }

  // Factory constructor for Provider compatibility
  factory PointProvider() => instance;

  PointBalance? _balance;
  List<PointTransaction> _transactions = [];
  bool _isLoading = false;
  String? _errorMessage;
  StreamSubscription<PointSyncEvent>? _syncSubscription;
  String? _currentUserId;
  bool _hasLoadedForCurrentUser = false;

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
  String? get errorMessage => _errorMessage;
  int get currentBalance => _balance?.currentBalance ?? 0;
  bool get hasPoints => currentBalance > 0;
  String get formattedBalance => _balance?.formattedBalance ?? '0 points';
  DateTime? get lastPushBalanceSnapshotAt => _lastPushBalanceSnapshotAt;

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
        _hasLoadedForCurrentUser = false;
        _lastTransactionsHash = null;
        _lastPushBalanceSnapshotAt = null;
        _balanceNonDowngradeUntil = null;
        _sessionInitialBalanceLoadComplete = false;
        notifyListeners(); // Notify UI immediately that data is cleared
      }

      // Only load if this is a new user or we haven't loaded for this user yet
      if (_currentUserId != userId || !_hasLoadedForCurrentUser) {
        _currentUserId = userId;
        Logger.info(
            'User authenticated, loading point balance for user: $userId',
            tag: 'PointProvider');
        // PROFESSIONAL FIX: Force refresh when user changes to ensure fresh data
        await loadBalance(userId, forceRefresh: _currentUserId != userId);
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
  }

  /// Load point balance for user
  /// If forceRefresh is true, will reload even if already loaded for this user
  /// PROFESSIONAL FIX: Validates user ID and clears old data on user change
  Future<void> loadBalance(String userId, {bool forceRefresh = false}) async {
    // First successful hydrate for this session (startup / login sync), not an in-session earn.
    final bool isInitialLoad = !_sessionInitialBalanceLoadComplete;

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

    _setLoading(true);
    _clearError();
    _currentUserId = userId;

    try {
      // Try to load from API if online
      // OPTIMIZED: Use cached connectivity service
      if (_connectivityService.isConnected) {
        // Load balance from API first (source of truth)
        final balance = await PointService.getPointBalance(userId);
        if (balance != null) {
          // PROFESSIONAL FIX: Don't overwrite with a LOWER balance when we recently
          // applied a poll/push snapshot. Prevents stale API from undoing a poll win.
          final now = DateTime.now();
          final lastSnapshot = _lastPushBalanceSnapshotAt;
          final isRecentSnapshot = lastSnapshot != null &&
              now.difference(lastSnapshot).inSeconds < 8;
          final guardUntil = _balanceNonDowngradeUntil;
          final guardActive =
              guardUntil != null && !now.isAfter(guardUntil);
          final currentFromSnapshot = _balance?.currentBalance ?? 0;
          if ((isRecentSnapshot || guardActive) &&
              currentFromSnapshot > 0 &&
              balance.currentBalance < currentFromSnapshot) {
            Logger.info(
                'Keeping applied snapshot balance $currentFromSnapshot (API returned ${balance.currentBalance})',
                tag: 'PointProvider');
          } else {
            _balance = balance;
            Logger.info(
                'Point balance loaded from API: ${balance.currentBalance} points',
                tag: 'PointProvider');
          }
          _hasLoadedForCurrentUser = true;
          _notifyListenersDebounced();
        } else {
          // If API fails, try cache
          await _loadCachedBalance(userId: userId);
        }
      } else {
        // Load from cache if offline
        await _loadCachedBalance(userId: userId);
      }
    } catch (e, stackTrace) {
      Logger.error('Error loading point balance: $e',
          tag: 'PointProvider', error: e, stackTrace: stackTrace);
      _setError('Failed to load point balance');
      // Try to load from cache on error
      await _loadCachedBalance(userId: userId);
    } finally {
      _setLoading(false);
      if (_balance != null && isInitialLoad) {
        _sessionInitialBalanceLoadComplete = true;
      }
    }
  }

  /// Apply optimistic balance update from in-app events (e.g. poll win).
  /// Does NOT set _lastPushBalanceSnapshotAt, so MainPage can show modal as fallback.
  void applyOptimisticBalanceUpdate({
    required String userId,
    required int currentBalance,
  }) {
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
    // Optimistic updates (e.g. poll win) need immediate UI refresh
    notifyListeners();
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

    _lastPushBalanceSnapshotAt = DateTime.now();
    // Extended window: poll win + deferred loadBalance (4s) + slow API/meta sync.
    _balanceNonDowngradeUntil =
        DateTime.now().add(const Duration(seconds: 35));
    _hasLoadedForCurrentUser = true;
    // PROFESSIONAL FIX: Notify immediately so My PNP card and popup show same balance.
    // Poll/push snapshots are user-critical; 300ms debounce caused balance to lag behind popup.
    notifyListeners();
  }

  /// OPTIMIZED: Debounced notifyListeners to prevent excessive rebuilds
  /// Only notifies if data actually changed
  /// PROFESSIONAL FIX: Include status in hash to detect status changes
  void _notifyListenersDebounced({bool force = false}) {
    if (!force) {
      // Calculate hash of current transactions to detect changes
      // Include status to detect when transactions change from pending to approved
      final currentHash = _transactions.length.hashCode ^
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
      {int page = 1, int perPage = 20, bool forceRefresh = false}) async {
    Logger.info(
        'PointProvider.loadTransactions called: userId=$userId, page=$page, perPage=$perPage, forceRefresh=$forceRefresh, currentUserId=$_currentUserId, hasTransactions=${_transactions.isNotEmpty}',
        tag: 'PointProvider');

    // PROFESSIONAL FIX: Check if userId matches before skipping
    // If userId changed, we need to reload even if transactions exist
    // CRITICAL: Always reload if userId doesn't match, even if transactions exist
    // CRITICAL FIX: Also check if _currentUserId is null (first load) - don't skip in that case
    if (!forceRefresh && _transactions.isNotEmpty && _currentUserId != null) {
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
        _hasLoadedForCurrentUser = false;
      }
    }

    // If userId changed, clear old data first (defensive check)
    if (_currentUserId != null && _currentUserId != userId) {
      Logger.info(
          'User changed from $_currentUserId to $userId, clearing old transactions',
          tag: 'PointProvider');
      _transactions = [];
      _lastTransactionsHash = null;
      _hasLoadedForCurrentUser = false;
    }

    _setLoading(true);
    _clearError();

    try {
      List<PointTransaction>? cachedFilteredTransactions;

      // CRITICAL FIX: Clear cache if forceRefresh is true to ensure fresh data
      // This prevents showing stale cached data when user explicitly refreshes
      if (forceRefresh) {
        Logger.info(
            'PointProvider - Force refresh requested, will load fresh data from API',
            tag: 'PointProvider');
        // Don't load from cache on force refresh - go straight to API
      } else if (_transactions.isEmpty) {
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

      // Now load fresh data from API
      final transactions = await PointService.getPointTransactions(userId,
          page: page, perPage: perPage);

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
      final filteredTransactions = sortedTransactions;

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
      _setLoading(false);
    }
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
        // Reload balance and transactions
        await loadBalance(userId);
        await loadTransactions(userId);
        Logger.info('Points earned successfully: $points points',
            tag: 'PointProvider');

        // Notify user about points earned (explicit API success — not cold-start hydrate).
        if (_balance != null) {
          // PROFESSIONAL FIX: Detect engagement points by checking orderId pattern
          // Engagement points have orderId starting with 'engagement:' (e.g., 'engagement:quiz:123:timestamp')
          final earnOrderId = orderId;
          final isEngagementPoints = earnOrderId != null &&
              earnOrderId.startsWith('engagement:');
          // Poll wins: in-app notification only (matches carousel / auto-run poll UX).
          final isPollEngagement = earnOrderId != null &&
              earnOrderId.startsWith('engagement:poll:');
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
  Future<void> _loadCachedBalance({String? userId}) async {
    try {
      final id =
          (userId != null && userId.isNotEmpty) ? userId : _currentUserId;
      if (id == null || id.isEmpty) return;

      final cached = await PointService.getCachedBalance(id);
      if (cached != null) {
        _balance = cached;
        _hasLoadedForCurrentUser = true;
        _notifyListenersDebounced();
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
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners(); // Immediate for loading state
  }

  /// Set error message
  /// OPTIMIZED: Debounced notification for errors
  void _setError(String error) {
    _errorMessage = error;
    _notifyListenersDebounced();
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
    super.dispose();
  }
}
