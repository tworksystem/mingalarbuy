/// Stub for web notification implementation on non-web platforms
/// This file is imported on mobile platforms
library;

class WebNotificationImpl {
  static bool isSupported() => false;
  static String getPermission() => 'denied';
  static Future<String> requestPermission() async => 'denied';
  static dynamic showNotification({
    required String title,
    required String body,
    String? tag,
  }) => null;
}

