import 'package:ecommerce_int2/app_properties.dart';
import 'package:ecommerce_int2/models/in_app_notification.dart';
import 'package:ecommerce_int2/providers/in_app_notification_provider.dart';
import 'package:ecommerce_int2/utils/logger.dart';
import 'package:ecommerce_int2/widgets/network_status_banner.dart';
import 'package:ecommerce_int2/screens/points/point_history_page.dart';
import 'package:ecommerce_int2/utils/in_app_notification_time.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
/// Professional enhanced notifications page
/// Shows all in-app notifications with read/unread status
class EnhancedNotificationsPage extends StatefulWidget {
  const EnhancedNotificationsPage({super.key});

  @override
  _EnhancedNotificationsPageState createState() =>
      _EnhancedNotificationsPageState();
}

class _EnhancedNotificationsPageState extends State<EnhancedNotificationsPage> {
  String _filter = 'all'; // 'all', 'unread', 'read'

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
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: IconThemeData(color: darkGrey),
          title: Text(
            'Notifications',
            style: TextStyle(
              color: darkGrey,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          actions: [
            Consumer<InAppNotificationProvider>(
              builder: (context, notificationProvider, _) {
                if (notificationProvider.unreadCount == 0) {
                  return const SizedBox.shrink();
                }

                return PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: darkGrey),
                  onSelected: (value) {
                    if (value == 'mark_all_read') {
                      notificationProvider.markAllAsRead();
                    } else if (value == 'delete_all') {
                      _showDeleteAllDialog(context, notificationProvider);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'mark_all_read',
                      child: Row(
                        children: [
                          Icon(Icons.done_all, size: 20),
                          SizedBox(width: 8),
                          Text('Mark All as Read'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete_all',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 20, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Delete All', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
        body: Column(
          children: [
            // Filter tabs
            _buildFilterTabs(),
            // Notifications list
            Expanded(
              child: Consumer<InAppNotificationProvider>(
                builder: (context, notificationProvider, _) {
                  if (notificationProvider.isLoading) {
                    return Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(mediumYellow),
                      ),
                    );
                  }

                  final notifications = _getFilteredNotifications(
                      notificationProvider.notifications);

                  if (notifications.isEmpty) {
                    return _buildEmptyState();
                  }

                  return RefreshIndicator(
                    onRefresh: () => notificationProvider.refresh(),
                    color: mediumYellow,
                    child: ListView.builder(
                      padding: EdgeInsets.all(16),
                      itemCount: notifications.length,
                      itemBuilder: (context, index) {
                        final notification = notifications[index];
                        return _buildNotificationCard(notification);
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build filter tabs
  Widget _buildFilterTabs() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildFilterTab('all', 'All'),
          SizedBox(width: 8),
          _buildFilterTab('unread', 'Unread'),
          SizedBox(width: 8),
          _buildFilterTab('read', 'Read'),
        ],
      ),
    );
  }

  /// Build filter tab
  Widget _buildFilterTab(String filter, String label) {
    final isSelected = _filter == filter;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _filter = filter;
          });
        },
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          decoration: BoxDecoration(
            color: isSelected ? mediumYellow : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? mediumYellow : Colors.grey[300]!,
              width: 1,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.white : darkGrey,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  /// Get filtered notifications
  List<InAppNotification> _getFilteredNotifications(
      List<InAppNotification> notifications) {
    switch (_filter) {
      case 'unread':
        return notifications.where((n) => !n.isRead).toList();
      case 'read':
        return notifications.where((n) => n.isRead).toList();
      default:
        return notifications;
    }
  }

  /// Build notification card
  Widget _buildNotificationCard(InAppNotification notification) {
    return Dismissible(
      key: Key(notification.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red[600],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (direction) {
        Provider.of<InAppNotificationProvider>(context, listen: false)
            .deleteNotification(notification.id);
      },
      child: Card(
        margin: EdgeInsets.only(bottom: 12),
        elevation: notification.isRead ? 1 : 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: () {
            _handleNotificationTap(notification);
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: notification.isRead ? Colors.white : Colors.blue[50],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon
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
                SizedBox(width: 12),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              notification.title,
                              style: TextStyle(
                                fontWeight: notification.isRead
                                    ? FontWeight.w500
                                    : FontWeight.bold,
                                fontSize: 16,
                                color: darkGrey,
                              ),
                            ),
                          ),
                          if (!notification.isRead)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: Colors.blue[600],
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      SizedBox(height: 4),
                      Text(
                        notification.body,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 8),
                      Text(
                        _formatDate(notification.createdAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                      if (notification.type == NotificationType.points &&
                          notification.actionUrl != null &&
                          notification.actionUrl!
                              .startsWith('/points/history')) ...[
                        SizedBox(height: 8),
                        InkWell(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) =>
                                    const PointHistoryPage(),
                              ),
                            );
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.visibility,
                                size: 14,
                                color: Colors.blue[700],
                              ),
                              SizedBox(width: 6),
                              Text(
                                'View',
                                style: TextStyle(
                                  color: Colors.blue[700],
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
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

  /// Handle notification tap
  /// Navigates to relevant page based on notification type and actionUrl
  void _handleNotificationTap(InAppNotification notification) {
    // Mark as read if unread
    if (!notification.isRead) {
      Provider.of<InAppNotificationProvider>(context, listen: false)
          .markAsRead(notification.id);
    }

    // Handle navigation based on notification type and actionUrl
    if (notification.actionUrl != null) {
      final actionUrl = notification.actionUrl!;
      Logger.info('Notification tapped: ${notification.id}, actionUrl: $actionUrl',
          tag: 'EnhancedNotificationsPage');

      // Navigate based on actionUrl
      if (actionUrl.startsWith('/points/history')) {
        // Navigate to points history page
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const PointHistoryPage(),
          ),
        );
        Logger.info('Navigated to points history', tag: 'EnhancedNotificationsPage');
      } else if (actionUrl.startsWith('/order/')) {
        // Extract order ID from actionUrl (format: /order/{orderId})
        final orderId = actionUrl.replaceFirst('/order/', '');
        if (orderId.isNotEmpty) {
          // Navigate to order details page
          // Note: You may need to fetch the order first or pass orderId
          // For now, we'll just log it - you can implement order fetching if needed
          Logger.info('Should navigate to order details: $orderId',
              tag: 'EnhancedNotificationsPage');
          // TODO: Implement order details navigation if needed
          // Navigator.of(context).push(
          //   MaterialPageRoute(
          //     builder: (context) => OrderDetailsPage(order: order),
          //   ),
          // );
        }
      } else {
        Logger.info('Unknown actionUrl: $actionUrl', tag: 'EnhancedNotificationsPage');
      }
    } else {
      Logger.info('Notification tapped but no actionUrl: ${notification.id}',
          tag: 'EnhancedNotificationsPage');
    }
  }

  /// Show delete all dialog
  void _showDeleteAllDialog(
      BuildContext context, InAppNotificationProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete All Notifications?'),
        content: Text('Are you sure you want to delete all notifications?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              provider.deleteAllNotifications();
              Navigator.of(context).pop();
            },
            child: Text(
              'Delete',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  /// Format date (timeago) for in-app notification rows.
  String _formatDate(DateTime date) {
    // Old Code: final now = DateTime.now(); final difference = now.difference(date);
    // Old Code: if (difference.inDays == 0) { ... } else if (difference.inDays == 1) { 'Yesterday' } ...
    return formatInAppNotificationRelativeTime(date);
  }
}

