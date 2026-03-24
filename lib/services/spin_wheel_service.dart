import 'dart:convert';

import 'package:http/http.dart' as http;

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

      final response = await NetworkUtils.executeRequest(
        () =>
            http.get(uri, headers: const {'Content-Type': 'application/json'}),
        context: 'luckybox.getConfig',
      );

      if (!NetworkUtils.isValidResponse(response)) return null;

      final data = json.decode(response!.body) as Map<String, dynamic>;

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

      final response = await NetworkUtils.executeRequest(
        () => http.post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: json.encode({'user_id': int.tryParse(userId) ?? 0}),
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

      if (!NetworkUtils.isValidResponse(response)) {
        Logger.error('Invalid response status: ${response.statusCode}',
            tag: 'SpinWheelService');
        Logger.error('Response body: ${response.body}',
            tag: 'SpinWheelService');

        // Try to extract error message from response body
        try {
          final errorData = json.decode(response.body) as Map<String, dynamic>;
          _lastError = errorData['message'] ??
              'Server error occurred. Please try again.';
        } catch (e) {
          _lastError =
              'Server error (${response.statusCode}). Please try again.';
        }
        return false;
      }

      try {
        final data = json.decode(response.body) as Map<String, dynamic>;
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
        Logger.error('Response body: ${response.body}',
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

      final response = await NetworkUtils.executeRequest(
        () =>
            http.get(uri, headers: const {'Content-Type': 'application/json'}),
        context: 'luckybox.banner',
      );

      if (!NetworkUtils.isValidResponse(response)) return null;

      final data = json.decode(response!.body) as Map<String, dynamic>;

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
