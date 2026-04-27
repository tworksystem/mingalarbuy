import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/in_app_notification.dart';
import '../utils/logger.dart';

/// Professional in-app notification service
/// Manages notification storage, retrieval, and persistence
class InAppNotificationService {
  static final InAppNotificationService _instance =
      InAppNotificationService._internal();
  factory InAppNotificationService() => _instance;
  InAppNotificationService._internal();

  static const String _notificationsKey = 'in_app_notifications';
  static const int _maxNotifications = 100; // Limit stored notifications

  /// Normalize notification timestamp for stable sorting.
  /// If date is missing/invalid, return epoch so it goes to the bottom in DESC order.
  DateTime _safeNotificationDate(InAppNotification notification) {
    try {
      final date = notification.createdAt;
      // Treat epoch-like values as "missing" (already used by model fallback).
      if (date.millisecondsSinceEpoch <= 0) {
        return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      }
      return date.toUtc();
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }
  }

  /// Canonical ordering: latest first (DESC by createdAt).
  /// Tie-breaker: id DESC for deterministic order.
  List<InAppNotification> _sortNotificationsLatestFirst(
      List<InAppNotification> notifications) {
    notifications.sort((a, b) {
      final aDate = _safeNotificationDate(a);
      final bDate = _safeNotificationDate(b);

      // DESC order: latest at top.
      final byDate = bDate.compareTo(aDate);
      if (byDate != 0) return byDate;

      // Deterministic fallback to prevent flicker when timestamps are equal/missing.
      return b.id.compareTo(a.id);
    });
    return notifications;
  }

  String _sanitizeKey(String value) {
    return value.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
  }

  String _canonicalPointNotificationKey({
    required String type,
    String? transactionId,
    String? requestId,
    Map<String, dynamic>? additionalData,
  }) {
    // Prefer immutable backend identifiers first.
    if (transactionId != null && transactionId.trim().isNotEmpty) {
      return 'txn_${type}_${transactionId.trim()}';
    }
    if (requestId != null && requestId.trim().isNotEmpty) {
      return 'req_${type}_${requestId.trim()}';
    }

    final pollId = (additionalData?['pollId'] ??
            additionalData?['poll_id'] ??
            additionalData?['itemId'] ??
            additionalData?['item_id'])
        ?.toString();
    final sessionId =
        (additionalData?['sessionId'] ?? additionalData?['session_id'])
            ?.toString();
    final itemType =
        (additionalData?['itemType'] ?? additionalData?['item_type'])
            ?.toString()
            .toLowerCase();
    if (type == 'engagement_points' &&
        itemType == 'poll' &&
        pollId != null &&
        pollId.isNotEmpty &&
        sessionId != null &&
        sessionId.isNotEmpty) {
      return 'poll_${type}_${pollId}_$sessionId';
    }

    // Last fallback: content-stable key (without wall-clock timestamp).
    final points = (additionalData?['points'] ?? '').toString();
    final currentBalance = (additionalData?['currentBalance'] ??
            additionalData?['current_balance'] ??
            '')
        .toString();
    return 'fallback_${type}_${points}_$currentBalance';
  }

  /// Save notification to storage
  Future<void> saveNotification(InAppNotification notification) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final notifications = await getNotifications();

      // OLD CODE:
      // Add new notification at the beginning
      // notifications.insert(0, notification);
      //
      // New Code:
      // Add first, then apply canonical latest-first sort.
      notifications.insert(0, notification);
      _sortNotificationsLatestFirst(notifications);

      // Limit to max notifications
      if (notifications.length > _maxNotifications) {
        notifications.removeRange(_maxNotifications, notifications.length);
      }

      // Save to storage
      final notificationsJson = json.encode(
        notifications.map((n) => n.toJson()).toList(),
      );
      await prefs.setString(_notificationsKey, notificationsJson);

      Logger.info('Notification saved: ${notification.id}',
          tag: 'InAppNotification');
    } catch (e, stackTrace) {
      Logger.error('Error saving notification: $e',
          tag: 'InAppNotification', error: e, stackTrace: stackTrace);
    }
  }

  /// Get all notifications
  Future<List<InAppNotification>> getNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final notificationsJson = prefs.getString(_notificationsKey);

      if (notificationsJson != null) {
        final List<dynamic> notificationsData = json.decode(notificationsJson);
        // OLD CODE:
        // return notificationsData
        //     .map((json) => InAppNotification.fromJson(json as Map<String, dynamic>))
        //     .toList();
        //
        // New Code:
        // Canonical sort at data layer so all UIs receive consistent latest-first order.
        final notifications = notificationsData
            .map((json) =>
                InAppNotification.fromJson(json as Map<String, dynamic>))
            .toList();
        return _sortNotificationsLatestFirst(notifications);
      }

      return [];
    } catch (e, stackTrace) {
      Logger.error('Error getting notifications: $e',
          tag: 'InAppNotification', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  /// Get unread notifications count
  Future<int> getUnreadCount() async {
    try {
      final notifications = await getNotifications();
      return notifications.where((n) => !n.isRead).length;
    } catch (e) {
      Logger.error('Error getting unread count: $e',
          tag: 'InAppNotification', error: e);
      return 0;
    }
  }

  /// Mark notification as read
  Future<void> markAsRead(String notificationId) async {
    try {
      final notifications = await getNotifications();
      final index = notifications.indexWhere((n) => n.id == notificationId);

      if (index != -1) {
        notifications[index] = notifications[index].copyWith(isRead: true);
        await _saveNotifications(notifications);
        Logger.info('Notification marked as read: $notificationId',
            tag: 'InAppNotification');
      }
    } catch (e, stackTrace) {
      Logger.error('Error marking notification as read: $e',
          tag: 'InAppNotification', error: e, stackTrace: stackTrace);
    }
  }

  /// Mark all notifications as read
  Future<void> markAllAsRead() async {
    try {
      final notifications = await getNotifications();
      final updatedNotifications = notifications
          .map((n) => n.copyWith(isRead: true))
          .toList();
      await _saveNotifications(updatedNotifications);
      Logger.info('All notifications marked as read',
          tag: 'InAppNotification');
    } catch (e, stackTrace) {
      Logger.error('Error marking all notifications as read: $e',
          tag: 'InAppNotification', error: e, stackTrace: stackTrace);
    }
  }

  /// Delete notification
  Future<void> deleteNotification(String notificationId) async {
    try {
      final notifications = await getNotifications();
      notifications.removeWhere((n) => n.id == notificationId);
      await _saveNotifications(notifications);
      Logger.info('Notification deleted: $notificationId',
          tag: 'InAppNotification');
    } catch (e, stackTrace) {
      Logger.error('Error deleting notification: $e',
          tag: 'InAppNotification', error: e, stackTrace: stackTrace);
    }
  }

  /// Delete all notifications
  Future<void> deleteAllNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_notificationsKey);
      Logger.info('All notifications deleted', tag: 'InAppNotification');
    } catch (e, stackTrace) {
      Logger.error('Error deleting all notifications: $e',
          tag: 'InAppNotification', error: e, stackTrace: stackTrace);
    }
  }

  /// Create notification from order update
  /// Returns true if notification was created, false if duplicate was found
  Future<bool> createOrderNotification({
    required String orderId,
    required String status,
    required String total,
    String? currency,
  }) async {
    // Check for duplicate notifications (same order ID and status within last 5 minutes)
    final existingNotifications = await getNotifications();
    final now = DateTime.now();
    final fiveMinutesAgo = now.subtract(Duration(minutes: 5));
    
    final duplicateExists = existingNotifications.any((n) {
      if (n.type != NotificationType.order) return false;
      final nOrderId = n.data?['orderId']?.toString();
      final nStatus = n.data?['status']?.toString();
      
      // Check if same order ID and status, and created within last 5 minutes
      return nOrderId == orderId.toString() &&
             nStatus == status.toString() &&
             n.createdAt.isAfter(fiveMinutesAgo);
    });
    
    if (duplicateExists) {
      Logger.info('Duplicate notification prevented for order: $orderId, status: $status',
          tag: 'InAppNotificationService');
      return false;
    }
    
    // Normalize currency to Kyats (Ks). If backend sends a different symbol,
    // we still present it as Ks to match the local UX.
    final displayCurrency = 'Ks';

    final notification = InAppNotification(
      id: 'order_${orderId}_${DateTime.now().millisecondsSinceEpoch}',
      title: 'Order #$orderId $status',
      body: 'Your order total is $displayCurrency $total',
      type: NotificationType.order,
      createdAt: DateTime.now(),
      isRead: false, // New notifications are unread
      data: {
        'orderId': orderId,
        'status': status,
        'total': total,
        'currency': displayCurrency,
      },
      actionUrl: '/order/$orderId',
    );

    await saveNotification(notification);
    
    Logger.info('Order notification created and saved: $orderId',
        tag: 'InAppNotificationService');
    return true;
  }

  /// Create promotion notification
  Future<void> createPromotionNotification({
    required String title,
    required String body,
    String? imageUrl,
    String? actionUrl,
  }) async {
    final notification = InAppNotification(
      id: 'promo_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      body: body,
      type: NotificationType.promotion,
      createdAt: DateTime.now(),
      imageUrl: imageUrl,
      actionUrl: actionUrl,
    );

    await saveNotification(notification);
  }

  /// Create shipping notification
  Future<void> createShippingNotification({
    required String orderId,
    required String trackingNumber,
    String? carrier,
  }) async {
    final notification = InAppNotification(
      id: 'shipping_${orderId}_${DateTime.now().millisecondsSinceEpoch}',
      title: 'Order #$orderId Shipped',
      body: carrier != null
          ? 'Your order has been shipped via $carrier. Tracking: $trackingNumber'
          : 'Your order has been shipped. Tracking: $trackingNumber',
      type: NotificationType.shipping,
      createdAt: DateTime.now(),
      data: {
        'orderId': orderId,
        'trackingNumber': trackingNumber,
        'carrier': carrier,
      },
      actionUrl: '/order/$orderId',
    );

    await saveNotification(notification);
  }

  /// Create point notification
  /// Returns true if notification was created, false if duplicate was found
  Future<bool> createPointNotification({
    required String type,
    required String title,
    required String body,
    String? transactionId,
    String? requestId,
    String? points,
    String? currentBalance,
    Map<String, dynamic>? additionalData,
    /// When set (e.g. transaction time or FCM `created_at`), avoids "Just now" for old events.
    DateTime? eventOccurredAt,
  }) async {
    // OLD CODE:
    // Check for duplicate notifications (same type and transaction/request ID within last 5 minutes)
    // final existingNotifications = await getNotifications();
    // final now = DateTime.now();
    // final fiveMinutesAgo = now.subtract(Duration(minutes: 5));
    // final duplicateExists = existingNotifications.any((n) { ... });
    // if (duplicateExists) { return false; }

    // New Code:
    // Use canonical idempotency key and UPSERT semantics to preserve read/unread state.
    final existingNotifications = await getNotifications();
    
    // Build notification data
    final canonicalKey = _canonicalPointNotificationKey(
      type: type,
      transactionId: transactionId,
      requestId: requestId,
      additionalData: additionalData,
    );
    final notificationData = <String, dynamic>{
      'notificationType': type,
      'canonicalKey': canonicalKey,
      if (transactionId != null) 'transactionId': transactionId,
      if (requestId != null) 'requestId': requestId,
      if (points != null) 'points': points,
      if (currentBalance != null) 'currentBalance': currentBalance,
      if (additionalData != null) ...additionalData,
    };
    
    // Determine action URL based on notification type
    String? actionUrl;
    switch (type) {
      case 'points_earned':
      case 'points_approved':
      case 'points_redeemed':
      case 'points_adjusted':
      case 'engagement_points':
        actionUrl = '/points/history';
        break;
      case 'exchange_approved':
      case 'exchange_rejected':
        actionUrl = '/points/exchange'; // Navigate to exchange history if available
        break;
      default:
        actionUrl = '/points/history'; // Default to point history
    }
    
    final createdAt = eventOccurredAt ?? DateTime.now();

    final existingIndex = existingNotifications.indexWhere((n) {
      if (n.type != NotificationType.points) return false;
      final nCanonical = n.data?['canonicalKey']?.toString();
      if (nCanonical != null && nCanonical.isNotEmpty) {
        return nCanonical == canonicalKey;
      }
      final nType = n.data?['notificationType']?.toString();
      final nTxn = n.data?['transactionId']?.toString();
      final nReq = n.data?['requestId']?.toString();
      if (nType != type) return false;
      if (transactionId != null && transactionId.isNotEmpty) return nTxn == transactionId;
      if (requestId != null && requestId.isNotEmpty) return nReq == requestId;
      return false;
    });

    if (existingIndex != -1) {
      // Keep read state from existing row (critical for app restart consistency).
      final existing = existingNotifications[existingIndex];
      existingNotifications[existingIndex] = existing.copyWith(
        title: title,
        body: body,
        createdAt: createdAt,
        data: notificationData,
        actionUrl: actionUrl,
        isRead: existing.isRead,
      );
      await _saveNotifications(existingNotifications);
      Logger.info(
          'Point notification upserted (existing row preserved): key=$canonicalKey',
          tag: 'InAppNotificationService');
      return false;
    }

    final notification = InAppNotification(
      id: 'points_${_sanitizeKey(canonicalKey)}',
      title: title,
      body: body,
      type: NotificationType.points,
      createdAt: createdAt,
      isRead: false,
      data: notificationData,
      actionUrl: actionUrl,
    );

    await saveNotification(notification);

    Logger.info(
        'Point notification created and saved: key=$canonicalKey, type=$type, transactionId=$transactionId, requestId=$requestId',
        tag: 'InAppNotificationService');
    return true;
  }

  /// Save notifications to storage
  Future<void> _saveNotifications(List<InAppNotification> notifications) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Ensure storage also remains in canonical latest-first order.
      _sortNotificationsLatestFirst(notifications);
      final notificationsJson = json.encode(
        notifications.map((n) => n.toJson()).toList(),
      );
      await prefs.setString(_notificationsKey, notificationsJson);
    } catch (e, stackTrace) {
      Logger.error('Error saving notifications: $e',
          tag: 'InAppNotification', error: e, stackTrace: stackTrace);
    }
  }
}

