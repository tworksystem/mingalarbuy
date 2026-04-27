import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ecommerce_int2/providers/point_provider.dart';
import 'package:ecommerce_int2/providers/auth_provider.dart';
import 'package:ecommerce_int2/models/point_transaction.dart';
import 'package:ecommerce_int2/app_properties.dart';
import 'package:ecommerce_int2/services/point_service.dart';
import 'package:ecommerce_int2/providers/exchange_settings_provider.dart';
import 'package:ecommerce_int2/widgets/modern_loading_indicator.dart';
import 'package:ecommerce_int2/utils/logger.dart';
import 'package:intl/intl.dart';

class PointHistoryPage extends StatefulWidget {
  const PointHistoryPage({super.key});

  @override
  _PointHistoryPageState createState() => _PointHistoryPageState();
}

/// Backend Transaction Type for filtering
/// Represents specific transaction types from backend (Lucky Box, Exchange Request, etc.)
enum BackendTransactionType {
  luckyBox,
  exchangeRequest,
  quizReward,
  codeRedemption,
  manualReward,
  manualPoint,
  order,
  other,
}

// TODO: Loyalty Analytics - Commented out temporarily, will be added back later
// enum AnalyticsTimePeriod {
//   last7Days,
//   last30Days,
//   last6Months,
//   last1Year,
//   allTime,
// }

class _PointHistoryPageState extends State<PointHistoryPage> {
  // Warning banner color constants - using const Color values for type safety
  // These match Material Design color swatches but are non-nullable for better type safety
  static const Color _warningBackgroundColor = Color(0xFFFFF3E0); // Orange 50
  static const Color _warningBorderColor = Color(0xFFFFB74D); // Orange 300
  static const Color _warningIconColor = Color(0xFFF57C00); // Orange 700
  static const Color _warningTitleColor = Color(0xFFE65100); // Orange 900
  static const Color _warningTextColor = Color(0xFFEF6C00); // Orange 800
  static const Color _expiringBadgeBackgroundColor =
      Color(0xFFFFE0B2); // Orange 100
  static const Color _expiringBadgeTextColor = Color(0xFFE65100); // Orange 900
  static const Color _pendingBorderColor = Color(0xFFFFC107); // Amber 400

  PointTransactionType? _selectedFilter;
  BackendTransactionType? _selectedBackendFilter;
  List<PointTransaction> _expiringSoon = [];
  DateTimeRange? _selectedDateRange;
  // TODO: Loyalty Analytics - Commented out temporarily, will be added back later
  // AnalyticsTimePeriod _analyticsTimePeriod = AnalyticsTimePeriod.last6Months;

  bool _isInitialLoadComplete = false;
  bool _isLoading = false;

  // Store all unique transaction types from cached data for filter chips
  Set<PointTransactionType> _allTransactionTypes = {};

  // Store all unique backend transaction types from cached data
  Set<BackendTransactionType> _allBackendTransactionTypes = {};

  // PROFESSIONAL FIX: Track last user ID to detect account switches
  String? _lastUserId;

  @override
  void initState() {
    super.initState();
    // Load point balance and transactions immediately when page opens
    // PointProvider now loads cached transactions first for immediate display
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isInitialLoadComplete && !_isLoading) {
        _loadPoints();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // PROFESSIONAL FIX: Detect user account switches and reset page state
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.isAuthenticated && authProvider.user != null) {
      final currentUserId = authProvider.user!.id.toString();
      if (_lastUserId != null && _lastUserId != currentUserId) {
        // User account changed - reset page state
        Logger.info(
            'PointHistoryPage - User account changed from $_lastUserId to $currentUserId, resetting state',
            tag: 'PointHistoryPage');
        setState(() {
          _isInitialLoadComplete = false;
          _isLoading = false;
          _allTransactionTypes.clear();
          _allBackendTransactionTypes.clear();
        });
        _lastUserId = currentUserId;
        // Reload points for new user
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_isLoading) {
            _loadPoints();
          }
        });
      } else {
        _lastUserId = currentUserId;
        // CRITICAL FIX:
        // When this page first opens, AuthProvider may still be hydrating `user`.
        // If `_loadPoints()` ran earlier while `user == null`, it would return early
        // and never retry. Ensure we kick off the initial load as soon as `user`
        // becomes available.
        if (!_isInitialLoadComplete && !_isLoading) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_isLoading && !_isInitialLoadComplete) {
              _loadPoints();
            }
          });
        }
      }
    } else if (_lastUserId != null) {
      // User logged out
      _lastUserId = null;
      setState(() {
        _isInitialLoadComplete = false;
        _isLoading = false;
        _allTransactionTypes.clear();
        _allBackendTransactionTypes.clear();
      });
    }
  }

  /// Helper method to parse balance value from string
  /// Handles various formats: "100", "100 points", "0", etc.
  int _parseBalanceValue(String? value) {
    if (value == null || value.isEmpty || value.trim().isEmpty) {
      return 0;
    }
    final trimmed = value.trim();
    // Try parsing as integer first
    final parsedInt = int.tryParse(trimmed);
    if (parsedInt != null) {
      return parsedInt;
    }
    // Try extracting first number sequence (handles "100 points", etc.)
    final match = RegExp(r'\d+').firstMatch(trimmed);
    if (match != null) {
      return int.tryParse(match.group(0)!) ?? 0;
    }
    return 0;
  }

  Future<void> _loadPoints({bool forceRefresh = false}) async {
    // PROFESSIONAL FIX: Allow refresh even if loading, if forceRefresh is true
    // This ensures pull-to-refresh always works even during initial load
    if (_isLoading && !forceRefresh)
      return; // Prevent concurrent loads (unless forcing refresh)

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final pointProvider = Provider.of<PointProvider>(context, listen: false);

    if (!authProvider.isAuthenticated || authProvider.user == null) {
      return;
    }

    final userId = authProvider.user!.id.toString();

    // PROFESSIONAL FIX: Check if user changed - if so, reset and reload
    if (_lastUserId != null && _lastUserId != userId) {
      Logger.info(
          'PointHistoryPage - User changed during load, resetting and reloading',
          tag: 'PointHistoryPage');
      setState(() {
        _isInitialLoadComplete = false;
        _allTransactionTypes.clear();
        _allBackendTransactionTypes.clear();
      });
      _lastUserId = userId;
    } else {
      _lastUserId = userId;
    }

    // PROFESSIONAL FIX: Skip if already loaded for current user, UNLESS forceRefresh is true
    // This allows pull-to-refresh to always refresh data even if already loaded
    if (!forceRefresh && _isInitialLoadComplete && _lastUserId == userId) {
      Logger.info(
          'PointHistoryPage - Already loaded for user $userId, skipping (use forceRefresh: true to reload)',
          tag: 'PointHistoryPage');
      return;
    }

    // PROFESSIONAL FIX: When forceRefresh is true, ensure we reset loading state properly
    // This ensures the UI shows loading indicator during refresh
    if (mounted) {
      setState(() {
        _isLoading = true;
        // When force refreshing, temporarily reset _isInitialLoadComplete to ensure fresh load
        if (forceRefresh) {
          Logger.info(
              'PointHistoryPage - Force refresh requested, reloading all data',
              tag: 'PointHistoryPage');
        }
      });
    }

    try {
      // PROFESSIONAL FIX: Refresh user data FIRST to ensure custom fields are available immediately
      // This ensures my_point, my_points, and points_balance are available for initial render
      // Run in parallel with transaction loading for better performance
      final refreshUserFuture = authProvider.refreshUser().catchError((e) {
        Logger.warning('PointHistoryPage - Failed to refresh user data: $e',
            tag: 'PointHistoryPage', error: e);
        // Continue even if refresh fails - we still have PointProvider balance
        return null;
      });

      // OPTIMIZED: Single coordinated load instead of multiple redundant calls
      // Load transactions (will load cached first, then API)
      // IMPORTANT: Load a large batch (200) to ensure we capture all transaction types
      // for dynamic filter chip generation, not just the first page
      final loadTransactionsFuture = pointProvider.loadTransactions(
        userId,
        page: 1,
        perPage: 200, // Load more transactions to get all unique types
        forceRefresh: true,
      );

      // Load balance from PointProvider (primary source) in parallel
      // This will load from API if online (which loads cache first internally), or cache if offline
      final loadBalanceFuture =
          pointProvider.loadBalance(userId, forceRefresh: true);

      // Wait for all critical data loads to complete
      await Future.wait([
        refreshUserFuture,
        loadTransactionsFuture,
        loadBalanceFuture,
      ]);

      Logger.info(
          'PointHistoryPage - All data loaded: user refreshed, transactions loaded, balance loaded',
          tag: 'PointHistoryPage');

      // PROFESSIONAL FIX: Trigger rebuild after all data loads to update UI with latest balance
      // Consumer2 will listen to AuthProvider and PointProvider changes, but setState ensures immediate update
      // This is essential because the balance display depends on user customFields from AuthProvider
      // and balance from PointProvider - both need to be refreshed
      if (mounted) {
        setState(() {
          // Force UI rebuild to pick up latest balance from both AuthProvider and PointProvider
          // The empty setState is intentional - it forces a rebuild which will read fresh data
          // from the providers via Consumer2 in the build method
        });
      }

      // PROFESSIONAL FIX: Explicitly notify listeners to ensure UI updates
      // This ensures that even if setState doesn't trigger, the providers notify the UI
      // This is especially important for pull-to-refresh scenarios
      if (mounted) {
        // Trigger a microtask to ensure providers have finished updating
        await Future.microtask(() {
          if (mounted) {
            // Force rebuild by updating a dummy state variable
            // This ensures Consumer2 picks up the latest provider values
            setState(() {
              // This will trigger Consumer2 to rebuild with latest provider data
            });
          }
        });
      }

      // Check for expired points and load expiring soon points
      await PointService.checkAndMarkExpiredPoints(userId);
      final expiring = await PointService.getPointsExpiringSoon(userId);

      // Load ALL transactions from API (all pages) to get all unique types
      // This ensures filter chips show all available types, not just those in current page
      // We use getAllPointTransactions which loads all pages automatically
      List<PointTransaction> allApiTransactions = [];
      try {
        Logger.info(
          'Loading ALL transactions from API to get all unique types for filter chips',
          tag: 'PointHistoryPage',
        );
        allApiTransactions = await PointService.getAllPointTransactions(userId);
        Logger.info(
          'Successfully loaded ${allApiTransactions.length} transactions from API',
          tag: 'PointHistoryPage',
        );
      } catch (e) {
        Logger.warning(
          'Error loading all transactions from API: $e. Falling back to cached transactions.',
          tag: 'PointHistoryPage',
        );
        // Fallback to cached transactions if API fails
        allApiTransactions = await PointService.getCachedTransactions(userId);
      }

      // Get unique transaction types from all loaded transactions
      final allTypes = allApiTransactions.map((t) => t.type).toSet();

      // Get unique backend transaction types from orderId and description
      final allBackendTypes = <BackendTransactionType>{};
      for (final transaction in allApiTransactions) {
        final backendType = _detectBackendTransactionType(transaction);
        allBackendTypes.add(backendType);
      }

      Logger.info(
        'Loaded ${allApiTransactions.length} total transactions for filter types',
        tag: 'PointHistoryPage',
      );
      Logger.info(
        'Found ${allTypes.length} unique transaction types: ${allTypes.map((t) => t.toValue()).join(", ")}',
        tag: 'PointHistoryPage',
      );
      Logger.info(
        'Found ${allBackendTypes.length} unique backend transaction types: ${allBackendTypes.map((t) => _getBackendTypeLabel(t)).join(", ")}',
        tag: 'PointHistoryPage',
      );

      // Log each transaction type count for debugging
      for (final type in allTypes) {
        final count = allApiTransactions.where((t) => t.type == type).length;
        Logger.info(
          '  - ${type.toValue()}: $count transactions',
          tag: 'PointHistoryPage',
        );
      }

      // Log each backend transaction type count for debugging
      for (final type in allBackendTypes) {
        final count = allApiTransactions
            .where((t) => _detectBackendTransactionType(t) == type)
            .length;
        Logger.info(
          '  - ${_getBackendTypeLabel(type)}: $count transactions',
          tag: 'PointHistoryPage',
        );
      }

      if (mounted) {
        setState(() {
          _expiringSoon = expiring;
          _allTransactionTypes = allTypes;
          _allBackendTransactionTypes = allBackendTypes;
          _isInitialLoadComplete = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      Logger.error('Error loading points in PointHistoryPage: $e',
          tag: 'PointHistoryPage', error: e);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isInitialLoadComplete =
              true; // Mark as complete even on error to prevent retry loops
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0.0,
        iconTheme: IconThemeData(color: darkGrey),
        title: Text(
          'Point History',
          style: TextStyle(
            color: darkGrey,
            fontWeight: FontWeight.w500,
            fontSize: 18.0,
          ),
        ),
        // TODO: Loyalty Analytics - Commented out temporarily, will be added back later
        // actions: [
        //   IconButton(
        //     icon: Icon(Icons.insights_outlined, color: darkGrey),
        //     tooltip: 'Analytics',
        //     onPressed: () {
        //       final transactions =
        //           Provider.of<PointProvider>(context, listen: false)
        //               .transactions;
        //       _showAnalytics(context, transactions);
        //     },
        //   ),
        // ],
      ),
      body: Consumer2<PointProvider, AuthProvider>(
        builder: (context, pointProvider, authProvider, child) {
          // PROFESSIONAL FIX: Listen to both PointProvider and AuthProvider
          // This ensures UI updates when:
          // 1. PointProvider balance changes (from API/cache)
          // 2. AuthProvider user data changes (after refreshUser in _loadPoints)
          // Without listening to AuthProvider, balance won't update after refreshUser()
          if (!authProvider.isAuthenticated || authProvider.user == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Please login to view your points',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            );
          }

          final balance = pointProvider.balance;
          final transactions = pointProvider.transactions;

          // Check if we have any balance data to display (from any source)
          // This allows us to show data immediately even if PointProvider is still loading
          final hasBalanceData = balance != null ||
              authProvider.user!.customFields.containsKey('points_balance') ||
              authProvider.user!.customFields.containsKey('my_point') ||
              authProvider.user!.customFields.containsKey('my_points');

          // Only show loading indicator if we don't have any balance data yet
          // This ensures users see their balance immediately from cached/user data
          if (pointProvider.isLoading &&
              !hasBalanceData &&
              transactions.isEmpty) {
            return Center(
              child: ModernLoadingIndicator(
                size: 50,
                color: mediumYellow,
              ),
            );
          }

          // PROFESSIONAL FIX: Use proper fallback hierarchy for point balance
          // Priority 1: PointProvider balance (most reliable, comes from API)
          // Priority 2: points_balance from user custom fields (backend value)
          // Priority 3: my_point/my_points from user custom fields (legacy field)
          // This ensures we always show the most accurate balance available

          // Get balance from PointProvider (primary source)
          final balanceFromProvider = balance?.currentBalance ?? 0;

          // Get points_balance from user custom fields (secondary source)
          final pointsBalanceValue =
              authProvider.user!.customFields['points_balance'];

          // Get my_point value from user custom fields (tertiary source)
          final myPointValue = authProvider.user!.customFields['my_point'] ??
              authProvider.user!.customFields['my_points'] ??
              authProvider.user!.customFields['My Point Value'];

          // Parse values from different sources
          final balanceFromPointsBalance =
              _parseBalanceValue(pointsBalanceValue);
          final balanceFromMyPoint = _parseBalanceValue(myPointValue);

          // PROFESSIONAL FIX: Use proper priority hierarchy matching main_page.dart logic
          // Priority 1: my_point/my_points from user custom fields (preferred for display)
          // Priority 2: points_balance from user custom fields (backend value)
          // Priority 3: PointProvider balance (fallback, most reliable API source)
          // This ensures we show user's balance immediately from custom fields before API loads
          int myPointBalance = 0;
          String balanceSource = 'default';

          // Priority 1: Check my_point/my_points first (matching main_page.dart behavior)
          // Use if field exists and is not empty (allow 0 as valid value - user might have 0 points)
          if (myPointValue != null && myPointValue.isNotEmpty) {
            myPointBalance = balanceFromMyPoint;
            balanceSource = 'my_point';
            Logger.info(
                'PointHistoryPage - Using my_point: $myPointBalance (raw: "$myPointValue", parsed: $balanceFromMyPoint)',
                tag: 'PointHistoryPage');
          }
          // Priority 2: Check points_balance from user custom fields
          // Use if field exists and is not empty (allow 0 as valid value)
          else if (pointsBalanceValue != null &&
              pointsBalanceValue.isNotEmpty) {
            myPointBalance = balanceFromPointsBalance;
            balanceSource = 'points_balance';
            Logger.info(
                'PointHistoryPage - Using points_balance: $myPointBalance (raw: "$pointsBalanceValue", parsed: $balanceFromPointsBalance)',
                tag: 'PointHistoryPage');
          }
          // Priority 3: Use PointProvider balance (API source - most reliable)
          // Use it if balance object exists, even if value is 0 (0 is valid)
          else if (balance != null) {
            myPointBalance = balanceFromProvider;
            balanceSource = 'PointProvider';
            Logger.info(
                'PointHistoryPage - Using PointProvider balance: $myPointBalance',
                tag: 'PointHistoryPage');
          }
          // Last resort: use maximum of all parsed values
          // This handles edge cases where values might be inconsistent
          else {
            myPointBalance = [
              balanceFromProvider,
              balanceFromPointsBalance,
              balanceFromMyPoint,
            ].reduce((a, b) => a > b ? a : b);
            balanceSource = 'maximum';
            Logger.warning(
                'PointHistoryPage - Using maximum available balance: $myPointBalance (PointProvider: $balanceFromProvider, points_balance: $balanceFromPointsBalance, my_point: $balanceFromMyPoint)',
                tag: 'PointHistoryPage');
          }

          // Additional comprehensive logging for debugging
          Logger.info('PointHistoryPage - Balance determination summary:',
              tag: 'PointHistoryPage');
          Logger.info(
              '  - PointProvider: $balanceFromProvider (object: ${balance != null ? "exists" : "null"})',
              tag: 'PointHistoryPage');
          Logger.info(
              '  - points_balance: $balanceFromPointsBalance (raw: "${pointsBalanceValue ?? "null"}")',
              tag: 'PointHistoryPage');
          Logger.info(
              '  - my_point: $balanceFromMyPoint (raw: "${myPointValue ?? "null"}")',
              tag: 'PointHistoryPage');
          Logger.info(
              '  - Final balance: $myPointBalance (source: $balanceSource)',
              tag: 'PointHistoryPage');

          // PROFESSIONAL FIX: Use RefreshIndicator to wrap entire page for pull-to-refresh
          // This allows users to refresh balance and transactions by pulling from anywhere
          return RefreshIndicator(
            onRefresh: () => _loadPoints(forceRefresh: true),
            color: mediumYellow,
            child: CustomScrollView(
              slivers: [
                // Expiration warning banner
                if (_expiringSoon.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _warningBackgroundColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _warningBorderColor),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: _warningIconColor,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Points Expiring Soon!',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: _warningTitleColor,
                                  ),
                                ),
                                Text(
                                  'You have ${_expiringSoon.length} transaction(s) expiring within 30 days',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: _warningTextColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Point balance card with Exchange button
                SliverToBoxAdapter(
                  child: Container(
                    margin: EdgeInsets.all(16),
                    padding: EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [mediumYellow, darkYellow],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: mediumYellow.withOpacity(0.3),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.stars,
                              color: Colors.white,
                              size: 24,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'My PNP',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Text(
                          '$myPointBalance PNP',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 16),
                        // Exchange button
                        if (myPointBalance > 0)
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => _showPointExchangeDialog(
                                context,
                                authProvider,
                                myPointBalance,
                              ),
                              icon: Icon(Icons.swap_horiz, color: mediumYellow),
                              label: Text(
                                'Exchange (လှဲလယ်ရန်)',
                                style: TextStyle(
                                  color: darkGrey,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 2,
                              ),
                            ),
                          ),
                        if (balance != null) ...[
                          SizedBox(height: 16),
                          Divider(color: Colors.white30, thickness: 1),
                          SizedBox(height: 16),
                          Wrap(
                            alignment: WrapAlignment.spaceAround,
                            spacing: 16,
                            runSpacing: 12,
                            children: [
                              if (balance.lifetimeExpired > 0)
                                _buildStatItem(
                                  'All Expired',
                                  '${balance.lifetimeExpired}',
                                  Colors.white70,
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // Date filter section
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 8),
                    child: Row(
                      children: [
                        OutlinedButton.icon(
                          icon: Icon(Icons.calendar_today_outlined,
                              size: 16, color: darkGrey),
                          label: Text(
                            _selectedDateRange == null
                                ? 'Date range'
                                : '${DateFormat.MMMd().format(_selectedDateRange!.start)} - ${DateFormat.MMMd().format(_selectedDateRange!.end)}',
                            style: TextStyle(color: darkGrey),
                          ),
                          onPressed: _pickDateRange,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: darkGrey,
                            side: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                        if (_selectedDateRange != null) ...[
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _selectedDateRange = null;
                              });
                            },
                            child: const Text('Clear'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // Filter chips - dynamically generated from backend data
                SliverToBoxAdapter(
                  child: Container(
                    height: 50,
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: _buildDynamicFilterChips(transactions),
                  ),
                ),

                // Transactions list
                Builder(
                  builder: (context) {
                    final filteredTransactions =
                        _getFilteredTransactions(transactions);

                    // 1) No transactions at all (raw list is empty)
                    if (transactions.isEmpty) {
                      // If we're still loading, don't show a misleading "No transactions" state yet.
                      if (pointProvider.isLoading) {
                        return SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: ModernLoadingIndicator(
                              size: 42,
                              color: mediumYellow,
                            ),
                          ),
                        );
                      }

                      // If provider has an error and we have no cached data, show an actionable error state.
                      if (pointProvider.errorMessage != null &&
                          pointProvider.errorMessage!.trim().isNotEmpty) {
                        return SliverFillRemaining(
                          hasScrollBody: false,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.cloud_off_outlined,
                                    size: 64,
                                    color: Colors.grey[400],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Couldn\'t load transactions',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey[700],
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    pointProvider.errorMessage!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton.icon(
                                    onPressed: () =>
                                        _loadPoints(forceRefresh: true),
                                    icon: const Icon(Icons.refresh, size: 18),
                                    label: const Text('Try again'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: mediumYellow,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }

                      // Otherwise: genuine empty history state.
                      return SliverFillRemaining(
                        hasScrollBody: false,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.history,
                                  size: 64,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No point transactions yet',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Your transaction history will appear here',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[500],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: () =>
                                      _loadPoints(forceRefresh: true),
                                  icon: const Icon(Icons.refresh, size: 18),
                                  label: const Text('Refresh'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: mediumYellow,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }

                    // 2) Transactions exist, but current filters/date range produce zero results.
                    if (filteredTransactions.isEmpty) {
                      return SliverFillRemaining(
                        hasScrollBody: false,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.filter_alt_off_outlined,
                                  size: 64,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No transactions match your filters',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[700],
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Try clearing filters or adjusting the date range.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  alignment: WrapAlignment.center,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () {
                                        if (!mounted) return;
                                        setState(() {
                                          _selectedBackendFilter = null;
                                          _selectedFilter = null;
                                          _selectedDateRange = null;
                                        });
                                      },
                                      icon: const Icon(Icons.clear, size: 18),
                                      label: const Text('Clear filters'),
                                    ),
                                    ElevatedButton.icon(
                                      onPressed: () =>
                                          _loadPoints(forceRefresh: true),
                                      icon: const Icon(Icons.refresh, size: 18),
                                      label: const Text('Refresh'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: mediumYellow,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 20,
                                          vertical: 12,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }

                    // 3) Normal list rendering.
                    return SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final transaction = filteredTransactions[index];
                            return _buildTransactionCard(transaction);
                          },
                          childCount: filteredTransactions.length,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  /// Build dynamic filter chips based on backend transaction types
  /// Shows Lucky Box, Exchange Request, Quiz Reward, etc. from backend data
  Widget _buildDynamicFilterChips(List<PointTransaction> transactions) {
    // Collect backend transaction types from current and cached transactions
    final backendTypesSet = <BackendTransactionType>{};

    // Add types from current transactions (for immediate display)
    for (final transaction in transactions) {
      final backendType = _detectBackendTransactionType(transaction);
      backendTypesSet.add(backendType);
    }

    // Also add types from cached transactions (to ensure we have all types)
    backendTypesSet.addAll(_allBackendTransactionTypes);

    final backendTypes = backendTypesSet.toList();

    // Sort backend transaction types in a logical order
    final typeOrder = [
      BackendTransactionType.luckyBox,
      BackendTransactionType.exchangeRequest,
      BackendTransactionType.quizReward,
      BackendTransactionType.codeRedemption,
      BackendTransactionType.manualReward,
      BackendTransactionType.manualPoint,
      BackendTransactionType.order,
      BackendTransactionType.other,
    ];

    backendTypes.sort((a, b) {
      final indexA = typeOrder.indexOf(a);
      final indexB = typeOrder.indexOf(b);
      if (indexA == -1 && indexB == -1) return 0;
      if (indexA == -1) return 1;
      if (indexB == -1) return -1;
      return indexA.compareTo(indexB);
    });

    Logger.info(
      'Building filter chips from ${transactions.length} transactions',
      tag: 'PointHistoryPage',
    );
    Logger.info(
      'Found unique backend transaction types: ${backendTypes.map((t) => _getBackendTypeLabel(t)).join(", ")}',
      tag: 'PointHistoryPage',
    );

    // Build filter chips dynamically based on backend transaction types
    final filterChips = <Widget>[
      _buildBackendFilterChip(null, 'All'),
    ];

    // Add filter chips for each unique backend transaction type found in data
    for (final type in backendTypes) {
      final label = _getBackendTypeLabel(type);
      Logger.info(
        'Adding backend filter chip: $label',
        tag: 'PointHistoryPage',
      );
      filterChips.add(_buildBackendFilterChip(type, label));
    }

    Logger.info(
      'Total filter chips: ${filterChips.length}',
      tag: 'PointHistoryPage',
    );

    return ListView(
      scrollDirection: Axis.horizontal,
      children: filterChips,
    );
  }

  /// Detect backend transaction type from orderId and description
  BackendTransactionType _detectBackendTransactionType(
      PointTransaction transaction) {
    final orderIdStr = transaction.orderId?.toLowerCase() ?? '';
    final descriptionStr = transaction.description?.toLowerCase() ?? '';

    if (orderIdStr.contains('luckybox') || orderIdStr == 'luckybox') {
      return BackendTransactionType.luckyBox;
    } else if (orderIdStr.startsWith('exchange:') ||
        descriptionStr.contains('exchange request')) {
      return BackendTransactionType.exchangeRequest;
    } else if (orderIdStr.contains('quiz') ||
        descriptionStr.contains('quiz') ||
        descriptionStr.contains('quiz reward') ||
        descriptionStr.contains('activity #')) {
      return BackendTransactionType.quizReward;
    } else if (orderIdStr.startsWith('code:') ||
        descriptionStr.contains('code redemption')) {
      return BackendTransactionType.codeRedemption;
    } else if (orderIdStr.startsWith('manual_reward:') ||
        descriptionStr.contains('manual reward')) {
      return BackendTransactionType.manualReward;
    } else if (orderIdStr.startsWith('manual:') ||
        transaction.type == PointTransactionType.adjust ||
        descriptionStr.contains('manual adjustment')) {
      return BackendTransactionType.manualPoint;
    } else if (transaction.orderId != null &&
        !orderIdStr.startsWith('exchange:') &&
        !orderIdStr.startsWith('code:') &&
        !orderIdStr.startsWith('manual:') &&
        !orderIdStr.startsWith('manual_reward:') &&
        !orderIdStr.contains('luckybox') &&
        !orderIdStr.contains('quiz')) {
      return BackendTransactionType.order;
    }
    return BackendTransactionType.other;
  }

  /// Get label for backend transaction type
  String _getBackendTypeLabel(BackendTransactionType type) {
    switch (type) {
      case BackendTransactionType.luckyBox:
        return 'Lucky Box';
      case BackendTransactionType.exchangeRequest:
        return 'Exchange Request';
      case BackendTransactionType.quizReward:
        return 'Quiz Reward';
      case BackendTransactionType.codeRedemption:
        return 'Code Redemption';
      case BackendTransactionType.manualReward:
        return 'Manual Reward';
      case BackendTransactionType.manualPoint:
        return 'Manual Point';
      case BackendTransactionType.order:
        return 'Order';
      case BackendTransactionType.other:
        return 'Other';
    }
  }

  /// Build backend transaction type filter chip
  ///
  /// Creates a filter chip widget for filtering transactions by backend type.
  /// Implements proper null safety, accessibility, and performance optimizations.
  ///
  /// [type] - The backend transaction type to filter by (null for "All")
  /// [label] - The display label for the filter chip
  ///
  /// Returns a [Widget] containing the filter chip with proper styling and behavior.
  Widget _buildBackendFilterChip(BackendTransactionType? type, String label) {
    // Explicit null-safe comparison - handles both null and non-null cases correctly
    final isSelected = _selectedBackendFilter == type;

    // Extract theme colors for consistency and maintainability
    final selectedColor = mediumYellow;
    final unselectedColor = darkGrey;
    final textColor = isSelected ? Colors.white : unselectedColor;

    // Create reusable text style to avoid recreation on every build
    // Using w600 for better visual hierarchy when selected
    final labelStyle = TextStyle(
      color: textColor,
      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      fontSize: 13,
      letterSpacing: 0.1,
    );

    // Create check icon only when selected (const for performance optimization)
    final checkIcon = isSelected
        ? const Icon(
            Icons.check,
            size: 18,
            color: Colors.white,
          )
        : null;

    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: Semantics(
        label: isSelected
            ? '$label filter selected. Tap to clear filter.'
            : 'Tap to filter by $label',
        selected: isSelected,
        button: true,
        child: Tooltip(
          message: 'Filter by $label',
          child: FilterChip(
            // Core properties
            label: Text(
              label,
              style: labelStyle,
            ),
            selected: isSelected,

            // Selection callback with proper state management and mounted check
            onSelected: (selected) {
              if (!mounted) return;

              setState(() {
                _selectedBackendFilter = selected ? type : null;
                // Clear PointTransactionType filter when backend filter is selected
                // This ensures only one filter type is active at a time for better UX
                if (selected) {
                  _selectedFilter = null;
                }
              });
            },

            // Visual styling with theme colors
            selectedColor: selectedColor,
            checkmarkColor: Colors.white,
            avatar: checkIcon,

            // Material Design 3 properties for better visual consistency
            side: BorderSide(
              color: isSelected ? selectedColor : Colors.grey.shade300,
              width: isSelected ? 1.5 : 1.0,
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
    );
  }

  List<PointTransaction> _getFilteredTransactions(
      List<PointTransaction> transactions) {
    Iterable<PointTransaction> filtered = transactions;

    // IMPORTANT:
    // Do NOT filter out pending transactions here.
    // PointProvider provides the full history list (including pending) for transparency.
    // Filtering pending here can accidentally hide the entire history (common when backend uses
    // pending status until admin approves).

    // Apply backend transaction type filter (priority over PointTransactionType filter)
    if (_selectedBackendFilter != null) {
      filtered = filtered.where(
          (t) => _detectBackendTransactionType(t) == _selectedBackendFilter);
    } else if (_selectedFilter != null) {
      // Fallback to PointTransactionType filter if backend filter is not selected
      filtered = filtered.where((t) => t.type == _selectedFilter);
    }

    if (_selectedDateRange != null) {
      final start = DateTime(
        _selectedDateRange!.start.year,
        _selectedDateRange!.start.month,
        _selectedDateRange!.start.day,
      );
      final end = DateTime(
        _selectedDateRange!.end.year,
        _selectedDateRange!.end.month,
        _selectedDateRange!.end.day,
        23,
        59,
        59,
      );
      filtered = filtered.where(
        (t) => !t.createdAt.isBefore(start) && !t.createdAt.isAfter(end),
      );
    }

    return filtered.toList();
  }

  Widget _buildTransactionCard(PointTransaction transaction) {
    final color = _getTransactionColor(transaction.type);
    final icon = _getTransactionIcon(transaction.type);
    final isExpiringSoon = transaction.isExpiringSoon;
    final isPending = transaction.isPending;

    // Detect transaction source types from orderId and description
    final orderIdStr = transaction.orderId?.toLowerCase() ?? '';
    final descriptionStr = transaction.description?.toLowerCase() ?? '';

    final isLuckyBox =
        orderIdStr.contains('luckybox') || orderIdStr == 'luckybox';
    final isExchangeRequest = orderIdStr.startsWith('exchange:');
    final isQuizReward = orderIdStr.contains('quiz') ||
        descriptionStr.contains('quiz') ||
        descriptionStr.contains('quiz reward') ||
        descriptionStr.contains('activity #');
    final isManualPoint = orderIdStr.startsWith('manual:') ||
        transaction.type == PointTransactionType.adjust;
    final isManualReward = orderIdStr.startsWith('manual_reward:');
    final isCodeRedemption = orderIdStr.startsWith('code:');
    final pollDetails = transaction.pollDetails;
    final hasPollDetails =
        pollDetails != null && pollDetails.selectedOptions.isNotEmpty;

    // Determine the transaction label
    final transactionLabel = _getTransactionLabel(
      transaction: transaction,
      isLuckyBox: isLuckyBox,
      isExchangeRequest: isExchangeRequest,
      isQuizReward: isQuizReward,
      isManualPoint: isManualPoint,
      isManualReward: isManualReward,
      isCodeRedemption: isCodeRedemption,
    );

    // Determine the transaction label color
    final labelColor = _getTransactionLabelColor(
      isLuckyBox: isLuckyBox,
      isExchangeRequest: isExchangeRequest,
      isQuizReward: isQuizReward,
      isManualPoint: isManualPoint,
      isManualReward: isManualReward,
      isCodeRedemption: isCodeRedemption,
    );

    // Determine the transaction label icon
    final labelIcon = _getTransactionLabelIcon(
      isLuckyBox: isLuckyBox,
      isExchangeRequest: isExchangeRequest,
      isQuizReward: isQuizReward,
      isManualPoint: isManualPoint,
      isManualReward: isManualReward,
      isCodeRedemption: isCodeRedemption,
    );

    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: isPending
            ? Border.all(color: _pendingBorderColor, width: 2)
            : isExpiringSoon
                ? Border.all(color: Colors.orange[300]!, width: 2)
                : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: color,
              size: 24,
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        transaction.description ??
                            _getDefaultDescription(transaction.type),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: darkGrey,
                        ),
                      ),
                    ),
                    if (isPending)
                      Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.amber[100],
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.amber[700]!,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.pending_outlined,
                              size: 12,
                              color: Colors.amber[900],
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Pending',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.amber[900],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (isExpiringSoon)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _expiringBadgeBackgroundColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Expiring',
                          style: TextStyle(
                            fontSize: 10,
                            color: _expiringBadgeTextColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                SizedBox(height: 4),
                Text(
                  _formatDate(transaction.createdAt),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                // OLD CODE:
                // if (transaction.orderId != null ||
                //     isManualPoint ||
                //     isManualReward ||
                //     isQuizReward) ...[
                //   ...
                // ],
                //
                // New Code: keep legacy label row, plus rich poll details block.
                if (transaction.orderId != null ||
                    isManualPoint ||
                    isManualReward ||
                    isQuizReward) ...[
                  SizedBox(height: 4),
                  Row(
                    children: [
                      if (labelIcon != null) ...[
                        Icon(
                          labelIcon,
                          size: 12,
                          color: labelColor,
                        ),
                        SizedBox(width: 4),
                      ],
                      Flexible(
                        child: Text(
                          transactionLabel,
                          style: TextStyle(
                            fontSize: 11,
                            color: labelColor,
                            fontWeight: (isLuckyBox ||
                                    isExchangeRequest ||
                                    isQuizReward ||
                                    isManualPoint ||
                                    isManualReward ||
                                    isCodeRedemption)
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (hasPollDetails) ...[
                  const SizedBox(height: 8),
                  _buildPollDetailsCard(pollDetails!),
                ],
                if (isPending) ...[
                  SizedBox(height: 6),
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber[50],
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Colors.amber[200]!,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 14,
                          color: Colors.amber[800],
                        ),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Waiting for admin approval',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.amber[900],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (transaction.expiresAt != null && !transaction.expired) ...[
                  SizedBox(height: 4),
                  Text(
                    'Expires: ${_formatDate(transaction.expiresAt!)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: transaction.isExpiringSoon
                          ? Colors.orange[700]
                          : Colors.grey[500],
                      fontWeight: transaction.isExpiringSoon
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                // PROFESSIONAL FIX: Handle negative adjustments properly
                // For Exchange Request and negative adjustments, show in red
                // Add "PNP" suffix after points value
                isExchangeRequest
                    ? '-${transaction.points} PNP'
                    : '${transaction.formattedPoints} PNP',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  // Show in red for exchange requests or negative adjustments
                  color: (isExchangeRequest ||
                          (isManualPoint && transaction.points < 0))
                      ? Colors.red
                      : color,
                ),
              ),
              if (transaction.type == PointTransactionType.earn &&
                  transaction.daysUntilExpiration != null)
                Text(
                  '${transaction.daysUntilExpiration}d left',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[500],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPollDetailsCard(PollTransactionDetails details) {
    final status = (details.resultStatus ?? 'pending').toLowerCase();
    final Color statusColor;
    final IconData statusIcon;
    final String statusLabel;

    // OLD CODE: poll transaction details UI did not exist.
    if (status == 'won') {
      statusColor = Colors.green;
      statusIcon = Icons.emoji_events;
      statusLabel = 'Win';
    } else if (status == 'lost') {
      statusColor = Colors.red;
      statusIcon = Icons.cancel_outlined;
      statusLabel = 'Loss';
    } else {
      statusColor = Colors.orange;
      statusIcon = Icons.hourglass_top;
      statusLabel = 'Pending';
    }

    final selectedText = details.selectedOptions
        .map((option) => '${option.label} (${option.betPnp} PNP)')
        .join(', ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(statusIcon, size: 14, color: statusColor),
              const SizedBox(width: 4),
              Text(
                statusLabel,
                style: TextStyle(
                  fontSize: 11,
                  color: statusColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                'Bet ${details.totalBetPnp} PNP',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if ((details.pollTitle ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              details.pollTitle!,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Your Option: $selectedText',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade700,
            ),
          ),
          if (details.winningOption != null) ...[
            const SizedBox(height: 2),
            Text(
              'Winning Option: ${details.winningOption!.label}',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Won ${details.wonAmountPnp} PNP (Net ${details.netAmountPnp >= 0 ? '+' : ''}${details.netAmountPnp} PNP)',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: details.netAmountPnp >= 0 ? Colors.green : Colors.red,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final initialRange = _selectedDateRange ??
        DateTimeRange(
          start: now.subtract(const Duration(days: 30)),
          end: now,
        );

    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
      initialDateRange: initialRange,
      helpText: 'Filter by date range',
    );

    if (range != null) {
      setState(() {
        _selectedDateRange = range;
      });
    }
  }

  // TODO: Loyalty Analytics - Commented out temporarily, will be added back later
  // void _showAnalytics(
  //     BuildContext context, List<PointTransaction> transactions) {
  //   final analytics = _buildAnalytics(transactions,
  //       Provider.of<PointProvider>(context, listen: false).balance);
  //   showModalBottomSheet<void>(
  //     context: context,
  //     isScrollControlled: true,
  //     shape: const RoundedRectangleBorder(
  //       borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
  //     ),
  //     builder: (context) {
  //       return Padding(
  //         padding: EdgeInsets.only(
  //           left: 20,
  //           right: 20,
  //           top: 24,
  //           bottom: MediaQuery.of(context).padding.bottom + 24,
  //         ),
  //         child: analytics,
  //       );
  //     },
  //   );
  // }

  // TODO: Loyalty Analytics - Commented out temporarily, will be added back later
  /*
  Widget _buildAnalytics(
      List<PointTransaction> transactions, PointBalance? balance) {
    // Filter transactions by selected time period
    final filteredTransactions = _filterTransactionsByPeriod(transactions);

    // Calculate comprehensive statistics
    final stats = _calculateAnalyticsStats(filteredTransactions, balance);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with time period selector
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Loyalty Analytics',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Time Period Selector
          _buildTimePeriodSelector(),
          const SizedBox(height: 20),

          // Overview Cards
          _buildOverviewCards(stats),
          const SizedBox(height: 20),

          // Earn vs Redeem Chart
          _buildEarnRedeemChart(filteredTransactions),
          const SizedBox(height: 20),

          // Transaction Type Breakdown
          _buildTransactionTypeBreakdown(filteredTransactions),
          const SizedBox(height: 20),

          // Backend Transaction Type Breakdown
          _buildBackendTransactionTypeBreakdown(filteredTransactions),
          const SizedBox(height: 20),

          // Program Health Metrics
          _buildProgramHealthMetrics(stats),
          const SizedBox(height: 20),

          // Trend Analysis & Insights
          _buildTrendAnalysisAndInsights(filteredTransactions, stats),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  /// Filter transactions by selected time period
  List<PointTransaction> _filterTransactionsByPeriod(
      List<PointTransaction> transactions) {
    final now = DateTime.now();
    DateTime startDate;

    switch (_analyticsTimePeriod) {
      case AnalyticsTimePeriod.last7Days:
        startDate = now.subtract(const Duration(days: 7));
        break;
      case AnalyticsTimePeriod.last30Days:
        startDate = now.subtract(const Duration(days: 30));
        break;
      case AnalyticsTimePeriod.last6Months:
        startDate = DateTime(now.year, now.month - 6, 1);
        break;
      case AnalyticsTimePeriod.last1Year:
        startDate = DateTime(now.year - 1, now.month, now.day);
        break;
      case AnalyticsTimePeriod.allTime:
        return transactions;
    }

    return transactions.where((t) => t.createdAt.isAfter(startDate)).toList();
  }

  /// Calculate comprehensive analytics statistics
  _AnalyticsStats _calculateAnalyticsStats(
      List<PointTransaction> transactions, PointBalance? balance) {
    int totalEarned = 0;
    int totalRedeemed = 0;
    int totalExpired = 0;
    int totalRefunded = 0;
    int totalAdjusted = 0;
    int totalReferral = 0;
    int totalBirthday = 0;

    // Backend transaction type counts
    final backendTypeCounts = <BackendTransactionType, int>{};
    final backendTypePoints = <BackendTransactionType, int>{};

    for (final transaction in transactions) {
      // Count by PointTransactionType
      switch (transaction.type) {
        case PointTransactionType.earn:
          totalEarned += transaction.points;
          break;
        case PointTransactionType.redeem:
          totalRedeemed += transaction.points;
          break;
        case PointTransactionType.expire:
          totalExpired += transaction.points;
          break;
        case PointTransactionType.refund:
          totalRefunded += transaction.points;
          break;
        case PointTransactionType.adjust:
          totalAdjusted += transaction.points;
          break;
        case PointTransactionType.referral:
          totalReferral += transaction.points;
          break;
        case PointTransactionType.birthday:
          totalBirthday += transaction.points;
          break;
      }

      // Count by BackendTransactionType
      final backendType = _detectBackendTransactionType(transaction);
      backendTypeCounts[backendType] =
          (backendTypeCounts[backendType] ?? 0) + 1;
      backendTypePoints[backendType] =
          (backendTypePoints[backendType] ?? 0) + transaction.points;
    }

    final netPoints = totalEarned - totalRedeemed - totalExpired;
    final redemptionRate = totalEarned > 0
        ? (totalRedeemed / totalEarned * 100).toStringAsFixed(1)
        : '0.0';

    return _AnalyticsStats(
      totalEarned: totalEarned,
      totalRedeemed: totalRedeemed,
      totalExpired: totalExpired,
      totalRefunded: totalRefunded,
      totalAdjusted: totalAdjusted,
      totalReferral: totalReferral,
      totalBirthday: totalBirthday,
      netPoints: netPoints,
      redemptionRate: double.tryParse(redemptionRate) ?? 0.0,
      transactionCount: transactions.length,
      backendTypeCounts: backendTypeCounts,
      backendTypePoints: backendTypePoints,
      currentBalance: balance?.currentBalance ?? 0,
      lifetimeEarned: balance?.lifetimeEarned ?? 0,
      lifetimeRedeemed: balance?.lifetimeRedeemed ?? 0,
      lifetimeExpired: balance?.lifetimeExpired ?? 0,
      expiringSoon: _expiringSoon.fold<int>(0, (sum, t) => sum + t.points),
    );
  }

  /// Build time period selector
  Widget _buildTimePeriodSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTimePeriodChip('7D', AnalyticsTimePeriod.last7Days),
          _buildTimePeriodChip('30D', AnalyticsTimePeriod.last30Days),
          _buildTimePeriodChip('6M', AnalyticsTimePeriod.last6Months),
          _buildTimePeriodChip('1Y', AnalyticsTimePeriod.last1Year),
          _buildTimePeriodChip('All', AnalyticsTimePeriod.allTime),
        ],
      ),
    );
  }

  Widget _buildTimePeriodChip(String label, AnalyticsTimePeriod period) {
    final isSelected = _analyticsTimePeriod == period;
    return GestureDetector(
      onTap: () {
        setState(() {
          _analyticsTimePeriod = period;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: isSelected ? mediumYellow : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : Colors.grey[700],
          ),
        ),
      ),
    );
  }

  /// Build overview cards
  Widget _buildOverviewCards(_AnalyticsStats stats) {
    return Row(
      children: [
        Expanded(
          child: _AnalyticsTile(
            title: 'Total Earned',
            value: '${stats.totalEarned}',
            subtitle: 'Points earned in period',
            color: Colors.green[700]!,
            icon: Icons.trending_up,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _AnalyticsTile(
            title: 'Total Redeemed',
            value: '${stats.totalRedeemed}',
            subtitle: 'Points redeemed in period',
            color: Colors.orange[700]!,
            icon: Icons.trending_down,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _AnalyticsTile(
            title: 'Net Points',
            value: '${stats.netPoints}',
            subtitle: 'Earned - Redeemed',
            color: stats.netPoints >= 0 ? Colors.blue[700]! : Colors.red[700]!,
            icon: Icons.account_balance_wallet,
          ),
        ),
      ],
    );
  }

  /// Build Earn vs Redeem chart
  Widget _buildEarnRedeemChart(List<PointTransaction> transactions) {
    final now = DateTime.now();
    final period = _analyticsTimePeriod;

    List<DateTime> periods;
    String periodFormat;

    if (period == AnalyticsTimePeriod.last7Days) {
      periods = List.generate(7, (i) => now.subtract(Duration(days: 6 - i)));
      periodFormat = 'EEE';
    } else if (period == AnalyticsTimePeriod.last30Days) {
      periods = List.generate(30, (i) => now.subtract(Duration(days: 29 - i)));
      periodFormat = 'd MMM';
    } else {
      // For months
      final monthCount = period == AnalyticsTimePeriod.last6Months ? 6 : 12;
      periods = List.generate(
        monthCount,
        (i) => DateTime(now.year, now.month - (monthCount - 1 - i), 1),
      );
      periodFormat = 'MMM';
    }

    final Map<String, _PeriodStats> periodStats = {};
    for (final p in periods) {
      final key = DateFormat(periodFormat).format(p);
      periodStats[key] = _PeriodStats();
    }

    for (final transaction in transactions) {
      String key;
      if (period == AnalyticsTimePeriod.last7Days ||
          period == AnalyticsTimePeriod.last30Days) {
        key = DateFormat(periodFormat).format(transaction.createdAt);
      } else {
        key = DateFormat(periodFormat).format(
          DateTime(transaction.createdAt.year, transaction.createdAt.month, 1),
        );
      }

      if (!periodStats.containsKey(key)) continue;
      final current = periodStats[key]!;

      if (transaction.type == PointTransactionType.earn ||
          transaction.type == PointTransactionType.referral ||
          transaction.type == PointTransactionType.birthday) {
        periodStats[key] = current.copyWith(
          earned: current.earned + transaction.points,
        );
      } else if (transaction.type == PointTransactionType.redeem ||
          transaction.type == PointTransactionType.expire) {
        periodStats[key] = current.copyWith(
          redeemed: current.redeemed + transaction.points,
        );
      }
    }

    final maxValue = periodStats.values
        .map((s) => s.earned > s.redeemed ? s.earned : s.redeemed)
        .fold<int>(0, (prev, elem) => elem > prev ? elem : prev)
        .toDouble()
        .clamp(1, double.infinity);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Earn vs Redeem Trend',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: darkGrey,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: periodStats.entries.map((entry) {
                final width = period == AnalyticsTimePeriod.last7Days
                    ? 40.0
                    : period == AnalyticsTimePeriod.last30Days
                        ? 8.0
                        : 28.0;

                // PROFESSIONAL FIX: Calculate max bar height accounting for spacing and text label
                // Total available height: 200px
                // Space needed: SizedBox (8px) + Text (~14px with font size 10) = ~22px
                // Max bar height: 200 - 22 = 178px, use 175px for safety margin
                const maxBarHeight = 175.0;
                const spacingHeight = 8.0;

                // Calculate bar heights and clamp to maxBarHeight to prevent overflow
                final earnedHeight =
                    ((entry.value.earned / maxValue) * maxBarHeight)
                        .clamp(0.0, maxBarHeight);
                final redeemedHeight =
                    ((entry.value.redeemed / maxValue) * maxBarHeight)
                        .clamp(0.0, maxBarHeight);

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      mainAxisSize: MainAxisSize
                          .min, // PROFESSIONAL FIX: Prevent Column from expanding beyond needed space
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Bar chart section - bars with explicit constrained heights
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize
                              .min, // PROFESSIONAL FIX: Prevent Row overflow
                          children: [
                            Container(
                              width: width * 0.45,
                              height: earnedHeight,
                              decoration: BoxDecoration(
                                color: Colors.green[400],
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                              ),
                            ),
                            SizedBox(width: width * 0.1),
                            Container(
                              width: width * 0.45,
                              height: redeemedHeight,
                              decoration: BoxDecoration(
                                color: Colors.orange[400],
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: spacingHeight),
                        // Label section - fixed height with overflow protection
                        Text(
                          entry.key.length > 4
                              ? entry.key.substring(0, 4)
                              : entry.key,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                            height:
                                1.2, // PROFESSIONAL FIX: Control line height to prevent overflow
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1, // PROFESSIONAL FIX: Limit to single line
                          overflow: TextOverflow
                              .ellipsis, // PROFESSIONAL FIX: Handle overflow gracefully
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendItem('Earned', Colors.green[400]!),
              const SizedBox(width: 16),
              _buildLegendItem('Redeemed', Colors.orange[400]!),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
        ),
      ],
    );
  }

  /// Build transaction type breakdown
  Widget _buildTransactionTypeBreakdown(List<PointTransaction> transactions) {
    final typeStats = <PointTransactionType, int>{};
    for (final transaction in transactions) {
      if (transaction.type == PointTransactionType.earn ||
          transaction.type == PointTransactionType.referral ||
          transaction.type == PointTransactionType.birthday) {
        typeStats[transaction.type] =
            (typeStats[transaction.type] ?? 0) + transaction.points;
      }
    }

    if (typeStats.isEmpty) {
      return const SizedBox.shrink();
    }

    final sortedTypes = typeStats.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Earning Sources',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: darkGrey,
            ),
          ),
          const SizedBox(height: 16),
          ...sortedTypes.map((entry) => _buildTypeBar(
                _getTransactionTypeLabel(entry.key),
                entry.value,
                _getTransactionColor(entry.key),
              )),
        ],
      ),
    );
  }

  /// Build backend transaction type breakdown
  Widget _buildBackendTransactionTypeBreakdown(
      List<PointTransaction> transactions) {
    final backendTypeStats = <BackendTransactionType, int>{};
    for (final transaction in transactions) {
      final backendType = _detectBackendTransactionType(transaction);
      backendTypeStats[backendType] =
          (backendTypeStats[backendType] ?? 0) + transaction.points;
    }

    // Remove 'other' and 'order' if they're not significant
    backendTypeStats.removeWhere((key, value) =>
        (key == BackendTransactionType.other ||
            key == BackendTransactionType.order) &&
        value == 0);

    if (backendTypeStats.isEmpty) {
      return const SizedBox.shrink();
    }

    final sortedTypes = backendTypeStats.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Activity Types',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: darkGrey,
            ),
          ),
          const SizedBox(height: 16),
          ...sortedTypes.map((entry) => _buildTypeBar(
                _getBackendTypeLabel(entry.key),
                entry.value,
                _getBackendTypeColor(entry.key),
              )),
        ],
      ),
    );
  }

  Widget _buildTypeBar(String label, int value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: darkGrey,
                ),
              ),
              Text(
                '$value pts',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: 1.0,
              minHeight: 8,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  Color _getBackendTypeColor(BackendTransactionType type) {
    switch (type) {
      case BackendTransactionType.luckyBox:
        return Colors.purple[400]!;
      case BackendTransactionType.exchangeRequest:
        return Colors.orange[400]!;
      case BackendTransactionType.quizReward:
        return Colors.green[400]!;
      case BackendTransactionType.codeRedemption:
        return Colors.indigo[400]!;
      case BackendTransactionType.manualReward:
        return Colors.teal[400]!;
      case BackendTransactionType.manualPoint:
        return Colors.blue[400]!;
      case BackendTransactionType.order:
        return Colors.grey[400]!;
      case BackendTransactionType.other:
        return Colors.grey[300]!;
    }
  }

  /// Build program health metrics
  Widget _buildProgramHealthMetrics(_AnalyticsStats stats) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Program Health',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: darkGrey,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _AnalyticsTile(
                title: 'Current Balance',
                value: '${stats.currentBalance}',
                subtitle: 'Available points',
                color: Colors.blue[700]!,
                icon: Icons.account_balance_wallet,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _AnalyticsTile(
                title: 'Expiring Soon',
                value: '${stats.expiringSoon}',
                subtitle: 'Within 30 days',
                color: Colors.orange[700]!,
                icon: Icons.warning_amber_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _AnalyticsTile(
                title: 'Redemption Rate',
                value: '${stats.redemptionRate}%',
                subtitle: 'Redeemed / Earned',
                color: Colors.purple[700]!,
                icon: Icons.percent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _AnalyticsTile(
                title: 'Lifetime Earned',
                value: '${stats.lifetimeEarned}',
                subtitle: 'All time total',
                color: Colors.green[700]!,
                icon: Icons.trending_up,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Build trend analysis and insights
  Widget _buildTrendAnalysisAndInsights(
      List<PointTransaction> transactions, _AnalyticsStats stats) {
    final insights = <String>[];

    // Calculate trends
    if (transactions.length >= 2) {
      final recent = transactions.take(transactions.length ~/ 2).toList();
      final older = transactions.skip(transactions.length ~/ 2).toList();

      final recentEarned = recent
          .where((t) =>
              t.type == PointTransactionType.earn ||
              t.type == PointTransactionType.referral ||
              t.type == PointTransactionType.birthday)
          .fold<int>(0, (sum, t) => sum + t.points);

      final olderEarned = older
          .where((t) =>
              t.type == PointTransactionType.earn ||
              t.type == PointTransactionType.referral ||
              t.type == PointTransactionType.birthday)
          .fold<int>(0, (sum, t) => sum + t.points);

      if (recentEarned > olderEarned * 1.2) {
        insights.add(
            '📈 Earning activity increased by ${((recentEarned / olderEarned - 1) * 100).toStringAsFixed(0)}% compared to previous period');
      } else if (recentEarned < olderEarned * 0.8) {
        insights.add(
            '📉 Earning activity decreased by ${((1 - recentEarned / olderEarned) * 100).toStringAsFixed(0)}% compared to previous period');
      }
    }

    if (stats.redemptionRate < 20) {
      insights.add(
          '💡 Low redemption rate. Consider promoting rewards to increase engagement.');
    } else if (stats.redemptionRate > 80) {
      insights
          .add('🎉 High redemption rate! Your loyalty program is very active.');
    }

    if (stats.expiringSoon > stats.currentBalance * 0.3) {
      insights.add(
          '⚠️ Significant points expiring soon. Consider sending reminders to users.');
    }

    if (stats.totalReferral > 0) {
      insights.add(
          '👥 Referral program is active with ${stats.totalReferral} points awarded.');
    }

    if (insights.isEmpty) {
      insights.add('✅ Program is performing well. Keep up the engagement!');
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, color: Colors.blue[700], size: 20),
              const SizedBox(width: 8),
              Text(
                'Insights & Recommendations',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[900],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...insights.map((insight) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        insight,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.blue[900],
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
  */
  // END: Loyalty Analytics Section

  Color _getTransactionColor(PointTransactionType type) {
    switch (type) {
      case PointTransactionType.earn:
        return Colors.green;
      case PointTransactionType.redeem:
        return Colors.orange;
      case PointTransactionType.expire:
        return Colors.red;
      case PointTransactionType.adjust:
        return Colors.blue;
      case PointTransactionType.referral:
        return Colors.purple;
      case PointTransactionType.birthday:
        return Colors.pink;
      case PointTransactionType.refund:
        return Colors.cyan;
    }
  }

  IconData _getTransactionIcon(PointTransactionType type) {
    switch (type) {
      case PointTransactionType.earn:
        return Icons.add_circle;
      case PointTransactionType.redeem:
        return Icons.remove_circle;
      case PointTransactionType.expire:
        return Icons.cancel;
      case PointTransactionType.adjust:
        return Icons.edit;
      case PointTransactionType.referral:
        return Icons.people;
      case PointTransactionType.birthday:
        return Icons.cake;
      case PointTransactionType.refund:
        return Icons.refresh;
    }
  }

  String _getDefaultDescription(PointTransactionType type) {
    switch (type) {
      case PointTransactionType.earn:
        return 'Points earned';
      case PointTransactionType.redeem:
        return 'Points redeemed';
      case PointTransactionType.expire:
        return 'Points expired';
      case PointTransactionType.adjust:
        return 'Manual Points Adjustment';
      case PointTransactionType.referral:
        return 'Referral bonus';
      case PointTransactionType.birthday:
        return 'Birthday bonus';
      case PointTransactionType.refund:
        return 'Points refunded';
    }
  }

  /// Get user-friendly label for transaction type (for filter chips)
  String _getTransactionTypeLabel(PointTransactionType type) {
    switch (type) {
      case PointTransactionType.earn:
        return 'Earned';
      case PointTransactionType.redeem:
        return 'Redeemed';
      case PointTransactionType.expire:
        return 'Expired';
      case PointTransactionType.adjust:
        return 'Adjusted';
      case PointTransactionType.referral:
        return 'Referral';
      case PointTransactionType.birthday:
        return 'Birthday';
      case PointTransactionType.refund:
        return 'Refunded';
    }
  }

  /// Get transaction label based on orderId and description
  String _getTransactionLabel({
    required PointTransaction transaction,
    required bool isLuckyBox,
    required bool isExchangeRequest,
    required bool isQuizReward,
    required bool isManualPoint,
    required bool isManualReward,
    required bool isCodeRedemption,
  }) {
    if (isLuckyBox) {
      return 'Lucky Box Request';
    } else if (isExchangeRequest) {
      return 'Exchange Request';
    } else if (isQuizReward) {
      return 'Quiz Reward';
    } else if (isManualReward) {
      return 'Manual Reward Adjustment';
    } else if (isManualPoint) {
      return 'Manual Points Adjustment';
    } else if (isCodeRedemption) {
      return 'Code Redemption';
    } else if (transaction.orderId != null) {
      // Show order ID for regular orders
      return 'Order #${transaction.orderId}';
    }
    return '';
  }

  /// Get transaction label color
  Color _getTransactionLabelColor({
    required bool isLuckyBox,
    required bool isExchangeRequest,
    required bool isQuizReward,
    required bool isManualPoint,
    required bool isManualReward,
    required bool isCodeRedemption,
  }) {
    if (isLuckyBox) {
      return Colors.purple[700]!;
    } else if (isExchangeRequest) {
      return Colors.orange[700]!;
    } else if (isQuizReward) {
      return Colors.green[700]!;
    } else if (isManualReward) {
      return Colors.teal[700]!;
    } else if (isManualPoint) {
      return Colors.blue[700]!;
    } else if (isCodeRedemption) {
      return Colors.indigo[700]!;
    }
    return Colors.grey[500]!;
  }

  /// Get transaction label icon
  IconData? _getTransactionLabelIcon({
    required bool isLuckyBox,
    required bool isExchangeRequest,
    required bool isQuizReward,
    required bool isManualPoint,
    required bool isManualReward,
    required bool isCodeRedemption,
  }) {
    if (isLuckyBox) {
      return Icons.casino_rounded;
    } else if (isExchangeRequest) {
      return Icons.swap_horiz;
    } else if (isQuizReward) {
      return Icons.quiz;
    } else if (isManualReward) {
      return Icons.card_giftcard;
    } else if (isManualPoint) {
      return Icons.admin_panel_settings_rounded;
    } else if (isCodeRedemption) {
      return Icons.confirmation_number;
    }
    return null;
  }

  /// Get current Myanmar time (UTC+06:30) as a local DateTime with Myanmar time values
  DateTime _getCurrentMyanmarTime() {
    final utcNow = DateTime.now().toUtc();
    // Convert UTC to Myanmar time (UTC+06:30 = +390 minutes)
    const myanmarOffsetMinutes = 390; // 6 hours 30 minutes
    final myanmarTime = utcNow.add(Duration(minutes: myanmarOffsetMinutes));

    // Create a local DateTime with Myanmar time values (not UTC)
    // This ensures consistency with how transaction dates are stored
    return DateTime(
      myanmarTime.year,
      myanmarTime.month,
      myanmarTime.day,
      myanmarTime.hour,
      myanmarTime.minute,
      myanmarTime.second,
      myanmarTime.millisecond,
      myanmarTime.microsecond,
    );
  }

  /// Format date as actual Myanmar time (UTC+06:30).
  ///
  /// Always shows actual date and time in Myanmar timezone for clarity.
  /// Format examples:
  /// - Same year: "Dec 25, 9:25 AM"
  /// - Different year: "25 Dec 2024, 9:25 AM"
  ///
  /// PROFESSIONAL FIX: Properly handles Myanmar timezone by ensuring
  /// DateTime values are formatted without device timezone conversion.
  /// The DateTime passed here is a local DateTime containing Myanmar time values
  /// (converted by _parseServerDateTime in point_transaction.dart from UTC to Myanmar time).
  String _formatDate(DateTime date) {
    // CRITICAL: The DateTime is a local DateTime with Myanmar time values already set.
    // We need to format it directly without any timezone conversion.
    // DateFormat will use the DateTime's internal values, which already represent Myanmar time.

    // Use Myanmar time for comparison to ensure consistency
    final myanmarNow = _getCurrentMyanmarTime();

    // Check if transaction is in the same year (using Myanmar time for both)
    if (date.year == myanmarNow.year) {
      // Show month, day, and time for same year (includes today's transactions)
      // Format: "Dec 25, 9:25 AM"
      final dateFormat = DateFormat('MMM d, h:mm a', 'en_US');
      // Format directly - date already contains Myanmar time values
      return dateFormat.format(date);
    }

    // Show full date and time for older transactions (different year)
    // Format: "25 Dec 2024, 9:25 AM"
    final fullDateFormat = DateFormat('d MMM yyyy, h:mm a', 'en_US');
    // Format directly - date already contains Myanmar time values
    return fullDateFormat.format(date);
  }

  /// Show simple success message using SnackBar
  /// This is cleaner and less intrusive than a modal
  void _showSimpleSuccessMessage(BuildContext context, int points) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Exchange request submitted successfully!\n$points points will be processed.',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green[600],
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  /// Show simple failure message using SnackBar
  void _showSimpleFailureMessage(BuildContext context) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Failed to submit exchange request.\nPlease try again later.',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.orange[600],
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  /// Show simple error message using SnackBar
  void _showSimpleErrorMessage(BuildContext context, dynamic error) {
    if (!context.mounted) return;

    String message = 'An error occurred. Please try again.';
    if (error.toString().contains('SocketException') ||
        error.toString().contains('Network')) {
      message =
          'No internet connection.\nPlease check your network and try again.';
    } else if (error.toString().contains('Timeout')) {
      message = 'Request timed out.\nPlease try again.';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red[600],
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  /// Show success modal dialog (kept for backward compatibility)
  /// Ensures no other dialogs are shown before this one
  void _showSuccessModal(BuildContext context, int points) {
    // Clear any existing SnackBars first
    ScaffoldMessenger.of(context).clearSnackBars();

    // Dismiss any existing dialogs first to prevent showing error before success
    Navigator.of(context, rootNavigator: true).popUntil((route) {
      return route.isFirst || !(route is DialogRoute);
    });

    // Small delay to ensure previous dialogs and SnackBars are dismissed
    Future.delayed(const Duration(milliseconds: 150), () {
      if (!context.mounted) return;

      try {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Success Icon
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.green.withValues(alpha: 0.1),
                    ),
                    child: const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 48,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Success Title
                  const Text(
                    'Success!',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Success Message
                  Text(
                    'Your request to exchange $points points has been submitted successfully!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: darkGrey.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // OK Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'OK',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      } catch (e) {
        // Context deactivated, cannot show dialog
        Logger.warning('Cannot show success modal: context deactivated',
            tag: 'PointHistoryPage');
      }
    });
  }

  /// Show failure modal dialog
  /// Ensures no other dialogs are shown before this one
  void _showFailureModal(BuildContext context) {
    // Check if context is still mounted before proceeding
    if (!context.mounted) return;

    // Clear any existing SnackBars first
    try {
      ScaffoldMessenger.of(context).clearSnackBars();
    } catch (e) {
      // Context might be deactivated, ignore
    }

    // Dismiss any existing dialogs first
    try {
      Navigator.of(context, rootNavigator: true).popUntil((route) {
        return route.isFirst || !(route is DialogRoute);
      });
    } catch (e) {
      // Navigator might be deactivated, ignore
    }

    // Small delay to ensure previous dialogs and SnackBars are dismissed
    Future.delayed(const Duration(milliseconds: 150), () {
      if (!context.mounted) return;

      try {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Failure Icon
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red.withValues(alpha: 0.1),
                    ),
                    child: const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 48,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Failure Title
                  const Text(
                    'Failed',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Failure Message
                  const Text(
                    'Failed to submit exchange request. Please check your connection and try again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: darkGrey,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // OK Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'OK',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      } catch (e) {
        // Context deactivated, cannot show dialog
        Logger.warning('Cannot show failure modal: context deactivated',
            tag: 'PointHistoryPage');
      }
    });
  }

  /// Show error modal dialog
  /// Ensures no other dialogs are shown before this one
  void _showErrorModal(BuildContext context, String message) {
    // Check if context is still mounted before proceeding
    if (!context.mounted) return;

    // Clear any existing SnackBars first
    try {
      ScaffoldMessenger.of(context).clearSnackBars();
    } catch (e) {
      // Context might be deactivated, ignore
    }

    // Dismiss any existing dialogs first
    try {
      Navigator.of(context, rootNavigator: true).popUntil((route) {
        return route.isFirst || !(route is DialogRoute);
      });
    } catch (e) {
      // Navigator might be deactivated, ignore
    }

    // Small delay to ensure previous dialogs and SnackBars are dismissed
    Future.delayed(const Duration(milliseconds: 150), () {
      if (!context.mounted) return;

      try {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Error Icon
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.orange.withValues(alpha: 0.1),
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange,
                      size: 48,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Error Title
                  const Text(
                    'Error',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Error Message
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: darkGrey.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // OK Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'OK',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      } catch (e) {
        // Context deactivated, cannot show dialog
        Logger.warning('Cannot show error modal: context deactivated',
            tag: 'PointHistoryPage');
      }
    });
  }

  /// PROFESSIONAL MODAL: Show minimum points required dialog
  /// Creative and professional modal box when user doesn't meet minimum PNP requirement
  void _showMinimumPointsRequiredModal(
    BuildContext context, {
    required int currentPoints,
    required int minRequired,
  }) {
    // Check if context is still mounted before proceeding
    if (!context.mounted) return;

    // Clear any existing SnackBars first
    try {
      ScaffoldMessenger.of(context).clearSnackBars();
    } catch (e) {
      // Context might be deactivated, ignore
    }

    // Dismiss any existing dialogs first
    try {
      Navigator.of(context, rootNavigator: true).popUntil((route) {
        return route.isFirst || !(route is DialogRoute);
      });
    } catch (e) {
      // Navigator might be deactivated, ignore
    }

    // Small delay to ensure previous dialogs and SnackBars are dismissed
    Future.delayed(const Duration(milliseconds: 150), () {
      if (!context.mounted) return;

      try {
        final pointsNeeded = minRequired - currentPoints;

        showDialog(
          context: context,
          barrierDismissible: true,
          barrierColor: Colors.black.withValues(alpha: 0.6),
          builder: (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            elevation: 8,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 24,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Container(
                  constraints: BoxConstraints(
                    maxWidth: 400,
                    maxHeight: MediaQuery.of(context).size.height * 0.9,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white,
                        Colors.grey[50]!,
                      ],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header with padding - Optimized for smaller screens
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Animated Icon Container with Gradient - Slightly smaller for better fit
                            Container(
                              width: 90,
                              height: 90,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Colors.orange[400]!,
                                    Colors.deepOrange[600]!,
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.orange.withValues(alpha: 0.4),
                                    blurRadius: 20,
                                    spreadRadius: 2,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.info_outline_rounded,
                                color: Colors.white,
                                size: 45,
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Title - Responsive font size
                            const Text(
                              'Minimum Points Required',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),

                      // Scrollable content area - Use Expanded with proper constraints
                      Expanded(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Current Points Card - Optimized padding
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.grey[300]!,
                                    width: 1.5,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      'Your Current Balance',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[700],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '$currentPoints PNP',
                                      style: TextStyle(
                                        fontSize: 32,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey[800],
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),

                              // Required Points Card with Highlight - Optimized padding
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Colors.orange[50]!,
                                      Colors.deepOrange[50]!,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.orange[300]!,
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.orange.withValues(alpha: 0.2),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.stars_rounded,
                                          color: Colors.orange[700],
                                          size: 24,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Minimum Required',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.orange[900],
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '$minRequired PNP',
                                      style: TextStyle(
                                        fontSize: 36,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange[900],
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Points Needed Calculation - Compact design
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue[50],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.blue[200]!,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.trending_up_rounded,
                                      color: Colors.blue[700],
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        'You need $pointsNeeded more PNP to exchange',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 15,
                                          color: Colors.blue[900],
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Message - Compact and clear
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  'Keep engaging with activities, quizzes, and polls to earn more points!',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[700],
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Action Buttons - Fixed at bottom with proper padding and shadow
                      Container(
                        padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(28),
                            bottomRight: Radius.circular(28),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, -2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            // Close Button
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(context).pop(),
                                style: OutlinedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  side: BorderSide(
                                    color: Colors.grey[400]!,
                                    width: 1.5,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: Text(
                                  'Close',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // View Activities Button
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  // PROFESSIONAL FIX: Navigate to main page (home tab) to access engagement hub
                                  // This allows users to easily earn more points through activities
                                  try {
                                    // Pop all routes until we reach the main page
                                    Navigator.of(context).popUntil((route) {
                                      return route.isFirst ||
                                          route.settings.name == '/' ||
                                          route.settings.name == '/main';
                                    });
                                  } catch (e) {
                                    // If navigation fails, just close the dialog
                                    Logger.warning(
                                      'Failed to navigate to main page: $e',
                                      tag: 'PointHistoryPage',
                                    );
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: mediumYellow,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: const Text(
                                  'Earn Points',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      } catch (e) {
        // Error showing dialog, ignore
        Logger.error(
          'Error showing minimum points modal: $e',
          tag: 'PointHistoryPage',
          error: e,
        );
      }
    });
  }

  /// Show point exchange dialog
  Future<void> _showPointExchangeDialog(
    BuildContext context,
    AuthProvider authProvider,
    int currentPoints,
  ) async {
    final user = authProvider.user;
    if (user == null) return;

    // PROFESSIONAL FIX: Refresh exchange settings from backend before showing dialog
    // This ensures we have the latest minimum exchange points
    final exchangeProvider = ExchangeSettingsProvider.instance;
    await exchangeProvider.refreshSettings(forceRefresh: true);

    final minExchangePoints = exchangeProvider.getMinExchangePoints();

    // PROFESSIONAL FIX: Show professional modal dialog instead of SnackBar
    if (currentPoints < minExchangePoints) {
      _showMinimumPointsRequiredModal(
        context,
        currentPoints: currentPoints,
        minRequired: minExchangePoints,
      );
      return;
    }

    if (currentPoints <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You have no points to exchange yet.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final userId = user.id.toString();
    final rawPhone = user.phone?.trim();

    // Show modal bottom sheet with proper StatefulWidget for lifecycle management
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      isDismissible: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        // Use StatefulWidget to properly manage controllers and focus nodes
        return _ExchangeRequestBottomSheet(
          userId: userId,
          currentPoints: currentPoints,
          initialPhone: rawPhone ?? '',
          onSuccess: (points) {
            // Refresh data after successful exchange
            _loadPoints();
          },
        );
      },
    );
  }
}

/// StatefulWidget for Exchange Request Bottom Sheet
/// Properly manages TextEditingController and FocusNode lifecycle
class _ExchangeRequestBottomSheet extends StatefulWidget {
  final String userId;
  final int currentPoints;
  final String initialPhone;
  final Function(int) onSuccess;

  const _ExchangeRequestBottomSheet({
    required this.userId,
    required this.currentPoints,
    required this.initialPhone,
    required this.onSuccess,
  });

  @override
  State<_ExchangeRequestBottomSheet> createState() =>
      _ExchangeRequestBottomSheetState();
}

class _ExchangeRequestBottomSheetState
    extends State<_ExchangeRequestBottomSheet> {
  late final TextEditingController _phoneController;
  late final TextEditingController _customPointController;
  late final FocusNode _customPointFocusNode;
  bool _isSubmitting = false;
  late ExchangeSettingsProvider _exchangeProvider;

  @override
  void initState() {
    super.initState();
    // Initialize controllers and focus node in initState
    _phoneController = TextEditingController(text: widget.initialPhone);
    _customPointController = TextEditingController();
    _customPointFocusNode = FocusNode();

    // Get exchange settings provider
    _exchangeProvider = ExchangeSettingsProvider.instance;

    // PROFESSIONAL FIX: Force refresh exchange settings when dialog opens
    // This ensures we always have the latest minimum exchange points from backend
    // When backend updates the limit, app will fetch fresh data immediately
    _exchangeProvider.refreshSettings(forceRefresh: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // PROFESSIONAL FIX: Refresh settings when dependencies change
    // This ensures we get latest data if provider was updated elsewhere
    _exchangeProvider.refreshSettings(forceRefresh: false);
  }

  @override
  void dispose() {
    // Properly dispose controllers and focus node
    // This is called automatically when the widget is removed from the tree
    _phoneController.dispose();
    _customPointController.dispose();
    _customPointFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleConfirm() async {
    final phone = _phoneController.text.trim();

    // Get points value from TextField
    final pointsText = _customPointController.text.trim();
    if (pointsText.isEmpty) {
      _showErrorSnackBar('Please enter the point amount you want to exchange.');
      return;
    }

    final actualPoints = int.tryParse(pointsText);
    if (actualPoints == null || actualPoints <= 0) {
      _showErrorSnackBar('Please enter a valid positive number for points.');
      return;
    }

    // Check minimum exchange points requirement (always get latest from provider)
    final minPoints = _exchangeProvider.getMinExchangePoints();
    if (widget.currentPoints < minPoints) {
      _showErrorSnackBar(
        'You need at least $minPoints PNP to exchange points.\n'
        'Current balance: ${widget.currentPoints} PNP',
      );
      return;
    }

    if (actualPoints > widget.currentPoints) {
      _showErrorSnackBar(
          'You don\'t have enough points. Available: ${widget.currentPoints} pts');
      return;
    }

    if (phone.isEmpty) {
      _showErrorSnackBar('Please enter your current phone number.');
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      // Make the API call
      final requestSuccess = await PointService.createClaimRequest(
        userId: widget.userId,
        points: actualPoints,
        phone: phone,
        note: 'Exchange request for $actualPoints pts from app',
      );

      // Update UI state
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
      });

      // Close the bottom sheet first
      Navigator.of(context).pop();

      // Wait for bottom sheet to fully close
      await Future.delayed(const Duration(milliseconds: 200));

      // Get the root navigator context for showing messages
      final rootContext = Navigator.of(context, rootNavigator: true).context;
      if (!rootContext.mounted) return;

      // Clear any existing messages
      ScaffoldMessenger.of(rootContext).clearSnackBars();

      // Show appropriate message based on result
      if (requestSuccess == true) {
        // SUCCESS: Show simple, clear success message
        _showSuccessSnackBar(rootContext, actualPoints);
        // Call success callback
        widget.onSuccess(actualPoints);
      } else {
        // FAILURE: Show simple failure message
        _showFailureSnackBar(rootContext);
      }
    } catch (e, stackTrace) {
      Logger.error(
        'Error in exchange request: $e',
        tag: 'PointHistoryPage',
        error: e,
        stackTrace: stackTrace,
      );

      // Update UI state
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }

      // Close the bottom sheet
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      // Wait for bottom sheet to close
      await Future.delayed(const Duration(milliseconds: 200));

      // Get the root navigator context
      final rootContext = Navigator.of(context, rootNavigator: true).context;
      if (!rootContext.mounted) return;

      // Show simple error message
      _showErrorSnackBarFromException(rootContext, e);
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccessSnackBar(BuildContext context, int points) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Exchange request submitted successfully!\n$points points will be processed.',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green[600],
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showFailureSnackBar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Failed to submit exchange request.\nPlease try again later.',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.orange[600],
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showErrorSnackBarFromException(BuildContext context, dynamic error) {
    String message = 'An error occurred. Please try again.';
    if (error.toString().contains('SocketException') ||
        error.toString().contains('Network')) {
      message =
          'No internet connection.\nPlease check your network and try again.';
    } else if (error.toString().contains('Timeout')) {
      message = 'Request timed out.\nPlease try again.';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red[600],
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;
    final screenHeight = mediaQuery.size.height;
    final maxHeight = screenHeight * 0.9;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // PROFESSIONAL FIX: Use Consumer to listen to exchange settings provider
    // This ensures UI updates automatically when backend changes the limit
    return Consumer<ExchangeSettingsProvider>(
      builder: (context, exchangeProvider, child) {
        // Calculate progress towards minimum requirement (always get latest)
        final minPoints = exchangeProvider.getMinExchangePoints();
        final progress = minPoints > 0
            ? (widget.currentPoints / minPoints).clamp(0.0, 1.0)
            : 1.0;
        final isEligible = widget.currentPoints >= minPoints;
        final pointsNeeded =
            (minPoints - widget.currentPoints).clamp(0, minPoints);

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white,
                Colors.grey[50]!,
              ],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 12,
              bottom: bottomInset + 24,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Drag handle indicator
                    Center(
                      child: Container(
                        width: 48,
                        height: 5,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey[400],
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),

                    // Creative Header with Gradient
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            mediumYellow.withValues(alpha: 0.2),
                            mediumYellow.withValues(alpha: 0.1),
                            Colors.white,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: mediumYellow.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            mediumYellow,
                                            mediumYellow.withValues(alpha: 0.8),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(
                                            color: mediumYellow.withValues(
                                                alpha: 0.3),
                                            blurRadius: 8,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.swap_horiz_rounded,
                                        color: Colors.white,
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Exchange (လှဲလယ်ရန်)',
                                            style: TextStyle(
                                              fontSize: 24,
                                              fontWeight: FontWeight.bold,
                                              color: colorScheme.onSurface,
                                              letterSpacing: -0.5,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Convert your PNP for processing',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey[600],
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.close_rounded, size: 20),
                              onPressed: () => Navigator.of(context).pop(),
                              color: Colors.grey[700],
                              padding: const EdgeInsets.all(8),
                              constraints: const BoxConstraints(),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Creative Minimum Requirement Card with Progress
                    // Always show if provider has data (or show loading state)
                    if (exchangeProvider.hasData || exchangeProvider.isLoading)
                      _MinRequirementCard(
                        minPoints: minPoints,
                        currentPoints: widget.currentPoints,
                        isEligible: isEligible,
                        progress: progress,
                        pointsNeeded: pointsNeeded,
                        isLoading: exchangeProvider.isLoading,
                      ),

                    if (exchangeProvider.hasData || exchangeProvider.isLoading)
                      const SizedBox(height: 24),

                    // Available Points Card - Enhanced Design
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isEligible
                              ? [
                                  mediumYellow.withValues(alpha: 0.15),
                                  mediumYellow.withValues(alpha: 0.08),
                                  Colors.white,
                                ]
                              : [
                                  Colors.grey[100]!,
                                  Colors.grey[50]!,
                                ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isEligible
                              ? mediumYellow.withValues(alpha: 0.3)
                              : Colors.grey[300]!,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: isEligible
                                ? mediumYellow.withValues(alpha: 0.1)
                                : Colors.grey.withValues(alpha: 0.1),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              gradient: isEligible
                                  ? LinearGradient(
                                      colors: [
                                        mediumYellow,
                                        mediumYellow.withValues(alpha: 0.8),
                                      ],
                                    )
                                  : LinearGradient(
                                      colors: [
                                        Colors.grey[400]!,
                                        Colors.grey[500]!,
                                      ],
                                    ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      (isEligible ? mediumYellow : Colors.grey)
                                          .withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Icon(
                              isEligible
                                  ? Icons.stars_rounded
                                  : Icons.star_border_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Your Available Points',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${widget.currentPoints}',
                                      style: TextStyle(
                                        fontSize: 32,
                                        fontWeight: FontWeight.bold,
                                        color: isEligible
                                            ? mediumYellow
                                            : Colors.grey[700],
                                        letterSpacing: -1,
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 6,
                                        left: 4,
                                      ),
                                      child: Text(
                                        'PNP',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (isEligible)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green[50],
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.green[300]!,
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    color: Colors.green[700],
                                    size: 16,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Eligible',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green[700],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Points input section with creative header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: mediumYellow.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.bolt_rounded,
                              color: mediumYellow,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Points to Exchange',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const ValueKey('point_input'),
                      controller: _customPointController,
                      focusNode: _customPointFocusNode,
                      enabled: true, // Explicitly enable the field
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      // PROFESSIONAL FIX: Use explicit high-contrast color for maximum visibility
                      style: const TextStyle(
                        fontSize: 16,
                        color: Color(
                            0xFF212121), // Material Design primary text color - ensures visibility
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.15, // Better readability
                      ),
                      // PROFESSIONAL FIX: Explicit cursor color for better visibility
                      cursorColor: mediumYellow,
                      cursorWidth: 2.0,
                      cursorRadius: const Radius.circular(1.0),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: InputDecoration(
                        labelText: 'Amount',
                        labelStyle: TextStyle(
                          color: Colors.grey[700],
                          fontSize: 14,
                        ),
                        hintText: 'Enter point amount',
                        hintStyle: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 16,
                        ),
                        helperText: exchangeProvider.hasData
                            ? (widget.currentPoints >= minPoints)
                                ? '✓ Minimum: $minPoints PNP • Maximum: ${widget.currentPoints} PNP'
                                : '⚠ Minimum: $minPoints PNP required • You have: ${widget.currentPoints} PNP'
                            : exchangeProvider.isLoading
                                ? 'Loading exchange settings...'
                                : 'Maximum: ${widget.currentPoints} PNP',
                        helperStyle: TextStyle(
                          color: exchangeProvider.hasData &&
                                  widget.currentPoints < minPoints
                              ? Colors.orange[700]
                              : Colors.grey[600],
                          fontSize: 12,
                          fontWeight: exchangeProvider.hasData &&
                                  widget.currentPoints < minPoints
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                        prefixIcon: const Icon(
                          Icons.bolt_rounded,
                          color: mediumYellow,
                        ),
                        // PROFESSIONAL FIX: Use suffixText instead of suffixIcon for better text visibility
                        // This ensures the input text area has proper space and is visible
                        suffixText: 'PNP',
                        suffixStyle: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.grey[300]!,
                            width: 1.5,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.grey[300]!,
                            width: 1.5,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: mediumYellow,
                            width: 2,
                          ),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.red[300]!,
                            width: 1.5,
                          ),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.red[400]!,
                            width: 2,
                          ),
                        ),
                        // PROFESSIONAL FIX: Use white background for maximum contrast
                        filled: true,
                        fillColor: Colors.white,
                        // PROFESSIONAL FIX: Proper contentPadding ensures text input area has enough space
                        // Right padding accounts for suffixText automatically
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Phone number input section
                    Text(
                      'Contact Information',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      // PROFESSIONAL FIX: Use explicit high-contrast color for maximum visibility
                      style: const TextStyle(
                        fontSize: 16,
                        color: Color(
                            0xFF212121), // Material Design primary text color - ensures visibility
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.15, // Better readability
                      ),
                      // PROFESSIONAL FIX: Explicit cursor color for better visibility
                      cursorColor: Colors.blue,
                      cursorWidth: 2.0,
                      cursorRadius: const Radius.circular(1.0),
                      decoration: InputDecoration(
                        labelText: 'Phone Number',
                        labelStyle: TextStyle(
                          color: Colors.grey[700],
                          fontSize: 14,
                        ),
                        hintText: 'Enter your current phone number',
                        hintStyle: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 16,
                        ),
                        helperText:
                            'This phone number will be used for the exchange process',
                        helperStyle: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                        prefixIcon: const Icon(
                          Icons.phone_iphone_rounded,
                          color: Colors.blue,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.grey[300]!,
                            width: 1.5,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.grey[300]!,
                            width: 1.5,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Colors.blue,
                            width: 2,
                          ),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.red[300]!,
                            width: 1.5,
                          ),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.red[400]!,
                            width: 2,
                          ),
                        ),
                        // PROFESSIONAL FIX: Use white background for maximum contrast
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Submit button
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: (_isSubmitting ||
                                exchangeProvider.isLoading ||
                                (exchangeProvider.hasData &&
                                    widget.currentPoints < minPoints))
                            ? null
                            : _handleConfirm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: mediumYellow,
                          foregroundColor: Colors.white,
                          elevation: 2,
                          shadowColor: mediumYellow.withValues(alpha: 0.4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          disabledBackgroundColor: Colors.grey[300],
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.swap_horiz_rounded,
                                      size: 20),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Confirm Exchange',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),

                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Creative Minimum Requirement Card with Progress Indicator
/// Shows minimum PNP requirement with visual progress and clear messaging
class _MinRequirementCard extends StatelessWidget {
  final int minPoints;
  final int currentPoints;
  final bool isEligible;
  final double progress;
  final int pointsNeeded;
  final bool isLoading;

  const _MinRequirementCard({
    required this.minPoints,
    required this.currentPoints,
    required this.isEligible,
    required this.progress,
    required this.pointsNeeded,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isEligible
              ? [
                  Colors.green[50]!,
                  Colors.green[100]!,
                  Colors.white,
                ]
              : [
                  Colors.orange[50]!,
                  Colors.orange[100]!,
                  Colors.white,
                ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isEligible ? Colors.green[300]! : Colors.orange[300]!,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: (isEligible ? Colors.green : Colors.orange)
                .withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, 6),
            spreadRadius: -2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Icon
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isEligible
                        ? [
                            Colors.green[400]!,
                            Colors.green[600]!,
                          ]
                        : [
                            Colors.orange[400]!,
                            Colors.orange[600]!,
                          ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: (isEligible ? Colors.green : Colors.orange)
                          .withValues(alpha: 0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  isEligible ? Icons.check_circle_rounded : Icons.info_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEligible
                          ? 'Minimum Requirement Met! ✓'
                          : 'Minimum Exchange Requirement',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color:
                            isEligible ? Colors.green[900] : Colors.orange[900],
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isEligible
                          ? 'You can exchange your points'
                          : 'You need at least $minPoints PNP to exchange',
                      style: TextStyle(
                        fontSize: 13,
                        color:
                            isEligible ? Colors.green[700] : Colors.orange[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Progress Indicator
          if (!isEligible) ...[
            // Progress Bar
            Container(
              height: 12,
              decoration: BoxDecoration(
                color: Colors.orange[100],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Stack(
                children: [
                  // Background
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.orange[100],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  // Progress Fill
                  FractionallySizedBox(
                    widthFactor: progress,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.orange[400]!,
                            Colors.orange[600]!,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.orange.withValues(alpha: 0.4),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Points Status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current Balance',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$currentPoints',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange[900],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2, left: 4),
                          child: Text(
                            'PNP',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Points Needed',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange[200],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.orange[400]!,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.trending_up_rounded,
                            color: Colors.orange[900],
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$pointsNeeded PNP',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange[900],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Encouragement Message
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.orange[200]!,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline_rounded,
                    color: Colors.orange[700],
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Keep earning points to reach the minimum requirement!',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange[800],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            // Success Message
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.green[200]!,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.celebration_rounded,
                    color: Colors.green[700],
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'You\'re all set!',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.green[900],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'You have enough points to exchange. Minimum requirement: $minPoints PNP',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// TODO: Loyalty Analytics - Commented out temporarily, will be added back later
/*
/// Analytics statistics data class
class _AnalyticsStats {
  final int totalEarned;
  final int totalRedeemed;
  final int totalExpired;
  final int totalRefunded;
  final int totalAdjusted;
  final int totalReferral;
  final int totalBirthday;
  final int netPoints;
  final double redemptionRate;
  final int transactionCount;
  final Map<BackendTransactionType, int> backendTypeCounts;
  final Map<BackendTransactionType, int> backendTypePoints;
  final int currentBalance;
  final int lifetimeEarned;
  final int lifetimeRedeemed;
  final int lifetimeExpired;
  final int expiringSoon;

  _AnalyticsStats({
    required this.totalEarned,
    required this.totalRedeemed,
    required this.totalExpired,
    required this.totalRefunded,
    required this.totalAdjusted,
    required this.totalReferral,
    required this.totalBirthday,
    required this.netPoints,
    required this.redemptionRate,
    required this.transactionCount,
    required this.backendTypeCounts,
    required this.backendTypePoints,
    required this.currentBalance,
    required this.lifetimeEarned,
    required this.lifetimeRedeemed,
    required this.lifetimeExpired,
    required this.expiringSoon,
  });
}

/// Period statistics for charts
class _PeriodStats {
  final int earned;
  final int redeemed;

  const _PeriodStats({this.earned = 0, this.redeemed = 0});

  _PeriodStats copyWith({int? earned, int? redeemed}) {
    return _PeriodStats(
      earned: earned ?? this.earned,
      redeemed: redeemed ?? this.redeemed,
    );
  }
}

class _AnalyticsTile extends StatelessWidget {
  const _AnalyticsTile({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
    this.icon,
  });

  final String title;
  final String value;
  final String subtitle;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: color.withOpacity(0.9)),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: color.withOpacity(0.9),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
*/
// END: Analytics Classes
