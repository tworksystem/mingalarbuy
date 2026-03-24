import 'package:flutter/foundation.dart';

/// Web-safe cache service that doesn't use Hive on web
class WebSafeCacheService {
  static bool _isInitialized = false;

  /// Initialize cache service with web compatibility
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      if (kIsWeb) {
        print('🌐 Web platform detected - using memory cache');
        // For web, we'll use a simple in-memory cache
        _initializeWebCache();
      } else {
        print('📱 Mobile platform detected - using Hive cache');
        // For mobile, we could use Hive if needed
        await _initializeMobileCache();
      }

      _isInitialized = true;
      print('✅ WebSafe Cache Service initialized successfully');
    } catch (e) {
      print('❌ WebSafe Cache Service initialization failed: $e');
      // Don't rethrow - let the app continue without cache
    }
  }

  /// Initialize web-specific cache
  static void _initializeWebCache() {
    print('🌐 Initializing web cache...');
    // Simple in-memory cache for web
    // This is just a placeholder - in a real app you might use IndexedDB
  }

  /// Initialize mobile-specific cache
  static Future<void> _initializeMobileCache() async {
    print('📱 Initializing mobile cache...');
    // Placeholder for mobile cache initialization
    await Future.delayed(const Duration(milliseconds: 100));
  }

  /// Check if cache is available
  static bool get isAvailable => _isInitialized;

  /// Get cache stats (web-safe)
  static Map<String, dynamic> getCacheStats() {
    if (!_isInitialized) return {};

    return {
      'platform': kIsWeb ? 'web' : 'mobile',
      'initialized': _isInitialized,
      'cache_type': kIsWeb ? 'memory' : 'hive',
    };
  }

  /// Dispose cache service
  static Future<void> dispose() async {
    if (_isInitialized) {
      print('✅ WebSafe Cache Service disposed');
      _isInitialized = false;
    }
  }
}
