import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:ecommerce_int2/app_properties.dart';
import 'package:ecommerce_int2/theme/app_theme.dart';
import 'package:ecommerce_int2/custom_background.dart';
import 'package:ecommerce_int2/models/product.dart';
import 'package:ecommerce_int2/woocommerce_service.dart';
import 'package:ecommerce_int2/screens/notifications_page.dart';
import 'package:ecommerce_int2/widgets/notification_badge.dart';
import 'package:ecommerce_int2/widgets/network_status_banner.dart';
import 'package:ecommerce_int2/services/connectivity_service.dart';
import 'package:ecommerce_int2/screens/profile/profile_page_new.dart';
import 'package:ecommerce_int2/utils/logger.dart';
import 'package:ecommerce_int2/providers/auth_provider.dart';
import 'package:ecommerce_int2/providers/point_provider.dart';
import 'package:ecommerce_int2/services/usage_tracking_service.dart';
import 'package:ecommerce_int2/models/point_transaction.dart';
import 'package:ecommerce_int2/providers/engagement_provider.dart';
import 'package:ecommerce_int2/widgets/engagement_carousel.dart';
import 'package:ecommerce_int2/screens/points/point_history_page.dart';
import 'package:ecommerce_int2/services/point_notification_manager.dart';
import 'package:ecommerce_int2/services/global_keys.dart';
import 'package:ecommerce_int2/widgets/point_notification_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'components/custom_bottom_bar.dart';
import '../../widgets/responsive_shell.dart';
import '../product/all_products_page.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class MainPage extends StatefulWidget {
  final int?
      engagementItemId; // PROFESSIONAL FIX: Support navigation to specific engagement item

  const MainPage({super.key, this.engagementItemId});

  @override
  _MainPageState createState() => _MainPageState();
}

class _MainPageState extends State<MainPage>
    with TickerProviderStateMixin<MainPage>, WidgetsBindingObserver {
  late TabController bottomTabController; // 0: Home, 1: Profile
  List<Product> products = [];
  bool isLoading = true;
  bool _isDisposed = false;
  static const String _cachedProductsKey = 'cached_products';
  // OPTIMIZED: Cache ConnectivityService instance to avoid repeated creation
  late final ConnectivityService _connectivityService = ConnectivityService();
  // GlobalKey for My Point Widget to allow refresh from parent
  final GlobalKey<_MyPointWidgetState> _myPointWidgetKey =
      GlobalKey<_MyPointWidgetState>();

  // Stream subscription for point notification events
  StreamSubscription<PointNotificationEvent>? _pointNotificationSubscription;
  bool _isModalShowing = false;
  int _lastMainTabIndexForPnp = 0;
  Timer? _homePnpDebouncedRefreshTimer;
  static const Duration _homePnpRefreshDebounce = Duration(seconds: 2);

  // Track point balance changes to detect updates from app side
  int? _lastKnownBalance;
  String? _lastKnownUserId;
  Timer? _pointChangeCheckTimer;
  String? _lastShownTransactionId; // Track last transaction we showed modal for
  DateTime? _lastModalShownTime; // Track when we last showed a modal
  /// After login, skip one balance baseline when [PointProvider] finishes first hydrate.
  bool _initialPointHydrationSyncHandled = false;
  bool _isResumeRefreshInProgress = false;
  DateTime? _lastResumeEngagementRefreshAt;
  static const Duration _resumeEngagementRefreshMinInterval = Duration(
    seconds: 30,
  );
  static const bool _forceNetworkOnResumeForEngagement = false;
  DateTime? _lastHomeTabEngagementRefreshAt;
  static const Duration _homeTabEngagementRefreshMinInterval = Duration(
    seconds: 30,
  );

  /// Poll / engagement automated popups: do not show [PointNotificationModal] from MainPage.
  bool _shouldSilencePollRelatedPointModal(PointNotificationEvent event) {
    // engagement_earned → engagement points (includes poll_win path via FCM / sync)
    if (event.type == PointNotificationType.engagementEarned) {
      return true;
    }
    // points_earned when clearly poll-related
    if (event.type == PointNotificationType.earned) {
      final oid = event.orderId ?? '';
      if (oid.startsWith('engagement:poll:')) return true;
      final itemType = (event.additionalData?['itemType'] ??
              event.additionalData?['item_type'])
          ?.toString()
          .toLowerCase();
      if (itemType == 'poll') return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Bottom navigation now only has Home and Profile tabs.
    bottomTabController = TabController(length: 2, vsync: this);
    _lastMainTabIndexForPnp = bottomTabController.index;
    bottomTabController.addListener(_onBottomTabChangedForMyPnp);
    // Load cached products first, then fetch fresh data if online
    _initializeProducts();
    // Listen for point notification events for modal popup
    _setupPointNotificationListener();
    // Setup point balance change listener
    _setupPointBalanceListener();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshStateAfterResume());
    }
  }

  Future<void> _refreshStateAfterResume() async {
    if (!mounted || _isDisposed || _isResumeRefreshInProgress) return;
    _isResumeRefreshInProgress = true;
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (!authProvider.isAuthenticated || authProvider.user == null) {
        return;
      }
      final engagementProvider = Provider.of<EngagementProvider>(
        context,
        listen: false,
      );
      final userId = authProvider.user!.id.toString();
      final parsedUserId = int.tryParse(userId);
      if (parsedUserId == null) return;

      final now = DateTime.now();
      final shouldRunEngagementNetworkRefresh =
          _forceNetworkOnResumeForEngagement ||
              _lastResumeEngagementRefreshAt == null ||
              now.difference(_lastResumeEngagementRefreshAt!) >=
                  _resumeEngagementRefreshMinInterval;

      if (shouldRunEngagementNetworkRefresh) {
        _lastResumeEngagementRefreshAt = now;
        Logger.info(
          'MainPage resume: engagement cache-first refresh triggered '
          '(force=$_forceNetworkOnResumeForEngagement, minInterval=${_resumeEngagementRefreshMinInterval.inSeconds}s)',
          tag: 'MainPage',
        );
        // Rehydrate immediately from local cache, then fetch latest from API in background.
        await engagementProvider.refreshFromCacheThenNetwork(
          userId: parsedUserId,
          token: authProvider.token,
        );
      } else {
        Logger.info(
          'MainPage resume: skipping engagement refresh '
          '(cooldown active: ${_resumeEngagementRefreshMinInterval.inSeconds}s)',
          tag: 'MainPage',
        );
      }

      if (mounted && !_isDisposed) {
        /*
        Old Code:
        Resume-time point reconcile lived here alongside engagement refresh.
        New Code:
        MyApp (main.dart) runs global [PointProvider.refreshPointState] on resume for all routes.
        */
      }
    } catch (e, st) {
      Logger.error(
        'Failed to refresh main page state after app resume: $e',
        tag: 'MainPage',
        error: e,
        stackTrace: st,
      );
    } finally {
      _isResumeRefreshInProgress = false;
    }
  }

  /// Initialize products: load cache first, then fetch fresh if online
  /// PROFESSIONAL FIX: Await _loadProducts with timeout to ensure loading state
  /// is always cleared - prevents Nav Bar loading spinner from getting stuck
  Future<void> _initializeProducts() async {
    try {
      // Load cached products first (synchronous-like behavior)
      await _loadCachedProducts();

      // Await products load with timeout so loading state is always cleared
      await _loadProducts().timeout(
        const Duration(seconds: 25),
        onTimeout: () {
          Logger.warning(
            'Product load timed out - clearing loading state',
            tag: 'MainPage',
          );
          if (mounted && !_isDisposed) {
            setState(() => isLoading = false);
          }
        },
      );
    } catch (e, st) {
      Logger.error(
        'Error in _initializeProducts: $e',
        tag: 'MainPage',
        error: e,
        stackTrace: st,
      );
      if (mounted && !_isDisposed) {
        setState(() => isLoading = false);
      }
    }
  }

  /// Setup listener for point notification events
  /// PROFESSIONAL FIX: Enhanced listener with better error handling and fallback logic
  void _setupPointNotificationListener() {
    _pointNotificationSubscription =
        PointNotificationManager.modalEvents.listen(
      (event) {
        // Only show modal if we're on the home tab and no modal is currently showing
        // Note: PointNotificationManager also handles modal display directly,
        // so this is a fallback mechanism
        if (mounted && bottomTabController.index == 0 && !_isModalShowing) {
          Logger.info(
            'MainPage: Received point notification event via stream: ${event.type.toString()}, ${event.points} points',
            tag: 'MainPage',
          );

          // Add small delay to ensure PointNotificationManager has a chance to show it first
          // This prevents duplicate modals
          Future.delayed(const Duration(milliseconds: 100), () {
            // Check if modal is still not showing (PointNotificationManager might have shown it)
            if (mounted && !_isModalShowing) {
              if (_shouldSilencePollRelatedPointModal(event)) {
                Logger.info(
                  'MainPage: silencing point modal (poll/engagement rule): ${event.type}',
                  tag: 'MainPage',
                );
                return;
              }
              _showPointNotificationModal(event);
            } else {
              Logger.info(
                'MainPage: Modal already showing (handled by PointNotificationManager), skipping duplicate.',
                tag: 'MainPage',
              );
            }
          });
        } else {
          Logger.info(
            'MainPage: Skipping modal display - mounted: $mounted, tabIndex: ${bottomTabController.index}, isModalShowing: $_isModalShowing',
            tag: 'MainPage',
          );
        }
      },
      onError: (error, stackTrace) {
        Logger.error(
          'Error in point notification stream listener: $error',
          tag: 'MainPage',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );
  }

  /// Setup listener for point balance changes to detect app-side updates
  /// This detects when points change from app operations (not just notifications)
  void _setupPointBalanceListener() {
    // Use a periodic check to monitor point balance changes
    // This ensures we catch updates even if notifyListeners doesn't fire
    // Old Code: const Duration(seconds: 2) — frequent rebuilds during long Home/poll sessions.
    _pointChangeCheckTimer = Timer.periodic(const Duration(seconds: 12), (
      timer,
    ) {
      if (!mounted || _isDisposed || !context.mounted) {
        timer.cancel();
        _pointChangeCheckTimer = null;
        return;
      }

      try {
        // Do not use Provider.of(context) here — timer can fire while this route
        // is deactivated (mounted may still be true). Use app singletons instead.
        final authProvider = AuthProvider();
        final pointProvider = PointProvider.instance;

        // Only check if user is authenticated
        if (!authProvider.isAuthenticated || authProvider.user == null) {
          _lastKnownBalance = null;
          _lastKnownUserId = null;
          _initialPointHydrationSyncHandled = false;
          return;
        }

        final currentUserId = authProvider.user!.id.toString();
        final currentBalance = pointProvider.currentBalance;

        // If user changed, reset tracking
        if (_lastKnownUserId != null && _lastKnownUserId != currentUserId) {
          _lastKnownBalance = currentBalance;
          _lastKnownUserId = currentUserId;
          _initialPointHydrationSyncHandled = false;
          return;
        }

        // Cold start / login: when the first server/cache sync completes, align baseline
        // so we do not treat "0 → real balance" as points earned in this session.
        if (pointProvider.hasCompletedSessionInitialBalanceLoad &&
            !_initialPointHydrationSyncHandled) {
          _initialPointHydrationSyncHandled = true;
          _lastKnownBalance = currentBalance;
          _lastKnownUserId = currentUserId;
          return;
        }

        // Until first hydrate completes, only track balance — do not show "earned" modal.
        if (!pointProvider.hasCompletedSessionInitialBalanceLoad) {
          _lastKnownBalance = currentBalance;
          _lastKnownUserId = currentUserId;
          return;
        }

        // Initialize tracking if first time
        if (_lastKnownBalance == null || _lastKnownUserId == null) {
          _lastKnownBalance = currentBalance;
          _lastKnownUserId = currentUserId;
          return;
        }

        // Detect positive balance change (points earned)
        if (_lastKnownBalance != null && currentBalance > _lastKnownBalance!) {
          final pointsGained = currentBalance - _lastKnownBalance!;

          // PROFESSIONAL FIX: If the balance update was applied from an incoming push snapshot,
          // skip the "balance-change-based" modal to avoid duplicate / wrong-type popups.
          final lastPushSnapshotAt = pointProvider.lastPushBalanceSnapshotAt;
          final isRecentPushSnapshot = lastPushSnapshotAt != null &&
              DateTime.now().difference(lastPushSnapshotAt).inSeconds < 5;
          if (isRecentPushSnapshot) {
            _lastKnownBalance = currentBalance;
            _lastKnownUserId = currentUserId;
            return;
          }

          // Only show modal for significant point gains (avoid noise from small updates)
          // Also check if we've already shown a modal recently (within last 5 seconds) to prevent duplicates
          final now = DateTime.now();
          final recentlyShownModal = _lastModalShownTime != null &&
              now.difference(_lastModalShownTime!).inSeconds < 5;

          if (pointsGained > 0 &&
              bottomTabController.index == 0 &&
              !_isModalShowing &&
              !recentlyShownModal) {
            // Check if this is an engagement-related transaction
            final transactions = pointProvider.transactions;
            final latestTransaction =
                transactions.isNotEmpty ? transactions.first : null;

            // Skip if we've already shown modal for this transaction
            if (latestTransaction != null &&
                latestTransaction.id == _lastShownTransactionId) {
              _lastKnownBalance = currentBalance;
              _lastKnownUserId = currentUserId;
              return;
            }

            // Poll winner PNP is handled via in-app notification (not a blocking modal).
            final latestOrderId = latestTransaction?.orderId;
            if (latestOrderId != null &&
                latestOrderId.startsWith('engagement:poll:')) {
              _lastKnownBalance = currentBalance;
              _lastKnownUserId = currentUserId;
              return;
            }

            Logger.info(
              'Point balance increased from $_lastKnownBalance to $currentBalance (+$pointsGained points). Showing modal.',
              tag: 'MainPage',
            );

            final isEngagementPoints =
                latestTransaction?.orderId?.startsWith('engagement:') ?? false;

            // Trigger modal notification
            final event = PointNotificationEvent(
              type: isEngagementPoints
                  ? PointNotificationType.engagementEarned
                  : PointNotificationType.earned,
              points: pointsGained,
              description: latestTransaction?.description ?? 'Points updated',
              transactionId: latestTransaction?.id,
              orderId: latestTransaction?.orderId,
              currentBalance: currentBalance,
              additionalData:
                  isEngagementPoints && latestTransaction?.orderId != null
                      ? _extractEngagementDataFromOrderId(
                          latestTransaction!.orderId!,
                        )
                      : null,
            );

            // Track that we've shown modal for this transaction
            _lastShownTransactionId = latestTransaction?.id;
            _lastModalShownTime = now;

            if (!mounted || _isDisposed || !context.mounted) {
              _lastKnownBalance = currentBalance;
              _lastKnownUserId = currentUserId;
              return;
            }

            if (!_shouldSilencePollRelatedPointModal(event)) {
              _showPointNotificationModal(event);
            } else {
              Logger.info(
                'MainPage: silencing balance-driven point modal (poll/engagement): ${event.type}',
                tag: 'MainPage',
              );
            }
          }
        }

        // Update last known balance
        _lastKnownBalance = currentBalance;
        _lastKnownUserId = currentUserId;
      } catch (e, stackTrace) {
        Logger.error(
          'Error in point balance change listener: $e',
          tag: 'MainPage',
          error: e,
          stackTrace: stackTrace,
        );
      }
    });
  }

  /// Extract engagement data from orderId
  /// Engagement orderId format: 'engagement:itemType:itemId:timestamp'
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
        tag: 'MainPage',
      );
      return null;
    }
  }

  /// Show point notification modal popup
  /// PROFESSIONAL FIX: Enhanced with better context handling and error recovery
  /// Uses local context if available, falls back to global navigator key
  Future<void> _showPointNotificationModal(PointNotificationEvent event) async {
    if (_isModalShowing) {
      Logger.info(
        'Modal already showing, skipping duplicate modal request.',
        tag: 'MainPage',
      );
      return;
    }

    if (_shouldSilencePollRelatedPointModal(event)) {
      Logger.info(
        'MainPage: _showPointNotificationModal blocked (poll/engagement rule): ${event.type}',
        tag: 'MainPage',
      );
      return;
    }

    _isModalShowing = true;
    _lastModalShownTime = DateTime.now();

    try {
      // Try to use local context first (if mounted and available)
      BuildContext? dialogContext = mounted ? context : null;

      // Verify context is mounted before using
      if (dialogContext != null && !dialogContext.mounted) {
        dialogContext = null;
      }

      // Fallback to global navigator key if local context not available
      if (dialogContext == null) {
        dialogContext = AppKeys.navigatorKey.currentContext;

        // Verify global context is mounted
        if (dialogContext != null && !dialogContext.mounted) {
          dialogContext = null;
        }
      }

      if (dialogContext != null) {
        Logger.info(
          'Showing point notification modal from MainPage: ${event.type.toString()}, ${event.points} points',
          tag: 'MainPage',
        );

        await showDialog(
          context: dialogContext,
          barrierDismissible: false, // User must interact with button
          barrierColor: Colors.black.withValues(alpha: 0.7),
          builder: (context) => PointNotificationModal(event: event),
        );

        Logger.info(
          'Point notification modal closed: ${event.type.toString()}',
          tag: 'MainPage',
        );
      } else {
        Logger.warning(
          'No valid context available to show point notification modal. PointNotificationManager will handle it.',
          tag: 'MainPage',
        );
      }
    } catch (e, stackTrace) {
      Logger.error(
        'Error showing point notification modal: $e',
        tag: 'MainPage',
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      _isModalShowing = false;
    }
  }

  void _onBottomTabChangedForMyPnp() {
    if (_isDisposed || !mounted) return;
    if (bottomTabController.indexIsChanging) return;
    final int current = bottomTabController.index;
    if (current == 0 && _lastMainTabIndexForPnp != 0) {
      _homePnpDebouncedRefreshTimer?.cancel();
      _homePnpDebouncedRefreshTimer = Timer(_homePnpRefreshDebounce, () {
        if (_isDisposed || !mounted) return;
        Logger.info(
          'MainPage: debounced Home revisit refresh for My PNP',
          tag: 'MainPage',
        );
        _myPointWidgetKey.currentState?.refreshBalance();

        final now = DateTime.now();
        final shouldRefreshEngagement =
            _lastHomeTabEngagementRefreshAt == null ||
                now.difference(_lastHomeTabEngagementRefreshAt!) >=
                    _homeTabEngagementRefreshMinInterval;
        if (!shouldRefreshEngagement) {
          Logger.info(
            'MainPage: skipping Home revisit engagement refresh '
            '(cooldown active: ${_homeTabEngagementRefreshMinInterval.inSeconds}s)',
            tag: 'MainPage',
          );
          return;
        }
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        if (!authProvider.isAuthenticated || authProvider.user == null) {
          return;
        }
        _lastHomeTabEngagementRefreshAt = now;
        final engagementProvider = Provider.of<EngagementProvider>(
          context,
          listen: false,
        );
        unawaited(
          engagementProvider
              .refresh(userId: authProvider.user!.id, token: authProvider.token)
              .then((_) {
            Logger.info(
              'MainPage: Home revisit engagement refresh completed',
              tag: 'MainPage',
            );
          }).catchError((Object e, StackTrace st) {
            Logger.warning(
              'MainPage: Home revisit engagement refresh failed: $e',
              tag: 'MainPage',
              error: e,
              stackTrace: st,
            );
          }),
        );
      });
    }
    _lastMainTabIndexForPnp = current;
  }

  @override
  void deactivate() {
    _pointChangeCheckTimer?.cancel();
    _pointChangeCheckTimer = null;
    super.deactivate();
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _homePnpDebouncedRefreshTimer?.cancel();
    bottomTabController.removeListener(_onBottomTabChangedForMyPnp);
    _pointNotificationSubscription?.cancel();
    _pointChangeCheckTimer?.cancel();
    bottomTabController.dispose();
    super.dispose();
  }

  /// Load cached products from local storage
  Future<void> _loadCachedProducts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(_cachedProductsKey);

      if (cachedJson != null && cachedJson.isNotEmpty) {
        final List<dynamic> cachedData = json.decode(cachedJson);
        final cachedProducts = cachedData
            .map((item) => Product.fromJson(item as Map<String, dynamic>))
            .toList();

        if (cachedProducts.isNotEmpty) {
          if (mounted) {
            setState(() {
              products = cachedProducts;
              isLoading = false; // Set loading to false when cache is loaded
            });
          }
          Logger.info(
            'Loaded ${cachedProducts.length} cached products',
            tag: 'MainPage',
          );
        } else {
          Logger.info('Cached products list is empty', tag: 'MainPage');
        }
      } else {
        Logger.info('No cached products found', tag: 'MainPage');
        // PROFESSIONAL FIX: Set loading false when offline so user sees empty state.
        // When online, _loadProducts will set it true then false - don't set here
        // to avoid flicker; rely on _loadProducts with timeout to clear.
        if (!_connectivityService.isConnected && mounted && !_isDisposed) {
          setState(() => isLoading = false);
        }
      }
    } catch (e) {
      Logger.error(
        'Error loading cached products: $e',
        tag: 'MainPage',
        error: e,
      );
      // On error, set loading to false if offline
      // OPTIMIZED: Use cached connectivity service
      if (!_connectivityService.isConnected && mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  /// Save products to local storage for offline viewing
  Future<void> _saveProductsToCache(List<Product> productsToCache) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final productsJson = json.encode(
        productsToCache.map((p) => p.toJson()).toList(),
      );
      await prefs.setString(_cachedProductsKey, productsJson);
      Logger.info('Cached ${productsToCache.length} products', tag: 'MainPage');
    } catch (e) {
      Logger.error('Error caching products: $e', tag: 'MainPage', error: e);
    }
  }

  Future<void> _loadProducts({
    int page = 1,
    bool skipLoadingState = false,
  }) async {
    if (_isDisposed) return;

    Logger.info('Loading products for page $page', tag: 'MainPage');

    // PROFESSIONAL FIX: Allow skipping loading state when called from refresh
    // (loading state is already set immediately in _refreshAllHomePageData)
    if (!skipLoadingState && mounted) {
      setState(() {
        isLoading = true;
      });
    }

    try {
      // Check connectivity first
      // OPTIMIZED: Use cached connectivity service
      final isOnline = _connectivityService.isConnected;

      if (!isOnline) {
        Logger.info(
          'Device is offline, loading cached products',
          tag: 'MainPage',
        );
        // Always try to load cached products when offline
        await _loadCachedProducts();
        // Set loading to false to show cached products
        if (mounted) {
          setState(() {
            isLoading = false;
          });
        }
        return;
      }

      final stopwatch = Stopwatch()..start();
      final wooProducts =
          await WooCommerceService.getProducts(perPage: 20, page: page).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          Logger.warning('Product loading timeout', tag: 'MainPage');
          throw Exception('Request timeout');
        },
      );
      stopwatch.stop();

      Logger.logPerformance('Load Products', stopwatch.elapsed);

      if (_isDisposed) return;

      final convertedProducts =
          wooProducts.map((wooProduct) => wooProduct.toProduct()).toList();

      // Cache products for offline viewing
      await _saveProductsToCache(convertedProducts);

      if (mounted) {
        setState(() {
          products = convertedProducts;
          // PROFESSIONAL FIX: Only set isLoading = false if not called from refresh
          // (refresh handles its own loading state)
          if (!skipLoadingState) {
            isLoading = false;
          }
        });
      }

      Logger.info(
        'Successfully loaded ${convertedProducts.length} products',
        tag: 'MainPage',
      );
    } catch (e, stackTrace) {
      Logger.logError('Load Products', e, stackTrace: stackTrace);
      // On error, try to load cached products as fallback
      if (mounted) {
        // Try to load cached products if available
        if (products.isEmpty) {
          await _loadCachedProducts();
        }
        setState(() {
          // Don't clear products on error - keep cached ones
          // PROFESSIONAL FIX: Only set isLoading = false if not called from refresh
          if (!skipLoadingState) {
            isLoading = false;
          }
        });
      }
    }
  }

  /// Refresh all Home Page data: products, points, and transactions
  /// OPTIMIZED: Immediate UI feedback + parallel execution for better performance
  Future<void> _refreshAllHomePageData() async {
    // PROFESSIONAL FIX: Set loading state immediately for instant UI feedback
    // This makes the refresh feel instant to the user
    if (mounted) {
      setState(() {
        isLoading = true;
      });
    }

    // Get providers once
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final pointProvider = Provider.of<PointProvider>(context, listen: false);
    final engagementProvider = Provider.of<EngagementProvider>(
      context,
      listen: false,
    );
    final user = authProvider.user;

    try {
      // PROFESSIONAL FIX: Run independent operations in parallel for faster refresh
      // Products loading and user data refresh can happen simultaneously
      final List<Future<void>> refreshTasks = [];

      // Task 1: Load products (independent operation)
      // Skip loading state since we already set it above
      refreshTasks.add(
        _loadProducts(page: 1, skipLoadingState: true).catchError((e) {
          Logger.warning(
            'Error loading products during refresh: $e',
            tag: 'MainPage',
          );
        }),
      );

      // Task 2: Refresh user-related data (if authenticated)
      if (authProvider.isAuthenticated &&
          user != null &&
          authProvider.token != null) {
        final userId = user.id.toString();

        // Refresh user and balance together for pull-to-refresh freshness.
        refreshTasks.add(
          (() async {
            try {
              /*
              Old Code:
              await authProvider.refreshUser();
              await Future.wait([
                pointProvider.loadBalance(userId, forceRefresh: true),
                ...
              ]);
              */
              await Future.wait([
                authProvider.refreshUser(),
                pointProvider.loadBalance(userId, forceRefresh: true),
              ]);
              Logger.info(
                'MainPage pull-to-refresh: refreshUser + loadBalance(forceRefresh) completed',
                tag: 'MainPage',
              );
              await Future.wait([
                pointProvider.loadTransactions(userId, forceRefresh: true),
                engagementProvider.refresh(
                  userId: user.id,
                  token: authProvider.token!,
                ),
              ]);
            } catch (e) {
              Logger.warning(
                'Error refreshing user data during refresh: $e',
                tag: 'MainPage',
              );
              // Error is logged, continue execution (don't throw)
            }
          })(),
        );
      }

      // Wait for all refresh tasks with timeout to prevent loading from getting stuck
      // if any provider (engagement, points, etc.) hangs
      await Future.wait(refreshTasks).timeout(
        const Duration(seconds: 45),
        onTimeout: () {
          Logger.warning(
            'Refresh timed out after 45s - some tasks may not have completed',
            tag: 'MainPage',
          );
          return <void>[];
        },
      );

      // Refresh UI widgets (non-blocking, can happen after data loads)
      if (mounted) {
        // These are synchronous UI updates, safe to call after async operations
        _myPointWidgetKey.currentState?.refreshBalance();
      }
    } catch (e, stackTrace) {
      Logger.error(
        'Error during refresh: $e',
        tag: 'MainPage',
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      // Ensure loading state is cleared even if errors occur
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return NetworkStatusBanner(child: _buildMainContent(context));
  }

  Widget _buildMainContent(BuildContext context) {
    Widget appBar = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: const _PlanetMMHeader()),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Notification Icon Button
              NotificationBadge(
                child: IconButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => NotificationsPage()),
                  ),
                  icon: const Icon(Icons.notifications),
                  tooltip: 'Notifications',
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final bool wideWeb = kIsWeb && ResponsiveShell.isWideLayout(context);

    final Widget tabBody = CustomPaint(
      painter: MainBackground(),
      child: TabBarView(
        controller: bottomTabController,
        physics: const NeverScrollableScrollPhysics(),
        children: <Widget>[
          SafeArea(
            child: RefreshIndicator(
              onRefresh: () async {
                // Refresh all Home Page data
                await _refreshAllHomePageData();
              },
              child: Builder(
                builder: (context) => CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: ClampingScrollPhysics(),
                  ),
                  slivers: [
                    // AppBar
                    SliverToBoxAdapter(child: appBar),
                    // My Point Widget - Creative display
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: _MyPointWidget(key: _myPointWidgetKey),
                      ),
                    ),
                    // Action Buttons (Buy Now)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: const _HomeActionButtons(),
                      ),
                    ),
                    // Interactive Engagement Carousel
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: EngagementCarousel(
                          initialItemId: widget
                              .engagementItemId, // PROFESSIONAL FIX: Pass item ID for navigation
                        ),
                      ),
                    ),
                    // FIXED: Add minimal bottom padding for safe area above bottom nav
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: MediaQuery.of(context).padding.bottom + 8,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Only Home and Profile tabs are accessible from the bottom bar.
          ProfilePageNew(),
        ],
      ),
    );

    if (wideWeb) {
      return Scaffold(
        body: Row(
          children: [
            WebSideNavigation(controller: bottomTabController),
            Expanded(
              child: ResponsiveShell(child: tabBody),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      bottomNavigationBar: CustomBottomBar(controller: bottomTabController),
      body: ResponsiveShell(child: tabBody),
    );
  }
}

/// Modern, creative action buttons for Home Page
/// Uses Material Design 3 features with enhanced visual appeal
/// OPTIMIZED: Converted to StatefulWidget to cache providers and prevent unnecessary rebuilds
class _HomeActionButtons extends StatefulWidget {
  const _HomeActionButtons();

  @override
  State<_HomeActionButtons> createState() => _HomeActionButtonsState();
}

class _HomeActionButtonsState extends State<_HomeActionButtons>
    with WidgetsBindingObserver {
  /// Handle usage tracking lifecycle changes
  void _handleUsageTrackingLifecycle(AppLifecycleState state) {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      if (!authProvider.isAuthenticated || authProvider.user == null) {
        return;
      }

      final userId = authProvider.user!.id.toString();

      if (state == AppLifecycleState.resumed) {
        // App resumed - start tracking
        UsageTrackingService.startSession(userId).catchError((e) {
          Logger.warning('Failed to start usage tracking: $e', tag: 'MainPage');
          return false;
        });
      } else if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.inactive) {
        // App paused - end tracking
        UsageTrackingService.endSession(userId).catchError((e) {
          Logger.warning('Failed to end usage tracking: $e', tag: 'MainPage');
          return false;
        });
      }
    } catch (e) {
      Logger.warning(
        'Error handling usage tracking lifecycle: $e',
        tag: 'MainPage',
      );
    }
  }

  /// Handle app lifecycle changes
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _handleUsageTrackingLifecycle(state);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        4,
        8,
        4,
        0,
      ), // No bottom padding to prevent extra space
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Buy Now Button - High-contrast PlanetMM primary color
          _ModernActionButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AllProductsPage()),
              );
            },
            icon: Icons.shopping_bag_rounded,
            label: 'Buy Now (ဝယ်ယူမည်)',
            subtitle: 'PNP ဝယ်ယူရန် ကြည့်ရှုမည်',
            // Use deep blue background with white text for strong contrast
            backgroundColor: AppTheme.deepBlue,
            foregroundColor: AppTheme.white,
            iconColor: AppTheme.white,
            isPrimary: true,
          ),
        ],
      ),
    );
  }
}

class _ModernActionButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final String? subtitle;
  final Widget? subtitleWidget; // Optional animated subtitle widget
  final Color backgroundColor;
  final Color foregroundColor;
  final Color iconColor;
  final bool isPrimary;
  final Color? borderColor;

  const _ModernActionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    this.subtitle,
    this.subtitleWidget,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.iconColor,
    this.isPrimary = false,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(20),
            border: borderColor != null
                ? Border.all(color: borderColor!, width: 2)
                : null,
            boxShadow: isPrimary
                ? [
                    BoxShadow(
                      color: mediumYellow.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                      spreadRadius: 0,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Row(
            children: [
              // Icon container with modern styling
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isPrimary
                      ? darkGrey.withValues(alpha: 0.1)
                      : iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 16),
              // Text content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: foregroundColor,
                        letterSpacing: 0.2,
                      ),
                    ),
                    if (subtitleWidget != null) ...[
                      const SizedBox(height: 4),
                      subtitleWidget!,
                    ] else if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: foregroundColor.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Arrow icon with transparent background
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: foregroundColor.withValues(alpha: 0.6),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Creative PlanetMM header shown at the top-left of the Home page
class _PlanetMMHeader extends StatelessWidget {
  const _PlanetMMHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // PlanetMM logo with circular frame
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [AppTheme.deepBlue, mediumYellow],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: mediumYellow.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Image.asset(
              'assets/icons/planetmm_inapplogo.png',
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Brand text
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Planet',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: darkGrey,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  'MM',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: mediumYellow,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Lifestyle & Rewards',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: darkGrey.withValues(alpha: 0.65),
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Creative Lucky Box Banner Widget
/// Displays HTML content from plugin in a beautiful, mobile-friendly design
class _MyPnpPointVm {
  const _MyPnpPointVm({
    required this.balance,
    required this.balanceIdentityEpoch,
    required this.pointIsLoading,
    required this.pointErrorMessage,
    required this.pointInitialHydrateDone,
    required this.hasPointBalanceObject,
    required this.isSyncingBalance,
    required this.balanceSyncLoadingSubtitle,
    required this.balanceSyncUsesExtendedPollWinUi,
    required this.syncNoticeMessage,
  });

  final int balance;
  final int balanceIdentityEpoch;
  final bool pointIsLoading;
  final String? pointErrorMessage;
  final bool pointInitialHydrateDone;
  final bool hasPointBalanceObject;
  final bool isSyncingBalance;
  final String balanceSyncLoadingSubtitle;
  final bool balanceSyncUsesExtendedPollWinUi;
  final String? syncNoticeMessage;

  @override
  bool operator ==(Object other) {
    return other is _MyPnpPointVm &&
        other.balance == balance &&
        other.balanceIdentityEpoch == balanceIdentityEpoch &&
        other.pointIsLoading == pointIsLoading &&
        other.pointErrorMessage == pointErrorMessage &&
        other.pointInitialHydrateDone == pointInitialHydrateDone &&
        other.hasPointBalanceObject == hasPointBalanceObject &&
        other.isSyncingBalance == isSyncingBalance &&
        other.balanceSyncLoadingSubtitle == balanceSyncLoadingSubtitle &&
        other.balanceSyncUsesExtendedPollWinUi ==
            balanceSyncUsesExtendedPollWinUi &&
        other.syncNoticeMessage == syncNoticeMessage;
  }

  @override
  int get hashCode => Object.hash(
        balance,
        balanceIdentityEpoch,
        pointIsLoading,
        pointErrorMessage,
        pointInitialHydrateDone,
        hasPointBalanceObject,
        isSyncingBalance,
        balanceSyncLoadingSubtitle,
        balanceSyncUsesExtendedPollWinUi,
        syncNoticeMessage,
      );
}

/// Creative My Point Widget - Displays user's point balance in a beautiful card
class _MyPointWidget extends StatefulWidget {
  const _MyPointWidget({super.key});

  @override
  State<_MyPointWidget> createState() => _MyPointWidgetState();
}

class _MyPointWidgetState extends State<_MyPointWidget> {
  /*
  Old Code:
  bool _isInitialLoadComplete = false;
  */
  bool _isRefreshing = false;
  String? _lastUserId; // Track last user ID to detect account switches

  @override
  void initState() {
    super.initState();
    // Trigger initial load after first frame to ensure context is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadBalanceIfNeeded();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // PROFESSIONAL FIX: Detect user account switches and reset widget state
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.isAuthenticated && authProvider.user != null) {
      final currentUserId = authProvider.user!.id.toString();
      if (_lastUserId != null && _lastUserId != currentUserId) {
        // User account changed - reset widget state
        Logger.info(
          'MyPointWidget - User account changed from $_lastUserId to $currentUserId, resetting state',
          tag: 'MyPointWidget',
        );
        setState(() {
          _isRefreshing = false;
        });
        _lastUserId = currentUserId;
        // Reload balance for new user
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _loadBalanceIfNeeded();
          }
        });
      } else {
        _lastUserId = currentUserId;
      }
    } else if (_lastUserId != null) {
      // User logged out
      _lastUserId = null;
      setState(() {
        _isRefreshing = false;
      });
    }
  }

  /// Public method to refresh balance - called from parent when refresh is triggered
  Future<void> refreshBalance() async {
    if (!mounted) return;
    /*
    Old Code:
    setState(() {
      _isInitialLoadComplete = false;
    });
    */

    // Load balance again
    await _loadBalanceIfNeeded();
  }

  /// Load/refresh balance whenever requested (guarded by [_isRefreshing]).
  /// PROFESSIONAL FIX: Validates user ID, timeout to prevent loading spinner from getting stuck
  Future<void> _loadBalanceIfNeeded() async {
    if (!mounted || _isRefreshing) return;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!authProvider.isAuthenticated || authProvider.user == null) {
      return;
    }

    final userId = authProvider.user!.id.toString();

    // PROFESSIONAL FIX: Check if user changed - if so, reset and reload
    if (_lastUserId != null && _lastUserId != userId) {
      Logger.info(
        'MyPointWidget - User changed during load, resetting and reloading',
        tag: 'MyPointWidget',
      );
      _lastUserId = userId;
    }

    // Removed old "load once" guard to allow revisit refresh.

    final pointProvider = Provider.of<PointProvider>(context, listen: false);

    // Always load on initial page load to ensure fresh data
    if (mounted) {
      setState(() {
        _isRefreshing = true;
      });
    }

    try {
      Logger.info(
        'MyPointWidget - Loading balance for user: $userId',
        tag: 'MyPointWidget',
      );

      // PROFESSIONAL FIX: Wrap in timeout so loading never gets stuck (e.g. API hang)
      /*
      // Old Code:
      await Future.wait([
        authProvider.refreshUser(),
        pointProvider.loadBalance(userId, forceRefresh: true),
      ]).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          Logger.warning(
            'MyPointWidget - Balance load timed out after 30s',
            tag: 'MyPointWidget',
          );
          return <void>[];
        },
      );
      */

      /*
      Old Code:
      await pointProvider.refreshPointState(
        userId: userId,
        forceRefresh: true,
        refreshBalance: true,
        refreshTransactions: false,
        refreshUserCallback: () => authProvider.refreshUser(),
      ).timeout(...)
      */
      await Future.wait([
        authProvider.refreshUser(),
        pointProvider.loadBalance(userId, forceRefresh: true),
      ]).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          Logger.warning(
            'MyPointWidget - Balance load timed out after 30s',
            tag: 'MyPointWidget',
          );
          return <void>[];
        },
      );
      Logger.info(
        'MyPointWidget - refreshUser + loadBalance(forceRefresh) pairing completed',
        tag: 'MyPointWidget',
      );

      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }

      Logger.info(
        'MyPointWidget - Balance loaded successfully',
        tag: 'MyPointWidget',
      );
    } catch (e) {
      Logger.error(
        'Error loading balance in MyPointWidget: $e',
        tag: 'MyPointWidget',
        error: e,
      );
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  /// Extract numeric value from points_balance string
  /// Handles various formats: "100", "100 points", "0", etc.
  // ignore: unused_element — retained for legacy My PNP max-balance logic (commented above).
  String _extractBalanceValue(String? rawValue) {
    if (rawValue == null || rawValue.isEmpty) {
      return '0';
    }

    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      return '0';
    }

    // Try parsing as integer first (handles pure numbers like "0", "100")
    final parsedInt = int.tryParse(trimmed);
    if (parsedInt != null) {
      return parsedInt.toString();
    }

    // Extract first number sequence from string (handles "100 points", etc.)
    final match = RegExp(r'\d+').firstMatch(trimmed);
    if (match != null) {
      return match.group(0)!;
    }

    // Fallback to original value if no number found
    return trimmed;
  }

  @override
  Widget build(BuildContext context) {
    /*
    Old Code:
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Use listen: true to rebuild when user data or point balance changes
    final authProvider = Provider.of<AuthProvider>(context, listen: true);
    final pointProvider = Provider.of<PointProvider>(context, listen: true);

    // Only show if user is authenticated
    if (!authProvider.isAuthenticated || authProvider.user == null) {
      return const SizedBox.shrink();
    }

    // ... balanceFromProvider / displayBalance / isLoading from pointProvider ...
    return RepaintBoundary(
      ...
    );
    */

    // Keep auth subscription at top level; point slices use one Selector<_MyPnpPointVm> below.
    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        /*
        Old Code — multiple independent [context.select] calls on [PointProvider] per build.

        ...
        (
          ...
        ); // duplicated slice reads — replaced by Selector<_MyPnpPointVm> for fewer rebuild deps.
        */
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;

        if (!authProvider.isAuthenticated || authProvider.user == null) {
          return const SizedBox.shrink();
        }

        final pointProvider = context.read<PointProvider>();

        return Selector<PointProvider, _MyPnpPointVm>(
          selector: (_, p) => _MyPnpPointVm(
            balance: p.currentBalance,
            balanceIdentityEpoch: p.balanceIdentityEpoch,
            pointIsLoading: p.isLoading,
            pointErrorMessage: p.errorMessage,
            pointInitialHydrateDone: p.hasCompletedSessionInitialBalanceLoad,
            hasPointBalanceObject: p.balance != null,
            isSyncingBalance: p.isSyncingBalance,
            balanceSyncLoadingSubtitle: p.balanceSyncLoadingSubtitle,
            balanceSyncUsesExtendedPollWinUi:
                p.balanceSyncUsesExtendedPollWinUi,
            syncNoticeMessage: p.syncNoticeMessage,
          ),
          shouldRebuild: (prev, next) => true,
          builder: (context, vm, _) {
            Logger.info(
              'DEBUG_SYNC: My PNP vm balance=${vm.balance} isLoading=${vm.pointIsLoading} '
              'isSyncingBalance=${vm.isSyncingBalance}',
              tag: 'MyPointWidget',
            );

            final syncNotice = vm.syncNoticeMessage;
            if (syncNotice != null && syncNotice.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final msg = pointProvider.consumeSyncNoticeMessage();
                if (msg == null || msg.isEmpty || !context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(msg),
                    duration: const Duration(seconds: 2),
                  ),
                );
              });
            }

            /*
        // Old Code:
        final user = authProvider.user!;
        */

            /*
        // Old Code:
        // Priority 1: Check for my_point or my_points (primary source for display)
        ...
        */

            // Home My PNP — single source of truth: [PointProvider.currentBalance] only.
            Logger.info(
              'MyPointWidget - Using PointProvider balance directly: ${vm.balance}',
              tag: 'MyPointWidget',
            );
            /*
        // OLD CODE:
        ...
        */

            // NEW FIX: Do not show misleading "0" before first trustworthy hydrate; use ··· / strip.
            final bool trustworthyBalanceForUi =
                vm.pointInitialHydrateDone || vm.hasPointBalanceObject;
            final bool showBalancePlaceholder = !trustworthyBalanceForUi;
            final int displayBalanceValue =
                trustworthyBalanceForUi ? vm.balance : 0;
            final bool showLoadingStrip =
                _isRefreshing || (vm.pointIsLoading && showBalancePlaceholder);
            final bool showSyncWarning = !showLoadingStrip &&
                vm.pointErrorMessage != null &&
                vm.pointErrorMessage!.isNotEmpty;

            final bool myPnpPointsReconciling = vm.isSyncingBalance ||
                (vm.pointIsLoading && trustworthyBalanceForUi);

            return RepaintBoundary(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.primary.withValues(alpha: 0.1),
                      colorScheme.secondary.withValues(alpha: 0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.2),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.1),
                      blurRadius: 12,
                      spreadRadius: 0,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: AbsorbPointer(
                    absorbing: myPnpPointsReconciling,
                    child: InkWell(
                      onTap: () {
                        // Navigate to My Points page (Point History with Exchange Process)
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const PointHistoryPage(),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            // Icon with gradient background
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    colorScheme.primary,
                                    colorScheme.secondary,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: colorScheme.primary.withValues(
                                      alpha: 0.3,
                                    ),
                                    blurRadius: 8,
                                    spreadRadius: 0,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.account_balance_wallet_rounded,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 16),
                            // Point balance info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'My PNP',
                                    style:
                                        theme.textTheme.labelMedium?.copyWith(
                                      color: colorScheme.onSurface
                                          .withValues(alpha: 0.6),
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  if (showLoadingStrip)
                                    SizedBox(
                                      height: 24,
                                      width: 80,
                                      child: LinearProgressIndicator(
                                        backgroundColor:
                                            colorScheme.surfaceContainerHighest,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          colorScheme.primary,
                                        ),
                                        minHeight: 2,
                                      ),
                                    )
                                  else if (showBalancePlaceholder)
                                    SizedBox(
                                      height: 32,
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          '···',
                                          style: theme.textTheme.headlineMedium
                                              ?.copyWith(
                                            color: colorScheme.primary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 28,
                                            height: 1.2,
                                            letterSpacing: 6,
                                          ),
                                        ),
                                      ),
                                    )
                                  else if (vm.isSyncingBalance)
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          height: 28,
                                          width: 140,
                                          child: Shimmer.fromColors(
                                            baseColor: colorScheme
                                                .surfaceContainerHighest,
                                            highlightColor:
                                                colorScheme.primary.withValues(
                                              alpha:
                                                  vm.balanceSyncUsesExtendedPollWinUi
                                                      ? 0.42
                                                      : 0.25,
                                            ),
                                            period: Duration(
                                              milliseconds:
                                                  vm.balanceSyncUsesExtendedPollWinUi
                                                      ? 700
                                                      : 1300,
                                            ),
                                            child: Container(
                                              height: 26,
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          vm.balanceSyncLoadingSubtitle,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: colorScheme.onSurface
                                                .withValues(alpha: 0.55),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    )
                                  else
                                    Opacity(
                                      opacity: (myPnpPointsReconciling &&
                                              !vm.isSyncingBalance)
                                          ? 0.48
                                          : 1.0,
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.baseline,
                                        textBaseline: TextBaseline.alphabetic,
                                        children: [
                                          Text(
                                            'ⓟ',
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                              color: colorScheme.onSurface
                                                  .withValues(alpha: 0.7),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(width: 6),

                                          /*
                                      Old Code — nested Selector on balance (redundant once vm bundles rebuilds):

                                      Selector<PointProvider, int>(
                                        selector: (_, provider) =>
                                            provider.currentBalance,
                                        builder: (context, animatedBalance, __) {
                                              final target =
                                                  trustworthyBalanceForUi
                                                      ? animatedBalance
                                                      : displayBalanceValue;
                                              return _AnimatedPointCounter(
                                                value: target,
                                              ...
                                              );
                                            },
                                      ),
                                      */
                                          _AnimatedPointCounter(
                                            value: displayBalanceValue,
                                            duration: const Duration(
                                              milliseconds: 650,
                                            ),
                                            style: theme
                                                .textTheme.headlineMedium
                                                ?.copyWith(
                                              color: colorScheme.primary,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 28,
                                              height: 1.2,
                                            ),
                                          ),
                                          if (showSyncWarning) ...[
                                            const SizedBox(width: 8),
                                            Tooltip(
                                              message:
                                                  vm.pointErrorMessage ?? '',
                                              child: IconButton(
                                                visualDensity:
                                                    VisualDensity.compact,
                                                constraints:
                                                    const BoxConstraints(
                                                  minWidth: 28,
                                                  minHeight: 28,
                                                ),
                                                padding: EdgeInsets.zero,
                                                splashRadius: 16,
                                                icon: Icon(
                                                  Icons.error_outline_rounded,
                                                  size: 18,
                                                  color: Colors.orange.shade700,
                                                ),
                                                onPressed: () async {
                                                  final user =
                                                      authProvider.user;
                                                  if (user == null) return;
                                                  final uid =
                                                      user.id.toString();
                                                  await pointProvider
                                                      .loadBalance(
                                                    uid,
                                                    forceRefresh: true,
                                                  );
                                                  if (!context.mounted) return;
                                                  final msg = pointProvider
                                                      .errorMessage;
                                                  if (msg != null &&
                                                      msg.isNotEmpty) {
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      SnackBar(
                                                        content: Text(msg),
                                                      ),
                                                    );
                                                  }
                                                },
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            // Arrow icon
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.arrow_forward_ios_rounded,
                                color: colorScheme.onPrimaryContainer,
                                size: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _AnimatedPointCounter extends ImplicitlyAnimatedWidget {
  final int value;
  final TextStyle? style;

  const _AnimatedPointCounter({
    required this.value,
    required Duration duration,
    this.style,
  }) : super(duration: duration, curve: Curves.easeOutCubic);

  @override
  ImplicitlyAnimatedWidgetState<_AnimatedPointCounter> createState() =>
      _AnimatedPointCounterState();
}

class _AnimatedPointCounterState
    extends AnimatedWidgetBaseState<_AnimatedPointCounter> {
  IntTween? _valueTween;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _valueTween = visitor(
      _valueTween,
      widget.value,
      (dynamic value) => IntTween(begin: value as int),
    ) as IntTween?;
  }

  @override
  Widget build(BuildContext context) {
    final current = _valueTween?.evaluate(animation) ?? widget.value;
    return Text('$current', style: widget.style);
  }
}
