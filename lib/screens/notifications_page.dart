import 'package:ecommerce_int2/app_properties.dart';
import 'package:ecommerce_int2/models/in_app_notification.dart';
import 'package:ecommerce_int2/models/order.dart';
import 'package:ecommerce_int2/providers/in_app_notification_provider.dart';
import 'package:ecommerce_int2/providers/order_provider.dart';
import 'package:ecommerce_int2/providers/auth_provider.dart';
import 'package:ecommerce_int2/screens/tracking_page.dart';
import 'package:ecommerce_int2/screens/orders/order_details_page.dart';
import 'package:ecommerce_int2/screens/points/point_history_page.dart';
import 'package:ecommerce_int2/utils/in_app_notification_time.dart';
import 'package:ecommerce_int2/utils/logger.dart';
import 'package:ecommerce_int2/widgets/network_status_banner.dart';
import 'package:ecommerce_int2/widgets/app_pull_to_refresh.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Professional notifications page with original design
/// Shows in-app notifications with original UI style
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  _NotificationsPageState createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  @override
  void initState() {
    super.initState();
    // Load notifications when page opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<InAppNotificationProvider>(context, listen: false)
          .loadNotifications();
    });
  }

  @override
  Widget build(BuildContext context) {
    return NetworkStatusBanner(
      child: Material(
        color: Colors.grey[100],
        child: SafeArea(
          child: Container(
            margin: const EdgeInsets.only(top: kToolbarHeight),
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: AppPullToRefresh(
              onRefresh: () async {
                await Provider.of<InAppNotificationProvider>(context, listen: false)
                    .loadNotifications();
              },
              child: Column(
                children: <Widget>[
                // Header with unread count
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Consumer<InAppNotificationProvider>(
                      builder: (context, provider, _) {
                        final unreadCount = provider.unreadCount;
                        return Row(
                          children: [
                            Text(
                              'Notification',
                              style: TextStyle(
                                color: darkGrey,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (unreadCount > 0) ...[
                              SizedBox(width: 8),
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red[600],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  unreadCount > 99 ? '99+' : '$unreadCount',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                    CloseButton(),
                  ],
                ),
                // Notifications list
                Flexible(
                  child: Consumer<InAppNotificationProvider>(
                    builder: (context, notificationProvider, _) {
                      if (notificationProvider.isLoading) {
                        return Center(
                          child: CircularProgressIndicator(
                            valueColor:
                                AlwaysStoppedAnimation<Color>(mediumYellow),
                          ),
                        );
                      }

                      final notifications = notificationProvider.notifications;

                      if (notifications.isEmpty) {
                        return _buildEmptyState();
                      }

                      return RefreshIndicator(
                        onRefresh: () => notificationProvider.refresh(),
                        color: mediumYellow,
                        child: ListView.builder(
                          itemCount: notifications.length,
                          itemBuilder: (context, index) {
                            final notification = notifications[index];
                            return _buildNotificationCard(
                              notification,
                              notificationProvider,
                            );
                          },
                        ),
                      );
                    },
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

  /// Build notification card with original design style
  Widget _buildNotificationCard(
    InAppNotification notification,
    InAppNotificationProvider provider,
  ) {
    // Mark as read when viewed
    if (!notification.isRead) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        provider.markAsRead(notification.id);
      });
    }

    // Build different card styles based on notification type
    switch (notification.type) {
      case NotificationType.order:
        return _buildOrderNotificationCard(notification, provider);
      case NotificationType.shipping:
        return _buildShippingNotificationCard(notification, provider);
      case NotificationType.promotion:
        return _buildPromotionNotificationCard(notification, provider);
      case NotificationType.points:
        return _buildPointsNotificationCard(notification, provider);
      default:
        return _buildDefaultNotificationCard(notification, provider);
    }
  }

  /// Build order notification card
  Widget _buildOrderNotificationCard(
    InAppNotification notification,
    InAppNotificationProvider provider,
  ) {
    final orderId = notification.data?['orderId'] ?? '';
    final status = notification.data?['status'] ?? 'updated';
    final total = notification.data?['total'] ?? '0';
    final currency = notification.data?['currency'] ?? 'Ks';

    return Container(
      padding: const EdgeInsets.all(16.0),
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      decoration: BoxDecoration(
        color: notification.isRead ? Colors.white : Colors.blue[50],
        borderRadius: BorderRadius.all(Radius.circular(5.0)),
        border: notification.isRead
            ? null
            : Border.all(color: Colors.blue[200]!, width: 1),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              // Notification icon/avatar
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Color(notification.colorValue).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    notification.icon,
                    style: TextStyle(fontSize: 24),
                  ),
                ),
              ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        color: Colors.black,
                        fontSize: 14,
                      ),
                      children: [
                        TextSpan(
                          text: 'Order #$orderId ',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextSpan(
                          text: _getStatusMessage(status),
                        ),
                        if (total != '0')
                          TextSpan(
                            text: ' Total: $currency$total',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: mediumYellow,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              InkWell(
                onTap: () {
                  if (orderId.isNotEmpty) {
                    _navigateToOrderDetails(context, orderId);
                  }
                },
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.visibility,
                      size: 14,
                      color: Colors.blue[700],
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text(
                        'View Order',
                        style: TextStyle(color: Colors.blue[700]),
                      ),
                    )
                  ],
                ),
              ),
              SizedBox(width: 16),
              InkWell(
                onTap: () {
                  provider.deleteNotification(notification.id);
                },
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.delete_outline,
                      size: 14,
                      color: Color(0xffF94D4D),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text(
                        'Delete',
                        style: TextStyle(color: Color(0xffF94D4D)),
                      ),
                    )
                  ],
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  /// Build shipping notification card
  Widget _buildShippingNotificationCard(
    InAppNotification notification,
    InAppNotificationProvider provider,
  ) {
    final orderId = notification.data?['orderId'] ?? '';
    final trackingNumber = notification.data?['trackingNumber'] ?? '';
    final productImage = notification.imageUrl;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      decoration: BoxDecoration(
        color: notification.isRead ? Colors.white : Colors.blue[50],
        borderRadius: BorderRadius.all(Radius.circular(5.0)),
        border: notification.isRead
            ? null
            : Border.all(color: Colors.blue[200]!, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                // Product image with yellow background
                SizedBox(
                  height: 110,
                  width: 110,
                  child: Stack(
                    children: <Widget>[
                      Positioned(
                        left: 5.0,
                        bottom: -10.0,
                        child: SizedBox(
                          height: 100,
                          width: 100,
                          child: Transform.scale(
                            scale: 1.2,
                            child: Image.asset(
                              'assets/bottom_yellow.png',
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  color: yellow,
                                  child: Icon(Icons.image),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 8.0,
                        left: 10.0,
                        child: SizedBox(
                          height: 80,
                          width: 80,
                          child: productImage != null
                              ? CachedNetworkImage(
                                  imageUrl: productImage,
                                  fit: BoxFit.cover,
                                  errorWidget: (context, url, error) {
                                    return Image.asset(
                                      'assets/headphones.png',
                                    );
                                  },
                                )
                              : Image.asset(
                                  'assets/headphones.png',
                                ),
                        ),
                      )
                    ],
                  ),
                ),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notification.title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      SizedBox(height: 4.0),
                      Text(
                        notification.body,
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 10,
                        ),
                      ),
                      if (trackingNumber.isNotEmpty) ...[
                        SizedBox(height: 4.0),
                        Text(
                          'Tracking: $trackingNumber',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              ],
            ),
          ),
          InkWell(
            onTap: () {
              if (orderId.isNotEmpty) {
                _navigateToOrderDetails(context, orderId);
              } else {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => TrackingPage()),
                );
              }
            },
            child: Container(
              padding: const EdgeInsets.all(14.0),
              decoration: BoxDecoration(
                color: yellow,
                borderRadius: BorderRadius.only(
                  bottomRight: Radius.circular(5.0),
                  bottomLeft: Radius.circular(5.0),
                ),
              ),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Track the product',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  /// Build promotion notification card
  Widget _buildPromotionNotificationCard(
    InAppNotification notification,
    InAppNotificationProvider provider,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: notification.isRead ? Colors.white : Colors.orange[50],
        borderRadius: BorderRadius.all(Radius.circular(5.0)),
        border: notification.isRead
            ? null
            : Border.all(color: Colors.orange[200]!, width: 1),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Color(notification.colorValue).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    notification.icon,
                    style: TextStyle(fontSize: 24),
                  ),
                ),
              ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notification.title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        notification.body,
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            ],
          ),
        ],
      ),
    );
  }

  /// Build points notification card (winner, earned, etc.) with View button
  Widget _buildPointsNotificationCard(
    InAppNotification notification,
    InAppNotificationProvider provider,
  ) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      decoration: BoxDecoration(
        color: notification.isRead ? Colors.white : Colors.blue[50],
        borderRadius: BorderRadius.all(Radius.circular(5.0)),
        border: notification.isRead
            ? null
            : Border.all(color: Colors.blue[200]!, width: 1),
      ),
      child: Column(
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Color(notification.colorValue).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    notification.icon,
                    style: TextStyle(fontSize: 24),
                  ),
                ),
              ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notification.title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        notification.body,
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        _formatDate(notification.createdAt),
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PointHistoryPage(),
                    ),
                  );
                },
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.visibility,
                      size: 14,
                      color: Colors.blue[700],
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text(
                        'View',
                        style: TextStyle(color: Colors.blue[700]),
                      ),
                    )
                  ],
                ),
              ),
              SizedBox(width: 16),
              InkWell(
                onTap: () {
                  provider.deleteNotification(notification.id);
                },
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.delete_outline,
                      size: 14,
                      color: Color(0xffF94D4D),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text(
                        'Delete',
                        style: TextStyle(color: Color(0xffF94D4D)),
                      ),
                    )
                  ],
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  /// Build default notification card
  Widget _buildDefaultNotificationCard(
    InAppNotification notification,
    InAppNotificationProvider provider,
  ) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      decoration: BoxDecoration(
        color: notification.isRead ? Colors.white : Colors.grey[50],
        borderRadius: BorderRadius.all(Radius.circular(5.0)),
        border: notification.isRead
            ? null
            : Border.all(color: Colors.grey[300]!, width: 1),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Color(notification.colorValue).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                notification.icon,
                style: TextStyle(fontSize: 24),
              ),
            ),
          ),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    notification.body,
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    _formatDate(notification.createdAt),
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  /// Build empty state
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_none,
            size: 80,
            color: Colors.grey[300],
          ),
          SizedBox(height: 16),
          Text(
            'No notifications',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: 8),
          Text(
            'You\'re all caught up!',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  /// Get status message
  String _getStatusMessage(String status) {
    final statusMap = {
      'pending': 'is being processed',
      'processing': 'is being prepared',
      'on-hold': 'is on hold',
      'completed': 'has been completed',
      'cancelled': 'has been cancelled',
      'refunded': 'has been refunded',
      'failed': 'payment failed',
      'shipped': 'has been shipped',
      'delivered': 'has been delivered',
    };
    return statusMap[status.toLowerCase()] ?? 'status has been updated';
  }

  /// Navigate to order details
  Future<void> _navigateToOrderDetails(
      BuildContext context, String orderId) async {
    try {
      final orderProvider = Provider.of<OrderProvider>(context, listen: false);

      // Try to find order locally first
      Order? order = orderProvider.getOrderById(orderId);

      // If not found, try with different ID formats
      order ??= orderProvider.getOrderById('WC-$orderId');

      if (order == null) {
        // Try to find by matching ID as string
        try {
          order = orderProvider.orders.firstWhere(
            (o) => o.id == orderId || o.id.toString() == orderId,
          );
        } catch (e) {
          // Order not found locally
        }
      }

      // If still not found, try to sync orders from WooCommerce
      if (order == null) {
        // Show loading dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => Center(
            child: Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(mediumYellow),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Loading order...',
                    style: TextStyle(
                      fontSize: 14,
                      color: darkGrey,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        try {
          // Get auth provider to get user ID
          final authProvider =
              Provider.of<AuthProvider>(context, listen: false);

          if (authProvider.isAuthenticated && authProvider.user != null) {
            final userId = authProvider.user!.id.toString();

            // Sync orders from WooCommerce
            await orderProvider.syncOrdersWithWooCommerce(userId);

            // Try to find order again after sync
            order = orderProvider.getOrderById(orderId);

            order ??= orderProvider.getOrderById('WC-$orderId');

            if (order == null) {
              try {
                order = orderProvider.orders.firstWhere(
                  (o) =>
                      o.id == orderId ||
                      o.id.toString() == orderId ||
                      o.metadata?['woocommerce_id']?.toString() == orderId,
                );
              } catch (e) {
                // Still not found
              }
            }
          }
        } catch (e) {
          Logger.error('Error syncing orders: $e',
              tag: 'NotificationsPage', error: e);
        } finally {
          // Close loading dialog
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        }
      }

      // Navigate to order details if found
      if (order != null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => OrderDetailsPage(order: order!),
          ),
        );
      } else {
        // Show error message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('Order #$orderId not found. Please try again later.'),
              backgroundColor: Colors.red[600],
              duration: Duration(seconds: 3),
              action: SnackBarAction(
                label: 'Retry',
                textColor: Colors.white,
                onPressed: () {
                  _navigateToOrderDetails(context, orderId);
                },
              ),
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      Logger.error('Error navigating to order details: $e',
          tag: 'NotificationsPage', error: e, stackTrace: stackTrace);

      if (mounted) {
        // Close loading dialog if still open
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load order details. Please try again.'),
            backgroundColor: Colors.red[600],
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Format date (timeago) for in-app notification rows.
  String _formatDate(DateTime date) {
    // Old Code: final now = DateTime.now(); final difference = now.difference(date);
    // Old Code: if (difference.inDays == 0) { ... } else if (difference.inDays == 1) { 'Yesterday' } ...
    return formatInAppNotificationRelativeTime(date);
  }
}
