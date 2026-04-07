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
import 'package:ecommerce_int2/providers/spin_wheel_provider.dart';
import 'package:ecommerce_int2/providers/engagement_provider.dart';
import 'package:ecommerce_int2/widgets/lucky_box_request_sheet.dart';
import 'package:ecommerce_int2/widgets/engagement_carousel.dart';
import 'package:ecommerce_int2/services/spin_wheel_service.dart';
import 'package:ecommerce_int2/screens/points/point_history_page.dart';
import 'package:ecommerce_int2/services/point_notification_manager.dart';
import 'package:ecommerce_int2/services/global_keys.dart';
import 'package:ecommerce_int2/widgets/point_notification_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'components/custom_bottom_bar.dart';
import '../product/all_products_page.dart';

class MainPage extends StatefulWidget {
  final int?
      engagementItemId; // PROFESSIONAL FIX: Support navigation to specific engagement item

  const MainPage({super.key, this.engagementItemId});

  @override
  _MainPageState createState() => _MainPageState();
}

class _MainPageState extends State<MainPage>
    with TickerProviderStateMixin<MainPage> {
  late TabController bottomTabController; // 0: Home, 1: Profile
  List<Product> products = [];
  bool isLoading = true;
  bool _isDisposed = false;
  static const String _cachedProductsKey = 'cached_products';
  // OPTIMIZED: Cache ConnectivityService instance to avoid repeated creation
  late final ConnectivityService _connectivityService = ConnectivityService();
  // GlobalKey for Lucky Box Banner widget to allow refresh from parent
  final GlobalKey<_LuckyBoxBannerWidgetState> _luckyBoxBannerKey =
      GlobalKey<_LuckyBoxBannerWidgetState>();
  // GlobalKey for My Point Widget to allow refresh from parent
  final GlobalKey<_MyPointWidgetState> _myPointWidgetKey =
      GlobalKey<_MyPointWidgetState>();

  // Stream subscription for point notification events
  StreamSubscription<PointNotificationEvent>? _pointNotificationSubscription;
  bool _isModalShowing = false;

  // Track point balance changes to detect updates from app side
  int? _lastKnownBalance;
  String? _lastKnownUserId;
  Timer? _pointChangeCheckTimer;
  String? _lastShownTransactionId; // Track last transaction we showed modal for
  DateTime? _lastModalShownTime; // Track when we last showed a modal
  /// After login, skip one balance baseline when [PointProvider] finishes first hydrate.
  bool _initialPointHydrationSyncHandled = false;

  @override
  void initState() {
    super.initState();
    // Bottom navigation now only has Home and Profile tabs.
    bottomTabController = TabController(length: 2, vsync: this);
    // Load cached products first, then fetch fresh data if online
    _initializeProducts();
    // Listen for point notification events for modal popup
    _setupPointNotificationListener();
    // Setup point balance change listener
    _setupPointBalanceListener();
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
      Logger.error('Error in _initializeProducts: $e',
          tag: 'MainPage', error: e, stackTrace: st);
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
    _pointChangeCheckTimer =
        Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted || _isDisposed) {
        timer.cancel();
        return;
      }

      try {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final pointProvider =
            Provider.of<PointProvider>(context, listen: false);

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
                          latestTransaction!.orderId!)
                      : null,
            );

            // Track that we've shown modal for this transaction
            _lastShownTransactionId = latestTransaction?.id;
            _lastModalShownTime = now;

            _showPointNotificationModal(event);
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
      Logger.warning('Error extracting engagement data from orderId: $e',
          tag: 'MainPage');
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

  @override
  void dispose() {
    _isDisposed = true;
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
          Logger.info('Loaded ${cachedProducts.length} cached products',
              tag: 'MainPage');
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
      Logger.error('Error loading cached products: $e',
          tag: 'MainPage', error: e);
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
      final productsJson =
          json.encode(productsToCache.map((p) => p.toJson()).toList());
      await prefs.setString(_cachedProductsKey, productsJson);
      Logger.info('Cached ${productsToCache.length} products', tag: 'MainPage');
    } catch (e) {
      Logger.error('Error caching products: $e', tag: 'MainPage', error: e);
    }
  }

  Future<void> _loadProducts(
      {int page = 1, bool skipLoadingState = false}) async {
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
        Logger.info('Device is offline, loading cached products',
            tag: 'MainPage');
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

      Logger.info('Successfully loaded ${convertedProducts.length} products',
          tag: 'MainPage');
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

  /// Refresh all Home Page data: products, points, transactions, and Lucky Box config
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
    final spinWheelProvider =
        Provider.of<SpinWheelProvider>(context, listen: false);
    final engagementProvider =
        Provider.of<EngagementProvider>(context, listen: false);
    final user = authProvider.user;

    try {
      // PROFESSIONAL FIX: Run independent operations in parallel for faster refresh
      // Products loading and user data refresh can happen simultaneously
      final List<Future<void>> refreshTasks = [];

      // Task 1: Load products (independent operation)
      // Skip loading state since we already set it above
      refreshTasks
          .add(_loadProducts(page: 1, skipLoadingState: true).catchError((e) {
        Logger.warning('Error loading products during refresh: $e',
            tag: 'MainPage');
      }));

      // Task 2: Refresh user-related data (if authenticated)
      if (authProvider.isAuthenticated &&
          user != null &&
          authProvider.token != null) {
        final userId = user.id.toString();

        // Refresh user data first (needed for other operations)
        // Use async/await pattern for cleaner error handling
        refreshTasks.add(
          (() async {
            try {
              await authProvider.refreshUser();
              // After user refresh, run dependent operations in parallel
              await Future.wait([
                // These can all run in parallel as they're independent
                pointProvider.loadBalance(userId, forceRefresh: true),
                pointProvider.loadTransactions(userId, forceRefresh: true),
                spinWheelProvider.loadConfigForUser(userId, forceRefresh: true),
                engagementProvider.refresh(
                  userId: user.id,
                  token: authProvider.token!,
                ),
              ]);
            } catch (e) {
              Logger.warning('Error refreshing user data during refresh: $e',
                  tag: 'MainPage');
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
        _luckyBoxBannerKey.currentState?.refreshBanner();
      }
    } catch (e, stackTrace) {
      Logger.error('Error during refresh: $e',
          tag: 'MainPage', error: e, stackTrace: stackTrace);
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
    return NetworkStatusBanner(
      child: _buildMainContent(context),
    );
  }

  Widget _buildMainContent(BuildContext context) {
    Widget appBar = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: const _PlanetMMHeader(),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Notification Icon Button
              NotificationBadge(
                child: IconButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => NotificationsPage(),
                    ),
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

    return Scaffold(
      bottomNavigationBar: CustomBottomBar(controller: bottomTabController),
      // Floating cart/order icon removed per design request.
      body: CustomPaint(
        painter: MainBackground(),
        child: TabBarView(
          controller: bottomTabController,
          physics: NeverScrollableScrollPhysics(),
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
                      SliverToBoxAdapter(
                        child: appBar,
                      ),
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
            ProfilePageNew()
          ],
        ),
      ),
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
      Logger.warning('Error handling usage tracking lifecycle: $e',
          tag: 'MainPage');
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
          4, 8, 4, 0), // No bottom padding to prevent extra space
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Buy Now Button - High-contrast PlanetMM primary color
          _ModernActionButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AllProductsPage(),
                ),
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

/// Lucky Box Section Widget
/// Contains the Lucky Box button and banner, moved below Engagement Hub
class _LuckyBoxSection extends StatefulWidget {
  final GlobalKey<_LuckyBoxBannerWidgetState> luckyBoxBannerKey;

  const _LuckyBoxSection({required this.luckyBoxBannerKey});

  @override
  State<_LuckyBoxSection> createState() => _LuckyBoxSectionState();
}

class _LuckyBoxSectionState extends State<_LuckyBoxSection>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  String? _lastUserId;
  Timer? _transactionRefreshTimer;

  // Track when we first detected approved state for each transaction
  // Key: transaction ID, Value: timestamp when first detected
  final Map<String, DateTime> _approvedStateTimestamps = {};
  Timer? _approvedStateResetTimer;

  // Animation controllers for approved message subtitle
  late AnimationController _pulseController;
  late AnimationController _bounceController;
  late AnimationController _shimmerController;

  late Animation<double> _pulseAnimation;
  late Animation<double> _bounceAnimation;
  late Animation<double> _shimmerAnimation;

  /// Professional vibration helper with fallback support
  Future<void> _triggerVibration() async {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        final hasAmplitudeControl = await Vibration.hasAmplitudeControl();

        if (hasAmplitudeControl == true) {
          await Vibration.vibrate(
            pattern: [0, 300, 40, 300],
            intensities: [255, 255],
          );
        } else {
          await Vibration.vibrate(duration: 500);
        }
        return;
      }
    } catch (e) {
      Logger.warning('Vibration package failed, using HapticFeedback: $e',
          tag: 'LuckyBox');
    }

    try {
      HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 50));
      HapticFeedback.heavyImpact();
    } catch (e) {
      Logger.warning('HapticFeedback failed: $e', tag: 'LuckyBox');
    }
  }

  /// Get Lucky Box subtitle based on transaction state
  String _getLuckyBoxSubtitle(PointProvider pointProvider) {
    try {
      final transactions = pointProvider.transactions;
      final now = DateTime.now();

      bool isLuckyBoxTransaction(PointTransaction txn) {
        if (txn.orderId == null) return false;
        return txn.orderId == 'luckybox' || txn.orderId!.contains('luckybox');
      }

      final luckyBoxTransactions =
          transactions.where((txn) => isLuckyBoxTransaction(txn)).toList();

      if (luckyBoxTransactions.isEmpty) {
        Logger.info('LuckyBox: No luckybox transactions found, showing default',
            tag: 'LuckyBox');
        return '🎁 Lucky Box ကို ဖွင့်ကြည့်ပါ';
      }

      luckyBoxTransactions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final mostRecentTransaction = luckyBoxTransactions.first;

      final hasPending = luckyBoxTransactions.any((txn) => txn.isPending);
      if (hasPending) {
        _approvedStateTimestamps.clear();
        Logger.info(
            'LuckyBox: Pending transaction found (most recent: ${mostRecentTransaction.id}, status: ${mostRecentTransaction.status})',
            tag: 'LuckyBox');
        return '⏳ တောင်းဆိုမှု ဆောင်ရွက်နေပါတယ်';
      }

      if (mostRecentTransaction.isApproved) {
        final transactionId = mostRecentTransaction.id;
        final firstSeenTime = _approvedStateTimestamps[transactionId];

        if (firstSeenTime == null) {
          _approvedStateTimestamps[transactionId] = now;
          _startApprovedStateResetTimer();
          Logger.info(
              'LuckyBox: First time detecting approved transaction, storing timestamp: $transactionId',
              tag: 'LuckyBox');
        } else {
          final timeSinceFirstSeen = now.difference(firstSeenTime);
          if (timeSinceFirstSeen.inSeconds < 60) {
            Logger.info(
                'LuckyBox: Approved transaction detected ${timeSinceFirstSeen.inSeconds} seconds ago: $transactionId',
                tag: 'LuckyBox');
            return '🎉 ကံကောင်းပါတယ်!';
          } else {
            Logger.info(
                'LuckyBox: Approved message shown for ${timeSinceFirstSeen.inSeconds} seconds (>= 60s), showing default: $transactionId',
                tag: 'LuckyBox');
            return '🎁 Lucky Box ကို ဖွင့်ကြည့်ပါ';
          }
        }
        return '🎉 ကံကောင်းပါတယ်!';
      }

      final approvedTransactions =
          luckyBoxTransactions.where((txn) => txn.isApproved).toList();
      if (approvedTransactions.isNotEmpty) {
        approvedTransactions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        final mostRecentApproved = approvedTransactions.first;
        final transactionId = mostRecentApproved.id;
        final firstSeenTime = _approvedStateTimestamps[transactionId];

        if (firstSeenTime == null) {
          _approvedStateTimestamps[transactionId] = now;
          _startApprovedStateResetTimer();
          Logger.info(
              'LuckyBox: First time detecting approved transaction (fallback): $transactionId',
              tag: 'LuckyBox');
          return '🎉 ကံကောင်းပါတယ်!';
        } else {
          final timeSinceFirstSeen = now.difference(firstSeenTime);
          if (timeSinceFirstSeen.inSeconds < 60) {
            Logger.info(
                'LuckyBox: Approved transaction detected ${timeSinceFirstSeen.inSeconds} seconds ago (fallback): $transactionId',
                tag: 'LuckyBox');
            return '🎉 ကံကောင်းပါတယ်!';
          } else {
            Logger.info(
                'LuckyBox: Approved message shown for ${timeSinceFirstSeen.inSeconds} seconds (>= 60s), showing default (fallback): $transactionId',
                tag: 'LuckyBox');
            return '🎁 Lucky Box ကို ဖွင့်ကြည့်ပါ';
          }
        }
      }

      Logger.info(
          'LuckyBox: No pending or recent approved transactions, showing default',
          tag: 'LuckyBox');
      return '🎁 Lucky Box ကို ဖွင့်ကြည့်ပါ';
    } catch (e, stackTrace) {
      Logger.error('Error getting Lucky Box subtitle: $e',
          tag: 'LuckyBox', error: e, stackTrace: stackTrace);
      return '🎁 Lucky Box ကို ဖွင့်ကြည့်ပါ';
    }
  }

  Widget _buildAnimatedApprovedSubtitle(String text, Color baseColor) {
    return AnimatedBuilder(
      animation: Listenable.merge(
          [_bounceAnimation, _pulseAnimation, _shimmerAnimation]),
      builder: (context, child) {
        final bounceScale = 0.7 + (_bounceAnimation.value * 0.3);
        final pulseScale = _pulseAnimation.value;
        final finalScale = bounceScale * pulseScale;

        final glowIntensity = 0.6 +
            (0.4 *
                (0.5 + 0.5 * math.sin(_shimmerAnimation.value * 2 * math.pi)));

        return Transform.scale(
          scale: finalScale,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: Colors.yellow.shade400
                      .withValues(alpha: 0.7 * glowIntensity),
                  blurRadius: 12 * finalScale,
                  spreadRadius: 2 * finalScale,
                ),
                BoxShadow(
                  color: Colors.amber.shade400
                      .withValues(alpha: 0.5 * glowIntensity),
                  blurRadius: 20 * finalScale,
                  spreadRadius: 1 * finalScale,
                ),
              ],
            ),
            child: Text(
              text,
              style: TextStyle(
                color: baseColor,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                  Shadow(
                    color: Colors.yellow.shade400
                        .withValues(alpha: 0.8 * glowIntensity),
                    blurRadius: 8,
                    offset: const Offset(0, 0),
                  ),
                  Shadow(
                    color: Colors.amber.shade400
                        .withValues(alpha: 0.6 * glowIntensity),
                    blurRadius: 12,
                    offset: const Offset(0, 0),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _startApprovedStateResetTimer() {
    _approvedStateResetTimer?.cancel();
    _approvedStateResetTimer =
        Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final now = DateTime.now();
      bool shouldUpdate = false;

      for (final entry in _approvedStateTimestamps.entries) {
        final timeSinceFirstSeen = now.difference(entry.value);
        if (timeSinceFirstSeen.inSeconds >= 60) {
          shouldUpdate = true;
          Logger.info(
              'LuckyBox: Approved state expired (${timeSinceFirstSeen.inSeconds}s >= 60s) for transaction: ${entry.key}',
              tag: 'LuckyBox');
          break;
        }
      }

      if (shouldUpdate && mounted) {
        setState(() {});
      }

      if (_approvedStateTimestamps.isEmpty) {
        timer.cancel();
      }
    });
  }

  void _startPeriodicTransactionRefresh() {
    _transactionRefreshTimer?.cancel();
    _transactionRefreshTimer =
        Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _refreshTransactionsSilently();
    });
  }

  Future<void> _refreshTransactionsSilently() async {
    if (!mounted) return;

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final pointProvider = Provider.of<PointProvider>(context, listen: false);
      final userId = authProvider.user?.id.toString();

      if (authProvider.isAuthenticated && userId != null) {
        await pointProvider.loadTransactions(userId, forceRefresh: true);
      }
    } catch (e) {
      Logger.warning('Error refreshing transactions silently: $e',
          tag: 'LuckyBox');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      _refreshTransactionsSilently();
      _startPeriodicTransactionRefresh();
    } else if (state == AppLifecycleState.paused) {
      _transactionRefreshTimer?.cancel();
    }
  }

  void _loadLuckyBoxConfig() {
    if (!mounted) return;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final spinWheelProvider =
        Provider.of<SpinWheelProvider>(context, listen: false);
    final userId = authProvider.user?.id.toString();
    if (authProvider.isAuthenticated && userId != null) {
      spinWheelProvider.loadConfigForUser(userId);
    }
  }

  void _loadInitialTransactions() {
    if (!mounted) return;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final pointProvider = Provider.of<PointProvider>(context, listen: false);
    final userId = authProvider.user?.id.toString();
    if (authProvider.isAuthenticated && userId != null) {
      pointProvider.loadTransactions(userId, forceRefresh: true);
    }
  }

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _bounceController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..forward();

    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _bounceAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.elasticOut),
    );

    _shimmerAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadLuckyBoxConfig();
      _loadInitialTransactions();
    });

    WidgetsBinding.instance.addObserver(this);
    _startPeriodicTransactionRefresh();
  }

  @override
  void dispose() {
    _transactionRefreshTimer?.cancel();
    _approvedStateResetTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _bounceController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final spinWheelProvider =
        Provider.of<SpinWheelProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.user?.id.toString();

    if (userId != null && userId != _lastUserId) {
      _lastUserId = userId;
    }

    if (!authProvider.isAuthenticated || userId == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Consumer<PointProvider>(
          builder: (context, pointProvider, child) {
            final subtitle = _getLuckyBoxSubtitle(pointProvider);
            final isApprovedMessage = subtitle == '🎉 ကံကောင်းပါတယ်!';
            final subtitleColor = !spinWheelProvider.isEnabled
                ? Colors.grey.withValues(alpha: 0.6)
                : colorScheme.secondary;

            if (isApprovedMessage && !_bounceController.isAnimating) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _bounceController.reset();
                  _bounceController.forward();
                }
              });
            }

            return _ModernActionButton(
              onPressed: (!spinWheelProvider.isEnabled ||
                      spinWheelProvider.isLoading)
                  ? () {}
                  : () async {
                      _triggerVibration();

                      if (!authProvider.isAuthenticated ||
                          authProvider.user == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please login first')),
                        );
                        return;
                      }

                      final uid = authProvider.user!.id.toString();

                      try {
                        await pointProvider.loadTransactions(uid,
                            forceRefresh: true);
                        final transactions = pointProvider.transactions;

                        bool isLuckyBoxTransaction(PointTransaction txn) {
                          if (txn.orderId == null) return false;
                          return txn.orderId == 'luckybox' ||
                              txn.orderId!.contains('luckybox');
                        }

                        final luckyBoxTransactions = transactions
                            .where((txn) => isLuckyBoxTransaction(txn))
                            .toList();

                        if (luckyBoxTransactions.isNotEmpty) {
                          luckyBoxTransactions.sort(
                              (a, b) => b.createdAt.compareTo(a.createdAt));
                          final mostRecentTransaction =
                              luckyBoxTransactions.first;

                          final hasPending =
                              luckyBoxTransactions.any((txn) => txn.isPending);
                          if (hasPending) {
                            await LuckyBoxRequestSheet.showPendingStatus(
                                context);
                            await pointProvider.loadTransactions(uid,
                                forceRefresh: true);
                            return;
                          }

                          bool shouldShowApprovedStatus = false;

                          if (mostRecentTransaction.isApproved) {
                            final transactionId = mostRecentTransaction.id;
                            final firstSeenTime =
                                _approvedStateTimestamps[transactionId];
                            final now = DateTime.now();

                            if (firstSeenTime != null) {
                              final timeSinceFirstSeen =
                                  now.difference(firstSeenTime);

                              if (timeSinceFirstSeen.inSeconds < 60) {
                                Logger.info(
                                    'LuckyBox: Approved transaction detected ${timeSinceFirstSeen.inSeconds} seconds ago, showing approved status: $transactionId',
                                    tag: 'LuckyBox');
                                shouldShowApprovedStatus = true;
                              } else {
                                Logger.info(
                                    'LuckyBox: Approved transaction older than 60 seconds (${timeSinceFirstSeen.inSeconds}s), skipping approved status and allowing new luckybox: $transactionId',
                                    tag: 'LuckyBox');
                              }
                            } else {
                              _approvedStateTimestamps[transactionId] =
                                  DateTime.now();
                              _startApprovedStateResetTimer();
                              Logger.info(
                                  'LuckyBox: First time detecting approved transaction on button click, storing timestamp: $transactionId',
                                  tag: 'LuckyBox');
                              shouldShowApprovedStatus = true;
                            }

                            if (shouldShowApprovedStatus) {
                              await LuckyBoxRequestSheet.showApprovedStatus(
                                  context);
                              await pointProvider.loadBalance(uid,
                                  forceRefresh: true);
                              await pointProvider.loadTransactions(uid,
                                  forceRefresh: true);
                              return;
                            }
                          }
                        }

                        final hasPendingLuckyBox = transactions.any((txn) =>
                            isLuckyBoxTransaction(txn) && txn.isPending);

                        if (hasPendingLuckyBox) {
                          await LuckyBoxRequestSheet.showPendingStatus(context);
                          return;
                        }
                      } catch (e) {
                        Logger.warning('Error checking transaction status: $e',
                            tag: 'LuckyBox');
                      }

                      Logger.info(
                          'LuckyBox: Opening new luckybox (no pending transactions and approved transaction is older than 60s or no approved transactions)',
                          tag: 'LuckyBox');
                      await LuckyBoxRequestSheet.show(
                        context,
                        submit: () =>
                            spinWheelProvider.openLuckyBox(userId: uid),
                        onSuccess: () async {
                          _approvedStateTimestamps.clear();
                          await pointProvider.loadBalance(uid,
                              forceRefresh: true);
                          await pointProvider.loadTransactions(uid,
                              forceRefresh: true);
                        },
                      );
                    },
              icon: Icons.casino_rounded,
              label: spinWheelProvider.isLoading
                  ? 'Lucky Box (processing...)'
                  : 'Lucky Box',
              subtitle: subtitle,
              subtitleWidget: isApprovedMessage
                  ? _buildAnimatedApprovedSubtitle(subtitle, subtitleColor)
                  : null,
              backgroundColor: Colors.transparent,
              foregroundColor: !spinWheelProvider.isEnabled
                  ? Colors.grey.withValues(alpha: 0.6)
                  : colorScheme.secondary,
              iconColor: !spinWheelProvider.isEnabled
                  ? Colors.grey.withValues(alpha: 0.6)
                  : colorScheme.secondary,
              isPrimary: false,
              borderColor: !spinWheelProvider.isEnabled
                  ? Colors.grey.withValues(alpha: 0.25)
                  : colorScheme.secondary.withValues(alpha: 0.3),
            );
          },
        ),
        const SizedBox(height: 16),
        _LuckyBoxBannerWidget(key: widget.luckyBoxBannerKey),
      ],
    );
  }
}

/// Modern action button with Material Design 3 styling
/// Features: Enhanced elevation, better spacing, subtitle support
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
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 24,
                ),
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
              colors: [
                AppTheme.deepBlue,
                mediumYellow,
              ],
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
class _LuckyBoxBannerWidget extends StatefulWidget {
  const _LuckyBoxBannerWidget({Key? key}) : super(key: key);

  @override
  State<_LuckyBoxBannerWidget> createState() => _LuckyBoxBannerWidgetState();
}

class _LuckyBoxBannerWidgetState extends State<_LuckyBoxBannerWidget> {
  LuckyBoxBanner? _banner;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBanner();
  }

  Future<void> _loadBanner() async {
    try {
      final banner = await SpinWheelService.getBanner();
      if (mounted) {
        setState(() {
          _banner = banner;
          _isLoading = false;
        });
      }
    } catch (e) {
      Logger.error('Error loading banner: $e', tag: 'LuckyBoxBanner');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Public method to refresh banner content
  /// Called from parent widget when refresh is triggered
  Future<void> refreshBanner() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }
    await _loadBanner();
    Logger.info('Lucky Box Banner refreshed', tag: 'LuckyBoxBanner');
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox.shrink(); // Don't show anything while loading
    }

    if (_banner == null || !_banner!.hasBanner || _banner!.content.isEmpty) {
      return const SizedBox.shrink(); // Don't show if no banner content
    }

    // OPTIMIZED: Cache theme colors to avoid repeated Theme.of(context) calls
    final colorScheme = Theme.of(context).colorScheme;
    final secondaryColor = colorScheme.secondary;
    final primaryColor = colorScheme.primary;

    return Container(
      margin: const EdgeInsets.fromLTRB(
          4, 8, 4, 0), // Remove bottom margin to prevent extra space
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                secondaryColor.withValues(alpha: 0.1),
                primaryColor.withValues(alpha: 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: secondaryColor.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _buildBannerContent(_banner!.content),
          ),
        ),
      ),
    );
  }

  // OPTIMIZED: Cache regex patterns to avoid recreation
  static final RegExp _headingRegex = RegExp(r'<h[1-6][^>]*>(.*?)</h[1-6]>',
      caseSensitive: false, dotAll: true);
  static final RegExp _paraRegex =
      RegExp(r'<p[^>]*>(.*?)</p>', caseSensitive: false, dotAll: true);
  static final RegExp _divRegex =
      RegExp(r'<div[^>]*>(.*?)</div>', caseSensitive: false, dotAll: true);
  static final RegExp _htmlTagRegex = RegExp(r'<[^>]*>');
  static final RegExp _whitespaceRegex = RegExp(r'\s+');

  Widget _buildBannerContent(String htmlContent) {
    // OPTIMIZED: Early return for empty content
    if (htmlContent.isEmpty) {
      return const SizedBox.shrink();
    }

    // OPTIMIZED: Cache theme colors once
    final colorScheme = Theme.of(context).colorScheme;
    final secondaryColor = colorScheme.secondary;
    final onSurfaceColor = colorScheme.onSurface.withValues(alpha: 0.87);

    // Extract structured content from HTML
    final hasImages =
        htmlContent.contains('<img') || htmlContent.contains('src=');

    // OPTIMIZED: Use cached regex patterns
    // Extract headings
    final headings = _headingRegex
        .allMatches(htmlContent)
        .map((m) => m.group(1)?.replaceAll(_htmlTagRegex, '') ?? '')
        .where((h) => h.isNotEmpty)
        .toList();

    // Extract paragraphs
    final paragraphs = _paraRegex
        .allMatches(htmlContent)
        .map((m) => m.group(1)?.replaceAll(_htmlTagRegex, '') ?? '')
        .where((p) => p.isNotEmpty)
        .toList();

    // Extract div content
    final divs = _divRegex
        .allMatches(htmlContent)
        .map((m) => m.group(1)?.replaceAll(_htmlTagRegex, '') ?? '')
        .where((d) => d.isNotEmpty)
        .toList();

    // Fallback: extract all text
    final allText = htmlContent
        .replaceAll(_htmlTagRegex, ' ')
        .replaceAll(_whitespaceRegex, ' ')
        .trim();

    final hasStructuredContent =
        headings.isNotEmpty || paragraphs.isNotEmpty || divs.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Display images first
        if (hasImages) _buildImageFromHtml(htmlContent),

        // Display headings
        if (headings.isNotEmpty)
          ...headings
              .map<Widget>((heading) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      heading,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: secondaryColor,
                        height: 1.3,
                      ),
                    ),
                  ))
              .toList(),

        // Display paragraphs
        if (paragraphs.isNotEmpty)
          ...paragraphs
              .map<Widget>((para) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      para,
                      style: TextStyle(
                        fontSize: 14,
                        color: onSurfaceColor,
                        height: 1.5,
                      ),
                    ),
                  ))
              .toList(),

        // Display div content
        if (divs.isNotEmpty && paragraphs.isEmpty)
          ...divs
              .map<Widget>((div) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      div,
                      style: TextStyle(
                        fontSize: 14,
                        color: onSurfaceColor,
                        height: 1.5,
                      ),
                    ),
                  ))
              .toList(),

        // Fallback: display all text if no structured content
        if (!hasStructuredContent && allText.isNotEmpty)
          Text(
            allText,
            style: TextStyle(
              fontSize: 14,
              color: onSurfaceColor,
              height: 1.5,
            ),
          ),
      ],
    );
  }

  // OPTIMIZED: Cache regex patterns for image extraction
  static final RegExp _imgPattern = RegExp('<img', caseSensitive: false);
  static final RegExp _srcPattern =
      RegExp('src\\s*=\\s*["\']([^"\']+)["\']', caseSensitive: false);

  Widget _buildImageFromHtml(String html) {
    // Extract image URLs from HTML - use simpler approach
    final imageUrls = <String>[];
    // OPTIMIZED: Use cached regex patterns
    final parts = html.split(_imgPattern);
    for (final part in parts.skip(1)) {
      final srcMatch = _srcPattern.firstMatch(part);
      if (srcMatch != null) {
        final url = srcMatch.group(1);
        if (url != null && url.isNotEmpty) {
          imageUrls.add(url);
        }
      }
    }

    if (imageUrls.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: imageUrls.map<Widget>((imageUrl) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              imageUrl,
              fit: BoxFit.cover,
              width: double.infinity,
              height: 200,
              // Improved image quality with better caching and error handling
              filterQuality: FilterQuality.high, // High quality rendering
              cacheWidth: (MediaQuery.of(context).size.width *
                      MediaQuery.of(context).devicePixelRatio)
                  .round(), // Optimize for device resolution
              errorBuilder: (context, error, stackTrace) {
                return const SizedBox.shrink();
              },
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  height: 200,
                  color: Colors.grey.withValues(alpha: 0.1),
                  child: Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Creative My Point Widget - Displays user's point balance in a beautiful card
class _MyPointWidget extends StatefulWidget {
  const _MyPointWidget({super.key});

  @override
  State<_MyPointWidget> createState() => _MyPointWidgetState();
}

class _MyPointWidgetState extends State<_MyPointWidget> {
  bool _isInitialLoadComplete = false;
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
            tag: 'MyPointWidget');
        setState(() {
          _isInitialLoadComplete = false;
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
        _isInitialLoadComplete = false;
        _isRefreshing = false;
      });
    }
  }

  /// Public method to refresh balance - called from parent when refresh is triggered
  Future<void> refreshBalance() async {
    if (!mounted) return;

    // Reset the initial load flag to allow refresh
    setState(() {
      _isInitialLoadComplete = false;
    });

    // Load balance again
    await _loadBalanceIfNeeded();
  }

  /// Load balance if user is authenticated and we haven't loaded yet
  /// This method is safe to call multiple times - it will only load once
  /// PROFESSIONAL FIX: Validates user ID, timeout to prevent loading spinner from getting stuck
  Future<void> _loadBalanceIfNeeded() async {
    if (!mounted || _isRefreshing) return;

    // Allow reload if user changed (even if _isInitialLoadComplete is true)
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!authProvider.isAuthenticated || authProvider.user == null) {
      return;
    }

    final userId = authProvider.user!.id.toString();

    // PROFESSIONAL FIX: Check if user changed - if so, reset and reload
    if (_lastUserId != null && _lastUserId != userId) {
      Logger.info(
          'MyPointWidget - User changed during load, resetting and reloading',
          tag: 'MyPointWidget');
      setState(() {
        _isInitialLoadComplete = false;
      });
      _lastUserId = userId;
    }

    // Skip if already loaded for current user
    if (_isInitialLoadComplete && _lastUserId == userId) {
      return;
    }

    final pointProvider = Provider.of<PointProvider>(context, listen: false);

    // Always load on initial page load to ensure fresh data
    if (mounted) {
      setState(() {
        _isRefreshing = true;
      });
    }

    try {
      Logger.info('MyPointWidget - Loading balance for user: $userId',
          tag: 'MyPointWidget');

      // PROFESSIONAL FIX: Wrap in timeout so loading never gets stuck (e.g. API hang)
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

      if (mounted) {
        setState(() {
          _isInitialLoadComplete = true;
          _isRefreshing = false;
        });
      }

      Logger.info('MyPointWidget - Balance loaded successfully',
          tag: 'MyPointWidget');
    } catch (e) {
      Logger.error('Error loading balance in MyPointWidget: $e',
          tag: 'MyPointWidget', error: e);
      if (mounted) {
        setState(() {
          _isRefreshing = false;
          // Still mark as complete to avoid infinite retry loops
          _isInitialLoadComplete = true;
        });
      }
    }
  }

  /// Extract numeric value from points_balance string
  /// Handles various formats: "100", "100 points", "0", etc.
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Use listen: true to rebuild when user data or point balance changes
    final authProvider = Provider.of<AuthProvider>(context, listen: true);
    final pointProvider = Provider.of<PointProvider>(context, listen: true);

    // Only show if user is authenticated
    if (!authProvider.isAuthenticated || authProvider.user == null) {
      return const SizedBox.shrink();
    }

    final user = authProvider.user!;

    // Priority 1: Check for my_point or my_points (primary source for display)
    final myPointValue = user.customFields['my_point'] ??
        user.customFields['my_points'] ??
        user.customFields['My Point Value'];

    // Priority 2: Get points_balance from user object (alternative source)
    final pointsBalanceFromBackend = user.customFields['points_balance'];

    // Fallback to PointProvider if backend value is not available
    final balanceFromProvider = pointProvider.currentBalance;
    Logger.info(
        'MyPointWidget - DEBUG: PointProvider balance: $balanceFromProvider',
        tag: 'MyPointWidget');

    // Determine which value to use — use MAX of all sources so poll win / push snapshot
    // is never hidden when one source updates before another.
    final fromMyPoint = (myPointValue != null && myPointValue.isNotEmpty)
        ? (int.tryParse(_extractBalanceValue(myPointValue)) ?? 0)
        : 0;
    final fromPointsBalance =
        (pointsBalanceFromBackend != null && pointsBalanceFromBackend.isNotEmpty)
            ? (int.tryParse(_extractBalanceValue(pointsBalanceFromBackend)) ?? 0)
            : 0;
    final maxBalance = [
      fromMyPoint,
      fromPointsBalance,
      balanceFromProvider,
    ].reduce((a, b) => a > b ? a : b);
    String displayBalance = maxBalance.toString();

    // Ensure we always have a valid display value (even if 0)
    if (displayBalance.isEmpty || displayBalance == 'null') {
      displayBalance = '0';
    }

    // Determine loading state - stop loading as soon as we have displayable data
    // Show loading if:
    // 1. We're actively refreshing, OR
    // 2. PointProvider is loading AND we have no backend value (my_point/points_balance)
    final hasBackendValue = (myPointValue != null &&
            myPointValue.isNotEmpty &&
            myPointValue != '0') ||
        (pointsBalanceFromBackend != null &&
            pointsBalanceFromBackend.isNotEmpty &&
            pointsBalanceFromBackend != '0');
    final isLoading = _isRefreshing ||
        (pointProvider.isLoading && !hasBackendValue);

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
                          color: colorScheme.primary.withValues(alpha: 0.3),
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
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colorScheme.onSurface.withValues(alpha: 0.6),
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (isLoading)
                          SizedBox(
                            height: 24,
                            width: 80,
                            child: LinearProgressIndicator(
                              backgroundColor:
                                  colorScheme.surfaceContainerHighest,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                colorScheme.primary,
                              ),
                              minHeight: 2,
                            ),
                          )
                        else
                          // Display actual user points count from points_balance custom field (same as Profile page)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                'ⓟ',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurface
                                      .withValues(alpha: 0.7),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                // Render backend points_balance value directly
                                displayBalance,
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 28,
                                  height: 1.2,
                                ),
                              ),
                            ],
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
    );
  }
}
