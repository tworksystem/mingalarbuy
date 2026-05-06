import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:workmanager/workmanager.dart';
import 'package:ecommerce_int2/providers/order_provider.dart';
import 'package:ecommerce_int2/services/auth_service.dart';
import 'package:ecommerce_int2/utils/app_config.dart';
import 'package:ecommerce_int2/utils/logger.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Background service for periodic order checking using Workmanager
class BackgroundService {
  static const String _taskName = 'orderCheckTask';
  static const String _autoRunPollTaskName = 'autoRunPollTickTask';
  static const String _autoRunPollOneOffTaskName = 'autoRunPollOneOffTickTask';
  static bool _isInitialized = false;

  /// Initialize Workmanager with callback configuration
  static Future<void> initialize() async {
    if (_isInitialized) {
      Logger.info('Background service already initialized',
          tag: 'BackgroundService');
      return;
    }

    try {
      // Old Code:
      // Initialize Workmanager with callback dispatcher
      // await Workmanager().initialize(
      //   callbackDispatcher,
      // );
      //
      // New Code:
      // Use explicit top-level entry-point that handles multiple background tasks
      // (order sync + auto-run poll server tick).
      await Workmanager().initialize(
        autoRunPollBackgroundEntryPoint,
      );

      _isInitialized = true;
      Logger.info('Background service initialized successfully',
          tag: 'BackgroundService');
    } catch (e, stackTrace) {
      Logger.error('Failed to initialize background service: $e',
          tag: 'BackgroundService', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Register periodic order checking task
  /// This will run every 5 minutes to check for order updates
  /// Note: Workmanager minimum interval is 15 minutes on most platforms,
  /// but we register it to run as often as possible
  static Future<bool> registerPeriodicTask() async {
    if (!_isInitialized) {
      Logger.warning('Background service not initialized. Initializing now...',
          tag: 'BackgroundService');
      await initialize();
    }

    try {
      // Cancel any existing task first
      await Workmanager().cancelByUniqueName(_taskName);
      await Workmanager().cancelByUniqueName(_autoRunPollTaskName);
      await Workmanager().cancelByUniqueName(_autoRunPollOneOffTaskName);

      // Register new periodic task
      // Note: frequency minimum is typically 15 minutes, but we set it to minimum
      await Workmanager().registerPeriodicTask(
        _taskName,
        _taskName,
        frequency: Duration(minutes: 15), // Minimum enforced by Workmanager
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
        initialDelay: Duration(seconds: 15), // Start sooner
      );

      // New Code:
      // Auto-run poll background tick task. This does NOT run client timers.
      // It only nudges backend `/poll/state/{id}` for active AUTO_RUN polls.
      await Workmanager().registerPeriodicTask(
        _autoRunPollTaskName,
        _autoRunPollTaskName,
        frequency: Duration(minutes: 15), // OS minimum interval
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
        initialDelay: Duration(seconds: 25),
      );

      Logger.info(
          'Periodic background tasks registered (order check + auto-run poll tick)',
          tag: 'BackgroundService');
      return true;
    } catch (e, stackTrace) {
      Logger.error('Failed to register periodic task: $e',
          tag: 'BackgroundService', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  /// Cancel periodic order checking task
  static Future<void> cancelPeriodicTask() async {
    try {
      await Workmanager().cancelByUniqueName(_taskName);
      await Workmanager().cancelByUniqueName(_autoRunPollTaskName);
      await Workmanager().cancelByUniqueName(_autoRunPollOneOffTaskName);
      Logger.info('Periodic order check task cancelled',
          tag: 'BackgroundService');
    } catch (e, stackTrace) {
      Logger.error('Failed to cancel periodic task: $e',
          tag: 'BackgroundService', error: e, stackTrace: stackTrace);
    }
  }

  /// Register one-off task for immediate order checking
  static Future<bool> registerOneOffTask() async {
    if (!_isInitialized) {
      Logger.warning('Background service not initialized. Initializing now...',
          tag: 'BackgroundService');
      await initialize();
    }

    try {
      await Workmanager().registerOneOffTask(
        'immediateOrderCheck',
        'immediateOrderCheck',
        inputData: {},
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
        initialDelay: Duration(seconds: 5),
      );

      Logger.info('One-off order check task registered successfully',
          tag: 'BackgroundService');
      return true;
    } catch (e, stackTrace) {
      Logger.error('Failed to register one-off task: $e',
          tag: 'BackgroundService', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  /// Schedule a one-off auto-run poll tick when app moves background/terminate.
  /// This is best-effort and complements periodic tasks; backend remains source of truth.
  static Future<bool> registerAutoRunPollOneOffTick(
      {Duration initialDelay = const Duration(seconds: 20)}) async {
    if (!_isInitialized) {
      Logger.warning('Background service not initialized. Initializing now...',
          tag: 'BackgroundService');
      await initialize();
    }

    try {
      // Old Code: no dedicated one-off scheduling for auto-run poll when app backgrounds.
      // New Code: replace prior pending one-off and request a near-term server tick.
      await Workmanager().registerOneOffTask(
        _autoRunPollOneOffTaskName,
        _autoRunPollTaskName,
        existingWorkPolicy: ExistingWorkPolicy.replace,
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
        initialDelay: initialDelay,
      );
      Logger.info('One-off auto-run poll tick registered',
          tag: 'BackgroundService');
      return true;
    } catch (e, stackTrace) {
      Logger.error('Failed to register one-off auto-run poll tick: $e',
          tag: 'BackgroundService', error: e, stackTrace: stackTrace);
      return false;
    }
  }
}

/// Old Code:
/// Callback dispatcher - This is the entry point for background tasks
/// @pragma('vm:entry-point')
/// void callbackDispatcher() {
///   Workmanager().executeTask((task, inputData) async {
///     ...
///   });
/// }
///
/// New Code:
/// Unified background entry point for Workmanager tasks.
@pragma('vm:entry-point')
void autoRunPollBackgroundEntryPoint() {
  Workmanager().executeTask((task, inputData) async {
    try {
      Logger.info('Background task started: $task', tag: 'BackgroundService');

      if (task == 'orderCheckTask' || task == 'immediateOrderCheck') {
        final ok = await _runOrderCheckTask();
        return Future.value(ok);
      }

      if (task == 'autoRunPollTickTask') {
        final ok = await _runAutoRunPollTickTask();
        return Future.value(ok);
      }

      Logger.warning('Unknown background task: $task',
          tag: 'BackgroundService');
      return Future.value(false);
    } catch (e, stackTrace) {
      Logger.error('Background task failed: $e',
          tag: 'BackgroundService', error: e, stackTrace: stackTrace);
      return Future.value(false);
    }
  });
}

Future<bool> _runOrderCheckTask() async {
  // Get stored user data from FlutterSecureStorage
  const FlutterSecureStorage secureStorage = FlutterSecureStorage();

  final userJson = await secureStorage.read(key: 'user_data');

  if (userJson == null) {
    Logger.warning('No user data found, skipping order check',
        tag: 'BackgroundService');
    return false;
  }

  final userData = json.decode(userJson) as Map<String, dynamic>;
  final userId = userData['id']?.toString();

  if (userId == null || userId.isEmpty || userId == '0') {
    Logger.warning('No valid user ID found, skipping order check',
        tag: 'BackgroundService');
    return false;
  }

  Logger.info('Checking orders for user: $userId', tag: 'BackgroundService');

  // Initialize providers and services
  final orderProvider = OrderProvider();
  // Notification disabled by user request (order notifications only).
  // final notificationService = NotificationService();
  // if (!notificationService.isInitialized) {
  //   await notificationService.initialize();
  // }

  // Wait for order provider to load from storage (constructor is async)
  // Poll until initialized to ensure orders are loaded
  int retries = 0;
  while (!orderProvider.isInitialized && retries < 20) {
    await Future.delayed(Duration(milliseconds: 100));
    retries++;
  }

  if (!orderProvider.isInitialized) {
    Logger.warning('OrderProvider failed to initialize after 2 seconds',
        tag: 'BackgroundService');
    return false;
  }

  // Now sync with WooCommerce - keep data sync, disable order notifications.
  await orderProvider.syncOrdersWithWooCommerce(
    userId,
    skipNotifications: true,
  );

  Logger.info('Background order check completed successfully',
      tag: 'BackgroundService');
  return true;
}

Future<bool> _runAutoRunPollTickTask() async {
  const FlutterSecureStorage secureStorage = FlutterSecureStorage();
  const String authTokenKey = 'auth_token';
  final userJson = await secureStorage.read(key: 'user_data');
  if (userJson == null) {
    Logger.warning('No user data found, skipping auto-run poll tick',
        tag: 'BackgroundService');
    return false;
  }

  final userData = json.decode(userJson) as Map<String, dynamic>;
  final userId = userData['id']?.toString();
  if (userId == null || userId.isEmpty || userId == '0') {
    Logger.warning('No valid user ID found, skipping auto-run poll tick',
        tag: 'BackgroundService');
    return false;
  }

  final token = await _resolveUsableBackgroundToken(
    secureStorage: secureStorage,
    authTokenKey: authTokenKey,
  );
  if (token == null || token.isEmpty) {
    Logger.warning(
      'No valid auth token found in secure storage, skipping auto-run poll tick',
      tag: 'BackgroundService',
    );
    return false;
  }
  final authContextHeaders =
      await _readOptionalBackgroundAuthContext(secureStorage);

  /*
  Old Code:
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 20),
    sendTimeout: const Duration(seconds: 20),
    headers: const {'Content-Type': 'application/json'},
  ));
  */
  // New Code: inject bearer token for background isolate requests.
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 20),
      headers: <String, dynamic>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
        ...authContextHeaders,
      },
      validateStatus: (status) => status != null && status >= 200 && status < 600,
    ),
  );

  try {
    final hasAuthHeader = token.isNotEmpty;
    /*
    Old Code:
    final feedUri = Uri.parse(
      '${AppConfig.backendUrl}/wp-json/twork/v1/engagement/feed/$userId',
    ).replace(queryParameters: _wooQueryParams());
    */
    final feedUri = _buildSignedUri('${AppConfig.tworkEngagementFeedPath}/$userId');
    _logRequestDiagnostics(
      scope: 'feed',
      uri: feedUri,
      hasAuthHeader: hasAuthHeader,
    );

    var feedRes = await dio.getUri(feedUri);
    if (feedRes.statusCode == 401 || feedRes.statusCode == 403) {
      Logger.warning(
        'Background poll tick unauthorized feed response: ${feedRes.statusCode}. '
        'Attempting silent token refresh before retry.',
        tag: 'BackgroundService',
      );
      final refreshedToken = await _resolveUsableBackgroundToken(
        secureStorage: secureStorage,
        authTokenKey: authTokenKey,
        previousToken: token,
      );
      if (refreshedToken == null || refreshedToken == token) {
        return false;
      }
      dio.options.headers['Authorization'] = 'Bearer $refreshedToken';
      feedRes = await dio.getUri(feedUri);
      if (feedRes.statusCode == 401 || feedRes.statusCode == 403) {
        return false;
      }
    }
    final feedData = feedRes.data;
    if (feedData is! Map || feedData['success'] != true) {
      Logger.warning('Background poll tick: feed response invalid',
          tag: 'BackgroundService');
      return false;
    }

    final rawItems = feedData['data'];
    if (rawItems is! List || rawItems.isEmpty) {
      Logger.info('Background poll tick: no engagement items',
          tag: 'BackgroundService');
      return true;
    }

    final Set<int> autoRunPollIds = <int>{};
    for (final item in rawItems) {
      if (item is! Map) continue;
      final itemType = (item['type'] ?? '').toString().toLowerCase();
      if (itemType != 'poll') continue;
      final scheduleRaw = item['poll_voting_schedule'];
      if (scheduleRaw is! Map) continue;
      final mode = (scheduleRaw['poll_mode'] ?? '').toString().toUpperCase();
      if (mode != 'AUTO_RUN') continue;
      final idVal = item['id'];
      final id = idVal is int ? idVal : int.tryParse(idVal.toString());
      if (id != null && id > 0) {
        autoRunPollIds.add(id);
      }
    }

    if (autoRunPollIds.isEmpty) {
      Logger.info('Background poll tick: no AUTO_RUN polls in feed',
          tag: 'BackgroundService');
      return true;
    }

    var successCount = 0;
    for (final pollId in autoRunPollIds) {
      /*
      Old Code:
      final stateUri = Uri.parse(
        '${AppConfig.backendUrl}/wp-json/twork/v1/poll/state/$pollId',
      ).replace(queryParameters: _wooQueryParams());
      */
      final stateUri = _buildSignedUri('${AppConfig.tworkPollStatePath}/$pollId');
      _logRequestDiagnostics(
        scope: 'state:$pollId',
        uri: stateUri,
        hasAuthHeader: hasAuthHeader,
      );

      try {
        final stateRes = await dio.getUri(stateUri);
        if (stateRes.statusCode == 401 || stateRes.statusCode == 403) {
          Logger.warning(
            'Background poll tick unauthorized state response for pollId=$pollId: '
            '${stateRes.statusCode}',
            tag: 'BackgroundService',
          );
          continue;
        }
        final stateData = stateRes.data;
        if (stateData is Map && stateData['success'] == true) {
          successCount++;
        }
      } catch (e) {
        Logger.warning('Background poll tick failed for pollId=$pollId: $e',
            tag: 'BackgroundService');
      }
    }

    Logger.info(
      'Background poll tick complete: polled=$successCount/${autoRunPollIds.length}',
      tag: 'BackgroundService',
    );
    return successCount > 0;
  } catch (e, stackTrace) {
    Logger.error('Background auto-run poll tick failed: $e',
        tag: 'BackgroundService', error: e, stackTrace: stackTrace);
    return false;
  } finally {
    dio.close(force: true);
  }
}

Uri _buildSignedUri(String path, [Map<String, dynamic>? extraQuery]) {
  final merged = <String, String>{
    ..._wooQueryParams(),
  };
  if (extraQuery != null) {
    for (final entry in extraQuery.entries) {
      final value = entry.value;
      if (value == null) continue;
      merged[entry.key] = value.toString();
    }
  }
  return Uri.parse('${AppConfig.backendUrl}$path').replace(queryParameters: merged);
}

void _logRequestDiagnostics({
  required String scope,
  required Uri uri,
  required bool hasAuthHeader,
}) {
  final hasConsumerKeyParam = uri.queryParameters.containsKey('consumer_key');
  final hasConsumerSecretParam =
      uri.queryParameters.containsKey('consumer_secret');
  Logger.info(
    'Background request diagnostic [$scope]: '
    'hasAuthHeader=$hasAuthHeader, '
    'hasConsumerKeyParam=$hasConsumerKeyParam, '
    'hasConsumerSecretParam=$hasConsumerSecretParam',
    tag: 'BackgroundService',
  );
}

Map<String, String> _wooQueryParams() {
  /*
  Old Code:
  return {
    'consumer_key': AppConfig.consumerKey,
    'consumer_secret': AppConfig.consumerSecret,
  };
  */
  // New Code: centralized WC signing parameters for all background requests.
  return {
    'consumer_key': AppConfig.consumerKey,
    'consumer_secret': AppConfig.consumerSecret,
  };
}

Future<Map<String, String>> _readOptionalBackgroundAuthContext(
    FlutterSecureStorage secureStorage) async {
  final nonce = await secureStorage.read(key: 'wp_nonce');
  final cookie = await secureStorage.read(key: 'wp_cookie');
  final headers = <String, String>{};
  if (nonce != null && nonce.isNotEmpty) {
    headers['X-WP-Nonce'] = nonce;
  }
  if (cookie != null && cookie.isNotEmpty) {
    headers['Cookie'] = cookie;
  }
  return headers;
}

Future<String?> _resolveUsableBackgroundToken({
  required FlutterSecureStorage secureStorage,
  required String authTokenKey,
  String? previousToken,
}) async {
  String? token = await secureStorage.read(key: authTokenKey);
  if ((token == null || token.isEmpty) && previousToken == null) {
    token = await AuthService.getStoredToken();
  }
  if (token == null || token.isEmpty) {
    return null;
  }

  final bool valid = await _isWpTokenValid(token);
  if (valid) {
    return token;
  }

  // Silent refresh strategy in background isolate:
  // re-read secure storage in case foreground refreshed token recently.
  final latest = await secureStorage.read(key: authTokenKey);
  if (latest != null && latest.isNotEmpty && latest != token) {
    final latestValid = await _isWpTokenValid(latest);
    if (latestValid) {
      return latest;
    }
  }
  return null;
}

Future<bool> _isWpTokenValid(String token) async {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 12),
      sendTimeout: const Duration(seconds: 12),
      headers: <String, dynamic>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
      validateStatus: (status) => status != null && status >= 200 && status < 600,
    ),
  );
  try {
    final uri = Uri.parse('${AppConfig.wpBaseUrl}/users/me').replace(
      queryParameters: <String, String>{
        '_t': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );
    final res = await dio.getUri(uri);
    return res.statusCode == 200;
  } catch (_) {
    return false;
  } finally {
    dio.close(force: true);
  }
}
