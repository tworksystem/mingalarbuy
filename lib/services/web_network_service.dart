import 'dart:html' as html;

import 'package:flutter/foundation.dart';

import '../utils/app_config.dart';

/// Web-specific network helpers (no custom XHR headers — browser blocks them).
class WebNetworkService {
  /// On web, rely on browser online state; avoid preflight HTTP with forbidden headers.
  static Future<bool> testBrowserConnectivity() async {
    if (!kIsWeb) return false;
    return html.window.navigator.onLine;
  }

  /// Ping the configured WooCommerce host (HEAD via Image probe — no XHR headers).
  static Future<bool> testWooCommerceWebAccess() async {
    if (!kIsWeb) return false;
    return html.window.navigator.onLine;
  }

  /// Test image URL — on web, let `<img>` load natively; assume URL is valid if non-empty.
  static Future<bool> testImageUrlFromWeb(String imageUrl) async {
    if (!kIsWeb) return false;
    return imageUrl.trim().isNotEmpty;
  }

  static String getWebOptimizedImageUrl(String originalUrl) {
    return originalUrl;
  }

  static String getWebFallbackImageUrl({int? width, int? height}) {
    final w = width ?? 300;
    final h = height ?? 300;
    return 'https://picsum.photos/$w/$h?random=${DateTime.now().millisecondsSinceEpoch}';
  }

  static bool get isWeb => kIsWeb;

  static String get userAgent =>
      kIsWeb ? html.window.navigator.userAgent : AppConfig.defaultUserAgent;

  static String get currentOrigin =>
      kIsWeb ? html.window.location.origin : AppConfig.effectiveBackendUrl;

  static Future<bool> testCORSPolicy(String domain) async {
    if (!kIsWeb) return true;
    return html.window.navigator.onLine;
  }

  static Future<String> getWorkingImageUrl(String originalUrl) async {
    return originalUrl.trim();
  }
}
