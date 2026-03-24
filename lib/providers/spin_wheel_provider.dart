import 'dart:async';
import 'package:flutter/foundation.dart';

import '../services/spin_wheel_service.dart';

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

  Future<void> loadConfigForUser(String userId, {bool forceRefresh = false}) async {
    if (!forceRefresh && _config != null && _userId == userId) return;
    _isLoading = true;
    _error = null;
    _notifyListenersImmediate(); // Immediate for loading state

    _userId = userId;
    final cfg = await SpinWheelService.getConfig(userId: userId);
    if (cfg == null) {
      _error = 'Failed to load Lucky Box config';
      // Don't clear existing config on error - keep last known state
    } else {
      _config = cfg;
      _error = null; // Clear error on success
    }
    _isLoading = false;
    _notifyListenersDebounced(); // Debounced for final state
  }

  Future<bool> openLuckyBox({required String userId}) async {
    _isLoading = true;
    _error = null;
    _notifyListenersImmediate(); // Immediate for loading state

    final ok = await SpinWheelService.openLuckyBox(userId: userId);
    if (!ok) {
      // Get error message from service
      final errorMessage = SpinWheelService.lastError;
      _error = errorMessage ?? 'Failed to open Lucky Box. Please try again.';
    } else {
      _error = null; // Clear error on success
      // Reload config after opening to get updated status from backend
      // Don't manually update - let backend control the state
      await loadConfigForUser(userId, forceRefresh: true);
    }

    _isLoading = false;
    _notifyListenersDebounced(); // Debounced for final state
    return ok;
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}


