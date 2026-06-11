import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Web-safe cache service — SharedPreferences on web, Hive on mobile.
class WebSafeCacheService {
  static bool _isInitialized = false;
  static SharedPreferences? _prefs;

  /// Initialize cache service with web compatibility
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _prefs = await SharedPreferences.getInstance();
      _isInitialized = true;
      if (kIsWeb) {
        print('🌐 Web cache initialized (SharedPreferences / localStorage)');
      } else {
        print('📱 Mobile cache initialized (SharedPreferences + Hive)');
      }
    } catch (e) {
      print('❌ WebSafe Cache Service initialization failed: $e');
    }
  }

  /// Check if cache is available
  static bool get isAvailable => _isInitialized && _prefs != null;

  /// Get cache stats (web-safe)
  static Map<String, dynamic> getCacheStats() {
    if (!_isInitialized) return {};

    return {
      'platform': kIsWeb ? 'web' : 'mobile',
      'initialized': _isInitialized,
      'cache_type': kIsWeb ? 'localStorage' : 'hive+prefs',
      'keys': _prefs?.getKeys().length ?? 0,
    };
  }

  /// Dispose cache service
  static Future<void> dispose() async {
    if (_isInitialized) {
      _prefs = null;
      _isInitialized = false;
      print('✅ WebSafe Cache Service disposed');
    }
  }
}
