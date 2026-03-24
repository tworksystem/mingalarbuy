import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import '../utils/logger.dart';
import 'web_notification_impl.dart' if (dart.library.io) 'web_notification_stub.dart';

/// Service for handling local notifications
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  bool _isWeb = false;
  
  /// Check if service is initialized
  bool get isInitialized => _isInitialized;

  /// Initialize notification service
  Future<void> initialize() async {
    if (_isInitialized) {
      Logger.info('Notification service already initialized',
          tag: 'NotificationService');
      return;
    }

    // Check if running on web
    _isWeb = kIsWeb;

    try {
      if (_isWeb) {
        // Web platform - use Web Notifications API
        Logger.info('Initializing notification service for web platform',
            tag: 'NotificationService');
        _isInitialized = true;
        
        // Request web notification permissions
        await requestPermissions();
      } else {
        // Mobile platforms - use flutter_local_notifications
        // Android initialization settings
        const AndroidInitializationSettings androidSettings =
            AndroidInitializationSettings('@mipmap/ic_launcher');

        // iOS initialization settings
        const DarwinInitializationSettings iosSettings =
            DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

        // Initialize plugin
        const InitializationSettings initSettings = InitializationSettings(
          android: androidSettings,
          iOS: iosSettings,
        );

        final bool? initialized = await _flutterLocalNotificationsPlugin.initialize(
          initSettings,
          onDidReceiveNotificationResponse: _onNotificationTapped,
        );

        if (initialized == true) {
          _isInitialized = true;
          Logger.info('Notification service initialized successfully',
              tag: 'NotificationService');

          // Request permissions
          await requestPermissions();
        } else {
          Logger.error('Failed to initialize notification service',
              tag: 'NotificationService');
        }
      }
    } catch (e, stackTrace) {
      Logger.error(
          'Error initializing notification service: $e',
          tag: 'NotificationService',
          error: e,
          stackTrace: stackTrace);
    }
  }

  /// Request notification permissions
  Future<bool> requestPermissions() async {
    try {
      if (_isWeb) {
        // Web platform - request notification permission
        try {
          if (!WebNotificationImpl.isSupported()) {
            Logger.warning('Web Notifications API not supported in this browser',
                tag: 'NotificationService');
            return false;
          }

          // Check current permission status
          final currentPermission = WebNotificationImpl.getPermission();
          
          if (currentPermission == 'granted') {
            Logger.info('Web notification permission already granted',
                tag: 'NotificationService');
            return true;
          } else if (currentPermission == 'prompt' || currentPermission == 'default') {
            // Request permission
            final permission = await WebNotificationImpl.requestPermission();
            final granted = permission == 'granted';
            Logger.info('Web notification permission: $granted',
                tag: 'NotificationService');
            return granted;
          } else {
            Logger.warning('Web notification permission denied',
                tag: 'NotificationService');
            return false;
          }
        } catch (e, stackTrace) {
          Logger.error(
              'Error requesting web notification permission: $e',
              tag: 'NotificationService',
              error: e,
              stackTrace: stackTrace);
          return false;
        }
      } else if (Platform.isAndroid) {
        // Android 13+ requires runtime permission
        final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
            _flutterLocalNotificationsPlugin
                .resolvePlatformSpecificImplementation<
                    AndroidFlutterLocalNotificationsPlugin>();

        if (androidImplementation != null) {
          // Check if permission is already granted
          final bool? granted = await androidImplementation.areNotificationsEnabled();
          Logger.info(
              'Android notification permission status: ${granted ?? false}',
              tag: 'NotificationService');
          
          // If not granted on Android 13+, request it
          if (granted == false) {
            Logger.info('Requesting Android notification permission',
                tag: 'NotificationService');
            try {
              // Request permission for Android 13+
              final bool? result = await androidImplementation.requestNotificationsPermission();
              Logger.info('Android notification permission result: ${result ?? false}',
                  tag: 'NotificationService');
              return result ?? false;
            } catch (e) {
              Logger.error('Error requesting Android notification permission: $e',
                  tag: 'NotificationService', error: e);
              // For Android < 13, notifications are enabled by default
              return true;
            }
          }
          
          return granted ?? true; // Default to true if cannot determine
        }
      } else if (Platform.isIOS) {
        // iOS permissions are requested during initialization
        // Permissions are handled automatically via DarwinInitializationSettings
        Logger.info('iOS notification permissions requested during initialization',
            tag: 'NotificationService');
        return true; // Assume granted if initialized successfully
      }
      return true;
    } catch (e, stackTrace) {
      Logger.error(
          'Error requesting notification permissions: $e',
          tag: 'NotificationService',
          error: e,
          stackTrace: stackTrace);
      return false;
    }
  }

  /// Show order status update notification
  Future<void> showOrderStatusUpdate({
    required String orderId,
    required String oldStatus,
    required String newStatus,
    String? orderTitle,
  }) async {
    if (!_isInitialized) {
      Logger.warning(
          'Notification service not initialized, skipping notification',
          tag: 'NotificationService');
      return;
    }

    try {
      // Format order ID for display (remove WC- prefix if exists)
      final displayOrderId = orderId.replaceAll('WC-', '');

      // Format status for display
      final displayNewStatus = _formatStatus(newStatus);
      final displayOldStatus = _formatStatus(oldStatus);

      // Create notification details
      final String title = orderTitle ?? 'Order Status Updated';
      final String body =
          'Order #$displayOrderId status changed from $displayOldStatus to $displayNewStatus';

      if (_isWeb) {
        // Web platform - use Web Notifications API
        _showWebNotification(
          title: title,
          body: body,
          tag: 'order_$orderId',
        );
      } else {
        // Mobile platforms - use flutter_local_notifications
        // Android notification details
        const AndroidNotificationDetails androidDetails =
            AndroidNotificationDetails(
          'order_updates',
          'Order Updates',
          channelDescription: 'Notifications for order status updates',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          enableVibration: true,
          playSound: true,
          styleInformation: BigTextStyleInformation(''),
        );

        // iOS notification details
        const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        );

        // Notification details
        const NotificationDetails notificationDetails = NotificationDetails(
          android: androidDetails,
          iOS: iosDetails,
        );

        // Generate unique notification ID from order ID
        final notificationId = _generateNotificationId(orderId);

        // Show notification
        await _flutterLocalNotificationsPlugin.show(
          notificationId,
          title,
          body,
          notificationDetails,
          payload: 'order_$orderId', // Pass order ID as payload for navigation
        );
      }

      Logger.info(
          'Order status update notification shown: Order #$displayOrderId - $displayOldStatus -> $displayNewStatus',
          tag: 'NotificationService');
    } catch (e, stackTrace) {
      Logger.error(
          'Error showing order status update notification: $e',
          tag: 'NotificationService',
          error: e,
          stackTrace: stackTrace);
    }
  }

  /// Show new order notification
  Future<void> showNewOrderNotification({
    required String orderId,
    required String total,
    String? orderTitle,
  }) async {
    if (!_isInitialized) {
      Logger.warning(
          'Notification service not initialized, skipping notification',
          tag: 'NotificationService');
      return;
    }

    try {
      // Format order ID for display
      final displayOrderId = orderId.replaceAll('WC-', '');

      // Create notification details
      final String title = orderTitle ?? 'New Order Received';
      final String body = 'Your order #$displayOrderId for $total has been confirmed';

      if (_isWeb) {
        // Web platform - use Web Notifications API
        _showWebNotification(
          title: title,
          body: body,
          tag: 'order_$orderId',
        );
      } else {
        // Mobile platforms - use flutter_local_notifications
        // Android notification details
        const AndroidNotificationDetails androidDetails =
            AndroidNotificationDetails(
          'new_orders',
          'New Orders',
          channelDescription: 'Notifications for new orders',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          enableVibration: true,
          playSound: true,
        );

        // iOS notification details
        const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        );

        // Notification details
        const NotificationDetails notificationDetails = NotificationDetails(
          android: androidDetails,
          iOS: iosDetails,
        );

        // Generate unique notification ID from order ID
        final notificationId = _generateNotificationId(orderId);

        // Show notification
        await _flutterLocalNotificationsPlugin.show(
          notificationId,
          title,
          body,
          notificationDetails,
          payload: 'order_$orderId',
        );
      }

      Logger.info(
          'New order notification shown: Order #$displayOrderId',
          tag: 'NotificationService');
    } catch (e, stackTrace) {
      Logger.error(
          'Error showing new order notification: $e',
          tag: 'NotificationService',
          error: e,
          stackTrace: stackTrace);
    }
  }

  /// Show web notification using Web Notifications API
  void _showWebNotification({
    required String title,
    required String body,
    required String tag,
  }) {
    try {
      if (!kIsWeb) return;

      // Check if notifications are supported
      if (!WebNotificationImpl.isSupported()) {
        Logger.warning('Web Notifications API not supported in this browser',
            tag: 'NotificationService');
        return;
      }

      // Check permission
      final permission = WebNotificationImpl.getPermission();
      
      if (permission == 'granted') {
        // Show notification
        final notification = WebNotificationImpl.showNotification(
          title: title,
          body: body,
          tag: tag,
        );

        if (notification != null) {
          Logger.info('Web notification shown: $title',
              tag: 'NotificationService');
        }
      } else if (permission == 'default' || permission == 'prompt') {
        // Request permission first
        Logger.info('Requesting web notification permission',
            tag: 'NotificationService');
        WebNotificationImpl.requestPermission().then((result) {
          if (result == 'granted') {
            // Retry showing notification
            _showWebNotification(title: title, body: body, tag: tag);
          } else {
            Logger.warning('Web notification permission denied',
                tag: 'NotificationService');
          }
        });
      } else {
        Logger.warning('Web notification permission denied',
            tag: 'NotificationService');
      }
    } catch (e, stackTrace) {
      Logger.error(
          'Error showing web notification: $e',
          tag: 'NotificationService',
          error: e,
          stackTrace: stackTrace);
    }
  }

  /// Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    Logger.info(
        'Notification tapped: ${response.payload}',
        tag: 'NotificationService');

    // Handle navigation based on payload
    if (response.payload != null && response.payload!.startsWith('order_')) {
      final orderId = response.payload!.substring(6); // Remove 'order_' prefix
      // Navigation will be handled by the app's notification handler
      Logger.info('Order notification tapped: $orderId',
          tag: 'NotificationService');
    }
  }

  /// Format status text for display
  String _formatStatus(String status) {
    return status
        .split('-')
        .map((word) => word.isEmpty
            ? ''
            : word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  /// Generate notification ID from order ID
  int _generateNotificationId(String orderId) {
    // Use order ID hash to generate consistent notification ID
    return orderId.hashCode.abs() % 2147483647; // Max int value
  }

  /// Cancel notification by ID
  Future<void> cancelNotification(int notificationId) async {
    try {
      await _flutterLocalNotificationsPlugin.cancel(notificationId);
      Logger.info('Notification cancelled: $notificationId',
          tag: 'NotificationService');
    } catch (e) {
      Logger.error('Error cancelling notification: $e',
          tag: 'NotificationService', error: e);
    }
  }

  /// Cancel all notifications
  Future<void> cancelAllNotifications() async {
    try {
      await _flutterLocalNotificationsPlugin.cancelAll();
      Logger.info('All notifications cancelled', tag: 'NotificationService');
    } catch (e) {
      Logger.error('Error cancelling all notifications: $e',
          tag: 'NotificationService', error: e);
    }
  }

  /// Check if notifications are enabled
  Future<bool> areNotificationsEnabled() async {
    if (!_isInitialized) {
      return false;
    }

    try {
      if (_isWeb) {
        // Web platform - check notification permission
        if (WebNotificationImpl.isSupported()) {
          return WebNotificationImpl.getPermission() == 'granted';
        }
        return false;
      } else if (Platform.isAndroid) {
        final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
            _flutterLocalNotificationsPlugin
                .resolvePlatformSpecificImplementation<
                    AndroidFlutterLocalNotificationsPlugin>();

        if (androidImplementation != null) {
          final bool? enabled = await androidImplementation.areNotificationsEnabled();
          return enabled ?? true; // Default to true if cannot determine
        }
      }
      // iOS doesn't have a way to check permission status via plugin
      // Assume enabled if initialized
      return _isInitialized;
    } catch (e) {
      Logger.error('Error checking notification status: $e',
          tag: 'NotificationService', error: e);
      return false;
    }
  }
}

