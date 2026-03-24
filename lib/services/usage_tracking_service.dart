import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../utils/app_config.dart';
import '../utils/logger.dart';
import '../utils/network_utils.dart';

/// Service for tracking app usage duration
/// Tracks when users open/close the app and calculates usage duration
class UsageTrackingService {
  static const String _sessionIdKey = 'usage_tracking_session_id';
  static const String _sessionStartKey = 'usage_tracking_session_start';
  static int? _currentSessionId;

  /// Get WooCommerce authentication query parameters
  static Map<String, String> _getWooCommerceAuthQueryParams() {
    return {
      'consumer_key': AppConfig.consumerKey,
      'consumer_secret': AppConfig.consumerSecret,
    };
  }

  /// Get device information
  static Future<String> _getDeviceInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return '${androidInfo.brand} ${androidInfo.model} (Android ${androidInfo.version.release})';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return '${iosInfo.name} ${iosInfo.model} (iOS ${iosInfo.systemVersion})';
      } else if (Platform.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo;
        return 'Windows ${windowsInfo.computerName}';
      } else if (Platform.isMacOS) {
        final macInfo = await deviceInfo.macOsInfo;
        return 'macOS ${macInfo.computerName}';
      } else if (Platform.isLinux) {
        final linuxInfo = await deviceInfo.linuxInfo;
        return 'Linux ${linuxInfo.prettyName}';
      }
      
      return 'Unknown Device';
    } catch (e) {
      Logger.warning('Failed to get device info: $e', tag: 'UsageTrackingService');
      return 'Unknown Device';
    }
  }

  /// Get app version
  static Future<String> _getAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return '${packageInfo.version} (${packageInfo.buildNumber})';
    } catch (e) {
      Logger.warning('Failed to get app version: $e', tag: 'UsageTrackingService');
      return 'Unknown';
    }
  }

  /// Start a usage tracking session
  /// Called when app opens or comes to foreground
  static Future<bool> startSession(String userId) async {
    try {
      // Check if we already have an active session
      final prefs = await SharedPreferences.getInstance();
      final savedSessionId = prefs.getInt(_sessionIdKey);
      final savedSessionStart = prefs.getString(_sessionStartKey);
      
        if (savedSessionId != null && savedSessionStart != null) {
          // Check if saved session is recent (within last 24 hours)
          final sessionStartTime = DateTime.parse(savedSessionStart);
          final hoursSinceStart = DateTime.now().difference(sessionStartTime).inHours;
          
          if (hoursSinceStart < 24) {
            // Use existing session
            _currentSessionId = savedSessionId;
            Logger.info(
              'Resuming existing session: $_currentSessionId',
              tag: 'UsageTrackingService',
            );
            return true;
          } else {
            // Session is too old, end it first
            await endSession(userId, savedSessionId);
          }
        }

      // Get device info and app version
      final deviceInfo = await _getDeviceInfo();
      final appVersion = await _getAppVersion();

      // Start new session
      final uri = Uri.parse(
        '${AppConfig.backendUrl}/wp-json/twork/v1/usage/start',
      ).replace(queryParameters: _getWooCommerceAuthQueryParams());

      final body = json.encode({
        'user_id': int.tryParse(userId) ?? 0,
        'device_info': deviceInfo,
        'app_version': appVersion,
      });

      Logger.info(
        'Starting usage session for user: $userId',
        tag: 'UsageTrackingService',
      );
      
      final response = await NetworkUtils.executeRequest(
        () => http.post(
          uri,
          headers: const {
            'Content-Type': 'application/json',
          },
          body: body,
        ),
        context: 'startUsageSession',
      );

      if (NetworkUtils.isValidResponse(response)) {
        final data = json.decode(response!.body);
        
        if (data['success'] == true && data['data'] != null) {
          final sessionId = data['data']['session_id'] as int;
          final sessionStart = data['data']['session_start'] as String;
          
          // Store session info locally
          _currentSessionId = sessionId;
          
          await prefs.setInt(_sessionIdKey, sessionId);
          await prefs.setString(_sessionStartKey, sessionStart);
          
          Logger.info(
            'Usage session started successfully: Session ID: $sessionId, User ID: $userId',
            tag: 'UsageTrackingService',
          );
          return true;
        } else {
          Logger.warning(
            'API returned success=false. Response: ${response?.body ?? 'null'}',
            tag: 'UsageTrackingService',
          );
        }
      } else {
        Logger.warning(
          'Failed to start usage session. Status: ${response?.statusCode}, Body: ${response?.body}',
          tag: 'UsageTrackingService',
        );
      }
      
      return false;
    } catch (e, stackTrace) {
      Logger.error(
        'Error starting usage session: $e',
        tag: 'UsageTrackingService',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// End a usage tracking session
  /// Called when app closes or goes to background
  static Future<bool> endSession(String userId, [int? sessionId]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Use provided session ID or get from storage
      final sessionIdToEnd = sessionId ?? 
                            _currentSessionId ?? 
                            prefs.getInt(_sessionIdKey);
      
      if (sessionIdToEnd == null) {
        Logger.info(
          'No active session to end',
          tag: 'UsageTrackingService',
        );
        return false;
      }

      Logger.info(
        'Ending usage session for user: $userId, Session ID: $sessionIdToEnd',
        tag: 'UsageTrackingService',
      );
      
      // End session via API
      final uri = Uri.parse(
        '${AppConfig.backendUrl}/wp-json/twork/v1/usage/end',
      ).replace(queryParameters: _getWooCommerceAuthQueryParams());

      final body = json.encode({
        'user_id': int.tryParse(userId) ?? 0,
        'session_id': sessionIdToEnd,
      });

      final response = await NetworkUtils.executeRequest(
        () => http.post(
          uri,
          headers: const {
            'Content-Type': 'application/json',
          },
          body: body,
        ),
        context: 'endUsageSession',
      );

      if (NetworkUtils.isValidResponse(response)) {
        final data = json.decode(response!.body);
        
        if (data['success'] == true && data['data'] != null) {
          final duration = data['data']['duration_seconds'] as int? ?? 0;
          final durationFormatted = data['data']['duration_formatted'] as String? ?? '0:00:00';
          
          Logger.info(
            'Usage session ended successfully: Session ID: $sessionIdToEnd, Duration: $durationFormatted ($duration seconds)',
            tag: 'UsageTrackingService',
          );
          
          // Clear session info
          _currentSessionId = null;
          await prefs.remove(_sessionIdKey);
          await prefs.remove(_sessionStartKey);
          
          return true;
        } else {
          Logger.warning(
            'API returned success=false. Response: ${response?.body ?? 'null'}',
            tag: 'UsageTrackingService',
          );
        }
      } else {
        Logger.warning(
          'Failed to end usage session. Status: ${response?.statusCode}, Body: ${response?.body}',
          tag: 'UsageTrackingService',
        );
      }
      
      // Even if API call fails, clear local session to prevent stale sessions
      _currentSessionId = null;
      await prefs.remove(_sessionIdKey);
      await prefs.remove(_sessionStartKey);
      
      return false;
    } catch (e, stackTrace) {
      Logger.error(
        'Error ending usage session: $e',
        tag: 'UsageTrackingService',
        error: e,
        stackTrace: stackTrace,
      );
      
      // Clear session even on error
      final prefs = await SharedPreferences.getInstance();
      _currentSessionId = null;
      await prefs.remove(_sessionIdKey);
      await prefs.remove(_sessionStartKey);
      
      return false;
    }
  }

  /// Get usage statistics for a user
  static Future<Map<String, dynamic>?> getUsageStats(String userId) async {
    try {
      final uri = Uri.parse(
        '${AppConfig.backendUrl}/wp-json/twork/v1/usage/stats/$userId',
      ).replace(queryParameters: _getWooCommerceAuthQueryParams());

      final response = await NetworkUtils.executeRequest(
        () => http.get(
          uri,
          headers: const {
            'Content-Type': 'application/json',
          },
        ),
        context: 'getUsageStats',
      );

      if (NetworkUtils.isValidResponse(response)) {
        final data = json.decode(response!.body);
        
        if (data['success'] == true && data['data'] != null) {
          return data['data'] as Map<String, dynamic>;
        }
      }

      return null;
    } catch (e, stackTrace) {
      Logger.error(
        'Error getting usage stats: $e',
        tag: 'UsageTrackingService',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Get current active session ID
  static int? getCurrentSessionId() {
    return _currentSessionId;
  }

  /// Clear any stale sessions (called on app start)
  static Future<void> clearStaleSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedSessionStart = prefs.getString(_sessionStartKey);
      
      if (savedSessionStart != null) {
        final sessionStartTime = DateTime.parse(savedSessionStart);
        final hoursSinceStart = DateTime.now().difference(sessionStartTime).inHours;
        
        // If session is older than 24 hours, clear it
        if (hoursSinceStart >= 24) {
          _currentSessionId = null;
          await prefs.remove(_sessionIdKey);
          await prefs.remove(_sessionStartKey);
          
          Logger.info(
            'Cleared stale session (older than 24 hours)',
            tag: 'UsageTrackingService',
          );
        }
      }
    } catch (e) {
      Logger.warning(
        'Error clearing stale sessions: $e',
        tag: 'UsageTrackingService',
      );
    }
  }
}

