import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import '../utils/logger.dart';
import '../utils/app_config.dart';
import 'in_app_notification_service.dart';
import '../providers/in_app_notification_provider.dart';
import '../models/in_app_notification.dart';
import '../providers/point_provider.dart';
import '../providers/auth_provider.dart';
import 'point_notification_manager.dart';
import 'missed_notification_recovery_service.dart';

/// PROFESSIONAL SECURITY: Helper function to verify notification user in background handler
/// This is a top-level function that can be called from background handler
Future<bool> _verifyNotificationUserInBackground(
    Map<String, dynamic> data) async {
  try {
    const secureStorage = FlutterSecureStorage();

    // Get userId from notification data
    final notificationUserId =
        data['userId']?.toString() ?? data['user_id']?.toString() ?? '';

    if (notificationUserId.isEmpty) {
      // If no userId in notification, log warning but allow processing
      // (some notifications might not have userId, e.g., system notifications)
      Logger.warning(
          'Background notification has no userId, allowing processing (may be system notification)',
          tag: 'PushNotification');
      return true;
    }

    // Get current logged-in user ID from secure storage
    final userJson = await secureStorage.read(key: 'user_data');
    if (userJson == null) {
      // No user logged in - reject notification
      Logger.info(
          'Background: No user logged in, rejecting notification for userId: $notificationUserId',
          tag: 'PushNotification');
      return false;
    }

    final userData = json.decode(userJson) as Map<String, dynamic>;
    final currentUserId = userData['id']?.toString();

    if (currentUserId == null ||
        currentUserId.isEmpty ||
        currentUserId == '0') {
      Logger.info(
          'Background: No valid user ID found, rejecting notification for userId: $notificationUserId',
          tag: 'PushNotification');
      return false;
    }

    // Verify userId matches
    if (notificationUserId != currentUserId) {
      Logger.warning(
          'Background: Notification userId mismatch: notification=$notificationUserId, current=$currentUserId. Rejecting notification.',
          tag: 'PushNotification');
      return false;
    }

    // User ID matches - allow processing
    Logger.info(
        'Background: Notification verified for current user: $currentUserId',
        tag: 'PushNotification');
    return true;
  } catch (e, stackTrace) {
    Logger.error('Error verifying notification user in background: $e',
        tag: 'PushNotification', error: e, stackTrace: stackTrace);
    // On error, reject notification for security
    return false;
  }
}

/// Background message handler (must be top-level function)
/// This handles notifications when app is terminated or in background
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    // Initialize Firebase if not already initialized
    await Firebase.initializeApp();

    Logger.info('Background message received: ${message.notification?.title}',
        tag: 'PushNotification');
    Logger.info('Message ID: ${message.messageId}, Data: ${message.data}',
        tag: 'PushNotification');

    // PROFESSIONAL SECURITY: Verify notification belongs to current user
    final isAuthorized =
        await _verifyNotificationUserInBackground(message.data);
    if (!isAuthorized) {
      Logger.info('Background notification rejected - not for current user',
          tag: 'PushNotification');
      return; // Reject notification if not for current user
    }

    // Initialize local notifications plugin for background notifications
    final FlutterLocalNotificationsPlugin localNotifications =
        FlutterLocalNotificationsPlugin();

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await localNotifications.initialize(initSettings);

    // Create notification channel for Android
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'order_updates',
      'Order Updates',
      description: 'Notifications for order status updates',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    await localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Show notification in background/terminated state
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'order_updates',
      'Order Updates',
      channelDescription: 'Notifications for order status updates',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await localNotifications.show(
      message.hashCode,
      message.notification?.title ?? 'Order Update',
      message.notification?.body ?? 'Your order has been updated',
      notificationDetails,
      payload: json.encode(message.data),
    );

    Logger.info('Background notification displayed successfully',
        tag: 'PushNotification');
  } catch (e, stackTrace) {
    Logger.error('Error handling background message: $e',
        tag: 'PushNotification', error: e, stackTrace: stackTrace);
  }
}

/// Service for Firebase Cloud Messaging push notifications
/// Handles instant notifications from server
///
/// This service provides INSTANT notifications when WooCommerce backend updates orders
/// It integrates with OrderProvider to immediately refresh orders when notifications arrive
class PushNotificationService {
  static final PushNotificationService _instance =
      PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  String? _fcmToken;
  bool _isInitialized = false;

  // Throttle expensive "hard sync" (network refresh) after point notifications.
  // We still apply the FCM `currentBalance` snapshot instantly to update UI.
  final Map<String, DateTime> _lastPointsHardSyncAtByUser = {};
  static const Duration _pointsHardSyncCooldown = Duration(seconds: 3);

  /// Callback for refreshing orders when notification arrives
  /// Set this from main.dart or app initialization
  Function(String orderId, Map<String, dynamic> data)? onOrderUpdate;

  /// Callback for navigating to order details
  /// Set this from main.dart with navigator key
  Function(String orderId)? onNavigateToOrder;

  /// Callback for navigating to points history page
  /// Set this from main.dart with navigator key
  Function()? onNavigateToPoints;

  /// Callback for navigating to engagement hub
  /// Set this from main.dart with navigator key
  Function({String? itemId, String? itemType})? onNavigateToEngagement;
  /// Callback for forcing engagement feed refresh (real-time config updates)
  Future<void> Function()? onEngagementFeedRefresh;

  /// Check if service is initialized
  bool get isInitialized => _isInitialized;

  /// Get FCM token
  String? get fcmToken => _fcmToken;

  /// Set order update callback (called when notification arrives)
  void setOrderUpdateCallback(
      Function(String orderId, Map<String, dynamic> data) callback) {
    onOrderUpdate = callback;
  }

  /// Set navigation callback (called when notification is tapped)
  void setNavigationCallback(Function(String orderId) callback) {
    onNavigateToOrder = callback;
  }

  /// Set callback for navigating to points history page
  void setPointsNavigationCallback(Function() callback) {
    onNavigateToPoints = callback;
  }

  /// Set callback for navigating to engagement hub
  void setEngagementNavigationCallback(
      Function({String? itemId, String? itemType}) callback) {
    onNavigateToEngagement = callback;
  }

  /// Set callback for forcing engagement feed refresh
  void setEngagementFeedRefreshCallback(Future<void> Function() callback) {
    onEngagementFeedRefresh = callback;
  }

  /// PROFESSIONAL SECURITY: Get current logged-in user ID from secure storage
  /// This ensures notifications are only processed for the current user
  Future<String?> _getCurrentUserId() async {
    try {
      final userJson = await _secureStorage.read(key: 'user_data');
      if (userJson == null) {
        return null;
      }
      final userData = json.decode(userJson) as Map<String, dynamic>;
      final userId = userData['id']?.toString();
      if (userId == null || userId.isEmpty || userId == '0') {
        return null;
      }
      return userId;
    } catch (e) {
      Logger.error('Error getting current user ID: $e',
          tag: 'PushNotification', error: e);
      return null;
    }
  }

  /// PROFESSIONAL SECURITY: Verify if notification belongs to current logged-in user
  /// Returns true if notification should be processed, false otherwise
  Future<bool> _verifyNotificationUser(Map<String, dynamic> data) async {
    try {
      // Get userId from notification data
      final notificationUserId =
          data['userId']?.toString() ?? data['user_id']?.toString() ?? '';

      if (notificationUserId.isEmpty) {
        // If no userId in notification, log warning but allow processing
        // (some notifications might not have userId, e.g., system notifications)
        Logger.warning(
            'Notification has no userId, allowing processing (may be system notification)',
            tag: 'PushNotification');
        return true;
      }

      // Get current logged-in user ID
      final currentUserId = await _getCurrentUserId();

      if (currentUserId == null) {
        // No user logged in - reject notification
        Logger.info(
            'No user logged in, rejecting notification for userId: $notificationUserId',
            tag: 'PushNotification');
        return false;
      }

      // Verify userId matches
      if (notificationUserId != currentUserId) {
        Logger.warning(
            'Notification userId mismatch: notification=$notificationUserId, current=$currentUserId. Rejecting notification.',
            tag: 'PushNotification');
        return false;
      }

      // User ID matches - allow processing
      Logger.info('Notification verified for current user: $currentUserId',
          tag: 'PushNotification');
      return true;
    } catch (e, stackTrace) {
      Logger.error('Error verifying notification user: $e',
          tag: 'PushNotification', error: e, stackTrace: stackTrace);
      // On error, reject notification for security
      return false;
    }
  }

  /// Initialize push notification service
  Future<void> initialize() async {
    if (_isInitialized) {
      Logger.info('PushNotificationService already initialized',
          tag: 'PushNotification');
      return;
    }

    try {
      Logger.info('Initializing Firebase Cloud Messaging',
          tag: 'PushNotification');

      // Request notification permissions
      NotificationSettings settings =
          await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
        criticalAlert: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        Logger.info('User granted notification permission',
            tag: 'PushNotification');

        // Get FCM token
        await _getFCMToken();

        // Configure message handlers
        await _configureMessageHandlers();

        // Configure local notifications for foreground
        await _configureLocalNotifications();

        _isInitialized = true;
        Logger.info('PushNotificationService initialized successfully',
            tag: 'PushNotification');
      } else if (settings.authorizationStatus ==
          AuthorizationStatus.provisional) {
        Logger.info('User granted provisional notification permission',
            tag: 'PushNotification');
        await _getFCMToken();
        await _configureMessageHandlers();
        await _configureLocalNotifications();
        _isInitialized = true;
      } else {
        Logger.warning('User declined notification permission',
            tag: 'PushNotification');
      }
    } catch (e, stackTrace) {
      Logger.error('Error initializing push notifications: $e',
          tag: 'PushNotification', error: e, stackTrace: stackTrace);
    }
  }

  /// Get FCM token
  Future<void> _getFCMToken() async {
    try {
      _fcmToken = await _firebaseMessaging.getToken();
      if (_fcmToken != null) {
        // Show full token for testing (will be in logs)
        Logger.info('FCM Token obtained (full): $_fcmToken',
            tag: 'PushNotification');
        Logger.info(
            'FCM Token (first 50 chars): ${_fcmToken!.substring(0, 50)}...',
            tag: 'PushNotification');

        // Send token to backend
        await _sendTokenToBackend(_fcmToken!);
      } else {
        Logger.warning('FCM token is null', tag: 'PushNotification');
      }
    } catch (e) {
      Logger.error('Failed to get FCM token: $e',
          tag: 'PushNotification', error: e);
    }
  }

  /// Send FCM token to backend server
  Future<void> _sendTokenToBackend(String token) async {
    try {
      // Get user ID from secure storage
      final userJson = await _secureStorage.read(key: 'user_data');

      if (userJson == null) {
        Logger.info('No user data found, skipping token upload',
            tag: 'PushNotification');
        return;
      }

      final userData = json.decode(userJson) as Map<String, dynamic>;
      final userId = userData['id']?.toString();

      if (userId == null || userId.isEmpty || userId == '0') {
        Logger.info('No valid user ID found, skipping token upload',
            tag: 'PushNotification');
        return;
      }

      Logger.info('Uploading FCM token to backend for user: $userId',
          tag: 'PushNotification');

      // Upload FCM token to backend server
      try {
        final backendUrl = _getBackendUrl();
        if (backendUrl == null || backendUrl.isEmpty) {
          Logger.info('Backend URL not configured, skipping token upload',
              tag: 'PushNotification');
          Logger.info('Configure backend URL in lib/utils/app_config.dart',
              tag: 'PushNotification');
          return;
        }

        final response = await http
            .post(
          Uri.parse('$backendUrl${AppConfig.backendRegisterTokenEndpoint}'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'userId': userId,
            'fcmToken': token,
            'platform': Platform.isAndroid ? 'android' : 'ios',
          }),
        )
            .timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            Logger.warning('Backend token upload timeout',
                tag: 'PushNotification');
            throw TimeoutException('Backend request timeout');
          },
        );

        if (response.statusCode == 200) {
          Logger.info('✅ FCM token uploaded successfully to backend',
              tag: 'PushNotification');
        } else {
          Logger.warning('Failed to upload FCM token: ${response.statusCode}',
              tag: 'PushNotification');
        }
      } on TimeoutException {
        Logger.warning(
            'Backend token upload timeout - continuing without backend sync',
            tag: 'PushNotification');
      } catch (e) {
        Logger.warning(
            'Backend not available - continuing without backend sync: $e',
            tag: 'PushNotification');
        // Don't fail the entire FCM initialization if backend is not available
      }
    } catch (e) {
      Logger.error('Failed to send FCM token to backend: $e',
          tag: 'PushNotification', error: e);
    }
  }

  /// Configure message handlers
  /// This sets up listeners for FCM messages in all app states (foreground, background, terminated)
  Future<void> _configureMessageHandlers() async {
    // Handle foreground messages (app is open)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      Logger.info('Foreground message received: ${message.notification?.title}',
          tag: 'PushNotification');
      Logger.info('Message data: ${message.data}', tag: 'PushNotification');

      // Show local notification in foreground
      _handleForegroundMessage(message);

      // Trigger immediate order refresh when notification arrives
      await _handleOrderUpdateNotification(message);
    });

    // Handle notification tap when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
      Logger.info(
          'Notification tapped (background): ${message.notification?.title}',
          tag: 'PushNotification');
      Logger.info('Message data: ${message.data}', tag: 'PushNotification');

      // Handle notification tap and navigate
      _handleNotificationTap(message);

      // Also trigger order refresh
      await _handleOrderUpdateNotification(message);
    });

    // Handle notification tap when app was terminated
    final initialMessage = await _firebaseMessaging.getInitialMessage();
    if (initialMessage != null) {
      Logger.info(
          'Notification tapped (terminated): ${initialMessage.notification?.title}',
          tag: 'PushNotification');
      Logger.info('Message data: ${initialMessage.data}',
          tag: 'PushNotification');

      // Handle notification tap and navigate
      await _handleNotificationTap(initialMessage);

      // Also trigger order refresh
      await _handleOrderUpdateNotification(initialMessage);
    }

    // Handle FCM token refresh
    _firebaseMessaging.onTokenRefresh.listen((newToken) {
      Logger.info('FCM token refreshed', tag: 'PushNotification');
      _fcmToken = newToken;
      _sendTokenToBackend(newToken);
    });

    Logger.info('Message handlers configured', tag: 'PushNotification');
  }

  /// PROFESSIONAL FCM INTEGRATION: Get list of point notification types
  /// Includes all point-related events for comprehensive notification coverage
  static const List<String> _pointNotificationTypes = [
    'points_earned',
    'points_approved',
    'points_redeemed',
    'exchange_approved',
    'exchange_rejected',
    'engagement_points',
    'points_adjusted', // Manual adjustment from dashboard
  ];

  /// PROFESSIONAL ENGAGEMENT NOTIFICATIONS: Get list of engagement notification types
  /// Includes all engagement hub activities for comprehensive notification coverage
  static const List<String> _engagementNotificationTypes = [
    'engagement_quiz_submitted',
    'engagement_poll_submitted',
    'engagement_banner_viewed',
    'engagement_announcement_viewed',
    'engagement_number_viewed', // PROFESSIONAL FIX: Added number type notification
    'engagement_new_item',
    'engagement_item_updated', // PROFESSIONAL FIX: Added update notification type
  ];

  /// Handle order update notification - triggers immediate order refresh
  /// This is called when FCM notification arrives to ensure orders are instantly updated
  /// Also creates in-app notification
  Future<void> _handleOrderUpdateNotification(RemoteMessage message) async {
    try {
      final data = message.data;
      final orderId = data['orderId'] ?? data['order_id'];
      final notificationType = data['type'] ?? '';
      final notificationReason = data['reason']?.toString() ??
          data['notification_reason']?.toString() ??
          '';

      // Global engagement settings changes are cross-user events by nature.
      // Do not block these by strict userId verification.
      final isGlobalEngagementSettingsUpdate =
          notificationType == 'engagement_item_updated' &&
              notificationReason == 'global_rotation_settings_changed';

      // PROFESSIONAL SECURITY: Verify notification belongs to current user
      final isAuthorized = isGlobalEngagementSettingsUpdate
          ? true
          : await _verifyNotificationUser(data);
      if (!isAuthorized) {
        Logger.info(
            'Notification rejected - not for current user. Type: $notificationType',
            tag: 'PushNotification');
        return; // Reject notification if not for current user
      }

      // PROFESSIONAL FCM INTEGRATION: Handle all point-related notifications
      // Supported types: points_earned, points_approved, points_redeemed,
      // exchange_approved, exchange_rejected, engagement_points
      if (_pointNotificationTypes.contains(notificationType)) {
        Logger.info('Point notification received: $notificationType',
            tag: 'PushNotification');

        final transactionId =
            data['transactionId'] ?? data['transaction_id'] ?? '';
        final requestId = data['requestId'] ?? data['request_id'] ?? '';
        final points = data['points'] ?? '0';
        final userId = data['userId'] ?? data['user_id'] ?? '';
        final currentBalance =
            data['currentBalance'] ?? data['current_balance'] ?? '0';
        final reason = data['reason'] ?? '';

        Logger.info(
            'Point notification details: type=$notificationType, transactionId=$transactionId, requestId=$requestId, points=$points, userId=$userId, balance=$currentBalance',
            tag: 'PushNotification');

        // PROFESSIONAL REAL-TIME UX:
        // 1) Apply payload snapshot instantly (no manual refresh needed).
        // 2) Throttle a background hard-sync to reconcile server state.
        if (userId.isNotEmpty) {
          final balanceInt = int.tryParse(currentBalance.toString()) ?? 0;

          // Update UI immediately (MyPointWidget uses AuthProvider customFields).
          AuthProvider().applyPointsBalanceSnapshot(balanceInt);
          PointProvider.instance.applyRemoteBalanceSnapshot(
            userId: userId.toString(),
            currentBalance: balanceInt,
          );

          // Reconcile from server in background (balance + transactions + user meta).
          _schedulePointsHardSync(userId.toString());
        } else {
          Logger.warning(
              'No userId in point notification, cannot apply point snapshot/sync',
              tag: 'PushNotification');
        }

        // Handle specific notification types for additional actions
        switch (notificationType) {
          case 'exchange_approved':
            Logger.info('Exchange request approved: Request ID $requestId',
                tag: 'PushNotification');
            // Could navigate to exchange history or show success message
            break;
          case 'exchange_rejected':
            Logger.info(
                'Exchange request rejected: Request ID $requestId, Reason: $reason',
                tag: 'PushNotification');
            // Could navigate to exchange history or show error message
            break;
          case 'engagement_points':
            final itemTitle = data['itemTitle'] ?? data['item_title'] ?? '';
            Logger.info(
                'Engagement points earned: $points points from $itemTitle',
                tag: 'PushNotification');
            // Could show celebration animation or navigate to engagement hub
            break;
        }

        // PROFESSIONAL FCM INTEGRATION: Create in-app notification for point events
        try {
          // Get notification title and body from message
          final notificationTitle = message.notification?.title ??
              _getPointNotificationTitle(notificationType, points);
          final notificationBody = message.notification?.body ??
              _getPointNotificationBody(
                  notificationType, points, currentBalance, data);

          // Create in-app notification
          final notificationCreated =
              await InAppNotificationService().createPointNotification(
            type: notificationType,
            title: notificationTitle,
            body: notificationBody,
            transactionId: transactionId.isNotEmpty ? transactionId : null,
            requestId: requestId.isNotEmpty ? requestId : null,
            points: points,
            currentBalance: currentBalance,
            additionalData: data,
          );

          if (notificationCreated) {
            // Update provider immediately for real-time UI update
            try {
              final notificationProvider = InAppNotificationProvider.instance;
              await notificationProvider.loadNotifications();
              Logger.info(
                  'In-app point notification created and provider updated: type=$notificationType',
                  tag: 'PushNotification');
            } catch (e) {
              Logger.error('Error updating notification provider: $e',
                  tag: 'PushNotification', error: e);
            }

            // PROFESSIONAL FIX: Mark transaction as notified to prevent duplicate on app reinstall
            if (transactionId.isNotEmpty && userId.isNotEmpty) {
              MissedNotificationRecoveryService.markTransactionAsNotified(
                  userId, transactionId);
              Logger.info(
                  'Transaction marked as notified: $transactionId',
                  tag: 'PushNotification');
            }
          } else {
            Logger.info(
                'Duplicate point notification prevented: type=$notificationType',
                tag: 'PushNotification');
          }

          // PROFESSIONAL MODAL INTEGRATION: Trigger modal popup for point events
          // Only trigger modal for positive events that should be celebrated
          try {
            // Map notification type to PointNotificationType
            PointNotificationType? modalType;
            bool shouldShowModal = false;
            bool? isAdjustmentPositive;

            switch (notificationType) {
              case 'points_earned':
                modalType = PointNotificationType.earned;
                shouldShowModal = true;
                break;
              case 'points_approved':
                modalType = PointNotificationType.approved;
                shouldShowModal = true;
                break;
              case 'engagement_points':
                modalType = PointNotificationType.engagementEarned;
                // Poll winner: FCM already surfaced the system notification; in-app row
                // was created above — do not stack a blocking modal.
                final engagementItemType = (data['itemType'] ??
                        data['item_type'] ??
                        '')
                    .toString()
                    .toLowerCase();
                shouldShowModal = engagementItemType != 'poll';
                break;
              case 'exchange_approved':
                modalType = PointNotificationType.exchangeApproved;
                shouldShowModal = true;
                break;
              case 'points_redeemed':
                modalType = PointNotificationType.redeemed;
                shouldShowModal = false; // Don't show modal for redeemed
                break;
              case 'exchange_rejected':
                modalType = PointNotificationType.exchangeRejected;
                shouldShowModal = false; // Don't show modal for rejected
                break;
              case 'points_adjusted':
                modalType = PointNotificationType.adjusted;
                // UX requirement: Do NOT show modal for negative manual adjustments.
                // Backend sends `points` as absolute value; direction comes from `isPositive` / `is_positive` / `points_value`.
                isAdjustmentPositive = _parseBool(data['isPositive']) ??
                    _parseBool(data['is_positive']);
                if (isAdjustmentPositive == null) {
                  final pointsValueRaw =
                      data['pointsValue'] ?? data['points_value'];
                  final parsedDelta =
                      int.tryParse(pointsValueRaw?.toString() ?? '');
                  if (parsedDelta != null) {
                    isAdjustmentPositive = parsedDelta >= 0;
                  }
                }
                shouldShowModal = isAdjustmentPositive == true;
                break;
            }

            if (modalType != null && shouldShowModal) {
              final pointsInt = int.tryParse(points) ?? 0;
              final balanceInt = int.tryParse(currentBalance) ?? 0;

              // Trigger modal event
              final itemIdRaw =
                  data['itemId'] ?? data['item_id'] ?? data['pollId'] ?? data['poll_id'];
              await PointNotificationManager().notifyPointEvent(
                type: modalType,
                points: pointsInt,
                currentBalance: balanceInt,
                description: message.notification?.body,
                transactionId: transactionId.isNotEmpty ? transactionId : null,
                orderId: transactionId.isNotEmpty
                    ? null
                    : (notificationType == 'engagement_points' &&
                            itemIdRaw != null &&
                            itemIdRaw.toString().isNotEmpty)
                        ? 'fcm_engagement_${itemIdRaw}'
                        : null,
                userId: userId,
                additionalData: {
                  if (notificationType == 'engagement_points') ...{
                    'itemType': data['itemType'] ?? data['item_type'] ?? '',
                    'itemTitle': data['itemTitle'] ?? data['item_title'] ?? '',
                    if (itemIdRaw != null) 'itemId': itemIdRaw,
                    if (data['pollId'] != null || data['poll_id'] != null)
                      'pollId': data['pollId'] ?? data['poll_id'],
                    if (data['sessionId'] != null || data['session_id'] != null)
                      'sessionId': data['sessionId'] ?? data['session_id'],
                  },
                  if (notificationType == 'exchange_rejected') 'reason': reason,
                  if (notificationType == 'points_adjusted') ...{
                    // Important: do NOT infer positivity from `points` because backend uses absolute value.
                    'isPositive': isAdjustmentPositive ?? true,
                  },
                },
                showPushNotification:
                    false, // Already shown via FCM, don't show again
                showInAppNotification:
                    false, // Already created above, don't create duplicate
                showModalPopup: true,
              );

              Logger.info(
                  'Point notification modal event triggered: type=$notificationType, points=$pointsInt',
                  tag: 'PushNotification');
            }

            // PROFESSIONAL FIX: Mark transaction as notified
            // This prevents duplicate notifications on app reinstall
            if (transactionId.isNotEmpty && userId.isNotEmpty) {
              MissedNotificationRecoveryService.markTransactionAsNotified(
                  userId, transactionId);
            }
          } catch (e, stackTrace) {
            Logger.error('Error triggering point notification modal: $e',
                tag: 'PushNotification', error: e, stackTrace: stackTrace);
          }
        } catch (e, stackTrace) {
          Logger.error('Error creating in-app point notification: $e',
              tag: 'PushNotification', error: e, stackTrace: stackTrace);
        }

        return; // Exit early for point notifications
      }

      // Handle reward update notifications (refresh user to update custom_fields['my_rewards'])
      if (notificationType == 'reward_updated') {
        Logger.info('Reward update notification received',
            tag: 'PushNotification');
        final userId = data['userId'] ?? data['user_id'] ?? '';
        final rewardValue = data['rewardValue'] ?? data['reward_value'] ?? '';
        Logger.info(
            'Reward notification details: userId=$userId, rewardValue=$rewardValue',
            tag: 'PushNotification');

        try {
          // Refresh user profile so UI shows latest custom field "my_rewards"
          await AuthProvider().refreshUser();
          Logger.info('User refreshed after reward update',
              tag: 'PushNotification');
        } catch (e, stackTrace) {
          Logger.error('Error refreshing user after reward update: $e',
              tag: 'PushNotification', error: e, stackTrace: stackTrace);
        }
        return;
      }

      // PROFESSIONAL ENGAGEMENT NOTIFICATIONS: Handle all engagement hub notifications
      if (_engagementNotificationTypes.contains(notificationType) ||
          isGlobalEngagementSettingsUpdate) {
        Logger.info('Engagement notification received: $notificationType',
            tag: 'PushNotification');
        final userId = data['userId'] ?? data['user_id'] ?? '';
        final itemId = data['itemId'] ?? data['item_id'] ?? '';
        final itemTitle = data['itemTitle'] ?? data['item_title'] ?? '';
        final itemType = data['itemType'] ?? data['item_type'] ?? '';
        final numberValue = data['numberValue'] ??
            data['number_value'] ??
            ''; // PROFESSIONAL FIX: Handle number value

        Logger.info(
            'Engagement notification details: type=$notificationType, userId=$userId, itemId=$itemId, itemType=$itemType, itemTitle=$itemTitle, numberValue=$numberValue',
            tag: 'PushNotification');

        // PROFESSIONAL FIX: Special handling for number type notifications
        if (itemType == 'number' && numberValue.isNotEmpty) {
          Logger.info(
              'Number type engagement notification: Number value=$numberValue',
              tag: 'PushNotification');
        }

        // Refresh engagement feed immediately for real-time config/content updates
        try {
          if (onEngagementFeedRefresh != null) {
            await onEngagementFeedRefresh!();
          } else {
            Logger.warning(
                'Engagement feed refresh callback not set. '
                'Set callback using PushNotificationService().setEngagementFeedRefreshCallback()',
                tag: 'PushNotification');
          }
          Logger.info('Engagement notification processed: $notificationType',
              tag: 'PushNotification');
        } catch (e, stackTrace) {
          Logger.error('Error processing engagement notification: $e',
              tag: 'PushNotification', error: e, stackTrace: stackTrace);
        }
        return;
      }

      // Only process order status update notifications
      if (notificationType == 'order_status_update' && orderId != null) {
        final userId = data['userId'] ?? data['user_id'] ?? '';
        Logger.info(
            'Order update notification received for order: $orderId, userId: $userId',
            tag: 'PushNotification');

        // Create in-app notification
        try {
          final status = data['status'] ?? 'updated';
          final total = data['total'] ?? '0';
          final currency = data['currency'] ?? 'Ks';

          // Create notification in service (with deduplication)
          final notificationCreated =
              await InAppNotificationService().createOrderNotification(
            orderId: orderId.toString(),
            status: status.toString(),
            total: total.toString(),
            currency: currency.toString(),
          );

          if (notificationCreated) {
            // Update provider immediately for real-time UI update
            try {
              final notificationProvider = InAppNotificationProvider.instance;
              await notificationProvider.loadNotifications();
              Logger.info(
                  'Notification provider updated immediately for order: $orderId',
                  tag: 'PushNotification');
            } catch (e) {
              Logger.error('Error updating notification provider: $e',
                  tag: 'PushNotification', error: e);
            }

            Logger.info('In-app notification created for order: $orderId',
                tag: 'PushNotification');
          } else {
            Logger.info('Duplicate notification prevented for order: $orderId',
                tag: 'PushNotification');
          }
        } catch (e) {
          Logger.error('Error creating in-app notification: $e',
              tag: 'PushNotification', error: e);
        }
        Logger.info('Triggering immediate order refresh',
            tag: 'PushNotification');

        // Call the callback to refresh orders immediately
        if (onOrderUpdate != null) {
          onOrderUpdate!(orderId.toString(), data);
          Logger.info('Order refresh callback triggered for order: $orderId',
              tag: 'PushNotification');
        } else {
          Logger.warning(
              'Order update callback not set, notification received but order not refreshed',
              tag: 'PushNotification');
          Logger.warning(
              'Set callback using PushNotificationService().setOrderUpdateCallback()',
              tag: 'PushNotification');
        }
      } else {
        Logger.info(
            'Notification type is not order_status_update, skipping order refresh',
            tag: 'PushNotification');
      }
    } catch (e, stackTrace) {
      Logger.error('Error handling order update notification: $e',
          tag: 'PushNotification', error: e, stackTrace: stackTrace);
    }
  }

  void _schedulePointsHardSync(String userId) {
    final now = DateTime.now();
    final last = _lastPointsHardSyncAtByUser[userId];
    if (last != null && now.difference(last) < _pointsHardSyncCooldown) {
      Logger.info(
        'Skipping points hard-sync (cooldown) for user: $userId',
        tag: 'PushNotification',
      );
      return;
    }

    _lastPointsHardSyncAtByUser[userId] = now;

    unawaited(() async {
      try {
        Logger.info('Running points hard-sync for user: $userId',
            tag: 'PushNotification');

        await Future.wait([
          // Refresh user meta (points_balance/my_points etc.)
          AuthProvider().refreshUser(),
          // Refresh balance from backend source-of-truth.
          PointProvider.instance.loadBalance(userId, forceRefresh: true),
          // Refresh transactions so history updates without manual refresh.
          PointProvider.instance.loadTransactions(userId, forceRefresh: true),
        ]);

        Logger.info('Points hard-sync completed for user: $userId',
            tag: 'PushNotification');
      } catch (e, stackTrace) {
        Logger.error('Points hard-sync failed: $e',
            tag: 'PushNotification', error: e, stackTrace: stackTrace);
      }
    }());
  }

  /// Configure local notifications for foreground
  Future<void> _configureLocalNotifications() async {
    // Configure Android notification channels for Android 8.0+
    const androidChannelOrder = AndroidNotificationChannel(
      'order_updates',
      'Order Updates',
      description: 'Notifications for order status updates',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    const androidChannelPoints = AndroidNotificationChannel(
      'points_updates',
      'Points Updates',
      description: 'Notifications for loyalty points updates',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    const androidChannelEngagement = AndroidNotificationChannel(
      'engagement_updates',
      'Engagement Hub',
      description:
          'Notifications for Engagement Hub activities, quizzes, polls, and announcements',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    // Initialize with channel creation
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        Logger.info('Local notification tapped: ${response.payload}',
            tag: 'PushNotification');

        // Handle notification tap
        if (response.payload != null && response.payload!.isNotEmpty) {
          try {
            final payloadData = json.decode(response.payload!);
            final notificationType = payloadData['type'] ?? '';
            final orderId = payloadData['orderId'] ?? payloadData['order_id'];

            Logger.info(
                'Notification tap - type: $notificationType, orderId: $orderId',
                tag: 'PushNotification');

            // PROFESSIONAL SECURITY: Verify notification belongs to current user
            final pushService = PushNotificationService();
            final isAuthorized =
                await pushService._verifyNotificationUser(payloadData);
            if (!isAuthorized) {
              Logger.info(
                  'Local notification tap rejected - not for current user. Type: $notificationType',
                  tag: 'PushNotification');
              return; // Reject notification if not for current user
            }

            // Handle point notifications
            if (_pointNotificationTypes.contains(notificationType)) {
              Logger.info('Point notification tapped: $notificationType',
                  tag: 'PushNotification');

              // Mark in-app notification as read if exists (fire and forget)
              _markPointNotificationAsRead(payloadData);

              // Call navigation callback for points if set
              // Use Future.microtask to ensure navigation happens after current frame
              if (onNavigateToPoints != null) {
                Future.microtask(() {
                  onNavigateToPoints!();
                  Logger.info('Navigation callback triggered for points',
                      tag: 'PushNotification');
                });
              } else {
                Logger.warning(
                    'Points navigation callback not set, notification tapped but navigation not handled',
                    tag: 'PushNotification');
                Logger.warning(
                    'Set callback using PushNotificationService().setPointsNavigationCallback()',
                    tag: 'PushNotification');
              }
              return;
            }

            // Handle engagement notifications
            if (_engagementNotificationTypes.contains(notificationType)) {
              Logger.info('Engagement notification tapped: $notificationType',
                  tag: 'PushNotification');

              final itemId = payloadData['itemId']?.toString() ??
                  payloadData['item_id']?.toString();
              final itemType = payloadData['itemType']?.toString() ??
                  payloadData['item_type']?.toString();

              // Call navigation callback for engagement if set
              // Use Future.microtask to ensure navigation happens after current frame
              if (onNavigateToEngagement != null) {
                Future.microtask(() {
                  onNavigateToEngagement!(
                    itemId: itemId,
                    itemType: itemType,
                  );
                  Logger.info(
                      'Navigation callback triggered for engagement: itemId=$itemId, itemType=$itemType',
                      tag: 'PushNotification');
                });
              } else {
                Logger.warning(
                    'Engagement navigation callback not set, notification tapped but navigation not handled',
                    tag: 'PushNotification');
                Logger.warning(
                    'Set callback using PushNotificationService().setEngagementNavigationCallback()',
                    tag: 'PushNotification');
              }
              return;
            }

            // Handle order notifications
            if (orderId != null && notificationType == 'order_status_update') {
              Logger.info('Order notification tapped: $orderId',
                  tag: 'PushNotification');

              // Mark in-app notification as read if exists (fire and forget)
              _markOrderNotificationAsRead(orderId.toString(), payloadData);

              // Call navigation callback if set
              // Use Future.microtask to ensure navigation happens after current frame
              if (onNavigateToOrder != null) {
                Future.microtask(() {
                  onNavigateToOrder!(orderId.toString());
                  Logger.info(
                      'Navigation callback triggered for order: $orderId',
                      tag: 'PushNotification');
                });
              } else {
                Logger.warning(
                    'Navigation callback not set, notification tapped but navigation not handled',
                    tag: 'PushNotification');
                Logger.warning(
                    'Set callback using PushNotificationService().setNavigationCallback()',
                    tag: 'PushNotification');
              }
            }
          } catch (e, stackTrace) {
            Logger.error('Error handling local notification tap: $e',
                tag: 'PushNotification', error: e, stackTrace: stackTrace);
          }
        } else {
          Logger.warning('Notification tapped but payload is empty',
              tag: 'PushNotification');
        }
      },
    );

    // Create the channels AFTER initialization
    final androidImplementation =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidImplementation?.createNotificationChannel(androidChannelOrder);
    await androidImplementation
        ?.createNotificationChannel(androidChannelPoints);
    await androidImplementation
        ?.createNotificationChannel(androidChannelEngagement);

    Logger.info(
        'Local notifications configured with channels: ${androidChannelOrder.id}, ${androidChannelPoints.id}, ${androidChannelEngagement.id}',
        tag: 'PushNotification');
  }

  /// Handle foreground message by showing local notification
  /// This displays notification when app is in foreground and triggers order refresh
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    try {
      // Extract notification data
      final data = message.data;
      final orderId = data['orderId'] ?? data['order_id'];
      final notificationType = data['type'] ?? '';

      // PROFESSIONAL SECURITY: Verify notification belongs to current user
      final isAuthorized = await _verifyNotificationUser(data);
      if (!isAuthorized) {
        Logger.info(
            'Foreground notification rejected - not for current user. Type: $notificationType',
            tag: 'PushNotification');
        return; // Reject notification if not for current user
      }

      // Use different channel for points notifications
      final String channelId;
      final String channelName;
      final String channelDescription;

      // PROFESSIONAL FCM INTEGRATION: Use appropriate channel based on notification type
      if (_pointNotificationTypes.contains(notificationType) ||
          notificationType == 'reward_updated') {
        channelId = 'points_updates';
        channelName = 'Points Updates';
        channelDescription =
            'Notifications for loyalty points and rewards updates';
      } else if (_engagementNotificationTypes.contains(notificationType)) {
        channelId = 'engagement_updates';
        channelName = 'Engagement Hub';
        channelDescription =
            'Notifications for Engagement Hub activities, quizzes, polls, and announcements';
      } else {
        channelId = 'order_updates';
        channelName = 'Order Updates';
        channelDescription = 'Notifications for order status updates';
      }

      // Prepare notification details
      final androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        // Enable heads-up notification for immediate visibility
        enableLights: true,
        ledColor: Color.fromARGB(255, 0, 122, 255),
        ledOnMs: 1000,
        ledOffMs: 500,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      // Cannot use const here because androidDetails is dynamic based on notification type
      final NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Show notification with payload containing order data
      await _localNotifications.show(
        message.hashCode,
        message.notification?.title ?? 'Order Update',
        message.notification?.body ?? 'Your order has been updated',
        details,
        payload: json.encode(message.data),
      );

      Logger.info('Foreground notification displayed for order: $orderId',
          tag: 'PushNotification');

      // PROFESSIONAL FCM INTEGRATION: Trigger immediate refresh for all point notifications
      // Trigger immediate order refresh and in-app notification update when notification arrives in foreground
      if ((notificationType == 'order_status_update' && orderId != null) ||
          _pointNotificationTypes.contains(notificationType) ||
          _engagementNotificationTypes.contains(notificationType) ||
          notificationType == 'reward_updated') {
        Logger.info(
            'Foreground notification received, triggering immediate refresh',
            tag: 'PushNotification');
        await _handleOrderUpdateNotification(message);
      }
    } catch (e, stackTrace) {
      Logger.error('Failed to display foreground notification: $e',
          tag: 'PushNotification', error: e, stackTrace: stackTrace);
    }
  }

  /// Handle notification tap
  /// Navigates to order details or point history when user taps on notification
  Future<void> _handleNotificationTap(RemoteMessage message) async {
    try {
      final data = message.data;
      final orderId = data['orderId'] ?? data['order_id'];
      final notificationType = data['type'] ?? '';

      // PROFESSIONAL SECURITY: Verify notification belongs to current user
      final isAuthorized = await _verifyNotificationUser(data);
      if (!isAuthorized) {
        Logger.info(
            'Notification tap rejected - not for current user. Type: $notificationType',
            tag: 'PushNotification');
        return; // Reject notification if not for current user
      }

      // Handle point notifications
      if (_pointNotificationTypes.contains(notificationType)) {
        Logger.info('Point notification tapped: $notificationType',
            tag: 'PushNotification');

        // Mark in-app notification as read if exists
        _markPointNotificationAsRead(data);

        // Call navigation callback for points if set
        if (onNavigateToPoints != null) {
          onNavigateToPoints!();
          Logger.info('Navigation callback triggered for points',
              tag: 'PushNotification');
        } else {
          Logger.warning(
              'Points navigation callback not set, notification tapped but navigation not handled',
              tag: 'PushNotification');
          Logger.warning(
              'Set callback using PushNotificationService().setPointsNavigationCallback()',
              tag: 'PushNotification');
        }
        return;
      }

      // Handle engagement notifications
      if (_engagementNotificationTypes.contains(notificationType)) {
        Logger.info('Engagement notification tapped: $notificationType',
            tag: 'PushNotification');

        final itemId =
            data['itemId']?.toString() ?? data['item_id']?.toString();
        final itemType =
            data['itemType']?.toString() ?? data['item_type']?.toString();

        // Call navigation callback for engagement if set
        if (onNavigateToEngagement != null) {
          onNavigateToEngagement!(
            itemId: itemId,
            itemType: itemType,
          );
          Logger.info(
              'Navigation callback triggered for engagement: itemId=$itemId, itemType=$itemType',
              tag: 'PushNotification');
        } else {
          Logger.warning(
              'Engagement navigation callback not set, notification tapped but navigation not handled',
              tag: 'PushNotification');
          Logger.warning(
              'Set callback using PushNotificationService().setEngagementNavigationCallback()',
              tag: 'PushNotification');
        }
        return;
      }

      // Handle order notifications
      if (orderId != null && notificationType == 'order_status_update') {
        Logger.info('Notification tapped for order: $orderId',
            tag: 'PushNotification');

        // Mark in-app notification as read if exists
        _markOrderNotificationAsRead(orderId.toString(), data);

        // Call navigation callback if set
        if (onNavigateToOrder != null) {
          onNavigateToOrder!(orderId.toString());
          Logger.info('Navigation callback triggered for order: $orderId',
              tag: 'PushNotification');
        } else {
          Logger.warning(
              'Navigation callback not set, notification tapped but navigation not handled',
              tag: 'PushNotification');
          Logger.warning(
              'Set callback using PushNotificationService().setNavigationCallback()',
              tag: 'PushNotification');
        }
      } else {
        Logger.info('Notification tapped but orderId not found or wrong type',
            tag: 'PushNotification');
      }

      Logger.info('Notification tap handled for message: ${message.messageId}',
          tag: 'PushNotification');
    } catch (e, stackTrace) {
      Logger.error('Error handling notification tap: $e',
          tag: 'PushNotification', error: e, stackTrace: stackTrace);
    }
  }

  /// Mark point notification as read in in-app notifications
  Future<void> _markPointNotificationAsRead(Map<String, dynamic> data) async {
    try {
      final notificationType = data['type'] ?? '';
      final transactionId =
          data['transactionId'] ?? data['transaction_id'] ?? '';
      final requestId = data['requestId'] ?? data['request_id'] ?? '';

      // Get all notifications and find matching one
      final notifications = await InAppNotificationService().getNotifications();

      // Find notification by type and transaction/request ID
      for (final notification in notifications) {
        if (notification.type == NotificationType.points) {
          final nType = notification.data?['notificationType']?.toString();
          final nTransactionId =
              notification.data?['transactionId']?.toString();
          final nRequestId = notification.data?['requestId']?.toString();

          if (nType == notificationType) {
            // Match by transaction ID or request ID
            if (transactionId.isNotEmpty && nTransactionId == transactionId) {
              await InAppNotificationService().markAsRead(notification.id);
              Logger.info(
                  'Marked point notification as read: ${notification.id}',
                  tag: 'PushNotification');
              break;
            } else if (requestId.isNotEmpty && nRequestId == requestId) {
              await InAppNotificationService().markAsRead(notification.id);
              Logger.info(
                  'Marked point notification as read: ${notification.id}',
                  tag: 'PushNotification');
              break;
            }
          }
        }
      }

      // PROFESSIONAL REAL-TIME ENGAGEMENT SYNC:
      // If notification indicates engagement hub content/settings changed,
      // trigger an immediate engagement-related action.
      if (_engagementNotificationTypes.contains(notificationType)) {
        Logger.info(
          'Engagement notification received: $notificationType, data=$data',
          tag: 'PushNotification',
        );
        // For now we rely on the existing engagement auto-poll (2s interval).
        // In a future step we can wire a direct callback from main.dart to
        // trigger EngagementProvider.loadFeed(forceRefresh: true) here.
      }

      // Update provider
      try {
        final notificationProvider = InAppNotificationProvider.instance;
        await notificationProvider.loadNotifications();
      } catch (e) {
        Logger.error('Error updating notification provider: $e',
            tag: 'PushNotification', error: e);
      }
    } catch (e, stackTrace) {
      Logger.error('Error marking point notification as read: $e',
          tag: 'PushNotification', error: e, stackTrace: stackTrace);
    }
  }

  /// Mark order notification as read in in-app notifications
  Future<void> _markOrderNotificationAsRead(
      String orderId, Map<String, dynamic> data) async {
    try {
      final status = data['status'] ?? '';

      // Get all notifications and find matching one
      final notifications = await InAppNotificationService().getNotifications();

      // Find notification by order ID and status
      for (final notification in notifications) {
        if (notification.type == NotificationType.order) {
          final nOrderId = notification.data?['orderId']?.toString();
          final nStatus = notification.data?['status']?.toString();

          if (nOrderId == orderId && nStatus == status) {
            await InAppNotificationService().markAsRead(notification.id);
            Logger.info('Marked order notification as read: ${notification.id}',
                tag: 'PushNotification');
            break;
          }
        }
      }

      // Update provider
      try {
        final notificationProvider = InAppNotificationProvider.instance;
        await notificationProvider.loadNotifications();
      } catch (e) {
        Logger.error('Error updating notification provider: $e',
            tag: 'PushNotification', error: e);
      }
    } catch (e, stackTrace) {
      Logger.error('Error marking order notification as read: $e',
          tag: 'PushNotification', error: e, stackTrace: stackTrace);
    }
  }

  /// Get notification title for point notifications
  /// Professional, clear, and user-friendly messages
  String _getPointNotificationTitle(String type, String points) {
    final pointsNum = int.tryParse(points) ?? 0;
    switch (type) {
      case 'points_earned':
        return pointsNum > 0
            ? '🎉 Congratulations! $pointsNum PNP Earned'
            : 'Points Balance Updated';
      case 'points_approved':
        return pointsNum > 0
            ? '✅ $pointsNum PNP Successfully Approved'
            : 'Points Request Approved';
      case 'points_redeemed':
        return pointsNum > 0
            ? '💎 Exchange Request Submitted'
            : 'Exchange Request Submitted';
      case 'exchange_approved':
        return '✅ Exchange Request Approved';
      case 'exchange_rejected':
        return '⚠️ Exchange Request Update';
      case 'engagement_points':
        return pointsNum > 0
            ? '🎯 $pointsNum PNP from Activity'
            : 'Activity Points Earned';
      case 'points_adjusted':
        return '📊 Points Balance Adjusted';
      default:
        return 'Points Update';
    }
  }

  /// Get notification body for point notifications
  /// Professional, clear, and user-friendly messages with balance information
  String _getPointNotificationBody(String type, String points,
      String currentBalance, Map<String, dynamic> data) {
    final pointsNum = int.tryParse(points) ?? 0;
    final balanceNum = int.tryParse(currentBalance) ?? 0;
    final formattedBalance = balanceNum.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');

    switch (type) {
      case 'points_earned':
        return pointsNum > 0
            ? 'Great news! You\'ve earned $pointsNum PNP. Your current balance is $formattedBalance PNP.'
            : 'Your points balance has been updated.';
      case 'points_approved':
        return pointsNum > 0
            ? 'Your $pointsNum PNP transaction has been approved and added to your account. Current balance: $formattedBalance PNP.'
            : 'Your points request has been approved.';
      case 'points_redeemed':
        return pointsNum > 0
            ? 'Your exchange request for $pointsNum PNP has been submitted and is pending review. Your balance: $formattedBalance PNP.'
            : 'Your exchange request has been submitted and is pending review.';
      case 'exchange_approved':
        return 'Your exchange request has been approved and is being processed. You will receive your reward shortly.';
      case 'exchange_rejected':
        final reason = data['reason'] ?? '';
        if (pointsNum > 0) {
          if (reason.isNotEmpty) {
            return 'Your exchange request was not approved. Reason: $reason. Your $pointsNum PNP have been refunded to your account.';
          }
          return 'Your exchange request was not approved. Your $pointsNum PNP have been refunded. Current balance: $formattedBalance PNP.';
        }
        // No points in payload -> balance unchanged, avoid saying "refunded"
        if (reason.isNotEmpty) {
          return 'Your exchange request was not approved. Reason: $reason. Your PNP balance remains unchanged.';
        }
        return 'Your exchange request was not approved. Your PNP balance remains unchanged. Current balance: $formattedBalance PNP.';
      case 'engagement_points':
        final itemTitle = data['itemTitle'] ?? data['item_title'] ?? '';
        final activityName = itemTitle.isNotEmpty ? itemTitle : 'this activity';
        return pointsNum > 0
            ? 'Thank you for your participation! You earned $pointsNum PNP from $activityName. Your balance is now $formattedBalance PNP.'
            : 'You earned points from an engagement activity. Check your balance for details.';
      case 'points_adjusted':
        final isPositive = _parseBool(data['isPositive']) ??
            _parseBool(data['is_positive']) ??
            true;
        final adjustType = isPositive ? 'increased' : 'decreased';
        final adjustVerb = isPositive ? 'added' : 'deducted';
        return pointsNum > 0
            ? 'Your points balance has been $adjustType. $pointsNum PNP has been $adjustVerb. Your current balance is $formattedBalance PNP.'
            : 'Your points balance has been adjusted. Current balance: $formattedBalance PNP.';
      default:
        return 'Your points balance has been updated. Current balance: $formattedBalance PNP.';
    }
  }

  /// Parse a loosely-typed boolean coming from FCM data payload.
  /// Supports: true/false, 1/0, "1"/"0", "true"/"false", "yes"/"no".
  bool? _parseBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) return value != 0;

    final str = value.toString().trim().toLowerCase();
    if (str.isEmpty) return null;
    if (str == '1' || str == 'true' || str == 'yes' || str == 'y') return true;
    if (str == '0' || str == 'false' || str == 'no' || str == 'n') return false;
    return null;
  }

  /// Manually upload FCM token (useful when user logs in)
  Future<void> refreshToken() async {
    await _getFCMToken();
  }

  /// Subscribe to topics (optional)
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _firebaseMessaging.subscribeToTopic(topic);
      Logger.info('Subscribed to topic: $topic', tag: 'PushNotification');
    } catch (e) {
      Logger.error('Failed to subscribe to topic: $e',
          tag: 'PushNotification', error: e);
    }
  }

  /// Unsubscribe from topics
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _firebaseMessaging.unsubscribeFromTopic(topic);
      Logger.info('Unsubscribed from topic: $topic', tag: 'PushNotification');
    } catch (e) {
      Logger.error('Failed to unsubscribe from topic: $e',
          tag: 'PushNotification', error: e);
    }
  }

  /// Get backend URL from configuration
  String? _getBackendUrl() {
    try {
      final url = AppConfig.backendUrl;
      if (url.isEmpty) return null;

      // Allow localhost only for debug builds to ease development
      if (url.startsWith('http://localhost') ||
          url.startsWith('http://127.0.0.1')) {
        assert(() {
          Logger.info('Using localhost backend URL in debug mode: $url',
              tag: 'PushNotification');
          return true;
        }());
        // In release, still treat localhost as not configured
        return bool.fromEnvironment('dart.vm.product') ? null : url;
      }

      return url;
    } catch (e) {
      Logger.warning('Error getting backend URL: $e', tag: 'PushNotification');
      return null;
    }
  }
}
