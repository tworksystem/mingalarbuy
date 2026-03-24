/// Web notification implementation using dart:html and dart:js
/// This file is only imported on web platform
library;

import 'dart:html' as html;
import 'dart:js' as js;

class WebNotificationImpl {
  /// Check if Notification API is supported
  static bool isSupported() {
    try {
      // Check if Notification constructor is available on window
      final jsWindow = html.window as dynamic;
      return jsWindow.Notification != null;
    } catch (e) {
      return false;
    }
  }

  /// Get notification permission status
  static String getPermission() {
    try {
      if (!isSupported()) return 'denied';
      // Access Notification.permission via JS interop
      final jsWindow = html.window as dynamic;
      final notification = jsWindow.Notification;
      if (notification == null) return 'denied';
      return notification.permission ?? 'denied';
    } catch (e) {
      return 'denied';
    }
  }

  /// Request notification permission
  static Future<String> requestPermission() async {
    try {
      if (!isSupported()) return 'denied';
      // Access Notification.requestPermission via JS interop
      final jsWindow = html.window as dynamic;
      final notification = jsWindow.Notification;
      if (notification == null) return 'denied';

      final permission = await notification.requestPermission();
      return permission?.toString() ?? 'denied';
    } catch (e) {
      return 'denied';
    }
  }

  /// Show notification
  static dynamic showNotification({
    required String title,
    required String body,
    String? tag,
  }) {
    try {
      if (!isSupported()) return null;

      final permission = getPermission();
      if (permission != 'granted') return null;

      // Access Notification constructor via JS interop
      final jsWindow = html.window as dynamic;
      final Notification = jsWindow.Notification;
      if (Notification == null) return null;

      // Create notification options
      final options = {
        'body': body,
        'tag': tag,
        'icon': '/icons/Icon-192.png',
      };

      // Create and show notification using JS interop
      // Create Notification instance using js package
      final optionsJs = js.JsObject.jsify(options);

      // Use js.context to get Notification constructor
      final NotificationConstructor = js.context['Notification'];
      final notification =
          js.JsObject(NotificationConstructor, [title, optionsJs]);

      // Handle click - use js to set onclick handler
      notification['onclick'] = js.JsFunction.withThis((_, __) {
        // Close on click
        notification.callMethod('close');
      });

      // Auto-close after 5 seconds
      Future.delayed(Duration(seconds: 5), () {
        try {
          notification.callMethod('close');
        } catch (e) {
          // Ignore close errors
        }
      });

      return notification;
    } catch (e) {
      return null;
    }
  }
}
