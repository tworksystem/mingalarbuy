import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/reward_exchange_service.dart';
import '../utils/logger.dart';

/// Exchange Settings Provider
/// Manages minimum exchange points state and provides real-time updates
/// When backend updates the limit, app will fetch fresh data on next access
class ExchangeSettingsProvider with ChangeNotifier {
  // Singleton instance
  static ExchangeSettingsProvider? _instance;
  static ExchangeSettingsProvider get instance {
    _instance ??= ExchangeSettingsProvider._internal();
    return _instance!;
  }

  ExchangeSettingsProvider._internal() {
    _initialize();
  }

  // Factory constructor for Provider compatibility
  factory ExchangeSettingsProvider() => instance;

  int? _minExchangePoints;
  bool _isLoading = false;
  String? _errorMessage;
  DateTime? _lastUpdated;
  
  // Cache duration - shorter for real-time updates
  static const Duration _cacheDuration = Duration(seconds: 30);
  
  // Auto-refresh timer
  Timer? _autoRefreshTimer;

  // Getters
  int? get minExchangePoints => _minExchangePoints;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasData => _minExchangePoints != null;
  DateTime? get lastUpdated => _lastUpdated;

  /// Initialize provider
  Future<void> _initialize() async {
    // Load initial data on app start
    // This ensures we have exchange settings available immediately
    await refreshSettings(forceRefresh: false);
    
    // PROFESSIONAL FIX: Start auto-refresh for real-time updates
    // Refresh every 2 minutes to catch backend changes automatically
    startAutoRefresh(interval: const Duration(minutes: 2));
  }

  /// Refresh exchange settings from backend
  /// forceRefresh: If true, bypasses cache and fetches fresh data
  Future<void> refreshSettings({bool forceRefresh = false}) async {
    // Check cache if not forcing refresh
    if (!forceRefresh &&
        _minExchangePoints != null &&
        _lastUpdated != null &&
        DateTime.now().difference(_lastUpdated!) < _cacheDuration) {
      Logger.info(
        'Using cached minimum exchange points: $_minExchangePoints',
        tag: 'ExchangeSettingsProvider',
      );
      return;
    }

    _setLoading(true);
    _clearError();

    try {
      // Clear service cache if forcing refresh to ensure fresh data
      if (forceRefresh) {
        RewardExchangeService.clearMinExchangePointsCache();
      }

      final minPoints = await RewardExchangeService.getMinExchangePoints(
        forceRefresh: forceRefresh,
      );

      // Always update to ensure UI reflects latest value
      final valueChanged = _minExchangePoints != minPoints;
      _minExchangePoints = minPoints;
      _lastUpdated = DateTime.now();
      
      if (valueChanged) {
        Logger.info(
          'Minimum exchange points updated: $minPoints (was: ${_minExchangePoints})',
          tag: 'ExchangeSettingsProvider',
        );
        notifyListeners();
      } else {
        Logger.info(
          'Minimum exchange points refreshed (unchanged): $minPoints',
          tag: 'ExchangeSettingsProvider',
        );
        // Still notify to update timestamp in UI if needed
        notifyListeners();
      }
    } catch (e, stackTrace) {
      Logger.error(
        'Error refreshing exchange settings: $e',
        tag: 'ExchangeSettingsProvider',
        error: e,
        stackTrace: stackTrace,
      );
      _setError('Failed to load exchange settings');
    } finally {
      _setLoading(false);
    }
  }

  /// Get minimum exchange points with fallback
  int getMinExchangePoints() {
    return _minExchangePoints ?? 100; // Default fallback
  }

  /// Check if user is eligible for exchange
  bool isEligibleForExchange(int currentPoints) {
    final minPoints = getMinExchangePoints();
    return currentPoints >= minPoints;
  }

  /// Get points needed to reach minimum
  int getPointsNeeded(int currentPoints) {
    final minPoints = getMinExchangePoints();
    return (minPoints - currentPoints).clamp(0, minPoints);
  }

  /// Start auto-refresh timer (optional - for periodic updates)
  void startAutoRefresh({Duration interval = const Duration(minutes: 2)}) {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(interval, (timer) {
      refreshSettings(forceRefresh: true);
    });
    Logger.info(
      'Started auto-refresh for exchange settings (interval: ${interval.inSeconds}s)',
      tag: 'ExchangeSettingsProvider',
    );
  }

  /// Stop auto-refresh timer
  void stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
    Logger.info(
      'Stopped auto-refresh for exchange settings',
      tag: 'ExchangeSettingsProvider',
    );
  }

  void _setLoading(bool value) {
    if (_isLoading != value) {
      _isLoading = value;
      notifyListeners();
    }
  }

  void _setError(String? message) {
    _errorMessage = message;
    notifyListeners();
  }

  void _clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
    }
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }
}

