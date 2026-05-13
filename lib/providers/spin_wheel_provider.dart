import 'dart:async';
import 'package:flutter/foundation.dart';

import '../services/spin_wheel_service.dart';
import '../utils/logger.dart';

/// OPTIMIZED: SpinWheelProvider with debounced notifications to prevent excessive rebuilds
class SpinWheelProvider with ChangeNotifier {
  SpinWheelConfig? _config;
  bool _isLoading = false;
  String? _error;
  String? _userId;

  // OPTIMIZED: Debounce timer to prevent excessive notifyListeners calls
  Timer? _debounceTimer;
  static const Duration _debounceDelay = Duration(milliseconds: 100);

  SpinWheelConfig? get config => _config;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isEnabled => _config?.enabled == true;
  bool get canOpen => _config?.canOpen == true;
  bool get hasPending => _config?.hasPending == true;

  /// OPTIMIZED: Debounced notifyListeners to prevent excessive rebuilds
  void _notifyListenersDebounced() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDelay, () {
      notifyListeners();
    });
  }

  /// OPTIMIZED: Immediate notification when needed (e.g., loading state)
  void _notifyListenersImmediate() {
    _debounceTimer?.cancel();
    notifyListeners();
  }

  /// Resets Lucky Box state when auth session changes (logout / account switch).
  Future<void> handleAuthStateChange({
    required bool isAuthenticated,
    String? userId,
  }) async {
    _debounceTimer?.cancel();
    if (!isAuthenticated) {
      _config = null;
      _userId = null;
      _error = null;
      _isLoading = false;
      notifyListeners();
      return;
    }
    if (userId == null || userId.isEmpty) return;
    _config = null;
    _error = null;
    await loadConfigForUser(userId, forceRefresh: true);
  }

  Future<void> loadConfigForUser(
    String userId, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _config != null && _userId == userId) return;
    _isLoading = true;
    _error = null;
    _notifyListenersImmediate();

    final String requestUserId = userId;
    final previousId = _userId;
    _userId = userId;
    if (previousId != userId) {
      _config = null;
    }

    final cfg = await SpinWheelService.getConfig(userId: userId);
    if (_userId != requestUserId) {
      Logger.info(
        'Discarding spin wheel config response for $requestUserId; active user is $_userId',
        tag: 'SpinWheelProvider',
      );
      _isLoading = false;
      _notifyListenersDebounced();
      return;
    }

    // OLD CODE: on API error, kept previous [_config] which could belong to another user.
    // if (cfg == null) {
    //   _error = 'Failed to load Lucky Box config';
    // } else {
    //   _config = cfg;
    //   _error = null;
    // }
    if (cfg == null) {
      _error = 'Failed to load Lucky Box config';
      _config = null;
    } else {
      _config = cfg;
      _error = null;
    }
    _isLoading = false;
    _notifyListenersDebounced();
  }

  Future<bool> openLuckyBox({required String userId}) async {
    _isLoading = true;
    _error = null;
    _notifyListenersImmediate();

    final ok = await SpinWheelService.openLuckyBox(userId: userId);
    if (_userId != userId) {
      _isLoading = false;
      _notifyListenersDebounced();
      return false;
    }
    if (!ok) {
      final errorMessage = SpinWheelService.lastError;
      _error = errorMessage ?? 'Failed to open Lucky Box. Please try again.';
    } else {
      _error = null;
      await loadConfigForUser(userId, forceRefresh: true);
    }

    _isLoading = false;
    _notifyListenersDebounced();
    return ok;
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}
