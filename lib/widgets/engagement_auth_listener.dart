import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/engagement_provider.dart';
import '../utils/logger.dart' as app_logger;

/// Widget that listens to authentication state changes
/// and automatically loads engagement feed when user is authenticated
class EngagementAuthListener extends StatefulWidget {
  final Widget child;

  const EngagementAuthListener({
    super.key,
    required this.child,
  });

  @override
  State<EngagementAuthListener> createState() => _EngagementAuthListenerState();
}

class _EngagementAuthListenerState extends State<EngagementAuthListener> {
  int? _lastUserId;
  bool _hasInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Check auth state when dependencies change (providers available)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAuthAndLoadEngagement();
    });
  }

  void _checkAuthAndLoadEngagement() {
    if (!mounted) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final engagementProvider =
        Provider.of<EngagementProvider>(context, listen: false);

    if (authProvider.isAuthenticated && authProvider.user != null) {
      final userId = authProvider.user!.id;

      // PROFESSIONAL FIX: Always reload if user changed, even if already initialized
      // This ensures fresh data when user switches accounts
      if (_lastUserId != userId || !_hasInitialized) {
        final previousUserId = _lastUserId;
        _lastUserId = userId;
        _hasInitialized = true;

        if (previousUserId != null && previousUserId != userId) {
          app_logger.Logger.info(
              'User account changed from $previousUserId to $userId, reloading engagement feed',
              tag: 'EngagementAuthListener');
        } else {
          app_logger.Logger.info(
              'User authenticated, loading engagement feed for user: $userId',
              tag: 'EngagementAuthListener');
        }

        // Load engagement feed asynchronously without blocking UI
        // handleAuthStateChange will handle clearing old user's data
        engagementProvider
            .handleAuthStateChange(
          isAuthenticated: true,
          userId: userId,
        )
            .catchError((e) {
          app_logger.Logger.error('Error loading engagement on auth: $e',
              tag: 'EngagementAuthListener', error: e);
        });
      }
    } else if (_lastUserId != null) {
      // User logged out
      final previousUserId = _lastUserId;
      _lastUserId = null;
      _hasInitialized = false;
      
      app_logger.Logger.info(
          'User logged out (previous user: $previousUserId), clearing engagement data',
          tag: 'EngagementAuthListener');
      
      engagementProvider
          .handleAuthStateChange(
        isAuthenticated: false,
        userId: null,
      )
          .catchError((e) {
        app_logger.Logger.error('Error clearing engagement on logout: $e',
            tag: 'EngagementAuthListener', error: e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen to auth changes - this will rebuild when auth state changes
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        // Check if auth state changed
        final currentUserId = authProvider.user?.id;
        final isAuthenticated = authProvider.isAuthenticated;

        // Only trigger check if state actually changed
        if ((isAuthenticated && currentUserId != _lastUserId) ||
            (!isAuthenticated && _lastUserId != null) ||
            (isAuthenticated && !_hasInitialized)) {
          // Use post-frame callback to avoid calling during build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _checkAuthAndLoadEngagement();
            }
          });
        }

        return widget.child;
      },
    );
  }
}

