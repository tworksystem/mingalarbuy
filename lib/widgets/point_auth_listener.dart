import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/point_provider.dart';
import '../providers/in_app_notification_provider.dart';
import '../services/missed_notification_recovery_service.dart';
import '../utils/logger.dart';

/// Widget that listens to authentication state changes
/// and automatically loads point balance when user is authenticated
class PointAuthListener extends StatefulWidget {
  final Widget child;

  const PointAuthListener({
    super.key,
    required this.child,
  });

  @override
  State<PointAuthListener> createState() => _PointAuthListenerState();
}

class _PointAuthListenerState extends State<PointAuthListener> {
  String? _lastUserId;
  bool _hasInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Check auth state when dependencies change (providers available)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAuthAndLoadPoints();
    });
  }

  void _checkAuthAndLoadPoints() {
    if (!mounted) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final pointProvider = Provider.of<PointProvider>(context, listen: false);

    if (authProvider.isAuthenticated && authProvider.user != null) {
      final userId = authProvider.user!.id.toString();

      // PROFESSIONAL FIX: Always reload if user changed, even if already initialized
      // This ensures fresh data when user switches accounts
      if (_lastUserId != userId || !_hasInitialized) {
        final previousUserId = _lastUserId;
        _lastUserId = userId;
        _hasInitialized = true;

        if (previousUserId != null && previousUserId != userId) {
          Logger.info(
              'User account changed from $previousUserId to $userId, reloading point balance',
              tag: 'PointAuthListener');
        } else {
          Logger.info(
              'User authenticated, loading point balance for user: $userId',
              tag: 'PointAuthListener');
        }

        // Load balance asynchronously without blocking UI
        // handleAuthStateChange will handle clearing old user's data
        pointProvider.handleAuthStateChange(
          isAuthenticated: true,
          userId: userId,
        ).then((_) {
          // PROFESSIONAL FIX: After balance loads, check for missed notifications
          // This handles case where user uninstalled app before receiving poll win FCM
          _checkForMissedNotifications(userId);
        }).catchError((e) {
          Logger.error('Error loading points on auth: $e',
              tag: 'PointAuthListener', error: e);
        });
      }
    } else if (_lastUserId != null) {
      // User logged out
      final previousUserId = _lastUserId;
      _lastUserId = null;
      _hasInitialized = false;

      Logger.info(
          'User logged out (previous user: $previousUserId), clearing point data',
          tag: 'PointAuthListener');

      pointProvider.handleAuthStateChange(
        isAuthenticated: false,
        userId: null,
      ).catchError((e) {
        Logger.error('Error clearing points on logout: $e',
            tag: 'PointAuthListener', error: e);
      });
    }
  }

  /// Check for missed poll winner notifications
  /// Called after user authenticates and point balance loads
  Future<void> _checkForMissedNotifications(String userId) async {
    try {
      Logger.info('Checking for missed poll winner notifications',
          tag: 'PointAuthListener');

      // Run recovery in background (don't block UI)
      final recoveredCount = await MissedNotificationRecoveryService
          .checkAndRecoverMissedNotifications(userId);

      if (recoveredCount > 0) {
        Logger.info(
            'Recovered $recoveredCount missed poll winner notification(s)',
            tag: 'PointAuthListener');

        // Refresh notification provider to update UI
        if (mounted) {
          final notificationProvider = Provider.of<InAppNotificationProvider>(
              context,
              listen: false);
          await notificationProvider.loadNotifications();
        }
      }
    } catch (e, stackTrace) {
      Logger.error('Error checking for missed notifications: $e',
          tag: 'PointAuthListener', error: e, stackTrace: stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen to auth changes - this will rebuild when auth state changes
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        // Check if auth state changed
        final currentUserId = authProvider.user?.id.toString();
        final isAuthenticated = authProvider.isAuthenticated;
        
        // Only trigger check if state actually changed
        if ((isAuthenticated && currentUserId != _lastUserId) ||
            (!isAuthenticated && _lastUserId != null) ||
            (isAuthenticated && !_hasInitialized)) {
          // Use post-frame callback to avoid calling during build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _checkAuthAndLoadPoints();
            }
          });
        }
        
        return widget.child;
      },
    );
  }
}

