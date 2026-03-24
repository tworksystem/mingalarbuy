// Stub file for Firebase on web platform
// Firebase packages are not fully supported on web without additional setup
// This stub provides empty implementations to allow compilation

/// Stub for Firebase class
class Firebase {
  static Future<void> initializeApp({String? name, Map<String, dynamic>? options}) async {
    // No-op for web
  }
}

/// Stub for FirebaseMessaging
class FirebaseMessaging {
  static FirebaseMessaging get instance => FirebaseMessaging();
  
  // Static method for background message handler
  static void onBackgroundMessage(Future<void> Function(RemoteMessage) handler) {
    // No-op for web
  }
  
  // Static streams (accessed via FirebaseMessaging.onMessage)
  static Stream<RemoteMessage> get onMessage => const Stream.empty();
  static Stream<RemoteMessage> get onMessageOpenedApp => const Stream.empty();
  
  // Instance methods and properties
  Future<NotificationSettings> requestPermission({
    bool alert = false,
    bool badge = false,
    bool sound = false,
    bool provisional = false,
    bool criticalAlert = false,
  }) async {
    return NotificationSettings(authorizationStatus: AuthorizationStatus.authorized);
  }
  
  Future<String?> getToken() async => null;
  
  Future<RemoteMessage?> getInitialMessage() async => null;
  
  Stream<String> get onTokenRefresh => const Stream.empty();
  
  Future<void> subscribeToTopic(String topic) async {}
  Future<void> unsubscribeFromTopic(String topic) async {}
}

/// Stub for RemoteMessage
class RemoteMessage {
  final Map<String, dynamic>? data;
  final Notification? notification;
  final String? messageId;
  
  RemoteMessage({
    this.data,
    this.notification,
    this.messageId,
  });
}

/// Stub for Notification
class Notification {
  final String? title;
  final String? body;
  
  Notification({this.title, this.body});
}

/// Stub for NotificationSettings
class NotificationSettings {
  final AuthorizationStatus authorizationStatus;
  
  NotificationSettings({required this.authorizationStatus});
}

/// Stub for AuthorizationStatus enum
enum AuthorizationStatus {
  notDetermined,
  denied,
  authorized,
  provisional,
}

