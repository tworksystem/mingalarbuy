import 'dart:html' as html;
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// Web-specific network service to handle CORS and connectivity issues
class WebNetworkService {
  static const Duration _timeout = Duration(seconds: 30);

  /// Test if the browser has internet connectivity
  static Future<bool> testBrowserConnectivity() async {
    if (!kIsWeb) return false;

    try {
      // Test with a reliable endpoint that supports CORS
      final response = await http.get(
        Uri.parse('https://httpbin.org/get'),
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'HomeAid-Flutter-App/1.0',
        },
      ).timeout(_timeout);

      final isConnected = response.statusCode == 200;
      print(
          '🌐 Browser connectivity test: ${isConnected ? "✅ Connected" : "❌ Failed"}');
      return isConnected;
    } catch (e) {
      print('❌ Browser connectivity test failed: $e');
      return false;
    }
  }

  /// Test WooCommerce server accessibility from web
  static Future<bool> testWooCommerceWebAccess() async {
    if (!kIsWeb) return false;

    try {
      // Use a CORS proxy or direct test
      final response = await http.get(
        Uri.parse('https://www.homeaid.com.mm'),
        headers: {
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'User-Agent': 'HomeAid-Flutter-App/1.0',
          'Accept-Language': 'en-US,en;q=0.5',
          'Accept-Encoding': 'gzip, deflate',
          'Connection': 'keep-alive',
        },
      ).timeout(_timeout);

      final isAccessible = response.statusCode == 200;
      print(
          '🌐 WooCommerce web access: ${isAccessible ? "✅ Accessible" : "❌ Failed"}');
      return isAccessible;
    } catch (e) {
      print('❌ WooCommerce web access failed: $e');
      return false;
    }
  }

  /// Test specific image URL from web browser
  static Future<bool> testImageUrlFromWeb(String imageUrl) async {
    if (!kIsWeb) return false;

    try {
      print('🖼️ Testing image URL from web: $imageUrl');

      final response = await http.head(
        Uri.parse(imageUrl),
        headers: {
          'Accept': 'image/*',
          'User-Agent': 'HomeAid-Flutter-App/1.0',
          'Accept-Encoding': 'gzip, deflate',
          'Connection': 'keep-alive',
          'Cache-Control': 'no-cache',
        },
      ).timeout(_timeout);

      final isAccessible = response.statusCode == 200;
      print(
          '🖼️ Image URL web test: ${isAccessible ? "✅ Accessible" : "❌ Failed"} (${response.statusCode})');

      if (isAccessible) {
        final contentType = response.headers['content-type'] ?? '';
        print('📊 Content-Type: $contentType');
      }

      return isAccessible;
    } catch (e) {
      print('❌ Image URL web test error: $e');
      return false;
    }
  }

  /// Get web-optimized image URL
  static String getWebOptimizedImageUrl(String originalUrl) {
    if (originalUrl.isEmpty) return originalUrl;

    try {
      final uri = Uri.parse(originalUrl);

      // For WordPress/WooCommerce images, add web optimization parameters
      if (uri.host.contains('homeaid.com.mm') &&
          uri.path.contains('wp-content/uploads')) {
        // Add WordPress image optimization parameters
        final queryParams = <String, String>{
          'w': '400', // Width
          'h': '400', // Height
          'fit': 'cover', // Fit mode
          'q': '80', // Quality
        };

        return uri.replace(queryParameters: queryParams).toString();
      }

      return originalUrl;
    } catch (e) {
      print('❌ Error optimizing web image URL: $e');
      return originalUrl;
    }
  }

  /// Get web-safe fallback image URL
  static String getWebFallbackImageUrl({int? width, int? height}) {
    final w = width ?? 300;
    final h = height ?? 300;

    // Use a reliable CDN that supports CORS
    return 'https://picsum.photos/$w/$h?random=${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Check if running on web platform
  static bool get isWeb => kIsWeb;

  /// Get user agent string for web requests
  static String get userAgent =>
      kIsWeb ? html.window.navigator.userAgent : 'HomeAid-Flutter-App/1.0';

  /// Test CORS policy for specific domain
  static Future<bool> testCORSPolicy(String domain) async {
    if (!kIsWeb) return true; // Assume CORS is not an issue on mobile

    try {
      final testUrl = 'https://$domain/wp-json/wp/v2/';
      final response = await http.get(
        Uri.parse(testUrl),
        headers: {
          'Origin': html.window.location.origin,
          'User-Agent': userAgent,
        },
      ).timeout(_timeout);

      final hasCORS =
          response.headers.containsKey('access-control-allow-origin');
      print(
          '🌐 CORS policy for $domain: ${hasCORS ? "✅ Allowed" : "❌ Restricted"}');
      return hasCORS;
    } catch (e) {
      print('❌ CORS test failed for $domain: $e');
      return false;
    }
  }

  /// Get current web page origin
  static String get currentOrigin =>
      kIsWeb ? html.window.location.origin : 'unknown';

  /// Test multiple fallback image sources
  static Future<String> getWorkingImageUrl(String originalUrl) async {
    final urlsToTest = [
      originalUrl,
      getWebOptimizedImageUrl(originalUrl),
      getWebFallbackImageUrl(),
      'https://via.placeholder.com/400x400/cccccc/666666?text=No+Image',
    ];

    for (final url in urlsToTest) {
      try {
        final isWorking = await testImageUrlFromWeb(url);
        if (isWorking) {
          print('✅ Found working image URL: $url');
          return url;
        }
      } catch (e) {
        print('❌ URL test failed: $url - $e');
        continue;
      }
    }

    // Return the last fallback if all fail
    return urlsToTest.last;
  }
}
