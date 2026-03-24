import 'package:http/http.dart' as http;

/// Stub implementation for non-web platforms
class WebNetworkService {
  static const Duration _timeout = Duration(seconds: 30);

  static Future<bool> testBrowserConnectivity() async {
    // Non-web platforms don't need browser connectivity test
    return false;
  }

  static Future<bool> testWooCommerceWebAccess() async {
    // Non-web platforms use native network
    return false;
  }

  static Future<bool> testImageUrlFromWeb(String imageUrl) async {
    // Non-web platforms use native network
    return true;
  }

  static String getWebOptimizedImageUrl(String originalUrl) {
    return originalUrl;
  }

  static String getWebFallbackImageUrl({int? width, int? height}) {
    final w = width ?? 300;
    final h = height ?? 300;
    return 'https://picsum.photos/$w/$h?random=${DateTime.now().millisecondsSinceEpoch}';
  }

  static bool get isWeb => false;

  static String get userAgent => 'HomeAid-Flutter-App/1.0';

  static String get currentOrigin => 'unknown';

  static Future<bool> testCORSPolicy(String domain) async {
    return true; // Non-web platforms don't have CORS
  }

  static Future<String> getWorkingImageUrl(String originalUrl) async {
    // Non-web platforms just return the original URL
    return originalUrl;
  }

  static Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    return http
        .get(
          url,
          headers: headers,
        )
        .timeout(timeout ?? _timeout);
  }

  static Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    return http
        .post(
          url,
          headers: headers,
          body: body,
        )
        .timeout(timeout ?? _timeout);
  }

  static String getUserAgent() {
    return userAgent;
  }

  static Map<String, String> getWebHeaders(Map<String, String>? headers) {
    return headers ?? {};
  }

  static String getOrigin() {
    return currentOrigin;
  }

  static bool checkCorsSupport() {
    return true; // Non-web platforms don't have CORS
  }

  static void setupCorsHeaders() {
    // No-op on non-web platforms
  }

  static Future<void> testNetworkStack() async {
    // No-op on non-web platforms
  }

  static Future<bool> testServerAccessibility(String url) async {
    try {
      final response = await http.get(Uri.parse(url)).timeout(_timeout);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
