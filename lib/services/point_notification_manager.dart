import 'dart:async';
import 'package:ecommerce_int2/providers/auth_provider.dart';
import 'package:ecommerce_int2/providers/in_app_notification_provider.dart';
import 'package:ecommerce_int2/services/in_app_notification_service.dart';
import 'package:ecommerce_int2/services/canonical_point_balance_sync.dart';
import 'package:ecommerce_int2/services/global_keys.dart';
import 'package:ecommerce_int2/widgets/point_notification_modal.dart';
import 'package:ecommerce_int2/utils/logger.dart';
import 'package:flutter/material.dart';

/// Point notification event to trigger modal popup
class PointNotificationEvent {
  final PointNotificationType type;
  final int points;
  final String? description;
  final String? transactionId;
  final String? orderId;
  final int currentBalance;
  final Map<String, dynamic>? additionalData;

  PointNotificationEvent({
    required this.type,
    required this.points,
    this.description,
    this.transactionId,
    this.orderId,
    required this.currentBalance,
    this.additionalData,
  });
}

/// Types of point notifications
enum PointNotificationType {
  earned,
  redeemed,
  approved,
  adjusted,
  expired,
  engagementEarned,
  exchangeApproved,
  exchangeRejected,
}

/// Professional Point Notification Manager
/// Handles all point-related notifications (push, in-app, and modal popup)
///
/// This service:
/// - Creates push notifications for point events
/// - Creates in-app notifications for point events
/// - Emits events for modal popup display on home page
/// - Prevents duplicate notifications
class PointNotificationManager {
  static final PointNotificationManager _instance =
      PointNotificationManager._internal();
  factory PointNotificationManager() => _instance;
  PointNotificationManager._internal();

  final InAppNotificationService _inAppNotificationService =
      InAppNotificationService();
  final InAppNotificationProvider _inAppNotificationProvider =
      InAppNotificationProvider.instance;

  // Stream controller for modal popup events
  static final StreamController<PointNotificationEvent> _modalEventController =
      StreamController<PointNotificationEvent>.broadcast();

  /// Stream of point notification events for modal popup
  static Stream<PointNotificationEvent> get modalEvents =>
      _modalEventController.stream;

  // Track recently shown notifications to prevent duplicates
  final Map<String, DateTime> _recentNotifications = {};
  static const Duration _duplicatePreventionWindow = Duration(minutes: 5);

  /// When true: no in-app rows, modals, or [modalEvents] — FCM tray + sync remain in [PushNotificationService] / callers.
  static const bool _suppressInternalPointNotificationUi = true;

  // Modal queue to handle multiple notifications
  final List<PointNotificationEvent> _modalQueue = [];
  bool _isShowingModal = false;
  Timer? _modalQueueTimer;
  Timer?
  _contextCheckTimer; // Timer to periodically check for context availability

  /// Poll wins: prefer in-app notification (non-blocking). Modal only when callers
  /// explicitly request it (e.g. some engagement types via FCM).

  /// Notify user about point event
  /// Optionally creates in-app notification, push hook, and/or modal (callers choose)
  /// [preferredContext] when provided and mounted, used to show modal directly (most reliable)
  Future<void> notifyPointEvent({
    required PointNotificationType type,
    required int points,
    required int currentBalance,
    String? description,
    String? transactionId,
    String? orderId,
    String? userId,
    Map<String, dynamic>? additionalData,
    bool showPushNotification = true,
    bool showInAppNotification = true,
    bool showModalPopup = true,
    BuildContext? preferredContext,
  }) async {
    try {
      final hasPreferredContext =
          preferredContext != null && preferredContext.mounted;
      debugPrint(
        '[PointNotification] notifyPointEvent type=$type points=$points '
        'showModal=$showModalPopup hasContext=$hasPreferredContext',
      );

      // Create unique key for duplicate prevention
      final notificationKey = _createNotificationKey(
        type: type,
        transactionId: transactionId,
        orderId: orderId,
        points: points,
        additionalData: additionalData,
      );

      // Check for duplicates
      if (_isDuplicate(notificationKey)) {
        debugPrint(
          '[PointNotification] DUPLICATE blocked key=$notificationKey',
        );
        Logger.info(
          'Duplicate point notification prevented: $notificationKey',
          tag: 'PointNotificationManager',
        );
        return;
      }

      // Record notification
      _recordNotification(notificationKey);

      /*
      Old Code:
      // Home "My PNP" only received balance updates when a modal was shown, because
      // AuthProvider + PointProvider snapshots lived exclusively inside
      // _ensureBalanceAppliedForWinModal (called from modal show / close paths).
      // notifyPointEvent(..., showModalPopup: false) — e.g. poll wins — therefore
      // skipped that sync and could leave PointProvider stale until another refresh.
      */

      // New Code: Apply authoritative [currentBalance] to Auth + PointProvider for every
      // notification type that carries a balance, before in-app / modal UX, so My PNP
      // rebuilds immediately even when no modal is shown.
      await _syncHomeBalanceFromNotifyPointEvent(
        type: type,
        currentBalance: currentBalance,
        userId: userId,
      );

      // Get notification content
      final notificationContent = _getNotificationContent(
        type: type,
        points: points,
        description: description,
        currentBalance: currentBalance,
        additionalData: additionalData,
      );

      // Create in-app notification (suppressed — rows come only from disabled writes; see InAppNotificationService).
      if (!_suppressInternalPointNotificationUi && showInAppNotification) {
        await _createInAppNotification(
          type: type,
          title: notificationContent['title'] as String,
          body: notificationContent['body'] as String,
          points: points,
          currentBalance: currentBalance,
          transactionId: transactionId,
          orderId: orderId,
          additionalData: additionalData,
        );
      }

      // Show push notification
      if (showPushNotification) {
        await _showPushNotification(
          title: notificationContent['title'] as String,
          body: notificationContent['body'] as String,
        );
      }

      // Show modal popup (only for positive/significant events)
      if (!_suppressInternalPointNotificationUi &&
          showModalPopup &&
          _shouldShowModal(
            type,
            additionalData: additionalData,
            points: points,
          )) {
        final event = PointNotificationEvent(
          type: type,
          points: points,
          description: description,
          transactionId: transactionId,
          orderId: orderId,
          currentBalance: currentBalance,
          additionalData: additionalData,
        );

        // Emit event for stream listeners (backward compatibility)
        _modalEventController.add(event);

        // Use context when available — immediate modal, no queue delay.
        // Sequential callers (e.g. carousel) still get one modal per explicit request.
        final hasContext = preferredContext != null && preferredContext.mounted;

        if (hasContext) {
          await _showModalWithContext(preferredContext, event);
        } else {
          _queueModalForDisplay(event);
        }

        Logger.info(
          'Point notification modal ${hasContext ? "shown with context" : "queued (root)"}: ${type.toString()}, $points points',
          tag: 'PointNotificationManager',
        );
        debugPrint(
          '[PointNotification] modal ${hasContext ? "context" : "queued root"} '
          '${type.toString()} $points pts',
        );
      }

      Logger.info(
        'Point notification created: ${type.toString()}, $points points',
        tag: 'PointNotificationManager',
      );
    } catch (e, stackTrace) {
      debugPrint('[PointNotification] ERROR: $e');
      Logger.error(
        'Error creating point notification: $e',
        tag: 'PointNotificationManager',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Create notification key for duplicate prevention
  String _createNotificationKey({
    required PointNotificationType type,
    String? transactionId,
    String? orderId,
    required int points,
    Map<String, dynamic>? additionalData,
  }) {
    /*
    Old Code:

    ```dart
    if (transactionId != null) {
      return '${type.toString()}_$transactionId';
    }
    if (type == engagementEarned && poll) {
       if (orderId != null) return ... poll_$orderId  // millis suffix broke nothing,
       ...
    }
    if (orderId != null) return ...
    ```

    Problem: Carousel + FCM emitted **different** `orderId` strings (`poll_…_millis`
    vs `fcm_engagement_ITEM`) so duplicates within `_duplicatePreventionWindow` slipped through.
    */

    // New Code — one stable key **per poll session** (Carousel + REST + backend FCM all align):
    if (type == PointNotificationType.engagementEarned &&
        additionalData?['itemType']?.toString() == 'poll') {
      final pollPk = additionalData?['pollId'] ?? additionalData?['poll_id'];
      final sessPk =
          additionalData?['sessionId'] ?? additionalData?['session_id'];
      if (pollPk != null && pollPk.toString().trim().isNotEmpty) {
        return '${type.toString()}_poll_stable_${pollPk}_${sessPk ?? ''}';
      }
      if (orderId != null && orderId.startsWith('poll_stable_')) {
        return '${type.toString()}_poll_${orderId}';
      }
    }

    // Use transaction ID if available (ledger-granular non-poll flows)
    if (transactionId != null && transactionId.isNotEmpty) {
      return '${type.toString()}_$transactionId';
    }
    // Fallback order id tie-breaker (quiz/banner/other engagement):
    if (orderId != null && orderId.isNotEmpty) {
      return '${type.toString()}_$orderId';
    }
    // Fallback to type + points + timestamp (rounded to minute)
    final now = DateTime.now();
    final minuteKey =
        '${now.year}-${now.month}-${now.day}-${now.hour}-${now.minute}';
    return '${type.toString()}_${points}_$minuteKey';
  }

  /// Check if notification is duplicate
  bool _isDuplicate(String key) {
    final lastShown = _recentNotifications[key];
    if (lastShown == null) return false;

    final now = DateTime.now();
    final timeSinceLastShown = now.difference(lastShown);

    if (timeSinceLastShown < _duplicatePreventionWindow) {
      return true; // Duplicate found
    }

    // Expired, remove from cache
    _recentNotifications.remove(key);
    return false;
  }

  /// Record notification to prevent duplicates
  void _recordNotification(String key) {
    _recentNotifications[key] = DateTime.now();

    // Clean up old entries (keep only last hour)
    final cutoff = DateTime.now().subtract(const Duration(hours: 1));
    _recentNotifications.removeWhere((key, time) => time.isBefore(cutoff));
  }

  /// Get notification content based on type
  Map<String, String> _getNotificationContent({
    required PointNotificationType type,
    required int points,
    String? description,
    required int currentBalance,
    Map<String, dynamic>? additionalData,
  }) {
    switch (type) {
      case PointNotificationType.earned:
        return {
          'title': '🎉 Points Earned!',
          'body':
              description ??
              'You earned $points points! Your new balance is $currentBalance points.',
        };

      case PointNotificationType.redeemed:
        return {
          'title': '✅ Points Redeemed',
          'body':
              description ??
              'You redeemed $points points. Your new balance is $currentBalance points.',
        };

      case PointNotificationType.approved:
        return {
          'title': '✨ Points Approved!',
          'body':
              description ??
              'Your $points points have been approved! Your new balance is $currentBalance points.',
        };

      case PointNotificationType.adjusted:
        final isPositive = additionalData?['isPositive'] as bool? ?? points > 0;
        return {
          'title': isPositive ? '📊 Points Added' : '📊 Points Adjusted',
          'body':
              description ??
              (isPositive
                  ? 'You received $points points. Your new balance is $currentBalance points.'
                  : '$points points were adjusted. Your new balance is $currentBalance points.'),
        };

      case PointNotificationType.expired:
        return {
          'title': '⏰ Points Expired',
          'body':
              description ??
              '$points points have expired. Your current balance is $currentBalance points.',
        };

      case PointNotificationType.engagementEarned:
        final isPollWinner = additionalData?['itemType']?.toString() == 'poll';
        final itemTitle = additionalData?['itemTitle'] as String?;
        if (isPollWinner) {
          // Poll-win celebration copy disabled (neutral placeholders for logs/FCM fallbacks).
          return {
            'title': 'Points update',
            'body': description ?? 'Your balance was updated.',
          };
        }
        return {
          'title': '🎯 Engagement Points!',
          'body':
              description ??
              (itemTitle != null
                  ? 'You earned $points points from $itemTitle! Your new balance is $currentBalance points.'
                  : 'You earned $points points from engagement! Your new balance is $currentBalance points.'),
        };

      case PointNotificationType.exchangeApproved:
        // PROFESSIONAL FIX: Exchange requests deduct points, so emphasize deduction
        return {
          'title': '💰 Exchange Approved!',
          'body':
              description ??
              'Your exchange request has been approved! $points points were deducted. Your new balance is $currentBalance points.',
        };

      case PointNotificationType.exchangeRejected:
        final reason = additionalData?['reason'] as String?;
        return {
          'title': '⚠️ Exchange Rejected',
          'body':
              description ??
              (reason != null
                  ? 'Your exchange request was rejected: $reason'
                  : 'Your exchange request was rejected. Your points remain unchanged.'),
        };
    }
  }

  /// Determine if modal popup should be shown for this event type
  /// PROFESSIONAL FIX: Avoid noisy/negative adjustment popups
  bool _shouldShowModal(
    PointNotificationType type, {
    Map<String, dynamic>? additionalData,
    int? points,
  }) {
    // Show modal for positive events and adjustments
    switch (type) {
      case PointNotificationType.earned:
      case PointNotificationType.approved:
      case PointNotificationType.exchangeApproved:
        return true;
      case PointNotificationType.engagementEarned:
        // POPUP KILL-SWITCH: poll wins use silent balance sync; never show winner modal.
        if (additionalData?['itemType']?.toString() == 'poll') {
          return false;
        }
        return true;
      case PointNotificationType.adjusted:
        // Manual adjustments can be positive (add) or negative (deduct).
        // UX requirement: do NOT show modal popup for negative manual adjustments.
        final isPositive =
            (additionalData?['isPositive'] as bool?) ??
            (additionalData?['is_positive'] as bool?) ??
            ((points ?? 0) > 0);
        return isPositive;
      case PointNotificationType.redeemed:
      case PointNotificationType.expired:
      case PointNotificationType.exchangeRejected:
        return false; // These can be shown as notifications only
    }
  }

  bool _isPollWinnerEvent(PointNotificationEvent event) {
    final itemType =
        (event.additionalData?['itemType'] ??
                event.additionalData?['item_type'])
            ?.toString()
            .toLowerCase();
    return event.type == PointNotificationType.engagementEarned &&
        itemType == 'poll';
  }

  /// Create in-app notification
  Future<void> _createInAppNotification({
    required PointNotificationType type,
    required String title,
    required String body,
    required int points,
    required int currentBalance,
    String? transactionId,
    String? orderId,
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      // Map PointNotificationType to string type for InAppNotificationService
      String notificationType;
      switch (type) {
        case PointNotificationType.earned:
          notificationType = 'points_earned';
          break;
        case PointNotificationType.redeemed:
          notificationType = 'points_redeemed';
          break;
        case PointNotificationType.approved:
          notificationType = 'points_approved';
          break;
        case PointNotificationType.adjusted:
          notificationType = 'points_adjusted';
          break;
        case PointNotificationType.expired:
          notificationType = 'points_expired';
          break;
        case PointNotificationType.engagementEarned:
          notificationType = 'engagement_points';
          break;
        case PointNotificationType.exchangeApproved:
          notificationType = 'exchange_approved';
          break;
        case PointNotificationType.exchangeRejected:
          notificationType = 'exchange_rejected';
          break;
      }

      // OLD CODE:
      // final success = await _inAppNotificationService.createPointNotification(
      //   type: notificationType,
      //   title: title,
      //   body: body,
      //   transactionId: transactionId,
      //   points: points.toString(),
      //   currentBalance: currentBalance.toString(),
      //   additionalData: additionalData,
      // );
      //
      // New Code:
      // For poll winners, pass a stable requestId derived from pollId+sessionId
      // so storage-level idempotency survives app restarts.
      final pollId =
          (additionalData?['pollId'] ??
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
      final stableRequestId =
          (notificationType == 'engagement_points' &&
              itemType == 'poll' &&
              pollId != null &&
              pollId.isNotEmpty &&
              sessionId != null &&
              sessionId.isNotEmpty)
          ? 'poll_${pollId}_$sessionId'
          : requestIdFromAdditional(additionalData);

      final success = await _inAppNotificationService.createPointNotification(
        type: notificationType,
        title: title,
        body: body,
        transactionId: transactionId,
        requestId: stableRequestId,
        points: points.toString(),
        currentBalance: currentBalance.toString(),
        additionalData: additionalData,
      );

      if (success) {
        // Refresh notification provider to update UI
        await _inAppNotificationProvider.loadNotifications();
      }
    } catch (e, stackTrace) {
      Logger.error(
        'Error creating in-app notification: $e',
        tag: 'PointNotificationManager',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  String? requestIdFromAdditional(Map<String, dynamic>? additionalData) {
    final v = additionalData?['requestId'] ?? additionalData?['request_id'];
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  /// Show push notification
  /// Note: Push notifications are typically handled by FCM/PushNotificationService
  /// This method is kept for future use if needed for local notifications
  Future<void> _showPushNotification({
    required String title,
    required String body,
  }) async {
    // Push notifications are handled by PushNotificationService via FCM
    // Local notifications can be added here if needed in the future
    Logger.info(
      'Push notification requested: $title - $body (handled by FCM)',
      tag: 'PointNotificationManager',
    );
  }

  /*
  // OLD CODE:
  /// Pushes [currentBalance] into user meta + PointProvider so Home My PNP listeners update.
  // void _applyBalanceSnapshotToProviders({
  //   required String userId,
  //   required int currentBalance,
  // }) {
  //   AuthProvider().applyPointsBalanceSnapshot(currentBalance);
  //   PointProvider.instance.applyRemoteBalanceSnapshot(
  //     userId: userId,
  //     currentBalance: currentBalance,
  //   );
  // }
  */

  /// NEW FIX: Same as above + disk; no extra broadcast (legacy behavior).
  /// Await canonical apply so it participates in [CanonicalPointBalanceSync] mutex ordering.
  Future<void> _applyBalanceSnapshotToProviders({
    required String userId,
    required int currentBalance,
  }) async {
    /*
    Old Code: fire-and-forget raced other canonical paths (FCM / poll win).
    unawaited(
      CanonicalPointBalanceSync.apply(
        userId: userId,
        currentBalance: currentBalance,
        source: 'point_notification_manager',
        emitBroadcast: false,
      ),
    );
    */
    await CanonicalPointBalanceSync.apply(
      userId: userId,
      currentBalance: currentBalance,
      source: 'point_notification_manager',
      emitBroadcast: false,
    );
  }

  /// Whether [notifyPointEvent] should treat [currentBalance] as server/UI truth for Home sync.
  bool _notificationTypeCarriesBalanceForHomeSync(PointNotificationType type) {
    switch (type) {
      case PointNotificationType.earned:
      case PointNotificationType.engagementEarned:
      case PointNotificationType.approved:
      case PointNotificationType.redeemed:
      case PointNotificationType.expired:
      case PointNotificationType.exchangeApproved:
      case PointNotificationType.adjusted:
        return true;
      case PointNotificationType.exchangeRejected:
        return false;
    }
  }

  /// Resolves user id and applies snapshot when authenticated user matches.
  Future<void> _syncHomeBalanceFromNotifyPointEvent({
    required PointNotificationType type,
    required int currentBalance,
    String? userId,
  }) async {
    if (!_notificationTypeCarriesBalanceForHomeSync(type)) {
      return;
    }
    final auth = AuthProvider();
    if (!auth.isAuthenticated || auth.user == null) {
      return;
    }
    final sessionUserId = auth.user!.id.toString();
    final effectiveUserId = (userId != null && userId.trim().isNotEmpty)
        ? userId.trim()
        : sessionUserId;
    if (effectiveUserId != sessionUserId) {
      return;
    }
    await _applyBalanceSnapshotToProviders(
      userId: sessionUserId,
      currentBalance: currentBalance,
    );
  }

  /// Ensure balance is applied to providers before/after showing win modal.
  /// Prevents "points not added" when modal is queued/delayed or something overwrote.
  Future<void> _ensureBalanceAppliedForWinModal(
    PointNotificationEvent event,
  ) async {
    /*
    Old Code:
    final isBalanceChange =
        event.type == PointNotificationType.engagementEarned ||
            event.type == PointNotificationType.earned ||
            event.type == PointNotificationType.approved ||
            event.type == PointNotificationType.exchangeApproved ||
            (event.type == PointNotificationType.adjusted &&
                (event.additionalData?['isPositive'] as bool? ?? event.points > 0));
    if (!isBalanceChange) return;
    final auth = AuthProvider();
    if (!auth.isAuthenticated || auth.user == null) return;
    final userId = auth.user!.id.toString();
    AuthProvider().applyPointsBalanceSnapshot(event.currentBalance);
    PointProvider.instance.applyRemoteBalanceSnapshot(
      userId: userId,
      currentBalance: event.currentBalance,
    );
    */

    // New Code: Same modal eligibility rules; delegate to shared snapshot helper.
    final isBalanceChange =
        event.type == PointNotificationType.engagementEarned ||
        event.type == PointNotificationType.earned ||
        event.type == PointNotificationType.approved ||
        event.type == PointNotificationType.exchangeApproved ||
        (event.type == PointNotificationType.adjusted &&
            (event.additionalData?['isPositive'] as bool? ?? event.points > 0));
    if (!isBalanceChange) return;
    final auth = AuthProvider();
    if (!auth.isAuthenticated || auth.user == null) return;
    final userId = auth.user!.id.toString();
    await _applyBalanceSnapshotToProviders(
      userId: userId,
      currentBalance: event.currentBalance,
    );
  }

  /// Show modal directly using provided context (most reliable when caller has valid context)
  Future<void> _showModalWithContext(
    BuildContext context,
    PointNotificationEvent event,
  ) async {
    if (!context.mounted) return;
    if (_suppressInternalPointNotificationUi) {
      return;
    }
    if (_isPollWinnerEvent(event)) {
      // Global UI silence: never show poll winner modal via showDialog.
      return;
    }
    try {
      await _ensureBalanceAppliedForWinModal(event);
      await showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.7),
        builder: (ctx) => PointNotificationModal(event: event),
      );
      await _ensureBalanceAppliedForWinModal(event);
    } catch (e, st) {
      Logger.error(
        'Failed to show modal with context, falling back to queue: $e',
        tag: 'PointNotificationManager',
        error: e,
        stackTrace: st,
      );
      _queueModalForDisplay(event);
    }
  }

  /// Queue modal for display using global navigator key
  /// This ensures modals can be shown from anywhere in the app
  void _queueModalForDisplay(PointNotificationEvent event) {
    _modalQueue.add(event);
    Logger.info(
      'Modal queued: ${event.type.toString()}, ${event.points} points. Queue length: ${_modalQueue.length}',
      tag: 'PointNotificationManager',
    );

    // Process queue if not already processing
    if (!_isShowingModal) {
      _processModalQueue();
    } else {
      Logger.info(
        'Modal already showing, event queued. Will process after current modal closes.',
        tag: 'PointNotificationManager',
      );
    }

    // Start context check timer if not already running
    _startContextCheckTimer();
  }

  /// Process modal queue and show modals one at a time
  /// PROFESSIONAL FIX: Enhanced with better context handling, retry logic, and error recovery
  Future<void> _processModalQueue() async {
    if (_isShowingModal || _modalQueue.isEmpty) {
      return;
    }

    _isShowingModal = true;

    var isFirstInBatch = true;
    while (_modalQueue.isNotEmpty) {
      final event = _modalQueue.removeAt(0);
      if (_suppressInternalPointNotificationUi) {
        continue;
      }
      if (_isPollWinnerEvent(event)) {
        continue;
      }

      try {
        // Stagger only *between* modals (not before the first), so the first
        // celebration appears immediately when points are credited.
        if (!isFirstInBatch) {
          await Future.delayed(const Duration(milliseconds: 450));
        }
        isFirstInBatch = false;

        // PROFESSIONAL FIX: Enhanced context retrieval with multiple retry attempts
        BuildContext? navigatorContext = AppKeys.navigatorKey.currentContext;

        // Retry logic: Try up to 5 times with increasing delays
        int retryCount = 0;
        const maxRetries = 5;
        const retryDelays = [
          Duration(milliseconds: 200),
          Duration(milliseconds: 500),
          Duration(seconds: 1),
          Duration(seconds: 2),
          Duration(seconds: 3),
        ];

        while (navigatorContext == null && retryCount < maxRetries) {
          Logger.warning(
            'Navigator context not available (attempt ${retryCount + 1}/$maxRetries). Retrying...',
            tag: 'PointNotificationManager',
          );

          await Future.delayed(retryDelays[retryCount]);
          navigatorContext = AppKeys.navigatorKey.currentContext;
          retryCount++;
        }

        if (navigatorContext != null) {
          // Verify context is still mounted before showing dialog
          if (!navigatorContext.mounted) {
            Logger.warning(
              'Navigator context is not mounted. Re-queuing modal.',
              tag: 'PointNotificationManager',
            );
            _modalQueue.insert(0, event);
            continue;
          }

          Logger.info(
            'Showing point notification modal: ${event.type.toString()}, ${event.points} points (attempt ${retryCount + 1})',
            tag: 'PointNotificationManager',
          );

          await _ensureBalanceAppliedForWinModal(event);

          try {
            await showDialog(
              context: navigatorContext,
              barrierDismissible: false,
              barrierColor: Colors.black.withValues(alpha: 0.7),
              builder: (context) => PointNotificationModal(event: event),
            );

            await _ensureBalanceAppliedForWinModal(event);

            Logger.info(
              'Point notification modal closed: ${event.type.toString()}',
              tag: 'PointNotificationManager',
            );
          } catch (dialogError, dialogStackTrace) {
            Logger.error(
              'Error showing dialog (context was available): $dialogError',
              tag: 'PointNotificationManager',
              error: dialogError,
              stackTrace: dialogStackTrace,
            );
            // Re-queue the event if dialog failed but context was available
            // This might be a temporary issue
            _modalQueue.insert(0, event);
            await Future.delayed(const Duration(seconds: 2));
          }
        } else {
          Logger.error(
            'Navigator context still not available after $maxRetries retries. Re-queuing modal for later processing.',
            tag: 'PointNotificationManager',
          );

          // Re-queue the event - context check timer will try again later
          _modalQueue.insert(0, event);

          // Start context check timer if not already running
          _startContextCheckTimer();

          // Exit processing loop - timer will retry later
          break;
        }
      } catch (e, stackTrace) {
        Logger.error(
          'Error processing point notification modal: $e',
          tag: 'PointNotificationManager',
          error: e,
          stackTrace: stackTrace,
        );

        // Re-queue event on error (unless it's a critical error)
        if (_modalQueue.length < 10) {
          // Prevent infinite queue growth
          _modalQueue.insert(0, event);
          await Future.delayed(const Duration(seconds: 2));
        } else {
          Logger.error(
            'Modal queue too large, dropping event to prevent memory issues',
            tag: 'PointNotificationManager',
          );
        }
      }
    }

    _isShowingModal = false;

    if (_modalQueue.isEmpty) {
      Logger.info(
        'Modal queue processed. All modals shown.',
        tag: 'PointNotificationManager',
      );
      // Stop context check timer if queue is empty
      _contextCheckTimer?.cancel();
      _contextCheckTimer = null;
    } else {
      Logger.info(
        'Modal queue partially processed. ${_modalQueue.length} modals remaining. Re-triggering process.',
        tag: 'PointNotificationManager',
      );
      // Events were added while we were showing; process the rest (e.g. parallel poll wins).
      _processModalQueue();
    }
  }

  /// Start context check timer to periodically retry showing modals when context becomes available
  void _startContextCheckTimer() {
    // Cancel existing timer if any
    _contextCheckTimer?.cancel();

    // Only start timer if we have queued modals and context is not available
    if (_modalQueue.isNotEmpty && AppKeys.navigatorKey.currentContext == null) {
      _contextCheckTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
        final context = AppKeys.navigatorKey.currentContext;

        if (context != null) {
          Logger.info(
            'Context became available! Processing ${_modalQueue.length} queued modals.',
            tag: 'PointNotificationManager',
          );
          timer.cancel();
          _contextCheckTimer = null;

          // Process queue now that context is available
          if (!_isShowingModal) {
            _processModalQueue();
          }
        } else if (_modalQueue.isEmpty) {
          // No more modals to show, stop timer
          Logger.info(
            'Modal queue empty, stopping context check timer.',
            tag: 'PointNotificationManager',
          );
          timer.cancel();
          _contextCheckTimer = null;
        }
        // Otherwise, continue checking
      });
    }
  }

  /// Dispose resources
  static void dispose() {
    _modalEventController.close();
    _instance._modalQueueTimer?.cancel();
    _instance._contextCheckTimer?.cancel();
    _instance._modalQueue.clear();
    _instance._isShowingModal = false;
  }
}
