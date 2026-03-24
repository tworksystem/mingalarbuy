import 'dart:async';
import 'dart:convert';
import 'package:workmanager/workmanager.dart';
import 'package:ecommerce_int2/providers/order_provider.dart';
import 'package:ecommerce_int2/services/notification_service.dart';
import 'package:ecommerce_int2/utils/logger.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Background service for periodic order checking using Workmanager
class BackgroundService {
  static const String _taskName = 'orderCheckTask';
  static bool _isInitialized = false;

  /// Initialize Workmanager with callback configuration
  static Future<void> initialize() async {
    if (_isInitialized) {
      Logger.info('Background service already initialized',
          tag: 'BackgroundService');
      return;
    }

    try {
      // Initialize Workmanager with callback dispatcher
      await Workmanager().initialize(
        callbackDispatcher,
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

      Logger.info(
          'Periodic order check task registered successfully (15 min interval)',
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
}

/// Callback dispatcher - This is the entry point for background tasks
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      Logger.info('Background task started: $task', tag: 'BackgroundService');

      // Get stored user data from FlutterSecureStorage
      const FlutterSecureStorage secureStorage = FlutterSecureStorage();

      final userJson = await secureStorage.read(key: 'user_data');

      if (userJson == null) {
        Logger.warning('No user data found, skipping order check',
            tag: 'BackgroundService');
        return Future.value(false);
      }

      final userData = json.decode(userJson) as Map<String, dynamic>;
      final userId = userData['id']?.toString();

      if (userId == null || userId.isEmpty || userId == '0') {
        Logger.warning('No valid user ID found, skipping order check',
            tag: 'BackgroundService');
        return Future.value(false);
      }

      Logger.info('Checking orders for user: $userId',
          tag: 'BackgroundService');

      // Initialize providers and services
      final orderProvider = OrderProvider();
      final notificationService = NotificationService();

      // Ensure notification service is initialized
      if (!notificationService.isInitialized) {
        await notificationService.initialize();
      }

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
        return Future.value(false);
      }

      // Now sync with WooCommerce - this will detect status changes
      await orderProvider.syncOrdersWithWooCommerce(userId);

      Logger.info('Background order check completed successfully',
          tag: 'BackgroundService');

      return Future.value(true);
    } catch (e, stackTrace) {
      Logger.error('Background task failed: $e',
          tag: 'BackgroundService', error: e, stackTrace: stackTrace);
      return Future.value(false);
    }
  });
}
