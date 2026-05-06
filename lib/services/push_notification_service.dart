import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api_service.dart';
import '../utils/logger.dart';
import '../utils/app_config.dart';
import 'in_app_notification_service.dart';
import '../providers/in_app_notification_provider.dart';
import '../models/in_app_notification.dart';
import '../providers/point_provider.dart';
import '../providers/auth_provider.dart';
import 'canonical_point_balance_sync.dart';
import 'point_notification_manager.dart';
import 'missed_notification_recovery_service.dart';

/// PROFESSIONAL SECURITY: Helper function to verify notification user in background handler
/// This is a top-level function that can be called from background handler
Future<bool> _verifyNotificationUserInBackground(
    Map<String, dynamic> data) async {
  try {
    const secureStorage = FlutterSecureStorage();

    // Get userId from notification data (camelCase / snake_case / legacy lowercased keys).
    /*
    Old Code:
    final notificationUserId =
        data['userId']?.toString() ?? data['user_id']?.toString() ?? '';
    */
    final notificationUserId = _fcmDataFirstString(data, const [
      'userId',
      'user_id',
      'userid',
    ]);

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

/// SharedPreferences key: background isolate persists last points FCM snapshot for main isolate.
const String _kPendingFcmPointSnapshotKey = 'twork_fcm_pending_point_snapshot_v1';

/// Point-related FCM `type` values that carry an authoritative balance snapshot.
const Set<String> _fcmPointBalanceNotificationTypes = {
  'points_earned',
  'points_approved',
  'points_redeemed',
  'exchange_approved',
  'exchange_rejected',
  'engagement_points',
  'points_adjusted',
};

/// First non-empty string among [keys] in FCM [data] (handles int/double from native maps).
String _fcmDataFirstString(Map<String, dynamic> data, List<String> keys) {
  for (final String k in keys) {
    if (!data.containsKey(k)) {
      continue;
    }
    final Object? v = data[k];
    if (v == null) {
      continue;
    }
    final String s = v.toString().trim();
    if (s.isNotEmpty) {
      return s;
    }
  }
  return '';
}

int _fcmDataFirstInt(Map<String, dynamic> data, List<String> keys, {int fallback = 0}) {
  final String raw = _fcmDataFirstString(data, keys);
  if (raw.isEmpty) {
    return fallback;
  }
  final num? n = num.tryParse(raw);
  if (n == null) {
    return fallback;
  }
  return n.round();
}

/// Background isolate cannot update [ChangeNotifier]s — persist snapshot for main isolate drain.
Future<void> persistFcmPointSnapshotForMainIsolate(Map<String, dynamic> data) async {
  if (kIsWeb) {
    return;
  }
  try {
    final String type = _fcmDataFirstString(data, const ['type']);
    if (!_fcmPointBalanceNotificationTypes.contains(type)) {
      return;
    }
    final String uid = _fcmDataFirstString(data, const [
      'userId',
      'user_id',
      'userid',
    ]);
    if (uid.isEmpty) {
      return;
    }
    final int balance = _fcmDataFirstInt(
      data,
      const [
        'currentBalance',
        'current_balance',
        'currentbalance',
        'balance',
      ],
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kPendingFcmPointSnapshotKey,
      json.encode(<String, dynamic>{
        'userId': uid,
        'currentBalance': balance,
        'type': type,
        'savedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
      }),
    );
    Logger.info(
      'Background FCM point snapshot persisted for user=$uid balance=$balance type=$type',
      tag: 'PushNotification',
    );
  } catch (e, stackTrace) {
    Logger.error(
      'persistFcmPointSnapshotForMainIsolate failed: $e',
      tag: 'PushNotification',
      error: e,
      stackTrace: stackTrace,
    );
  }
}

/// Best-effort event time from FCM [data] for in-app [createdAt] (backend keys vary).
DateTime? _tryParseFcmDataEventTime(Map<String, dynamic> data) {
  for (final String key in <String>[
    'timestamp',
    'created_at',
    'createdAt',
    'sent_at',
    'time',
  ]) {
    final Object? v = data[key];
    if (v == null) {
      continue;
    }
    if (v is int) {
      if (v > 1000000000000) {
        return DateTime.fromMillisecondsSinceEpoch(v, isUtc: true);
      }
      if (v > 1000000000) {
        return DateTime.fromMillisecondsSinceEpoch(v * 1000, isUtc: true);
      }
    } else {
      final String s = v.toString().trim();
      if (s.isNotEmpty) {
        final DateTime? p = DateTime.tryParse(s);
        if (p != null) {
          return p;
        }
      }
    }
  }
  return null;
}

// -----------------------------------------------------------------------------
// Tray title/body + channel helpers (shared by foreground handler + BG isolate).
// Non-order payloads must NOT fall back to fake "Your order has been updated" copy.
// -----------------------------------------------------------------------------

/// Like [PushNotificationService._parseBool] — tri-state for adjustment rows.
bool? _parseTrayBoolNullable(dynamic value) {
  if (value == null) return null;
  if (value is bool) return value;
  if (value is num) return value != 0;
  final str = value.toString().trim().toLowerCase();
  if (str.isEmpty) return null;
  if (str == '0' || str == 'false' || str == 'no') return false;
  if (str == '1' || str == 'true' || str == 'yes') return true;
  return null;
}

String _trayPointTitleForType(String type, String points) {
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
      return pointsNum > 0 ? '🎯 $pointsNum PNP from Activity' : 'Activity Points Earned';
    case 'points_adjusted':
      return '📊 Points Balance Adjusted';
    default:
      return 'Points Update';
  }
}

String _trayPointBodyForType(
    String type, String points, String balance, Map<String, dynamic> data) {
  final pointsNum = int.tryParse(points) ?? 0;
  final balanceNum = int.tryParse(balance) ?? 0;
  final fb = balanceNum.toString().replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (Match m) => '${m[1]},',
  );
  switch (type) {
    case 'points_earned':
      return pointsNum > 0
          ? 'Great news! You\'ve earned $pointsNum PNP. Your current balance is $fb PNP.'
          : 'Your points balance has been updated.';
    case 'points_approved':
      return pointsNum > 0
          ? 'Your $pointsNum PNP transaction has been approved and added to your account. Current balance: $fb PNP.'
          : 'Your points request has been approved.';
    case 'points_redeemed':
      return pointsNum > 0
          ? 'Your exchange request for $pointsNum PNP has been submitted and is pending review. Your balance: $fb PNP.'
          : 'Your exchange request has been submitted and is pending review.';
    case 'exchange_approved':
      return 'Your exchange request has been approved and is being processed. You will receive your reward shortly.';
    case 'exchange_rejected':
      final reason = data['reason'] ?? '';
      if (pointsNum > 0) {
        if (reason.toString().isNotEmpty) {
          return 'Your exchange request was not approved. Reason: $reason. Your $pointsNum PNP have been refunded to your account.';
        }
        return 'Your exchange request was not approved. Your $pointsNum PNP have been refunded. Current balance: $fb PNP.';
      }
      if (reason.toString().isNotEmpty) {
        return 'Your exchange request was not approved. Reason: $reason. Your PNP balance remains unchanged.';
      }
      return 'Your exchange request was not approved. Your PNP balance remains unchanged. Current balance: $fb PNP.';
    case 'engagement_points':
      final itemTitle = _fcmDataFirstString(
        data,
        const ['itemTitle', 'item_title', 'itemtitle'],
      );
      final activityName = itemTitle.toString().isNotEmpty ? itemTitle : 'this activity';
      return pointsNum > 0
          ? 'Thank you for your participation! You earned $pointsNum PNP from $activityName. Your balance is now $fb PNP.'
          : 'You earned points from an engagement activity. Check your balance for details.';
    case 'points_adjusted':
      final isPositive = _parseTrayBoolNullable(data['isPositive']) ??
          _parseTrayBoolNullable(data['is_positive']) ??
          true;
      final adj = isPositive ? 'increased' : 'decreased';
      final vb = isPositive ? 'added' : 'deducted';
      return pointsNum > 0
          ? 'Your points balance has been $adj. $pointsNum PNP has been $vb. Your current balance is $fb PNP.'
          : 'Your points balance has been adjusted. Current balance: $fb PNP.';
    default:
      return 'Your points balance has been updated. Current balance: $fb PNP.';
  }
}

/// Public factory so Isolate / internal logic share one resolver.
///
/// Old behavior (removed): every missing title/body used **Order Update** placeholders.
///
/// New behavior: chooses channel + sane copy from [Message.data]['type']; only genuine
/// `order_status_update` rows use Order-style placeholders.
class TrayLocalSpec {
  const TrayLocalSpec({
    required this.channelId,
    required this.channelName,
    required this.channelDescription,
    required this.title,
    required this.body,
  });

  final String channelId;
  final String channelName;
  final String channelDescription;
  final String title;
  final String body;

  factory TrayLocalSpec.fromRemoteMessage(RemoteMessage message) {
    final d = Map<String, dynamic>.from(message.data);
    final nt = _fcmDataFirstString(d, const ['type', 'notification_type']);
    final orderId = _fcmDataFirstString(d, const ['orderId', 'order_id', 'orderid']);

    /*
    Old Code:

    ```
    title: message.notification?.title ?? 'Order Update',
    body: message.notification?.body ?? 'Your order has been updated',
    ```

    (Always wrong for points/engagement data-only payloads.)
    */

    // New Code:

    final notifT = message.notification?.title?.trim();
    final notifB = message.notification?.body?.trim();

    /// Points-ish set (mirror `PushNotificationService._pointNotificationTypes`).
    const trayPointKinds = {
      'points_earned',
      'points_approved',
      'points_redeemed',
      'exchange_approved',
      'exchange_rejected',
      'engagement_points',
      'points_adjusted',
    };
    /// Mirror `PushNotificationService._engagementNotificationTypes`.
    const trayEngKinds = {
      'engagement_quiz_submitted',
      'engagement_poll_submitted',
      'engagement_banner_viewed',
      'engagement_announcement_viewed',
      'engagement_number_viewed',
      'engagement_new_item',
      'engagement_item_updated',
    };

    if (trayPointKinds.contains(nt) || nt == 'reward_updated') {
      final points = _fcmDataFirstString(d, const [
        'points',
        'points_value',
        'pointsValue',
        'pointsEarned',
      ]);
      final cb = _fcmDataFirstString(d, const [
        'currentBalance',
        'current_balance',
        'currentbalance',
        'balance',
      ]);
      final t = (notifT != null && notifT.isNotEmpty)
          ? notifT
          : (nt == 'reward_updated')
              ? 'Reward update'
              : _trayPointTitleForType(nt, points);
      final bodyText = (notifB != null && notifB.isNotEmpty)
          ? notifB
          : (nt == 'reward_updated')
              ? 'Your rewards profile may have changed. Open the app to review.'
              : _trayPointBodyForType(nt, points, cb, d);

      return TrayLocalSpec(
        channelId: 'points_updates',
        channelName: 'Points Updates',
        channelDescription: 'Notifications for loyalty points and rewards updates',
        title: t,
        body: bodyText,
      );
    }

    if (trayEngKinds.contains(nt)) {
      final t =
          (notifT != null && notifT.isNotEmpty) ? notifT : 'Engagement Hub';
      final b = (notifB != null && notifB.isNotEmpty)
          ? notifB
          : 'You have a new Engagement Hub activity or update.';
      return TrayLocalSpec(
        channelId: 'engagement_updates',
        channelName: 'Engagement Hub',
        channelDescription:
            'Notifications for Engagement Hub activities and announcements',
        title: t,
        body: b,
      );
    }

    // Canonical WooCommerce order push from server plugin:
    if (nt == 'order_status_update' && orderId.isNotEmpty) {
      return TrayLocalSpec(
        channelId: 'order_updates',
        channelName: 'Order Updates',
        channelDescription: 'Notifications for order status updates',
        title:
            notifT?.isNotEmpty == true ? notifT! : 'Order update',
        body:
            notifB?.isNotEmpty == true ? notifB! : 'Your order has been updated',
      );
    }

    // Unknown / malformed type — NEVER masquerade as an order shipment:
    final tFallback =
        notifT?.isNotEmpty == true ? notifT! : 'Notification';
    final bFallback = notifB?.isNotEmpty == true
        ? notifB!
        : 'Open the app for details.';
    return TrayLocalSpec(
      channelId: 'app_general',
      channelName: 'App notifications',
      channelDescription: 'General app notifications',
      title: tFallback,
      body: bFallback,
    );
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

    await localNotifications.initialize(settings: initSettings);

    /*
    Old Code — single `order_updates` channel + **Order Update** defaults for every payload:
    const AndroidNotificationChannel channel = AndroidNotificationChannel(...);
    ...
    await localNotifications.show(... title: ... ?? 'Order Update', body: ... ?? 'Your order has been updated', ...);
    */

    // New Code — register all tray channels (Android 8+) so non-order rows never look like orders.
    final androidImpl = localNotifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    const androidChannels = [
      AndroidNotificationChannel(
        'order_updates',
        'Order Updates',
        description: 'Notifications for order status updates',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
      AndroidNotificationChannel(
        'points_updates',
        'Points Updates',
        description: 'Notifications for loyalty points and rewards updates',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
      AndroidNotificationChannel(
        'engagement_updates',
        'Engagement Hub',
        description: 'Notifications for Engagement Hub activities',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
      AndroidNotificationChannel(
        'app_general',
        'App notifications',
        description: 'General app notifications',
        importance: Importance.defaultImportance,
      ),
    ];
    for (final ch in androidChannels) {
      await androidImpl?.createNotificationChannel(ch);
    }

    final nt = _fcmDataFirstString(message.data, const ['type', 'notification_type']);
    if (nt == 'order_status_update') {
      // Notification disabled by user request (order tray notifications only).
      Logger.info(
        'Skipping background tray display for order notification',
        tag: 'PushNotification',
      );
      return;
    }

    final tray = TrayLocalSpec.fromRemoteMessage(message);

    final androidDetails = AndroidNotificationDetails(
      tray.channelId,
      tray.channelName,
      channelDescription: tray.channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await localNotifications.show(
      id: message.hashCode,
      title: tray.title,
      body: tray.body,
      notificationDetails: notificationDetails,
      payload: json.encode(message.data),
    );

    Logger.info('Background notification displayed successfully',
        tag: 'PushNotification');

    // Main isolate cannot read background isolate memory — persist balance for startup drain.
    await persistFcmPointSnapshotForMainIsolate(
      Map<String, dynamic>.from(message.data),
    );
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

  /// Holds FCM stream subscriptions so we can [disposeMessagingSubscriptions] and avoid duplicate listeners.
  final List<StreamSubscription<RemoteMessage>> _fcmMessageSubscriptions = [];
  StreamSubscription<String>? _fcmTokenRefreshSubscription;

  // Throttle expensive "hard sync" (network refresh) after point notifications.
  // We still apply the FCM `currentBalance` snapshot instantly to update UI.
  final Map<String, DateTime> _lastPointsHardSyncAtByUser = {};
  static const Duration _pointsHardSyncCooldown = Duration(seconds: 3);
  Timer? _tokenRecoveryTimer;

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

  /// Re-send FCM token to backend when a session exists (e.g. after login / cold start with stored user).
  ///
  /// // Old Code: Token upload only ran once inside [initialize] -> [_getFCMToken], often
  /// // when SecureStorage `user_data` was still null — server could not target the device.
  Future<void> syncFcmTokenToBackendForCurrentUser() async {
    if (!_isInitialized) {
      Logger.info(
        'syncFcmTokenToBackendForCurrentUser: service not initialized; skipping',
        tag: 'PushNotification',
      );
      return;
    }
    try {
      if (_fcmToken == null || _fcmToken!.isEmpty) {
        await _getFCMToken();
      } else {
        final uploaded = await _sendTokenToBackend(_fcmToken!);
        if (!uploaded) {
          _scheduleTokenRecovery(
            reason: 'post-auth reconcile upload failed',
          );
        }
      }
    } catch (e, stackTrace) {
      Logger.error(
        'syncFcmTokenToBackendForCurrentUser failed: $e',
        tag: 'PushNotification',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Cancel FCM listeners (e.g. before tests or to replace handlers). Safe to call if empty.
  void disposeMessagingSubscriptions() {
    for (final s in _fcmMessageSubscriptions) {
      s.cancel();
    }
    _fcmMessageSubscriptions.clear();
    _fcmTokenRefreshSubscription?.cancel();
    _fcmTokenRefreshSubscription = null;
    _tokenRecoveryTimer?.cancel();
    _tokenRecoveryTimer = null;
    Logger.info('FCM messaging subscriptions disposed', tag: 'PushNotification');
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
      // Get userId from notification data (camelCase / snake_case / legacy lowercased keys).
      /*
      Old Code:
      final notificationUserId =
          data['userId']?.toString() ?? data['user_id']?.toString() ?? '';
      */
      final notificationUserId = _fcmDataFirstString(data, const [
        'userId',
        'user_id',
        'userid',
      ]);

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

  /// Applies a points balance snapshot written from [firebaseMessagingBackgroundHandler]
  /// so Home "My PNP" updates immediately on cold start without manual refresh.
  Future<void> _applyPendingFcmBalanceSnapshotFromDisk() async {
    if (kIsWeb) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kPendingFcmPointSnapshotKey);
      if (raw == null || raw.isEmpty) {
        return;
      }
      await prefs.remove(_kPendingFcmPointSnapshotKey);
      final decoded = json.decode(raw);
      if (decoded is! Map<String, dynamic>) {
        return;
      }
      final String uid = decoded['userId']?.toString() ?? '';
      final int bal =
          int.tryParse(decoded['currentBalance']?.toString() ?? '') ?? 0;
      final String? current = await _getCurrentUserId();
      if (current == null || uid.isEmpty || uid != current) {
        Logger.info(
          'Pending FCM balance snapshot skipped (user mismatch or logged out) pending=$uid current=$current',
          tag: 'PushNotification',
        );
        return;
      }
      /*
      // OLD CODE:
      // AuthProvider().applyPointsBalanceSnapshot(bal);
      // PointProvider.instance.applyRemoteBalanceSnapshot(
      //   userId: uid,
      //   currentBalance: bal,
      // );
      */

      // NEW FIX: Pending FCM snapshot — full canonical sync.
      await CanonicalPointBalanceSync.apply(
        userId: uid,
        currentBalance: bal,
        source: 'push_fcm_pending_snapshot',
        emitBroadcast: false,
      );
      _schedulePointsHardSync(uid);
      Logger.info(
        'Pending FCM balance snapshot applied user=$uid balance=$bal (My PNP + reconcile)',
        tag: 'PushNotification',
      );
    } catch (e, stackTrace) {
      Logger.error(
        '_applyPendingFcmBalanceSnapshotFromDisk failed: $e',
        tag: 'PushNotification',
        error: e,
        stackTrace: stackTrace,
      );
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
        await _applyPendingFcmBalanceSnapshotFromDisk();
        // New Code: ensure backend token registration is eventually consistent
        // even when release startup races with secure-storage/session hydration.
        _scheduleTokenRecovery(reason: 'initial release reliability check');
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
        await _applyPendingFcmBalanceSnapshotFromDisk();
        _scheduleTokenRecovery(reason: 'provisional permission reliability check');
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
        final uploaded = await _sendTokenToBackend(_fcmToken!);
        if (!uploaded) {
          _scheduleTokenRecovery(reason: 'initial token upload failed');
        }
      } else {
        Logger.warning('FCM token is null', tag: 'PushNotification');
      }
    } catch (e) {
      Logger.error('Failed to get FCM token: $e',
          tag: 'PushNotification', error: e);
    }
  }

  /// Send FCM token to backend server
  // OLD CODE:
  // Future<void> _sendTokenToBackend(String token) async {
  //   try {
  //     // Get user ID from secure storage
  //     final userJson = await _secureStorage.read(key: 'user_data');
  //
  //     if (userJson == null) {
  //       Logger.info('No user data found, skipping token upload',
  //           tag: 'PushNotification');
  //       return;
  //     }
  //
  //     final userData = json.decode(userJson) as Map<String, dynamic>;
  //     final userId = userData['id']?.toString();
  //
  //     if (userId == null || userId.isEmpty || userId == '0') {
  //       Logger.info('No valid user ID found, skipping token upload',
  //           tag: 'PushNotification');
  //       return;
  //     }
  //
  //     Logger.info('Uploading FCM token to backend for user: $userId',
  //         tag: 'PushNotification');
  //
  //     // Upload FCM token to backend server
  //     try {
  //       final backendUrl = _getBackendUrl();
  //       if (backendUrl == null || backendUrl.isEmpty) {
  //         Logger.info('Backend URL not configured, skipping token upload',
  //             tag: 'PushNotification');
  //         Logger.info('Configure backend URL in lib/utils/app_config.dart',
  //             tag: 'PushNotification');
  //         return;
  //       }
  //
  //       final response = await ApiService.executeWithRetry(
  //         () => ApiService.post(
  //           AppConfig.backendRegisterTokenEndpoint,
  //           skipAuth: false,
  //           headers: const <String, dynamic>{
  //             'Content-Type': 'application/json',
  //           },
  //           data: <String, dynamic>{
  //             'userId': userId,
  //             'fcmToken': token,
  //             'platform': Platform.isAndroid ? 'android' : 'ios',
  //           },
  //         ),
  //         context: 'registerFcmToken',
  //         timeout: const Duration(seconds: 10),
  //       );
  //
  //       if (response != null && ApiService.isSuccessResponse(response)) {
  //         Logger.info('✅ FCM token uploaded successfully to backend',
  //             tag: 'PushNotification');
  //       } else {
  //         Logger.warning(
  //             'Failed to upload FCM token: ${response?.statusCode}',
  //             tag: 'PushNotification');
  //       }
  //     } on TimeoutException {
  //       Logger.warning(
  //           'Backend token upload timeout - continuing without backend sync',
  //           tag: 'PushNotification');
  //     } catch (e) {
  //       Logger.warning(
  //           'Backend not available - continuing without backend sync: $e',
  //           tag: 'PushNotification');
  //       // Don't fail the entire FCM initialization if backend is not available
  //     }
  //   } catch (e) {
  //     Logger.error('Failed to send FCM token to backend: $e',
  //         tag: 'PushNotification', error: e);
  //   }
  // }
  //
  // New Code:
  // Return explicit success/failure so release-mode recovery can retry when
  // startup/login timing causes token sync to be skipped.
  Future<bool> _sendTokenToBackend(String token) async {
    try {
      // Get user ID from secure storage
      final userJson = await _secureStorage.read(key: 'user_data');

      if (userJson == null) {
        Logger.info('No user data found, skipping token upload',
            tag: 'PushNotification');
        return false;
      }

      final userData = json.decode(userJson) as Map<String, dynamic>;
      final userId = userData['id']?.toString();

      if (userId == null || userId.isEmpty || userId == '0') {
        Logger.info('No valid user ID found, skipping token upload',
            tag: 'PushNotification');
        return false;
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
          return false;
        }

        final response = await ApiService.executeWithRetry(
          () => ApiService.post(
            AppConfig.backendRegisterTokenEndpoint,
            skipAuth: false,
            headers: const <String, dynamic>{
              'Content-Type': 'application/json',
            },
            data: <String, dynamic>{
              'userId': userId,
              'fcmToken': token,
              'platform': Platform.isAndroid ? 'android' : 'ios',
            },
          ),
          context: 'registerFcmToken',
          timeout: const Duration(seconds: 10),
        );

        if (response != null && ApiService.isSuccessResponse(response)) {
          Logger.info('✅ FCM token uploaded successfully to backend',
              tag: 'PushNotification');
          return true;
        } else {
          Logger.warning(
              'Failed to upload FCM token: ${response?.statusCode}',
              tag: 'PushNotification');
          return false;
        }
      } on TimeoutException {
        Logger.warning(
            'Backend token upload timeout - continuing without backend sync',
            tag: 'PushNotification');
        return false;
      } catch (e) {
        Logger.warning(
            'Backend not available - continuing without backend sync: $e',
            tag: 'PushNotification');
        // Don't fail the entire FCM initialization if backend is not available
        return false;
      }
    } catch (e) {
      Logger.error('Failed to send FCM token to backend: $e',
          tag: 'PushNotification', error: e);
      return false;
    }
  }

  void _scheduleTokenRecovery({required String reason}) {
    _tokenRecoveryTimer?.cancel();
    Logger.info(
      'Scheduling token recovery sync: $reason',
      tag: 'PushNotification',
    );
    _tokenRecoveryTimer = Timer(const Duration(seconds: 8), () async {
      try {
        await syncFcmTokenToBackendForCurrentUser();
      } catch (e, stackTrace) {
        Logger.error(
          'Token recovery sync failed: $e',
          tag: 'PushNotification',
          error: e,
          stackTrace: stackTrace,
        );
      }
    });
  }

  /// Configure message handlers
  /// This sets up listeners for FCM messages in all app states (foreground, background, terminated)
  Future<void> _configureMessageHandlers() async {
    // Old Code: Bare .listen() calls with no [StreamSubscription] tracking — re-init would leak
    // and tests could not cancel. We cancel any prior subs before attaching.
    disposeMessagingSubscriptions();

    // Handle foreground messages (app is open)
    _fcmMessageSubscriptions.add(
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        Logger.info('Foreground message received: ${message.notification?.title}',
            tag: 'PushNotification');
        Logger.info('Message data: ${message.data}', tag: 'PushNotification');

        // Show local notification in foreground
        _handleForegroundMessage(message);

        // Trigger immediate order refresh when notification arrives
        await _handleOrderUpdateNotification(message);
      }),
    );

    // Handle notification tap when app is in background
    _fcmMessageSubscriptions.add(
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
        Logger.info(
            'Notification tapped (background): ${message.notification?.title}',
            tag: 'PushNotification');
        Logger.info('Message data: ${message.data}', tag: 'PushNotification');

        // Handle notification tap and navigate
        _handleNotificationTap(message);

        // Also trigger order refresh
        await _handleOrderUpdateNotification(message);
      }),
    );

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
    // OLD CODE:
    // _fcmTokenRefreshSubscription =
    //     _firebaseMessaging.onTokenRefresh.listen((newToken) {
    //   Logger.info('FCM token refreshed', tag: 'PushNotification');
    //   _fcmToken = newToken;
    //   _sendTokenToBackend(newToken);
    // });
    //
    // New Code:
    _fcmTokenRefreshSubscription =
        _firebaseMessaging.onTokenRefresh.listen((newToken) {
      Logger.info('FCM token refreshed', tag: 'PushNotification');
      _fcmToken = newToken;
      unawaited(() async {
        final uploaded = await _sendTokenToBackend(newToken);
        if (!uploaded) {
          _scheduleTokenRecovery(reason: 'token refresh upload failed');
        }
      }());
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

  /// Poll/quiz win uses `engagement_points` in the point branch; feed refresh was never invoked.
  Future<void> _refreshEngagementFeedAfterEngagementPointsFcm() async {
    try {
      if (onEngagementFeedRefresh != null) {
        await onEngagementFeedRefresh!();
        Logger.info(
          'Engagement feed refreshed after engagement_points (real-time poll win UI)',
          tag: 'PushNotification',
        );
      } else {
        Logger.warning(
          'onEngagementFeedRefresh not set; engagement hub may stay stale',
          tag: 'PushNotification',
        );
      }
    } catch (e, stackTrace) {
      Logger.error(
        'Engagement feed refresh after engagement_points failed: $e',
        tag: 'PushNotification',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Handle order update notification - triggers immediate order refresh
  /// This is called when FCM notification arrives to ensure orders are instantly updated
  /// Also creates in-app notification
  Future<void> _handleOrderUpdateNotification(RemoteMessage message) async {
    try {
      final data = message.data;
      /*
      Old Code:
      final orderId = data['orderId'] ?? data['order_id'];
      final notificationType = data['type'] ?? '';
      */
      final String orderId = _fcmDataFirstString(data, const [
        'orderId',
        'order_id',
        'orderid',
      ]);
      final String notificationType = _fcmDataFirstString(data, const [
        'type',
        'notification_type',
      ]);
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
        /*
        // Old Code:
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
        */

        // New Code:
        final effectiveUserId = userId.isNotEmpty
            ? userId.toString()
            : AuthProvider().user?.id.toString();

        if (effectiveUserId != null && effectiveUserId.isNotEmpty) {
          final balanceInt = int.tryParse(currentBalance.toString()) ?? 0;

          /*
          // OLD CODE:
          // AuthProvider().applyPointsBalanceSnapshot(balanceInt);
          // PointProvider.instance.applyRemoteBalanceSnapshot(
          //   userId: effectiveUserId,
          //   currentBalance: balanceInt,
          // );
          */

          // NEW FIX: Point notification payload — canonical sync (broadcast optional off).
          await CanonicalPointBalanceSync.apply(
            userId: effectiveUserId,
            currentBalance: balanceInt,
            source: 'push_point_notification',
            emitBroadcast: false,
          );

          // Reconcile from server in background using the centralized refresh flow.
          _schedulePointsHardSync(effectiveUserId);
        } else {
          Logger.warning(
              'No userId in point notification and no authenticated fallback user available',
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

        // OLD CODE:
        // - createPointNotification(...) directly
        // - then notifyPointEvent(... showInAppNotification: false)
        // This created two independent writer paths and could duplicate winner rows.
        //
        // New Code:
        // Single-writer path via PointNotificationManager for both in-app row and modal decision.
        try {
          final notificationTitle = message.notification?.title ??
              _getPointNotificationTitle(notificationType, points);
          final notificationBody = message.notification?.body ??
              _getPointNotificationBody(
                  notificationType, points, currentBalance, data);
          final eventOccurredAt =
              _tryParseFcmDataEventTime(Map<String, dynamic>.from(data));

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
              final engagementItemType =
                  (data['itemType'] ?? data['item_type'] ?? '')
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
              shouldShowModal = false;
              break;
            case 'exchange_rejected':
              modalType = PointNotificationType.exchangeRejected;
              shouldShowModal = false;
              break;
            case 'points_adjusted':
              modalType = PointNotificationType.adjusted;
              isAdjustmentPositive = _parseBool(data['isPositive']) ??
                  _parseBool(data['is_positive']);
              if (isAdjustmentPositive == null) {
                final pointsValueRaw = data['pointsValue'] ?? data['points_value'];
                final parsedDelta = int.tryParse(pointsValueRaw?.toString() ?? '');
                if (parsedDelta != null) {
                  isAdjustmentPositive = parsedDelta >= 0;
                }
              }
              shouldShowModal = isAdjustmentPositive == true;
              break;
          }

          if (modalType != null) {
            final pointsInt = int.tryParse(points) ?? 0;
            final balanceInt = int.tryParse(currentBalance) ?? 0;
            final itemIdRaw =
                data['itemId'] ?? data['item_id'] ?? data['pollId'] ?? data['poll_id'];

            final pollDedupeId = data['pollId'] ?? data['poll_id'];
            final sessionDedupeId = data['sessionId'] ?? data['session_id'];
            /*
            Old Code — FCM fallback `fcm_engagement_$itemId` could not collide with Carousel’s
                        per-millisecond `poll_${id}_${session}_${ts}`, so Poll wins doubled rows:
                orderId: transactionId.isNotEmpty
                  ? null
                  : (notificationType == 'engagement_points' &&
                          itemIdRaw != null &&
                          itemIdRaw.toString().isNotEmpty)
                      ? 'fcm_engagement_${itemIdRaw}'
                      : null,
            */

            final String? pollStableOrderKey = (notificationType ==
                        'engagement_points' &&
                    pollDedupeId != null &&
                    pollDedupeId.toString().trim().isNotEmpty)
                ? 'poll_stable_${pollDedupeId}_${sessionDedupeId ?? ''}'
                : null;

            await PointNotificationManager().notifyPointEvent(
              type: modalType,
              points: pointsInt,
              currentBalance: balanceInt,
              description: notificationBody,
              transactionId: transactionId.isNotEmpty ? transactionId : null,
              orderId: transactionId.isNotEmpty
                  ? null
                  : (pollStableOrderKey ??
                      ((notificationType == 'engagement_points' &&
                              itemIdRaw != null &&
                              itemIdRaw.toString().isNotEmpty)
                          ? 'fcm_engagement_${itemIdRaw}'
                          : null)),
              userId: userId,
              additionalData: {
                ...Map<String, dynamic>.from(data),
                if (eventOccurredAt != null)
                  'eventOccurredAt': eventOccurredAt.toUtc().toIso8601String(),
                'displayTitle': notificationTitle,
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
                if (notificationType == 'points_adjusted')
                  'isPositive': isAdjustmentPositive ?? true,
              },
              showPushNotification: false,
              showInAppNotification: true,
              showModalPopup: shouldShowModal,
            );

            // Ensure badges/UI are fresh.
            final notificationProvider = InAppNotificationProvider.instance;
            await notificationProvider.loadNotifications();

            Logger.info(
                'Point notification handled via manager: type=$notificationType',
                tag: 'PushNotification');
          }

          if (transactionId.isNotEmpty && userId.isNotEmpty) {
            MissedNotificationRecoveryService.markTransactionAsNotified(
                userId, transactionId);
            Logger.info('Transaction marked as notified: $transactionId',
                tag: 'PushNotification');
          }
        } catch (e, stackTrace) {
          Logger.error('Error handling in-app point notification: $e',
              tag: 'PushNotification', error: e, stackTrace: stackTrace);
        }

        // Old Code: `return` only — engagement_points (poll win) left EngagementCarousel
        // stale; user had to pull-to-refresh to see new balance/result on cards.
        if (notificationType == 'engagement_points') {
          await _refreshEngagementFeedAfterEngagementPointsFcm();
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
      if (notificationType == 'order_status_update' && orderId.isNotEmpty) {
        final userId = data['userId'] ?? data['user_id'] ?? '';
        Logger.info(
            'Order update notification received for order: $orderId, userId: $userId',
            tag: 'PushNotification');

        // Notification disabled by user request
        // try {
        //   final status = data['status'] ?? 'updated';
        //   final total = data['total'] ?? '0';
        //   final currency = data['currency'] ?? 'Ks';
        //
        //   final notificationCreated =
        //       await InAppNotificationService().createOrderNotification(
        //     orderId: orderId.toString(),
        //     status: status.toString(),
        //     total: total.toString(),
        //     currency: currency.toString(),
        //   );
        //
        //   if (notificationCreated) {
        //     final notificationProvider = InAppNotificationProvider.instance;
        //     await notificationProvider.loadNotifications();
        //     Logger.info(
        //         'Notification provider updated immediately for order: $orderId',
        //         tag: 'PushNotification');
        //     Logger.info('In-app notification created for order: $orderId',
        //         tag: 'PushNotification');
        //   } else {
        //     Logger.info('Duplicate notification prevented for order: $orderId',
        //         tag: 'PushNotification');
        //   }
        // } catch (e) {
        //   Logger.error('Error creating in-app notification: $e',
        //       tag: 'PushNotification', error: e);
        // }
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

        /*
        // Old Code:
        await Future.wait([
          // Refresh user meta (points_balance/my_points etc.)
          AuthProvider().refreshUser(),
          // Refresh balance from backend source-of-truth.
          PointProvider.instance.loadBalance(userId, forceRefresh: true),
          // Refresh transactions so history updates without manual refresh.
          PointProvider.instance.loadTransactions(userId, forceRefresh: true),
        ]);
        */

        // New Code:
        await PointProvider.instance.refreshPointState(
          userId: userId,
          forceRefresh: true,
          refreshBalance: true,
          refreshTransactions: true,
          refreshUserCallback: () => AuthProvider().refreshUser(),
        );

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

    /*
    Old Code — no `app_general` channel for non-order / unknown FCM rows that must not steal the Order tray.
    */

    const androidChannelGeneral = AndroidNotificationChannel(
      'app_general',
      'App notifications',
      description: 'General notifications that are not WooCommerce orders',
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
      settings: initSettings,
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
    await androidImplementation?.createNotificationChannel(androidChannelGeneral);

    Logger.info(
        'Local notifications configured with channels: ${androidChannelOrder.id}, ${androidChannelPoints.id}, ${androidChannelEngagement.id}, ${androidChannelGeneral.id}',
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

      /*
      Old Code — channel selection OK, but **title/body** always fell back to Order copy:
      final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        channelId, ...
      );
      await _localNotifications.show(
        ...,
        title: message.notification?.title ?? 'Order Update',
        body: message.notification?.body ?? 'Your order has been updated',
      );
      */

      final bool isOrderNotification =
          notificationType == 'order_status_update' && orderId != null;
      // New Code — same Android heads-up knobs, paired with [TrayLocalSpec]:
      final tray = TrayLocalSpec.fromRemoteMessage(message);

      final androidDetails = AndroidNotificationDetails(
        tray.channelId,
        tray.channelName,
        channelDescription: tray.channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
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

      final NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      if (isOrderNotification) {
        // Notification disabled by user request (order tray notifications only).
        Logger.info(
          'Skipping foreground tray display for order notification',
          tag: 'PushNotification',
        );
      } else {
        await _localNotifications.show(
          id: message.hashCode,
          title: tray.title,
          body: tray.body,
          notificationDetails: details,
          payload: json.encode(message.data),
        );

        Logger.info(
            'Foreground tray shown type=$notificationType orderId=${orderId ?? "-"} trayChannel=${tray.channelId}',
            tag: 'PushNotification');
      }

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
