import 'package:flutter/foundation.dart';
import '../models/in_app_notification.dart';
import '../services/in_app_notification_service.dart';
import '../utils/logger.dart';

/// In-app notification provider
/// Manages notification state and UI updates
class InAppNotificationProvider with ChangeNotifier {
  // Singleton instance for global access
  static InAppNotificationProvider? _instance;
  static InAppNotificationProvider get instance {
    _instance ??= InAppNotificationProvider._internal();
    return _instance!;
  }
  
  InAppNotificationProvider._internal();
  
  // Factory constructor for Provider
  factory InAppNotificationProvider() => instance;

  final InAppNotificationService _notificationService =
      InAppNotificationService();

  List<InAppNotification> _notifications = [];
  bool _isLoading = false;
  int _unreadCount = 0;

  // Getters
  List<InAppNotification> get notifications => List.unmodifiable(_notifications);
  bool get isLoading => _isLoading;
  int get unreadCount => _unreadCount;
  bool get hasUnread => _unreadCount > 0;
  List<InAppNotification> get unreadNotifications =>
      _notifications.where((n) => !n.isRead).toList();
  List<InAppNotification> get readNotifications =>
      _notifications.where((n) => n.isRead).toList();

  /// Initialize provider and load notifications
  Future<void> initialize() async {
    await loadNotifications();
  }

  /// Load notifications from storage
  Future<void> loadNotifications() async {
    // Prevent duplicate loads
    if (_isLoading) {
      Logger.info('Already loading notifications, skipping duplicate load',
          tag: 'InAppNotificationProvider');
      return;
    }
    
    _setLoading(true);

    try {
      final notifications = await _notificationService.getNotifications();
      final unreadCount = await _notificationService.getUnreadCount();

      _notifications = notifications;
      _unreadCount = unreadCount;
      
      // Notify listeners immediately
      notifyListeners();

      Logger.info('Loaded ${notifications.length} notifications ($unreadCount unread)',
          tag: 'InAppNotificationProvider');
    } catch (e, stackTrace) {
      Logger.error('Error loading notifications: $e',
          tag: 'InAppNotificationProvider', error: e, stackTrace: stackTrace);
    } finally {
      _setLoading(false);
      // Notify again after loading completes to ensure UI is updated
      notifyListeners();
    }
  }

  /// Add notification
  Future<void> addNotification(InAppNotification notification) async {
    try {
      await _notificationService.saveNotification(notification);
      
      // Update local state immediately for real-time UI update
      _notifications.insert(0, notification);
      if (!notification.isRead) {
        _unreadCount++;
      }
      notifyListeners();
      
      // Reload to ensure consistency
      await loadNotifications();
      Logger.info('Notification added: ${notification.id}',
          tag: 'InAppNotificationProvider');
    } catch (e, stackTrace) {
      Logger.error('Error adding notification: $e',
          tag: 'InAppNotificationProvider', error: e, stackTrace: stackTrace);
    }
  }

  /// Mark notification as read
  Future<void> markAsRead(String notificationId) async {
    try {
      await _notificationService.markAsRead(notificationId);
      await loadNotifications(); // Reload to update UI
      Logger.info('Notification marked as read: $notificationId',
          tag: 'InAppNotificationProvider');
    } catch (e, stackTrace) {
      Logger.error('Error marking notification as read: $e',
          tag: 'InAppNotificationProvider', error: e, stackTrace: stackTrace);
    }
  }

  /// Mark all notifications as read
  Future<void> markAllAsRead() async {
    try {
      await _notificationService.markAllAsRead();
      await loadNotifications(); // Reload to update UI
      Logger.info('All notifications marked as read',
          tag: 'InAppNotificationProvider');
    } catch (e, stackTrace) {
      Logger.error('Error marking all notifications as read: $e',
          tag: 'InAppNotificationProvider', error: e, stackTrace: stackTrace);
    }
  }

  /// Delete notification
  Future<void> deleteNotification(String notificationId) async {
    try {
      await _notificationService.deleteNotification(notificationId);
      await loadNotifications(); // Reload to update UI
      Logger.info('Notification deleted: $notificationId',
          tag: 'InAppNotificationProvider');
    } catch (e, stackTrace) {
      Logger.error('Error deleting notification: $e',
          tag: 'InAppNotificationProvider', error: e, stackTrace: stackTrace);
    }
  }

  /// Delete all notifications
  Future<void> deleteAllNotifications() async {
    try {
      await _notificationService.deleteAllNotifications();
      await loadNotifications(); // Reload to update UI
      Logger.info('All notifications deleted',
          tag: 'InAppNotificationProvider');
    } catch (e, stackTrace) {
      Logger.error('Error deleting all notifications: $e',
          tag: 'InAppNotificationProvider', error: e, stackTrace: stackTrace);
    }
  }

  /// Create order notification
  Future<void> createOrderNotification({
    required String orderId,
    required String status,
    required String total,
    String? currency,
  }) async {
    await _notificationService.createOrderNotification(
      orderId: orderId,
      status: status,
      total: total,
      currency: currency,
    );
    
    // Reload notifications to update UI immediately
    await loadNotifications();
    
    Logger.info('Order notification created: $orderId',
        tag: 'InAppNotificationProvider');
  }

  /// Create promotion notification
  Future<void> createPromotionNotification({
    required String title,
    required String body,
    String? imageUrl,
    String? actionUrl,
  }) async {
    await _notificationService.createPromotionNotification(
      title: title,
      body: body,
      imageUrl: imageUrl,
      actionUrl: actionUrl,
    );
    await loadNotifications();
  }

  /// Create shipping notification
  Future<void> createShippingNotification({
    required String orderId,
    required String trackingNumber,
    String? carrier,
  }) async {
    await _notificationService.createShippingNotification(
      orderId: orderId,
      trackingNumber: trackingNumber,
      carrier: carrier,
    );
    await loadNotifications();
  }

  /// Refresh notifications
  Future<void> refresh() async {
    await loadNotifications();
  }

  /// Private helper methods
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }
}

