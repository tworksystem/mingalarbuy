import 'dart:async';

import 'package:flutter/foundation.dart';
import '../models/auth_user.dart';
import '../models/auth_response.dart';
import '../models/login_request.dart';
import '../models/register_request.dart';
import '../services/auth_service.dart';
import '../services/connectivity_service.dart';
import '../services/missed_notification_recovery_service.dart';
import '../services/push_notification_service.dart';
import 'in_app_notification_provider.dart';
import '../utils/logger.dart';

enum AuthStatus {
  initial,
  loading,
  authenticated,
  unauthenticated,
  error,
}

class AuthProvider with ChangeNotifier {
  static final AuthProvider _instance = AuthProvider._internal();
  factory AuthProvider() => _instance;

  AuthStatus _status = AuthStatus.initial;
  AuthUser? _user;
  String? _errorMessage;
  bool _isLoading = false;
  bool _hasInitialized = false;
  String? _cachedToken; // Cache token for synchronous access

  /// After poll win / push snapshot, do not let [refreshUser] overwrite points
  /// with a lower API value until this time (server read replicas / meta lag).
  DateTime? _pointsBalanceNonDowngradeUntil;
  int _lastAppliedPointsBalance = 0;

  // Getters
  AuthStatus get status => _status;
  AuthUser? get user => _user;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _isLoading;
  bool get isAuthenticated =>
      _status == AuthStatus.authenticated && _user != null;
  bool get isUnauthenticated => _status == AuthStatus.unauthenticated;
  String? get token => _cachedToken; // Synchronous getter

  /// Get stored auth token (async method)
  Future<String?> getToken() async {
    if (_cachedToken == null) {
      _cachedToken = await AuthService.getStoredToken();
    }
    return _cachedToken;
  }

  AuthProvider._internal() {
    _initializeAuth();
  }

  /// Initialize authentication state
  Future<void> _initializeAuth() async {
    if (_hasInitialized && _status != AuthStatus.initial) {
      return;
    }

    _hasInitialized = true;
    _setLoading(true);

    try {
      // Load cached token
      _cachedToken = await AuthService.getStoredToken();

      final storedUser = await AuthService.getStoredUser();
      final isLoggedIn = await AuthService.isLoggedIn();

      if (isLoggedIn && storedUser != null) {
        Logger.debug('User is logged in, verifying token...',
            tag: 'AuthProvider');
        Logger.debug(
            'Stored user: ${storedUser.firstName} ${storedUser.lastName}, Phone: ${storedUser.phone}',
            tag: 'AuthProvider');

        // Use stored user immediately to avoid blocking on network
        _user = storedUser;
        _status = AuthStatus.authenticated;
        _setLoading(false); // Set loading to false early to allow navigation

        _reconcilePushAndInAppAfterAuth();

        // Verify token in background (non-blocking) - only if online
        try {
          // Check connectivity before making network call
          final connectivityService = _getConnectivityService();
          if (connectivityService != null && connectivityService.isConnected) {
            // Try to verify token with timeout (non-blocking)
            final currentUser = await AuthService.getCurrentUser().timeout(
              const Duration(seconds: 5),
              onTimeout: () {
                Logger.debug('Token verification timeout, using stored user',
                    tag: 'AuthProvider');
                return null;
              },
            ).catchError((e) {
              Logger.debug('Token verification error: $e, using stored user',
                  tag: 'AuthProvider', error: e);
              return null;
            });

            if (currentUser != null) {
              Logger.debug('Token is valid, user authenticated',
                  tag: 'AuthProvider');
              Logger.debug(
                  'Current user: ${currentUser.firstName} ${currentUser.lastName}, Phone: ${currentUser.phone}',
                  tag: 'AuthProvider');
              _user = currentUser;
              _status = AuthStatus.authenticated;
              notifyListeners();
              _reconcilePushAndInAppAfterAuth();
            } else {
              Logger.debug(
                  'Token verification failed, but keeping user logged in with stored data',
                  tag: 'AuthProvider');
            }
          } else {
            Logger.debug('Offline, using stored user data',
                tag: 'AuthProvider');
          }
        } catch (e) {
          Logger.debug(
              'Background token verification error: $e, using stored user',
              tag: 'AuthProvider',
              error: e);
          // Keep using stored user on error
        }
      } else {
        Logger.debug('User not logged in or no stored user',
            tag: 'AuthProvider');
        _status = AuthStatus.unauthenticated;
        _setLoading(false);
      }
    } catch (e) {
      Logger.error('Error during initialization: $e',
          tag: 'AuthProvider', error: e);
      // On error, try to use stored user data to keep user logged in
      // This prevents auto-logout on network errors or temporary issues
      try {
        final storedUser = await AuthService.getStoredUser();
        final isLoggedIn = await AuthService.isLoggedIn();

        if (isLoggedIn && storedUser != null) {
          Logger.warning(
              'Error occurred but keeping user logged in with stored data',
              tag: 'AuthProvider');
          _user = storedUser;
          _status = AuthStatus.authenticated;
          _reconcilePushAndInAppAfterAuth();
        } else {
          _setError('Failed to initialize authentication: $e');
          _status = AuthStatus.unauthenticated;
        }
      } catch (fallbackError) {
        Logger.error('Fallback also failed: $fallbackError',
            tag: 'AuthProvider', error: fallbackError);
        _setError('Failed to initialize authentication: $e');
        _status = AuthStatus.unauthenticated;
      } finally {
        _setLoading(false);
      }
    }
  }

  /// Get connectivity service
  ConnectivityService? _getConnectivityService() {
    try {
      return ConnectivityService();
    } catch (e) {
      return null;
    }
  }

  // Old Code: No call after session became available — FCM device token was only uploaded
  // during PushNotificationService.initialize() when `user_data` was often still missing;
  // in-app list was not re-hydrated from storage after new login.
  /// Register FCM token with backend (once [user_data] exists) and reload in-app notification list.
  void _reconcilePushAndInAppAfterAuth() {
    unawaited(Future(() async {
      try {
        await PushNotificationService().syncFcmTokenToBackendForCurrentUser();
        await InAppNotificationProvider.instance.loadNotifications();
      } catch (e, stackTrace) {
        Logger.debug(
          'Post-auth push / in-app reconcile: $e',
          tag: 'AuthProvider',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }));
  }

  /// Login user
  Future<AuthResponse> login(LoginRequest request) async {
    _setLoading(true);
    _clearError();

    try {
      final response = await AuthService.login(request);

      if (response.success && response.user != null) {
        _user = response.user;
        _status = AuthStatus.authenticated;
        // PROFESSIONAL FIX: Update cached token immediately after login
        // This ensures token is available synchronously for subsequent API calls
        if (response.token != null) {
          _cachedToken = response.token;
          Logger.info(
              'AuthProvider.login - Token cached after successful login',
              tag: 'AuthProvider');
        } else {
          // Fallback: Load token from storage if not in response
          _cachedToken = await AuthService.getStoredToken();
          Logger.info(
              'AuthProvider.login - Token loaded from storage (not in response)',
              tag: 'AuthProvider');
        }
        notifyListeners();
        // Old Code: `notifyListeners()` only; backend never got FCM token after fresh login.
        _reconcilePushAndInAppAfterAuth();
        return response;
      } else {
        _setError(response.message);
        _status = AuthStatus.unauthenticated;
        return response;
      }
    } catch (e) {
      final errorMsg = 'Login failed: $e';
      _setError(errorMsg);
      _status = AuthStatus.error;
      return AuthResponse.error(message: errorMsg);
    } finally {
      _setLoading(false);
    }
  }

  /// Register user
  Future<AuthResponse> register(RegisterRequest request) async {
    _setLoading(true);
    _clearError();

    try {
      final response = await AuthService.register(request);

      if (response.success && response.user != null) {
        _user = response.user;
        _status = AuthStatus.authenticated;
        // PROFESSIONAL FIX: Update cached token after registration
        // This ensures token is available synchronously for subsequent API calls
        if (response.token != null) {
          _cachedToken = response.token;
          Logger.info(
              'AuthProvider.register - Token cached after successful registration',
              tag: 'AuthProvider');
        } else {
          // Fallback: Load token from storage if not in response
          _cachedToken = await AuthService.getStoredToken();
          Logger.info(
              'AuthProvider.register - Token loaded from storage (not in response)',
              tag: 'AuthProvider');
        }
        notifyListeners();
        // Old Code: `notifyListeners()` only; same FCM registration gap as login.
        _reconcilePushAndInAppAfterAuth();
        return response;
      } else {
        _setError(response.message);
        _status = AuthStatus.unauthenticated;
        return response;
      }
    } catch (e) {
      final errorMsg = 'Registration failed: $e';
      _setError(errorMsg);
      _status = AuthStatus.error;
      return AuthResponse.error(message: errorMsg);
    } finally {
      _setLoading(false);
    }
  }

  /// Update user profile
  Future<AuthResponse> updateProfile(AuthUser updatedUser) async {
    _setLoading(true);
    _clearError();

    try {
      final response = await AuthService.updateProfile(updatedUser);

      if (response.success && response.user != null) {
        _user = response.user;
        notifyListeners();
        return response;
      } else {
        _setError(response.message);
        return response;
      }
    } catch (e) {
      final errorMsg = 'Profile update failed: $e';
      _setError(errorMsg);
      return AuthResponse.error(message: errorMsg);
    } finally {
      _setLoading(false);
    }
  }

  /// Update WooCommerce billing details for the current user
  Future<AuthResponse> updateBilling({
    String? firstName,
    String? lastName,
    String? phone,
    Map<String, dynamic>? billingExtra,
  }) async {
    _setLoading(true);
    _clearError();

    try {
      final response = await AuthService.updateBillingForCurrentUser(
        firstName: firstName,
        lastName: lastName,
        phone: phone,
        billingExtra: billingExtra,
      );

      if (response.success && response.user != null) {
        _user = response.user;
        notifyListeners();
      } else if (!response.success) {
        _setError(response.message);
      }

      return response;
    } catch (e) {
      final errorMsg = 'Billing update failed: $e';
      _setError(errorMsg);
      return AuthResponse.error(message: errorMsg);
    } finally {
      _setLoading(false);
    }
  }

  /// Change password
  Future<AuthResponse> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    _setLoading(true);
    _clearError();

    try {
      final response = await AuthService.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );

      if (!response.success) {
        _setError(response.message);
      }

      return response;
    } catch (e) {
      final errorMsg = 'Password change failed: $e';
      _setError(errorMsg);
      return AuthResponse.error(message: errorMsg);
    } finally {
      _setLoading(false);
    }
  }

  /// Forgot password
  Future<AuthResponse> forgotPassword(String email) async {
    _setLoading(true);
    _clearError();

    try {
      final response = await AuthService.forgotPassword(email);

      if (!response.success) {
        _setError(response.message);
      }

      return response;
    } catch (e) {
      final errorMsg = 'Password reset failed: $e';
      _setError(errorMsg);
      return AuthResponse.error(message: errorMsg);
    } finally {
      _setLoading(false);
    }
  }

  /// Logout user
  Future<void> logout() async {
    _setLoading(true);

    try {
      // Get user ID before clearing
      final userId = _user?.id.toString();
      
      await AuthService.logout();
      _user = null;
      _cachedToken = null; // Clear cached token
      _pointsBalanceNonDowngradeUntil = null;
      _lastAppliedPointsBalance = 0;
      _status = AuthStatus.unauthenticated;
      _clearError();
      
      // PROFESSIONAL FIX: Clear notification tracking on logout
      // This ensures clean state when user switches accounts
      if (userId != null) {
        MissedNotificationRecoveryService.clearTrackingForUser(userId);
      }
      
      notifyListeners();
    } catch (e) {
      _setError('Logout failed: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Refresh user data
  Future<void> refreshUser() async {
    if (!isAuthenticated) return;

    try {
      Logger.info('Refreshing user data...', tag: 'AuthProvider');
      // PROFESSIONAL FIX: Refresh cached token before getting user data
      // This ensures token is up-to-date after user switch
      _cachedToken = await AuthService.getStoredToken();
      if (_cachedToken == null) {
        Logger.warning('No token found in storage during refresh',
            tag: 'AuthProvider');
      }

      final currentUser = await AuthService.getCurrentUser();
      if (currentUser != null) {
        Logger.info(
            'Refreshed user data - Name: ${currentUser.firstName} ${currentUser.lastName}, Phone: ${currentUser.phone}',
            tag: 'AuthProvider');
        _user = currentUser;

        // Non-downgrade: do not overwrite points with lower API value right after
        // poll win / push snapshot (server read replicas or meta lag).
        final now = DateTime.now();
        if (_pointsBalanceNonDowngradeUntil != null &&
            now.isBefore(_pointsBalanceNonDowngradeUntil!) &&
            _lastAppliedPointsBalance > 0) {
          final apiBalance = _extractPointsFromCustomFields(
              currentUser.customFields);
          if (apiBalance < _lastAppliedPointsBalance) {
            Logger.info(
                'AuthProvider: preserving applied balance $_lastAppliedPointsBalance (API returned $apiBalance)',
                tag: 'AuthProvider');
            final patched =
                Map<String, String>.from(currentUser.customFields);
            final balanceStr = _lastAppliedPointsBalance.toString();
            patched['points_balance'] = balanceStr;
            patched['my_points'] = balanceStr;
            patched['my_point'] = balanceStr;
            _user = currentUser.copyWith(customFields: patched);
          }
        }

        // Ensure token is still cached after refresh
        if (_cachedToken == null) {
          _cachedToken = await AuthService.getStoredToken();
        }
        notifyListeners();
        Logger.info('Notified listeners of user data update',
            tag: 'AuthProvider');
      } else {
        Logger.warning('Failed to get current user, but keeping user logged in',
            tag: 'AuthProvider');
        // Don't logout on refresh failure - user might still be authenticated
        // Only logout if explicitly called or during initialization
      }
    } catch (e) {
      Logger.error('Error refreshing user data: $e',
          tag: 'AuthProvider', error: e);
      _setError('Failed to refresh user data: $e');
      // Don't logout on refresh error - user might still be authenticated
    }
  }

  /// Apply latest points balance from push notification payload (optimistic UI update).
  ///
  /// Why:
  /// - Admin can manually adjust points (add/deduct) from dashboard.
  /// - App should update instantly without requiring a manual refresh.
  /// - FCM payload already includes `currentBalance`, so we can update UI immediately,
  ///   then let `refreshUser()` reconcile from server in the background.
  void applyPointsBalanceSnapshot(int currentBalance) {
    if (!isAuthenticated || _user == null) return;

    final patched = Map<String, String>.from(_user!.customFields);
    final balanceStr = currentBalance.toString();

    // Keep multiple keys in sync because different screens use different fields.
    patched['points_balance'] = balanceStr;
    patched['my_points'] = balanceStr;
    patched['my_point'] = balanceStr;

    _user = _user!.copyWith(customFields: patched);
    _lastAppliedPointsBalance = currentBalance;
    // Extended window: poll win + deferred loadBalance (4s) + slow API/meta sync.
    _pointsBalanceNonDowngradeUntil =
        DateTime.now().add(const Duration(seconds: 35));
    notifyListeners();
  }

  /// Current points balance from user custom fields (used by MyPointWidget and poll win fallback).
  int get userPointsBalance =>
      _user != null ? _extractPointsFromCustomFields(_user!.customFields) : 0;

  /// Extract numeric points from user custom fields (my_point, my_points, points_balance).
  int _extractPointsFromCustomFields(Map<String, String> customFields) {
    final raw = customFields['my_point'] ??
        customFields['my_points'] ??
        customFields['points_balance'] ??
        customFields['My Point Value'];
    if (raw == null || raw.isEmpty) return 0;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 0;
    final parsed = int.tryParse(trimmed);
    if (parsed != null) return parsed;
    final match = RegExp(r'\d+').firstMatch(trimmed);
    return match != null ? int.tryParse(match.group(0) ?? '0') ?? 0 : 0;
  }

  /// Ensure token is synchronized with storage
  /// This is useful after user switch or when token might be stale
  Future<void> ensureTokenSynchronized() async {
    if (_cachedToken == null && _user != null) {
      Logger.info('Token is null but user exists, loading from storage...',
          tag: 'AuthProvider');
      _cachedToken = await AuthService.getStoredToken();
      if (_cachedToken != null) {
        Logger.info('Token synchronized from storage', tag: 'AuthProvider');
      } else {
        Logger.warning('Token not found in storage even though user exists',
            tag: 'AuthProvider');
      }
    }
  }

  /// Private helper methods
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String error) {
    _errorMessage = error;
    _status = AuthStatus.error;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
    if (_status == AuthStatus.error) {
      _status =
          _user != null ? AuthStatus.authenticated : AuthStatus.unauthenticated;
    }
  }
}
