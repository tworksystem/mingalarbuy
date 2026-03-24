import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/app_config.dart';
import '../utils/logger.dart';
import '../utils/network_utils.dart';

/// App Update Information Model
class AppUpdateInfo {
  final bool enabled;
  final String updateLink;
  final String version;

  AppUpdateInfo({
    required this.enabled,
    required this.updateLink,
    required this.version,
  });

  bool get hasUpdate => enabled && updateLink.isNotEmpty;
}

/// Service for handling app update information from backend
class AppUpdateService {
  /// Cache for app update info (fetched from backend)
  static AppUpdateInfo? _cachedUpdateInfo;
  static DateTime? _cacheTimestamp;
  static const Duration _cacheDuration =
      Duration(minutes: 5); // Cache for 5 minutes

  /// Get WooCommerce auth query parameters
  static Map<String, String> _getWooCommerceAuthQueryParams() {
    return {
      'consumer_key': AppConfig.consumerKey,
      'consumer_secret': AppConfig.consumerSecret,
    };
  }

  /// Clear cache for app update info
  /// Call this when backend updates the settings to force refresh
  static void clearCache() {
    _cachedUpdateInfo = null;
    _cacheTimestamp = null;
    Logger.info(
      'Cleared app update info cache',
      tag: 'AppUpdateService',
    );
  }

  /// Get app update information from backend
  /// Returns cached value if available and not expired
  /// forceRefresh: If true, bypasses cache and fetches fresh data
  static Future<AppUpdateInfo> getUpdateInfo(
      {bool forceRefresh = false}) async {
    // Return cached value if available and not expired
    if (!forceRefresh &&
        _cachedUpdateInfo != null &&
        _cacheTimestamp != null &&
        DateTime.now().difference(_cacheTimestamp!) < _cacheDuration) {
      return _cachedUpdateInfo!;
    }

    try {
      final uri = Uri.parse(
        '${AppConfig.backendUrl}/wp-json/twork/v1/app/update-settings',
      ).replace(queryParameters: _getWooCommerceAuthQueryParams());

      final response = await NetworkUtils.executeRequest(
        () => http.get(
          uri,
          headers: const {
            'Content-Type': 'application/json',
          },
        ),
        context: 'getUpdateInfo',
      );

      if (NetworkUtils.isValidResponse(response)) {
        final data = json.decode(response!.body) as Map<String, dynamic>;
        if (data['success'] == true && data['data'] != null) {
          final settings = data['data'] as Map<String, dynamic>;
          final updateInfo = AppUpdateInfo(
            enabled: (settings['enabled'] as bool?) ?? false,
            updateLink: (settings['update_link'] as String?) ?? '',
            version: (settings['version'] as String?) ?? '',
          );

          // Cache the value
          _cachedUpdateInfo = updateInfo;
          _cacheTimestamp = DateTime.now();

          Logger.info(
            'Fetched app update info: enabled=${updateInfo.enabled}, hasLink=${updateInfo.updateLink.isNotEmpty}',
            tag: 'AppUpdateService',
          );

          return updateInfo;
        }
      }

      // If API call fails, return default (no update)
      Logger.warning(
        'Failed to fetch app update info from backend, using default (no update)',
        tag: 'AppUpdateService',
      );
      _cachedUpdateInfo = AppUpdateInfo(
        enabled: false,
        updateLink: '',
        version: '',
      );
      _cacheTimestamp = DateTime.now();
      return _cachedUpdateInfo!;
    } catch (e, stackTrace) {
      Logger.error(
        'Error fetching app update info: $e',
        tag: 'AppUpdateService',
        error: e,
        stackTrace: stackTrace,
      );
      // Return default on error
      _cachedUpdateInfo = AppUpdateInfo(
        enabled: false,
        updateLink: '',
        version: '',
      );
      _cacheTimestamp = DateTime.now();
      return _cachedUpdateInfo!;
    }
  }
}
