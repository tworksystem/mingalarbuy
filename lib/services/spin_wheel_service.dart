import 'package:dio/dio.dart';

import '../api_service.dart';
import '../utils/app_config.dart';
import '../utils/logger.dart';
import '../utils/network_utils.dart';

class SpinWheelConfig {
  final bool enabled;
  final bool hasPending;
  final bool canOpen;

  const SpinWheelConfig({
    required this.enabled,
    required this.hasPending,
    required this.canOpen,
  });

  factory SpinWheelConfig.fromJson(Map<String, dynamic> json) {
    // Handle boolean values - WordPress might return 1/0 or true/false
    final enabledValue = json['enabled'];
    final enabled =
        enabledValue == true || enabledValue == 1 || enabledValue == '1';

    final hasPendingValue = json['has_pending'];
    final hasPending = hasPendingValue == true ||
        hasPendingValue == 1 ||
        hasPendingValue == '1';

    final canOpenValue = json['can_open'];
    final canOpen =
        canOpenValue == true || canOpenValue == 1 || canOpenValue == '1';

    return SpinWheelConfig(
      enabled: enabled,
      hasPending: hasPending,
      canOpen: canOpen,
    );
  }
}

class SpinWheelService {
  static String? _lastError;

  static String? get lastError => _lastError;

  static Map<String, String> _getWooCommerceAuthQueryParams() {
    return {
      'consumer_key': AppConfig.consumerKey,
      'consumer_secret': AppConfig.consumerSecret,
    };
  }

  static Future<SpinWheelConfig?> getConfig({required String userId}) async {
    try {
      final uri = Uri.parse(
        '${AppConfig.backendUrl}/wp-json/twork/v1/luckybox/config/$userId',
      ).replace(queryParameters: _getWooCommerceAuthQueryParams());

      final Response<dynamic>? response = await ApiService.executeWithRetry(
        () => ApiService.get(
          uri.path,
          queryParameters: uri.queryParameters,
          skipAuth: false,
          headers: const <String, dynamic>{'Content-Type': 'application/json'},
        ),
        context: 'luckybox.getConfig',
      );

      if (!NetworkUtils.isValidDioResponse(response)) return null;

      final Map<String, dynamic>? data = ApiService.responseAsJsonMap(response);
      if (data == null) return null;

      // Handle WordPress REST API response format
      // Response might be wrapped in 'data' or directly contain the fields
      final configData = data.containsKey('data') ? data['data'] : data;

      // Ensure we have the required fields
      if (configData is! Map<String, dynamic>) {
        Logger.error('Invalid Lucky Box config response format',
            tag: 'SpinWheelService');
        return null;
      }

      // Log for debugging
      Logger.debug('Lucky Box config response: $configData',
          tag: 'SpinWheelService');

      return SpinWheelConfig.fromJson(configData);
    } catch (e, stackTrace) {
      Logger.error('Error loading spin wheel config: $e',
          tag: 'SpinWheelService', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  /// Creates a pending transaction on the backend. Admin will later approve and set reward.
  static Future<bool> openLuckyBox({required String userId}) async {
    try {
      final uri =
          Uri.parse('${AppConfig.backendUrl}/wp-json/twork/v1/luckybox/open')
              .replace(queryParameters: _getWooCommerceAuthQueryParams());

      Logger.debug('Opening Lucky Box for user: $userId',
          tag: 'SpinWheelService');

      final Response<dynamic>? response = await ApiService.executeWithRetry(
        () => ApiService.post(
          uri.path,
          queryParameters: uri.queryParameters,
          skipAuth: false,
          headers: const <String, dynamic>{'Content-Type': 'application/json'},
          data: <String, dynamic>{'user_id': int.tryParse(userId) ?? 0},
        ),
        context: 'luckybox.open',
      );

      if (response == null) {
        Logger.error('Network request failed - no response',
            tag: 'SpinWheelService');
        _lastError =
            'Network connection failed. Please check your internet connection.';
        return false;
      }

      if (!NetworkUtils.isValidDioResponse(response)) {
        Logger.error('Invalid response status: ${response.statusCode}',
            tag: 'SpinWheelService');
        final String bodyStr = ApiService.responseBodyString(response);
        Logger.error('Response body: $bodyStr',
            tag: 'SpinWheelService');

        try {
          final Map<String, dynamic>? errorData =
              ApiService.responseAsJsonMap(response);
          _lastError = errorData?['message']?.toString() ??
              'Server error occurred. Please try again.';
        } catch (e) {
          _lastError =
              'Server error (${response.statusCode}). Please try again.';
        }
        return false;
      }

      try {
        final Map<String, dynamic>? data = ApiService.responseAsJsonMap(response);
        if (data == null) {
          throw const FormatException('Not JSON');
        }
        final success = data['success'] == true;

        if (!success) {
          final message = data['message'] ?? 'Unknown error';
          Logger.error('Lucky Box open failed: $message',
              tag: 'SpinWheelService');
          // Store error message in a static variable for provider to access
          _lastError = message;
        } else {
          Logger.info('Lucky Box opened successfully for user: $userId',
              tag: 'SpinWheelService');
          _lastError = null;
        }

        return success;
      } catch (e) {
        Logger.error('Error parsing response body: $e',
            tag: 'SpinWheelService');
        Logger.error('Response body: ${ApiService.responseBodyString(response)}',
            tag: 'SpinWheelService');
        _lastError = 'Failed to parse server response';
        return false;
      }
    } catch (e, stackTrace) {
      Logger.error('Error opening lucky box: $e',
          tag: 'SpinWheelService', error: e, stackTrace: stackTrace);
      _lastError = 'Network error occurred. Please try again.';
      return false;
    }
  }

  /// Get Lucky Box Banner Content
  static Future<LuckyBoxBanner?> getBanner() async {
    try {
      final uri =
          Uri.parse('${AppConfig.backendUrl}/wp-json/twork/v1/luckybox/banner')
              .replace(queryParameters: _getWooCommerceAuthQueryParams());

      Logger.debug('Fetching Lucky Box banner', tag: 'SpinWheelService');

      final Response<dynamic>? response = await ApiService.executeWithRetry(
        () => ApiService.get(
          uri.path,
          queryParameters: uri.queryParameters,
          skipAuth: false,
          headers: const <String, dynamic>{'Content-Type': 'application/json'},
        ),
        context: 'luckybox.banner',
      );

      if (!NetworkUtils.isValidDioResponse(response)) return null;

      final Map<String, dynamic>? data = ApiService.responseAsJsonMap(response);
      if (data == null) return null;

      // Handle WordPress REST API response format
      final bannerData = data.containsKey('data') ? data['data'] : data;

      if (bannerData is! Map<String, dynamic>) {
        Logger.error('Invalid Lucky Box banner response format',
            tag: 'SpinWheelService');
        return null;
      }

      return LuckyBoxBanner.fromJson(bannerData);
    } catch (e, stackTrace) {
      Logger.error('Error loading lucky box banner: $e',
          tag: 'SpinWheelService', error: e, stackTrace: stackTrace);
      return null;
    }
  }
}

class LuckyBoxBanner {
  final bool hasBanner;
  final String content;

  const LuckyBoxBanner({
    required this.hasBanner,
    required this.content,
  });

  factory LuckyBoxBanner.fromJson(Map<String, dynamic> json) {
    return LuckyBoxBanner(
      hasBanner: json['has_banner'] == true,
      content: json['content'] ?? '',
    );
  }
}
