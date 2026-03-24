/// In-app notification model
class InAppNotification {
  final String id;
  final String title;
  final String body;
  final NotificationType type;
  final DateTime createdAt;
  final bool isRead;
  final Map<String, dynamic>? data;
  final String? imageUrl;
  final String? actionUrl;

  InAppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.createdAt,
    this.isRead = false,
    this.data,
    this.imageUrl,
    this.actionUrl,
  });

  /// Create from JSON
  factory InAppNotification.fromJson(Map<String, dynamic> json) {
    return InAppNotification(
      id: json['id'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      type: NotificationType.values.firstWhere(
        (e) => e.toString() == json['type'],
        orElse: () => NotificationType.info,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      isRead: json['isRead'] as bool? ?? false,
      data: json['data'] as Map<String, dynamic>?,
      imageUrl: json['imageUrl'] as String?,
      actionUrl: json['actionUrl'] as String?,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'type': type.toString(),
      'createdAt': createdAt.toIso8601String(),
      'isRead': isRead,
      'data': data,
      'imageUrl': imageUrl,
      'actionUrl': actionUrl,
    };
  }

  /// Create a copy with updated values
  InAppNotification copyWith({
    String? id,
    String? title,
    String? body,
    NotificationType? type,
    DateTime? createdAt,
    bool? isRead,
    Map<String, dynamic>? data,
    String? imageUrl,
    String? actionUrl,
  }) {
    return InAppNotification(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
      data: data ?? this.data,
      imageUrl: imageUrl ?? this.imageUrl,
      actionUrl: actionUrl ?? this.actionUrl,
    );
  }

  /// Get icon for notification type
  String get icon {
    switch (type) {
      case NotificationType.order:
        return '📦';
      case NotificationType.promotion:
        return '🎉';
      case NotificationType.payment:
        return '💳';
      case NotificationType.shipping:
        return '🚚';
      case NotificationType.review:
        return '⭐';
      case NotificationType.points:
        return '🎯';
      case NotificationType.info:
        return 'ℹ️';
      case NotificationType.warning:
        return '⚠️';
      case NotificationType.success:
        return '✅';
    }
  }

  /// Get color for notification type
  int get colorValue {
    switch (type) {
      case NotificationType.order:
        return 0xFF2196F3; // Blue
      case NotificationType.promotion:
        return 0xFFFF9800; // Orange
      case NotificationType.payment:
        return 0xFF4CAF50; // Green
      case NotificationType.shipping:
        return 0xFF9C27B0; // Purple
      case NotificationType.review:
        return 0xFFFFC107; // Amber
      case NotificationType.points:
        return 0xFFFFB300; // Gold/Amber for points
      case NotificationType.info:
        return 0xFF2196F3; // Blue
      case NotificationType.warning:
        return 0xFFFF5722; // Deep Orange
      case NotificationType.success:
        return 0xFF4CAF50; // Green
    }
  }
}

/// Notification types
enum NotificationType {
  order,
  promotion,
  payment,
  shipping,
  review,
  points, // Point-related notifications
  info,
  warning,
  success,
}

