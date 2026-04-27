import 'package:intl/intl.dart';

/// Normalize stored instant to local wall clock for display comparisons.
DateTime inAppNotificationAtLocal(DateTime t) => t.isUtc ? t.toLocal() : t;

/// In-app list relative labels (e.g. "Just now", "5m ago", "Yesterday").
/// Uses the event time in the user's local zone when [createdAt] is UTC.
String formatInAppNotificationRelativeTime(DateTime createdAt) {
  // Old Code: bucketed on Duration.inDays/inHours/inMinutes which misclassifies
  // "Yesterday" and sub-minute "Just now"; [date] was not consistently local vs UTC.
  // Old Code:    final now = DateTime.now();
  // Old Code:    final difference = now.difference(date);
  // Old Code:    if (difference.inDays == 0) {
  // Old Code:      if (difference.inHours == 0) {
  // Old Code:        if (difference.inMinutes == 0) {
  // Old Code:          return 'Just now';
  // Old Code:        }
  // Old Code:        return '${difference.inMinutes}m ago';
  // Old Code:      }
  // Old Code:      return '${difference.inHours}h ago';
  // Old Code:    } else if (difference.inDays == 1) {
  // Old Code:      return 'Yesterday';
  // Old Code:    } ...

  final DateTime at = inAppNotificationAtLocal(createdAt);
  final DateTime now = DateTime.now();

  if (at.isAfter(now)) {
    return 'Just now';
  }

  final Duration diff = now.difference(at);
  if (diff.inSeconds < 60) {
    return 'Just now';
  }
  if (diff.inSeconds < 3600) {
    return '${diff.inMinutes}m ago';
  }

  final DateTime startOfToday = DateTime(now.year, now.month, now.day);
  final DateTime startOfEventDay = DateTime(at.year, at.month, at.day);
  final int calendarDaysDiff = startOfToday.difference(startOfEventDay).inDays;

  if (calendarDaysDiff == 0) {
    return '${diff.inHours}h ago';
  }
  if (calendarDaysDiff == 1) {
    return 'Yesterday';
  }
  if (calendarDaysDiff < 7) {
    return '${calendarDaysDiff}d ago';
  }
  return DateFormat('MMM d, y').format(at);
}
