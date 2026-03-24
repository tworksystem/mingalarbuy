import 'dart:async';
import '../utils/logger.dart';
import '../providers/order_provider.dart';
import '../providers/auth_provider.dart';

/// Service for active polling when app is in foreground
/// This runs more frequently than Workmanager to provide near-instant notifications
class ActiveSyncService {
  static final ActiveSyncService _instance = ActiveSyncService._internal();
  factory ActiveSyncService() => _instance;
  ActiveSyncService._internal();

  Timer? _pollTimer;
  bool _isRunning = false;
  // OPTIMIZED: Increased from 30s to 60s since FCM push notifications handle instant updates
  // This reduces CPU usage while still providing good responsiveness
  static const Duration _pollInterval = Duration(seconds: 60);
  
  /// Check if service is running
  bool get isRunning => _isRunning;
  
  /// Start active polling for order updates
  /// This should only be called when app is in foreground
  Future<void> startPolling({
    required OrderProvider orderProvider,
    required AuthProvider authProvider,
  }) async {
    if (_isRunning) {
      Logger.info('ActiveSyncService already running', tag: 'ActiveSyncService');
      return;
    }

    Logger.info('Starting active order polling (every 60 seconds)',
        tag: 'ActiveSyncService');

    _isRunning = true;

    // Do initial sync immediately
    await _syncOrders(orderProvider, authProvider);

    // Then poll at regular intervals
    _pollTimer = Timer.periodic(_pollInterval, (_) async {
      if (_isRunning) {
        await _syncOrders(orderProvider, authProvider);
      }
    });
  }

  /// Stop active polling
  /// Should be called when app goes to background
  void stopPolling() {
    if (!_isRunning) {
      return;
    }

    Logger.info('Stopping active order polling', tag: 'ActiveSyncService');
    
    _pollTimer?.cancel();
    _pollTimer = null;
    _isRunning = false;
  }

  /// Perform order sync
  Future<void> _syncOrders(
    OrderProvider orderProvider,
    AuthProvider authProvider,
  ) async {
    try {
      if (!authProvider.isAuthenticated || authProvider.user == null) {
        Logger.info('User not authenticated, skipping active sync',
            tag: 'ActiveSyncService');
        return;
      }

      Logger.info('Active sync: Checking for order updates',
          tag: 'ActiveSyncService');

      await orderProvider.syncOrdersWithWooCommerce(
        authProvider.user!.id.toString(),
      );

      Logger.info('Active sync completed successfully',
          tag: 'ActiveSyncService');
    } catch (e) {
      Logger.error('Active sync failed: $e', tag: 'ActiveSyncService', error: e);
      // Don't stop polling on single failure
    }
  }

  /// Trigger immediate sync manually
  Future<void> forceSyncNow({
    required OrderProvider orderProvider,
    required AuthProvider authProvider,
  }) async {
    Logger.info('Force sync triggered', tag: 'ActiveSyncService');
    await _syncOrders(orderProvider, authProvider);
  }
}

