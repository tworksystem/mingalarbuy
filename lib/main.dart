import 'package:ecommerce_int2/screens/splash_page.dart';
import 'dart:async';
import 'package:ecommerce_int2/screens/orders/order_details_page.dart';
import 'package:ecommerce_int2/screens/points/point_history_page.dart';
import 'package:ecommerce_int2/screens/main/main_page.dart';
import 'package:ecommerce_int2/providers/auth_provider.dart';
import 'package:ecommerce_int2/providers/cart_provider.dart';
import 'package:ecommerce_int2/providers/order_provider.dart';
import 'package:ecommerce_int2/providers/address_provider.dart';
import 'package:ecommerce_int2/providers/review_provider.dart';
import 'package:ecommerce_int2/providers/wishlist_provider.dart';
import 'package:ecommerce_int2/providers/product_filter_provider.dart';
import 'package:ecommerce_int2/providers/point_provider.dart';
import 'package:ecommerce_int2/providers/spin_wheel_provider.dart';
import 'package:ecommerce_int2/providers/wallet_provider.dart';
import 'package:ecommerce_int2/providers/category_provider.dart';
import 'package:ecommerce_int2/providers/engagement_provider.dart';
import 'package:ecommerce_int2/providers/exchange_settings_provider.dart';
import 'package:ecommerce_int2/widgets/point_auth_listener.dart';
import 'package:ecommerce_int2/widgets/wallet_auth_listener.dart';
import 'package:ecommerce_int2/widgets/order_auth_listener.dart';
import 'package:ecommerce_int2/widgets/engagement_auth_listener.dart';
import 'package:ecommerce_int2/providers/in_app_notification_provider.dart';
import 'package:ecommerce_int2/services/notification_service.dart';
import 'package:ecommerce_int2/services/background_service.dart';
import 'package:ecommerce_int2/services/active_sync_service.dart';
import 'package:ecommerce_int2/services/push_notification_service.dart';
import 'package:ecommerce_int2/services/connectivity_service.dart';
import 'package:ecommerce_int2/services/offline_queue_service.dart';
import 'package:ecommerce_int2/services/point_service.dart';
import 'package:ecommerce_int2/services/usage_tracking_service.dart';
import 'package:ecommerce_int2/services/app_logger.dart';
import 'package:ecommerce_int2/services/log_buffer_service.dart';
import 'package:ecommerce_int2/services/global_keys.dart';
import 'package:ecommerce_int2/utils/logger.dart';
import 'package:ecommerce_int2/theme/app_theme.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ecommerce_int2/models/order.dart';

void main() async {
  // CRITICAL FIX: Initialize bindings in root zone BEFORE any guarded zones
  // This ensures ensureInitialized and runApp are in the same zone
  // This prevents "Zone mismatch" errors
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize error handlers in root zone
  AppLogger.initialize();
  LogBufferService.initialize();

  // Web-specific error handling
  if (kIsWeb) {
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      Logger.error('Flutter Error: ${details.exception}',
          tag: 'Main', error: details.exception, stackTrace: details.stack);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      Logger.error('Platform Error: $error',
          tag: 'Main', error: error, stackTrace: stack);
      return true;
    };
  }

  // Run async initialization in guarded zone, but runApp in root zone
  try {
    await AppLogger.guard(() async {
      // Initialize connectivity service first (needed by other services)
      try {
        await ConnectivityService().initialize();
        Logger.info('Connectivity service initialized', tag: 'Main');
      } catch (e) {
        Logger.error('Connectivity service initialization failed: $e',
            tag: 'Main', error: e);
        // Continue even if connectivity service fails
      }

      // Initialize offline queue service
      try {
        await OfflineQueueService().initialize();
        Logger.info('Offline queue service initialized', tag: 'Main');
        PointService.registerOfflineQueueHandler();
      } catch (e) {
        Logger.error('Offline queue service initialization failed: $e',
            tag: 'Main', error: e);
        // Continue even if offline queue fails
      }

      // Initialize in-app notification provider (singleton instance)
      try {
        final notificationProvider = InAppNotificationProvider.instance;
        await notificationProvider.initialize();
        Logger.info('In-app notification provider initialized', tag: 'Main');
      } catch (e) {
        Logger.error('In-app notification provider initialization failed: $e',
            tag: 'Main', error: e);
        // Continue even if notification provider fails
      }

      // Initialize notification service
      try {
        await NotificationService().initialize();
      } catch (e) {
        Logger.error('Notification service initialization failed: $e',
            tag: 'Main', error: e);
        // Continue even if notification service fails
      }

      // Background service for periodic order checks (unsupported on web)
      if (!kIsWeb) {
        try {
          await BackgroundService.initialize();
          await BackgroundService.registerPeriodicTask();
          // Old Code: only periodic registration at startup.
          // New Code: also request a near-term one-off tick so backend gets nudged
          // quickly after cold start (best effort, OS may defer).
          await BackgroundService.registerAutoRunPollOneOffTick(
            initialDelay: const Duration(seconds: 30),
          );
        } catch (e) {
          Logger.error('Background service initialization failed: $e',
              tag: 'Main', error: e);
        }
      } else {
        Logger.info('Skipping background service initialization on web',
            tag: 'Main');
      }

      // Firebase Cloud Messaging (FCM) for instant push notifications
      // Skip Firebase on web if not configured
      if (!kIsWeb || _hasFirebaseConfig()) {
        try {
          // Initialize Firebase
          await Firebase.initializeApp();
          Logger.info('Firebase initialized successfully', tag: 'Main');

          // Register background message handler (mobile only)
          if (!kIsWeb) {
            FirebaseMessaging.onBackgroundMessage(
                firebaseMessagingBackgroundHandler);
          }

          // Initialize push notification service
          await PushNotificationService().initialize();
          Logger.info('Push notification service initialized', tag: 'Main');
        } catch (e) {
          Logger.error('Firebase initialization failed: $e',
              tag: 'Main', error: e);
          // App will continue without push notifications (fallback to polling)
        }
      } else {
        Logger.info('Skipping Firebase initialization on web (not configured)',
            tag: 'Main');
      }
    });

    // CRITICAL: Call runApp in root zone (outside guard) to match ensureInitialized
    // This prevents zone mismatch errors - both are now in the same root zone
    runApp(MyApp());
  } catch (e, stackTrace) {
    // Fallback: Run app even if initialization fails
    Logger.fatal('Critical error during initialization: $e',
        tag: 'Main', error: e, stackTrace: stackTrace);
    Logger.warning('Running app with minimal initialization...', tag: 'Main');

    // runApp is already in root zone (same as ensureInitialized above)
    runApp(MyApp());
  }
}

/// Check if Firebase is configured for web
bool _hasFirebaseConfig() {
  // Check if firebase_options.dart exists or if we can initialize Firebase
  // For now, return false for web to skip Firebase
  return false;
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  Timer? _releaseFallbackSyncTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Start polling after frame is built (when providers are ready)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // OLD CODE:
      // _startActiveSyncWithRetry();
      // _setupPushNotificationCallbacks();
      // _initializeUsageTracking();
      //
      // New Code:
      _startActiveSyncWithRetry();
      _setupPushNotificationCallbacks();
      _initializeUsageTracking();
      _startReleaseFallbackSyncLoop();
    });
  }

  /// Initialize usage tracking on app start
  Future<void> _initializeUsageTracking() async {
    try {
      // Clear any stale sessions first
      await UsageTrackingService.clearStaleSessions();

      // Get auth provider to check if user is logged in
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      if (authProvider.isAuthenticated && authProvider.user != null) {
        final userId = authProvider.user!.id.toString();

        // Start usage tracking session
        await UsageTrackingService.startSession(userId);

        Logger.info('Usage tracking initialized for user: $userId',
            tag: 'Main');
      }
    } catch (e, stackTrace) {
      Logger.error(
        'Error initializing usage tracking: $e',
        tag: 'Main',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Setup push notification callbacks for instant order updates
  void _setupPushNotificationCallbacks() {
    // Setup callback for order refresh when notification arrives
    PushNotificationService().setOrderUpdateCallback(
        (String orderId, Map<String, dynamic> data) async {
      try {
        Logger.info('FCM notification received, refreshing orders immediately',
            tag: 'Main');

        // Get providers from context
        final orderProvider =
            Provider.of<OrderProvider>(context, listen: false);
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        // Use singleton instance to ensure we're updating the same provider instance used in UI
        final notificationProvider = InAppNotificationProvider.instance;

        // Reload notifications to update count immediately
        await notificationProvider.loadNotifications();
        Logger.info(
            'Notification count updated after FCM notification (${notificationProvider.unreadCount} unread)',
            tag: 'Main');

        if (authProvider.isAuthenticated && authProvider.user != null) {
          final userId = authProvider.user!.id.toString();

          // Trigger immediate order sync to get latest status
          // Skip notifications during sync since push notification already created it
          Logger.info(
              'Triggering immediate order sync after FCM notification (skipping duplicate notifications)',
              tag: 'Main');
          await orderProvider.syncOrdersWithWooCommerce(userId,
              skipNotifications: true);

          Logger.info('Orders refreshed successfully after FCM notification',
              tag: 'Main');
        } else {
          Logger.warning('User not authenticated, skipping order refresh',
              tag: 'Main');
        }
      } catch (e, stackTrace) {
        Logger.error('Error refreshing orders after FCM notification: $e',
            tag: 'Main', error: e, stackTrace: stackTrace);
      }
    });

    // Setup callback for navigation when notification is tapped
    PushNotificationService().setNavigationCallback((String orderId) async {
      try {
        Logger.info('Navigating to order details: $orderId', tag: 'Main');

        // Get order provider to find the order
        final orderProvider =
            Provider.of<OrderProvider>(context, listen: false);

        // Find order by ID (handle both WC- prefix and plain ID)
        Order? order;
        try {
          // Try to find by WooCommerce ID
          order = orderProvider.orders.firstWhere(
            (o) =>
                o.metadata?['woocommerce_id']?.toString() == orderId ||
                o.id == 'WC-$orderId' ||
                o.id == orderId,
            orElse: () => throw StateError('Order not found'),
          );
        } catch (e) {
          Logger.warning(
              'Order not found in local cache, need to sync: $orderId',
              tag: 'Main');

          // If order not found, sync orders first
          final authProvider =
              Provider.of<AuthProvider>(context, listen: false);
          if (authProvider.isAuthenticated && authProvider.user != null) {
            await orderProvider
                .syncOrdersWithWooCommerce(authProvider.user!.id.toString());

            // Try to find order again after sync
            try {
              order = orderProvider.orders.firstWhere(
                (o) =>
                    o.metadata?['woocommerce_id']?.toString() == orderId ||
                    o.id == 'WC-$orderId' ||
                    o.id == orderId,
                orElse: () => throw StateError('Order not found'),
              );
            } catch (e2) {
              Logger.error('Order still not found after sync: $orderId',
                  tag: 'Main');
              return;
            }
          } else {
            Logger.warning('User not authenticated, cannot navigate to order',
                tag: 'Main');
            return;
          }
        }

        // Navigate to order details page
        // Use Future.microtask to ensure navigation happens after current frame
        // This is important when called from notification tap handler
        Future.microtask(() {
          final navigatorContext = AppKeys.navigatorKey.currentContext;
          if (navigatorContext != null) {
            Navigator.of(navigatorContext).push(
              MaterialPageRoute(
                builder: (context) => OrderDetailsPage(order: order!),
              ),
            );
            Logger.info('Navigated to order details: $orderId', tag: 'Main');
          } else {
            Logger.warning('Navigator context not available, retrying...',
                tag: 'Main');
            // Retry after a short delay if context is not available
            Future.delayed(Duration(milliseconds: 500), () {
              final retryContext = AppKeys.navigatorKey.currentContext;
              if (retryContext != null) {
                Navigator.of(retryContext).push(
                  MaterialPageRoute(
                    builder: (context) => OrderDetailsPage(order: order!),
                  ),
                );
                Logger.info('Navigated to order details (retry): $orderId',
                    tag: 'Main');
              } else {
                Logger.error(
                    'Navigator context still not available after retry',
                    tag: 'Main');
              }
            });
          }
        });
      } catch (e, stackTrace) {
        Logger.error('Error navigating to order details: $e',
            tag: 'Main', error: e, stackTrace: stackTrace);
      }
    });

    // Setup callback for navigating to points history when point notification is tapped
    PushNotificationService().setPointsNavigationCallback(() async {
      try {
        Logger.info('Navigating to points history', tag: 'Main');

        // Navigate to points history page using navigator key
        if (AppKeys.navigatorKey.currentContext != null) {
          Navigator.of(AppKeys.navigatorKey.currentContext!).push(
            MaterialPageRoute(
              builder: (context) => const PointHistoryPage(),
            ),
          );
          Logger.info('Navigated to points history', tag: 'Main');
        } else {
          Logger.warning('Navigator context not available, cannot navigate',
              tag: 'Main');
        }
      } catch (e, stackTrace) {
        Logger.error('Error navigating to points history: $e',
            tag: 'Main', error: e, stackTrace: stackTrace);
      }
    });

    // Setup callback for navigating to engagement hub when engagement notification is tapped
    PushNotificationService().setEngagementNavigationCallback((
        {String? itemId, String? itemType}) async {
      try {
        Logger.info(
            'Navigating to engagement hub: itemId=$itemId, itemType=$itemType',
            tag: 'Main');

        // PROFESSIONAL FIX: Parse itemId to integer for navigation
        int? parsedItemId;
        if (itemId != null && itemId.isNotEmpty) {
          parsedItemId = int.tryParse(itemId);
          if (parsedItemId == null) {
            Logger.warning('Invalid itemId format: $itemId', tag: 'Main');
          }
        }

        // Navigate to MainPage (where EngagementCarousel is displayed)
        // Use Future.microtask to ensure navigation happens after current frame
        Future.microtask(() {
          final navigatorContext = AppKeys.navigatorKey.currentContext;
          if (navigatorContext != null) {
            // Navigate to MainPage with itemId - this will show the Engagement Hub and scroll to specific item
            // If already on MainPage, it will just refresh the engagement feed and scroll to item
            Navigator.of(navigatorContext).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (context) => MainPage(
                  engagementItemId:
                      parsedItemId, // PROFESSIONAL FIX: Pass item ID for deep linking
                ),
              ),
              (route) => route.isFirst, // Keep only the first route (MainPage)
            );

            Logger.info(
                'Navigated to engagement hub (MainPage) with itemId: $parsedItemId',
                tag: 'Main');
          } else {
            Logger.warning('Navigator context not available, retrying...',
                tag: 'Main');
            // Retry after a short delay if context is not available
            Future.delayed(Duration(milliseconds: 500), () {
              final retryContext = AppKeys.navigatorKey.currentContext;
              if (retryContext != null) {
                Navigator.of(retryContext).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (context) => MainPage(
                      engagementItemId:
                          parsedItemId, // PROFESSIONAL FIX: Pass item ID for deep linking
                    ),
                  ),
                  (route) => route.isFirst,
                );
                Logger.info(
                    'Navigated to engagement hub (retry) with itemId: $parsedItemId',
                    tag: 'Main');
              } else {
                Logger.error(
                    'Navigator context still not available after retry',
                    tag: 'Main');
              }
            });
          }
        });
      } catch (e, stackTrace) {
        Logger.error('Error navigating to engagement hub: $e',
            tag: 'Main', error: e, stackTrace: stackTrace);
      }
    });

    // Setup callback for real-time engagement feed refresh on FCM updates
    PushNotificationService().setEngagementFeedRefreshCallback(() async {
      try {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final engagementProvider =
            Provider.of<EngagementProvider>(context, listen: false);

        if (!authProvider.isAuthenticated || authProvider.user == null) {
          Logger.warning(
            'Engagement refresh callback skipped: user not authenticated',
            tag: 'Main',
          );
          return;
        }

        final userId = authProvider.user!.id;
        Logger.info(
          'FCM engagement update received, forcing feed refresh for user=$userId',
          tag: 'Main',
        );

        await engagementProvider.loadFeed(
          userId: userId,
          forceRefresh: true,
        );
      } catch (e, stackTrace) {
        Logger.error(
          'Error in engagement feed refresh callback: $e',
          tag: 'Main',
          error: e,
          stackTrace: stackTrace,
        );
      }
    });

    Logger.info('Push notification callbacks configured successfully',
        tag: 'Main');
  }

  @override
  void dispose() {
    _releaseFallbackSyncTimer?.cancel();
    _releaseFallbackSyncTimer = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App came to foreground - start active polling for near-instant notifications
      _startActiveSync();
      _startReleaseFallbackSyncLoop();

      // Refresh notification count when app comes to foreground
      try {
        final notificationProvider = InAppNotificationProvider.instance;
        notificationProvider.loadNotifications();
        Logger.info('Notification count refreshed on app resume', tag: 'Main');
      } catch (e) {
        Logger.error('Error refreshing notifications on app resume: $e',
            tag: 'Main', error: e);
      }

      // Immediately refresh engagement feed when app comes to foreground
      try {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final engagementProvider = Provider.of<EngagementProvider>(context, listen: false);
        
        if (authProvider.isAuthenticated && authProvider.user != null) {
          final userId = authProvider.user!.id;
          final token = authProvider.token;
          final userIdString = userId.toString();

          // Sync point balance with server (e.g. poll winner credits from WP-Cron / background).
          PointProvider.instance
              .loadBalance(userIdString, forceRefresh: true)
              .catchError((e) {
            Logger.warning(
                'Error refreshing point balance on app resume: $e',
                tag: 'Main',
                error: e);
          });
          Logger.info('Point balance refresh triggered on app resume (forceRefresh)',
              tag: 'Main');

          engagementProvider.refreshImmediately(
            userId: userId,
            token: token,
          ).catchError((e) {
            Logger.warning('Error refreshing engagement feed on app resume: $e',
                tag: 'Main', error: e);
          });
          
          Logger.info('Engagement feed refresh triggered on app resume', tag: 'Main');
        }
      } catch (e) {
        Logger.error('Error refreshing engagement feed on app resume: $e',
            tag: 'Main', error: e);
      }

      // Start usage tracking session when app resumes
      _handleUsageTrackingResume();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // App going to background - stop active polling to save battery
      _stopActiveSync();
      _stopReleaseFallbackSyncLoop();

      // Old Code: no immediate background task nudge for auto-run poll lifecycle.
      // New Code: schedule one-off background tick so backend keeps progressing
      // AUTO_RUN state while app is backgrounded.
      if (!kIsWeb) {
        BackgroundService.registerAutoRunPollOneOffTick(
          initialDelay: const Duration(seconds: 15),
        ).catchError((e) {
          Logger.warning('Failed scheduling background auto-run poll tick: $e',
              tag: 'Main', error: e);
          return false;
        });
      }

      // End usage tracking session when app goes to background
      _handleUsageTrackingPause();
    } else if (state == AppLifecycleState.detached) {
      _stopReleaseFallbackSyncLoop();
      // Old Code: detached only ended usage tracking.
      // New Code: request one last best-effort server tick before termination.
      if (!kIsWeb) {
        BackgroundService.registerAutoRunPollOneOffTick(
          initialDelay: const Duration(seconds: 5),
        ).catchError((e) {
          Logger.warning(
              'Failed scheduling detached auto-run poll background tick: $e',
              tag: 'Main',
              error: e);
          return false;
        });
      }
      // App is being terminated - end session
      _handleUsageTrackingDetached();
    }
  }

  /// Handle usage tracking when app resumes
  Future<void> _handleUsageTrackingResume() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      if (authProvider.isAuthenticated && authProvider.user != null) {
        final userId = authProvider.user!.id.toString();
        await UsageTrackingService.startSession(userId);

        Logger.info('Usage tracking resumed for user: $userId', tag: 'Main');
      }
    } catch (e, stackTrace) {
      Logger.error(
        'Error resuming usage tracking: $e',
        tag: 'Main',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Handle usage tracking when app pauses
  Future<void> _handleUsageTrackingPause() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      if (authProvider.isAuthenticated && authProvider.user != null) {
        final userId = authProvider.user!.id.toString();
        await UsageTrackingService.endSession(userId);

        Logger.info('Usage tracking paused for user: $userId', tag: 'Main');
      }
    } catch (e, stackTrace) {
      Logger.error(
        'Error pausing usage tracking: $e',
        tag: 'Main',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Handle usage tracking when app is detached (terminated)
  Future<void> _handleUsageTrackingDetached() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      if (authProvider.isAuthenticated && authProvider.user != null) {
        final userId = authProvider.user!.id.toString();
        await UsageTrackingService.endSession(userId);

        Logger.info('Usage tracking ended (app detached) for user: $userId',
            tag: 'Main');
      }
    } catch (e, stackTrace) {
      Logger.error(
        'Error ending usage tracking on detach: $e',
        tag: 'Main',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Start active sync with retry in case auth is not ready yet
  Future<void> _startActiveSyncWithRetry({int retry = 0}) async {
    try {
      final orderProvider = Provider.of<OrderProvider>(context, listen: false);
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      if (authProvider.isAuthenticated && authProvider.user != null) {
        await ActiveSyncService().startPolling(
          orderProvider: orderProvider,
          authProvider: authProvider,
        );
      } else if (retry < 5) {
        // Retry after 1 second if auth not ready yet
        await Future.delayed(Duration(seconds: 1));
        _startActiveSyncWithRetry(retry: retry + 1);
      }
    } catch (e, stackTrace) {
      Logger.error('Error starting active sync: $e',
          tag: 'Main', error: e, stackTrace: stackTrace);
    }
  }

  /// Start active sync polling for near-instant notifications
  Future<void> _startActiveSync() async {
    try {
      final orderProvider = Provider.of<OrderProvider>(context, listen: false);
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      if (authProvider.isAuthenticated && authProvider.user != null) {
        await ActiveSyncService().startPolling(
          orderProvider: orderProvider,
          authProvider: authProvider,
        );
      }
    } catch (e, stackTrace) {
      Logger.error('Error starting active sync: $e',
          tag: 'Main', error: e, stackTrace: stackTrace);
    }
  }

  /// Stop active sync polling when app goes to background
  void _stopActiveSync() {
    ActiveSyncService().stopPolling();
  }

  void _startReleaseFallbackSyncLoop() {
    if (kIsWeb) {
      return;
    }

    // Keep release fallback sync lean and idempotent.
    _releaseFallbackSyncTimer?.cancel();
    _releaseFallbackSyncTimer = Timer.periodic(
      const Duration(seconds: 75),
      (_) => _runReleaseFallbackSync(),
    );
    _runReleaseFallbackSync();
  }

  void _stopReleaseFallbackSyncLoop() {
    _releaseFallbackSyncTimer?.cancel();
    _releaseFallbackSyncTimer = null;
  }

  Future<void> _runReleaseFallbackSync() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (!authProvider.isAuthenticated || authProvider.user == null) {
        return;
      }

      final userIdString = authProvider.user!.id.toString();
      await Future.wait([
        PointProvider.instance.loadBalance(userIdString, forceRefresh: true),
        PointProvider.instance.loadTransactions(userIdString, forceRefresh: true),
      ]);
      Logger.info(
        'Release fallback sync completed for user=$userIdString',
        tag: 'Main',
      );
    } catch (e, stackTrace) {
      Logger.warning(
        'Release fallback sync failed: $e',
        tag: 'Main',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: AuthProvider()),
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => OrderProvider()),
        ChangeNotifierProvider(create: (_) => AddressProvider()),
        ChangeNotifierProvider(create: (_) => ReviewProvider()),
        ChangeNotifierProvider(create: (_) => WishlistProvider()),
        ChangeNotifierProvider(create: (_) => ProductFilterProvider()),
        ChangeNotifierProvider.value(value: PointProvider.instance),
        ChangeNotifierProvider(create: (_) => SpinWheelProvider()),
        ChangeNotifierProvider.value(value: WalletProvider.instance),
        ChangeNotifierProvider(create: (_) => CategoryProvider()),
        ChangeNotifierProvider(create: (_) => EngagementProvider()),
        ChangeNotifierProvider.value(value: ExchangeSettingsProvider.instance),
        ChangeNotifierProvider.value(value: InAppNotificationProvider.instance),
        // Connectivity and offline services
        ChangeNotifierProvider.value(value: ConnectivityService()),
        ChangeNotifierProvider.value(value: OfflineQueueService()),
      ],
      child: PointAuthListener(
        child: WalletAuthListener(
          child: OrderAuthListener(
            child: EngagementAuthListener(
              child: MaterialApp(
                navigatorKey: AppKeys
                    .navigatorKey, // Global navigator key for navigation from anywhere
                scaffoldMessengerKey: AppKeys.scaffoldMessengerKey,
                title: 'PlanetMM',
                debugShowCheckedModeBanner: false,
                theme: AppTheme.lightTheme,
                home: SplashScreen(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
