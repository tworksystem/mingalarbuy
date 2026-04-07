import 'package:dio/dio.dart';

import '../api_service.dart';
import '../utils/app_config.dart';
import '../utils/logger.dart';
import '../utils/network_utils.dart';

/// Service for handling reward and points exchange requests
class RewardExchangeService {
  /// Cache for minimum exchange points (fetched from backend)
  /// NOTE: This cache is used as fallback. ExchangeSettingsProvider is the primary source.
  static int? _cachedMinExchangePoints;
  static DateTime? _cacheTimestamp;
  static const Duration _cacheDuration =
      Duration(seconds: 30); // Reduced cache duration for real-time updates

  /// Request throttling to prevent duplicate/subsequent requests
  /// Key: userId, Value: last request timestamp
  static final Map<String, DateTime> _lastRequestTimestamps = {};
  static const Duration _throttleDuration =
      Duration(seconds: 3); // Prevent requests within 3 seconds

  /// Get WooCommerce auth query parameters
  static Map<String, String> _getWooCommerceAuthQueryParams() {
    return {
      'consumer_key': AppConfig.consumerKey,
      'consumer_secret': AppConfig.consumerSecret,
    };
  }

  /// Clear cache for minimum exchange points
  /// Call this when backend updates the limit to force refresh
  static void clearMinExchangePointsCache() {
    _cachedMinExchangePoints = null;
    _cacheTimestamp = null;
    Logger.info(
      'Cleared minimum exchange points cache',
      tag: 'RewardExchangeService',
    );
  }

  /// Get minimum exchange points from backend
  /// Returns cached value if available and not expired
  /// forceRefresh: If true, bypasses cache and fetches fresh data
  static Future<int> getMinExchangePoints({bool forceRefresh = false}) async {
    // Return cached value if available and not expired
    if (!forceRefresh &&
        _cachedMinExchangePoints != null &&
        _cacheTimestamp != null &&
        DateTime.now().difference(_cacheTimestamp!) < _cacheDuration) {
      return _cachedMinExchangePoints!;
    }

    try {
      final uri = Uri.parse(
        '${AppConfig.backendUrl}/wp-json/twork/v1/rewards/exchange-settings',
      ).replace(queryParameters: _getWooCommerceAuthQueryParams());

      final Response<dynamic>? response = await ApiService.executeWithRetry(
        () => ApiService.get(
          uri.path,
          queryParameters: uri.queryParameters,
          skipAuth: false,
          headers: const <String, dynamic>{
            'Content-Type': 'application/json',
          },
        ),
        context: 'getMinExchangePoints',
      );

      if (NetworkUtils.isValidDioResponse(response)) {
        final Map<String, dynamic>? data = ApiService.responseAsJsonMap(response);
        if (data == null) {
          Logger.warning(
            'Failed to fetch minimum exchange points from backend, using default: 100',
            tag: 'RewardExchangeService',
          );
          _cachedMinExchangePoints = 100;
          _cacheTimestamp = DateTime.now();
          return 100;
        }
        if (data['success'] == true && data['data'] != null) {
          final settings = data['data'] as Map<String, dynamic>;
          final minPoints =
              (settings['min_exchange_points'] as num?)?.toInt() ?? 100;

          // Cache the value
          _cachedMinExchangePoints = minPoints;
          _cacheTimestamp = DateTime.now();

          Logger.info(
            'Fetched minimum exchange points: $minPoints',
            tag: 'RewardExchangeService',
          );

          return minPoints;
        }
      }

      // If API call fails, use default and cache it
      Logger.warning(
        'Failed to fetch minimum exchange points from backend, using default: 100',
        tag: 'RewardExchangeService',
      );
      _cachedMinExchangePoints = 100;
      _cacheTimestamp = DateTime.now();
      return 100;
    } catch (e, stackTrace) {
      Logger.error(
        'Error fetching minimum exchange points: $e',
        tag: 'RewardExchangeService',
        error: e,
        stackTrace: stackTrace,
      );
      // Return default on error
      _cachedMinExchangePoints = 100;
      _cacheTimestamp = DateTime.now();
      return 100;
    }
  }

  /// Create a reward exchange request
  static Future<bool> createRewardExchangeRequest({
    required String userId,
    required String rewardValue,
    required String phone,
    String? note,
  }) async {
    // PROFESSIONAL: Request throttling to prevent duplicate requests
    final now = DateTime.now();
    final lastRequestTime = _lastRequestTimestamps[userId];
    if (lastRequestTime != null) {
      final timeSinceLastRequest = now.difference(lastRequestTime);
      if (timeSinceLastRequest < _throttleDuration) {
        Logger.warning(
          'Exchange request throttled: Last request was ${timeSinceLastRequest.inMilliseconds}ms ago (minimum ${_throttleDuration.inSeconds}s required). User: $userId',
          tag: 'RewardExchangeService',
        );
        return false;
      }
    }
    _lastRequestTimestamps[userId] = now;

    try {
      final uri = Uri.parse(
        '${AppConfig.backendUrl}/wp-json/twork/v1/rewards/exchange-request',
      ).replace(queryParameters: _getWooCommerceAuthQueryParams());

      final Map<String, dynamic> body = <String, dynamic>{
        'user_id': int.tryParse(userId) ?? 0,
        'type': 'rewards',
        'reward_value': rewardValue,
        'phone': phone,
        if (note != null && note.isNotEmpty) 'note': note,
      };

      final Response<dynamic>? response = await ApiService.executeWithRetry(
        () => ApiService.post(
          uri.path,
          queryParameters: uri.queryParameters,
          skipAuth: false,
          headers: const <String, dynamic>{
            'Content-Type': 'application/json',
          },
          data: body,
        ),
        context: 'createRewardExchangeRequest',
      );

      if (!NetworkUtils.isValidDioResponse(response)) {
        final String errorBody = ApiService.responseBodyString(response);
        Logger.warning(
          'Failed to submit reward exchange request. Status: ${response?.statusCode}, Body: ${errorBody.isEmpty ? 'No response body' : errorBody}',
          tag: 'RewardExchangeService',
        );
        return false;
      }

      final String responseBody = ApiService.responseBodyString(response);
      Logger.info(
        'Reward exchange API response: $responseBody',
        tag: 'RewardExchangeService',
      );

      final Map<String, dynamic>? data = ApiService.responseAsJsonMap(response);
      if (data == null) {
        Logger.warning(
          'Reward exchange: invalid JSON response',
          tag: 'RewardExchangeService',
        );
        return false;
      }
      final success = data['success'] == true;

      if (success) {
        Logger.info(
          'Reward exchange request submitted for $rewardValue',
          tag: 'RewardExchangeService',
        );
      } else {
        final errorMessage = data['message']?.toString() ?? 'Unknown error';
        Logger.warning(
          'Reward exchange request API responded without success flag. Message: $errorMessage, Response: $responseBody',
          tag: 'RewardExchangeService',
        );
      }

      return success;
    } catch (e, stackTrace) {
      Logger.error(
        'Error submitting reward exchange request: $e',
        tag: 'RewardExchangeService',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Create a points exchange request
  static Future<bool> createPointExchangeRequest({
    required String userId,
    required String pointsValue,
    required String phone,
    String? note,
  }) async {
    // PROFESSIONAL: Request throttling to prevent duplicate requests
    final now = DateTime.now();
    final lastRequestTime = _lastRequestTimestamps[userId];
    if (lastRequestTime != null) {
      final timeSinceLastRequest = now.difference(lastRequestTime);
      if (timeSinceLastRequest < _throttleDuration) {
        Logger.warning(
          'Exchange request throttled: Last request was ${timeSinceLastRequest.inMilliseconds}ms ago (minimum ${_throttleDuration.inSeconds}s required). User: $userId',
          tag: 'RewardExchangeService',
        );
        return false;
      }
    }
    _lastRequestTimestamps[userId] = now;

    try {
      final uri = Uri.parse(
        '${AppConfig.backendUrl}/wp-json/twork/v1/rewards/exchange-request',
      ).replace(queryParameters: _getWooCommerceAuthQueryParams());

      final Map<String, dynamic> body = <String, dynamic>{
        'user_id': int.tryParse(userId) ?? 0,
        'type': 'points',
        'points_value': pointsValue,
        'phone': phone,
        if (note != null && note.isNotEmpty) 'note': note,
      };

      final Response<dynamic>? response = await ApiService.executeWithRetry(
        () => ApiService.post(
          uri.path,
          queryParameters: uri.queryParameters,
          skipAuth: false,
          headers: const <String, dynamic>{
            'Content-Type': 'application/json',
          },
          data: body,
        ),
        context: 'createPointExchangeRequest',
      );

      if (!NetworkUtils.isValidDioResponse(response)) {
        final String errorBody = ApiService.responseBodyString(response);
        Logger.warning(
          'Failed to submit point exchange request. Status: ${response?.statusCode}, Body: ${errorBody.isEmpty ? 'No response body' : errorBody}',
          tag: 'RewardExchangeService',
        );
        return false;
      }

      final String responseBody = ApiService.responseBodyString(response);
      Logger.info(
        'Point exchange API response: $responseBody',
        tag: 'RewardExchangeService',
      );

      final Map<String, dynamic>? data = ApiService.responseAsJsonMap(response);
      if (data == null) {
        Logger.warning(
          'Point exchange: invalid JSON response',
          tag: 'RewardExchangeService',
        );
        return false;
      }
      final success = data['success'] == true;

      if (success) {
        Logger.info(
          'Point exchange request submitted for $pointsValue',
          tag: 'RewardExchangeService',
        );
      } else {
        final errorMessage = data['message']?.toString() ?? 'Unknown error';
        Logger.warning(
          'Point exchange request API responded without success flag. Message: $errorMessage, Response: $responseBody',
          tag: 'RewardExchangeService',
        );
      }

      return success;
    } catch (e, stackTrace) {
      Logger.error(
        'Error submitting point exchange request: $e',
        tag: 'RewardExchangeService',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }
}
