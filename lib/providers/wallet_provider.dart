import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/widgets.dart';
import '../services/wallet_service.dart';
import '../services/withdrawal_service.dart';
import '../models/withdrawal.dart';
import '../utils/logger.dart';
import '../services/connectivity_service.dart';

/// Wallet provider for managing wallet balance state
/// Handles wallet balance and UI updates
/// Uses singleton pattern to ensure same instance across the app
class WalletProvider with ChangeNotifier {
  // Singleton instance
  static WalletProvider? _instance;
  static WalletProvider get instance {
    _instance ??= WalletProvider._internal();
    return _instance!;
  }

  WalletProvider._internal();

  // Factory constructor for Provider compatibility
  factory WalletProvider() => instance;

  WalletBalance? _balance;
  bool _isLoading = false;
  String? _errorMessage;
  String? _currentUserId;
  bool _hasLoadedForCurrentUser = false;
  DateTime?
  _lastBalanceUpdateTime; // Track when balance was last updated locally

  // OPTIMIZED: Debounce timer to prevent excessive notifications
  Timer? _notificationDebounceTimer;
  static const Duration _debounceDelay = Duration(milliseconds: 100);

  // Getters
  WalletBalance? get balance => _balance;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  double get currentBalance => _balance?.currentBalance ?? 0.0;
  bool get hasBalance => currentBalance > 0;
  String get formattedBalance => _balance?.formattedBalance ?? '0.00 Ks';
  String get formattedBalanceWithoutSymbol =>
      _balance?.formattedBalanceWithoutSymbol ?? '0.00';

  /// Handle authentication state changes
  /// Automatically loads balance when user becomes authenticated
  Future<void> handleAuthStateChange({
    required bool isAuthenticated,
    String? userId,
  }) async {
    if (isAuthenticated && userId != null) {
      if (_currentUserId != userId || !_hasLoadedForCurrentUser) {
        final bool switchedAccount =
            _currentUserId != null && _currentUserId != userId;
        if (switchedAccount) {
          _balance = null;
          _hasLoadedForCurrentUser = false;
          _lastBalanceUpdateTime = null;
          notifyListeners();
        }
        _currentUserId = userId;
        Logger.info(
          'User authenticated, loading wallet balance for user: $userId',
          tag: 'WalletProvider',
        );
        await loadBalance(userId, forceRefresh: switchedAccount);
        _hasLoadedForCurrentUser = true;
      }
    } else {
      // User logged out - clear state
      _currentUserId = null;
      _hasLoadedForCurrentUser = false;
      _balance = null;
      _lastBalanceUpdateTime = null;
      notifyListeners();
      Logger.info(
        'User logged out, cleared wallet data',
        tag: 'WalletProvider',
      );
    }
  }

  /// Load wallet balance for user
  /// If forceRefresh is true, will reload even if already loaded for this user
  ///
  /// IMPORTANT: This method will NOT overwrite a balance that was recently updated
  /// locally (e.g. after a wallet credit) to prevent race conditions. If balance was
  /// updated within the last 3 seconds, this method will skip the API call and use
  /// the current balance.
  /// However, if forceRefresh is true, it will still load but will preserve recent updates.
  Future<void> loadBalance(String userId, {bool forceRefresh = false}) async {
    if (forceRefresh) {
      _hasLoadedForCurrentUser = false;
    }
    // Skip if already loaded for this user and not forcing refresh
    if (!forceRefresh &&
        _currentUserId == userId &&
        _hasLoadedForCurrentUser &&
        _balance != null) {
      Logger.info(
        'Wallet balance already loaded for user $userId, skipping',
        tag: 'WalletProvider',
      );
      return;
    }

    // CRITICAL: Prevent overwriting a balance that was just updated locally (credit / server-sync helpers)
    // This prevents race conditions where loadBalance() overwrites a freshly updated balance
    // Exception: If balance is null, always load (we need initial data)
    // Exception: If forceRefresh is true, respect it (caller explicitly wants fresh data)
    // Exception: If forceRefresh is true, we still want to load but will preserve recent updates if they're newer
    if (!forceRefresh &&
        _lastBalanceUpdateTime != null &&
        _currentUserId == userId &&
        _balance != null) {
      final timeSinceUpdate = DateTime.now().difference(
        _lastBalanceUpdateTime!,
      );
      if (timeSinceUpdate.inSeconds < 3) {
        Logger.info(
          'Balance was recently updated (${timeSinceUpdate.inSeconds}s ago), skipping loadBalance to prevent overwrite. Current balance: \$${_balance!.currentBalance}',
          tag: 'WalletProvider',
        );
        // Still notify listeners to ensure UI is updated
        notifyListeners();
        return;
      }
    }

    _currentUserId = userId;
    _isLoading = true; // Set directly without notification
    _clearError();

    try {
      // Try to load from API if online
      final connectivityService = ConnectivityService();
      if (connectivityService.isConnected) {
        // Load balance from API first (source of truth)
        final balance = await WalletService.getWalletBalance(userId);
        if (_currentUserId != userId) {
          Logger.info(
            'Discarding wallet API response: active user is $_currentUserId, '
            'completed request was for $userId',
            tag: 'WalletProvider',
          );
        } else if (balance != null) {
          // Only update if the new balance is not older than our current balance
          // or if we don't have a recent update
          final shouldUpdate =
              _lastBalanceUpdateTime == null ||
              balance.lastUpdated.isAfter(
                _balance?.lastUpdated ?? DateTime(1970),
              ) ||
              DateTime.now().difference(_lastBalanceUpdateTime!).inSeconds >= 3;

          if (shouldUpdate) {
            _balance = balance;
            _hasLoadedForCurrentUser = true;
            notifyListeners();
            Logger.info(
              'Wallet balance loaded from API: \$${balance.currentBalance}',
              tag: 'WalletProvider',
            );
          } else {
            Logger.info(
              'Skipping API balance update - local balance is more recent. Local: \$${_balance!.currentBalance}, API: \$${balance.currentBalance}',
              tag: 'WalletProvider',
            );
            // Still notify to ensure UI is updated
            notifyListeners();
          }
        } else {
          // If API fails, try cache
          await _loadCachedBalance(userId);
        }
      } else {
        // Load from cache if offline
        await _loadCachedBalance(userId);
      }
    } catch (e, stackTrace) {
      Logger.error(
        'Error loading wallet balance: $e',
        tag: 'WalletProvider',
        error: e,
        stackTrace: stackTrace,
      );
      _setError('Failed to load wallet balance');
      // Try to load from cache on error
      await _loadCachedBalance(userId);
    } finally {
      _setLoading(false);
    }
  }

  /// Update wallet balance when the backend has already applied a credit and returns
  /// the new balance (avoids calling the add-to-wallet API again).
  Future<WalletUpdateResult> updateBalanceFromClaim(
    String userId,
    double newBalanceValue,
    String description,
  ) async {
    if (_currentUserId == null) {
      _currentUserId = userId;
    }

    if (_currentUserId != userId) {
      Logger.warning(
        'User ID mismatch in updateBalanceFromClaim. Expected: $_currentUserId, Got: $userId',
        tag: 'WalletProvider',
      );
      return WalletUpdateResult(success: false, message: 'User ID mismatch');
    }

    // Validate balance value
    if (newBalanceValue < 0) {
      Logger.warning(
        'updateBalanceFromClaim called with negative balance: $newBalanceValue',
        tag: 'WalletProvider',
      );
      return WalletUpdateResult(
        success: false,
        message: 'Invalid balance value',
      );
    }

    final previousBalance = _balance?.currentBalance ?? 0.0;
    Logger.info(
      'Updating wallet balance from claim result: \$${newBalanceValue.toStringAsFixed(2)} (was \$${previousBalance.toStringAsFixed(2)})',
      tag: 'WalletProvider',
    );

    _isLoading = true;
    _clearError();
    _notifyListenersImmediate(); // Notify loading state

    try {
      // Create updated balance object
      final updatedBalance = WalletBalance(
        userId: userId,
        currentBalance: newBalanceValue,
        currency: _balance?.currency ?? 'USD',
        lastUpdated: DateTime.now(),
      );

      // Update provider state
      _balance = updatedBalance;
      _hasLoadedForCurrentUser = true;
      _isLoading = false;
      _lastBalanceUpdateTime = DateTime.now(); // Track update time

      // Save to cache - critical for persistence
      await WalletService.saveBalanceToStorage(updatedBalance);

      // Immediate notification - critical for UI update
      _notifyListenersImmediate();

      Logger.info(
        '✅ Wallet balance updated from claim: \$${newBalanceValue.toStringAsFixed(2)} (was \$${previousBalance.toStringAsFixed(2)})',
        tag: 'WalletProvider',
      );

      return WalletUpdateResult(
        success: true,
        message: description.isNotEmpty
            ? description
            : 'Balance updated successfully',
        newBalance: updatedBalance,
        transactionId: 'CLAIM-${DateTime.now().millisecondsSinceEpoch}',
      );
    } catch (e, stackTrace) {
      Logger.error(
        'Error updating balance from claim: $e',
        tag: 'WalletProvider',
        error: e,
        stackTrace: stackTrace,
      );
      _isLoading = false;
      final errorMsg = 'Failed to update wallet balance: ${e.toString()}';
      _setError(errorMsg);
      notifyListeners();
      return WalletUpdateResult(success: false, message: errorMsg);
    }
  }

  /// Add amount to wallet balance via API (with local fallback).
  ///
  /// Note: This method only affects wallet balance, not the points system.
  /// In test mode or when API fails, updates local balance directly
  /// This method ensures immediate UI updates by calling notifyListeners() multiple times
  Future<WalletUpdateResult> addToBalance(
    double amount,
    String description,
  ) async {
    if (_currentUserId == null) {
      Logger.warning(
        'addToBalance called but user not authenticated',
        tag: 'WalletProvider',
      );
      return WalletUpdateResult(
        success: false,
        message: 'User not authenticated',
      );
    }

    // Validate amount
    if (amount <= 0) {
      Logger.warning(
        'addToBalance called with invalid amount: $amount',
        tag: 'WalletProvider',
      );
      return WalletUpdateResult(
        success: false,
        message: 'Invalid amount. Amount must be greater than 0.',
      );
    }

    // Ensure balance is loaded before updating
    // Use forceRefresh: true to get the latest balance from server
    // This prevents race conditions where we might be working with stale data
    if (_balance == null || !_hasLoadedForCurrentUser) {
      Logger.info(
        'Balance not loaded yet, loading first for user: $_currentUserId',
        tag: 'WalletProvider',
      );
      // Force refresh to get latest balance from server
      await loadBalance(_currentUserId!, forceRefresh: true);

      // If still null after loading, initialize with 0
      if (_balance == null) {
        Logger.info(
          'Balance still null after load, initializing with 0.0',
          tag: 'WalletProvider',
        );
        _balance = WalletBalance(
          userId: _currentUserId!,
          currentBalance: 0.0,
          currency: 'USD',
          lastUpdated: DateTime.now(),
        );
        _hasLoadedForCurrentUser = true;
        _lastBalanceUpdateTime = null; // Reset to allow API calls
        _notifyListenersImmediate();
      }
    }

    final previousBalance = _balance!.currentBalance;
    Logger.info(
      'Adding \$${amount.toStringAsFixed(2)} to wallet. Current: \$${previousBalance.toStringAsFixed(2)}',
      tag: 'WalletProvider',
    );

    _isLoading = true;
    _clearError();
    _notifyListenersImmediate(); // Notify loading state

    try {
      // Try API first
      final result = await WalletService.addToWalletBalance(
        _currentUserId!,
        amount,
        description,
      );

      // Validate API result - check if it succeeded and has valid balance
      if (result.success && result.newBalance != null) {
        final newBalanceValue = result.newBalance!.currentBalance;

        // Validate that the new balance makes sense (should be previous + amount, within tolerance)
        // Allow some tolerance for rounding or if server had a different previous balance
        final expectedMin =
            previousBalance + amount - 0.01; // Small tolerance for rounding
        final expectedMax = previousBalance + amount + 0.01;

        if (newBalanceValue >= expectedMin && newBalanceValue <= expectedMax) {
          _balance = result.newBalance;
          _hasLoadedForCurrentUser = true;
          _isLoading = false;
          _lastBalanceUpdateTime = DateTime.now(); // Track update time

          // Save to cache
          await WalletService.saveBalanceToStorage(result.newBalance!);

          // Immediate notification - critical for UI update
          _notifyListenersImmediate();

          Logger.info(
            '✅ Wallet balance updated via API: \$${newBalanceValue.toStringAsFixed(2)} (was \$${previousBalance.toStringAsFixed(2)}, added \$${amount.toStringAsFixed(2)})',
            tag: 'WalletProvider',
          );
          return result;
        } else {
          Logger.warning(
            'API returned unexpected balance: \$${newBalanceValue.toStringAsFixed(2)} (expected ~\$${(previousBalance + amount).toStringAsFixed(2)}). Using local calculation.',
            tag: 'WalletProvider',
          );
          // Fall through to local update
        }
      } else {
        Logger.info(
          'API call returned success=false or null balance. Result: success=${result.success}, newBalance=${result.newBalance?.currentBalance}. Updating locally.',
          tag: 'WalletProvider',
        );
        // Fall through to local update
      }

      // If API fails or returns unexpected result, update local balance directly
      // This handles test mode, offline scenarios, or API inconsistencies
      Logger.info(
        'Updating local balance directly: + \$${amount.toStringAsFixed(2)}',
        tag: 'WalletProvider',
      );

      final currentBalanceValue = _balance!.currentBalance;
      final newBalanceValue = currentBalanceValue + amount;

      // Validate the calculation
      if (newBalanceValue < currentBalanceValue) {
        Logger.error(
          'Invalid balance calculation: $currentBalanceValue + $amount = $newBalanceValue',
          tag: 'WalletProvider',
        );
        _isLoading = false;
        _setError('Invalid balance calculation');
        notifyListeners();
        return WalletUpdateResult(
          success: false,
          message: 'Invalid balance calculation',
        );
      }

      final updatedBalance = WalletBalance(
        userId: _currentUserId!,
        currentBalance: newBalanceValue,
        currency: _balance!.currency,
        lastUpdated: DateTime.now(),
      );

      _balance = updatedBalance;
      _hasLoadedForCurrentUser = true;
      _isLoading = false;
      _lastBalanceUpdateTime = DateTime.now(); // Track update time

      // Save to cache - critical for persistence
      await WalletService.saveBalanceToStorage(updatedBalance);

      // Immediate notification - critical for UI update
      _notifyListenersImmediate();

      Logger.info(
        '✅ Wallet balance updated locally: \$${updatedBalance.currentBalance.toStringAsFixed(2)} (was \$${previousBalance.toStringAsFixed(2)}, added \$${amount.toStringAsFixed(2)})',
        tag: 'WalletProvider',
      );

      // Verify the balance was actually updated
      if (_balance?.currentBalance != newBalanceValue) {
        Logger.error(
          'Balance state mismatch after update! Expected: \$${newBalanceValue.toStringAsFixed(2)}, Actual: \$${_balance?.currentBalance.toStringAsFixed(2)}',
          tag: 'WalletProvider',
        );
        // Force set it again
        _balance = updatedBalance;
        _notifyListenersImmediate();
      }

      return WalletUpdateResult(
        success: true,
        message: 'Balance updated successfully',
        newBalance: updatedBalance,
        transactionId: 'LOCAL-${DateTime.now().millisecondsSinceEpoch}',
      );
    } catch (e, stackTrace) {
      Logger.error(
        'Error adding to wallet balance: $e',
        tag: 'WalletProvider',
        error: e,
        stackTrace: stackTrace,
      );

      // Fallback: Update local balance even on error
      try {
        final currentBalanceValue = _balance?.currentBalance ?? 0.0;
        final newBalanceValue = currentBalanceValue + amount;

        final updatedBalance = WalletBalance(
          userId: _currentUserId!,
          currentBalance: newBalanceValue,
          currency: _balance?.currency ?? 'USD',
          lastUpdated: DateTime.now(),
        );

        _balance = updatedBalance;
        _hasLoadedForCurrentUser = true;
        _isLoading = false;
        _lastBalanceUpdateTime = DateTime.now(); // Track update time

        // Save to cache
        await WalletService.saveBalanceToStorage(updatedBalance);

        // Immediate notification - critical for UI update
        _notifyListenersImmediate();

        Logger.info(
          '✅ Wallet balance updated locally (fallback): \$${updatedBalance.currentBalance.toStringAsFixed(2)} (was \$${currentBalanceValue.toStringAsFixed(2)}, added \$${amount.toStringAsFixed(2)})',
          tag: 'WalletProvider',
        );

        return WalletUpdateResult(
          success: true,
          message: 'Balance updated (offline mode)',
          newBalance: updatedBalance,
          transactionId: 'LOCAL-${DateTime.now().millisecondsSinceEpoch}',
        );
      } catch (fallbackError, fallbackStackTrace) {
        Logger.error(
          'Error in fallback balance update: $fallbackError',
          tag: 'WalletProvider',
          error: fallbackError,
          stackTrace: fallbackStackTrace,
        );
        _isLoading = false;
        final errorMsg =
            'Failed to update wallet balance: ${fallbackError.toString()}';
        _setError(errorMsg);
        notifyListeners();
        return WalletUpdateResult(success: false, message: errorMsg);
      }
    }
  }

  /// Load cached balance from local storage for [forUserId].
  /// Ignores the result if the active user changed before the read completed.
  Future<void> _loadCachedBalance(String forUserId) async {
    try {
      final balance = await WalletService.getCachedBalance(forUserId);
      if (_currentUserId != forUserId) {
        Logger.info(
          'Ignoring cached wallet result: active user is $_currentUserId, '
          'cache read was for $forUserId',
          tag: 'WalletProvider',
        );
        return;
      }
      if (balance != null) {
        _balance = balance;
        _hasLoadedForCurrentUser = true;
        notifyListeners();
        Logger.info(
          'Cached wallet balance loaded: \$${balance.currentBalance}',
          tag: 'WalletProvider',
        );
      } else {
        // Initialize with zero balance if no cache exists
        _balance = WalletBalance(
          userId: forUserId,
          currentBalance: 0.0,
          currency: 'USD',
          lastUpdated: DateTime.now(),
        );
        _hasLoadedForCurrentUser = true;
        notifyListeners();
        Logger.info(
          'No cached balance found, initialized with 0.00 Ks',
          tag: 'WalletProvider',
        );
      }
    } catch (e) {
      Logger.error(
        'Error loading cached wallet balance: $e',
        tag: 'WalletProvider',
        error: e,
      );
      if (_currentUserId != forUserId) {
        return;
      }
      // Initialize with zero balance on error
      _balance = WalletBalance(
        userId: forUserId,
        currentBalance: 0.0,
        currency: 'USD',
        lastUpdated: DateTime.now(),
      );
      _hasLoadedForCurrentUser = true;
      notifyListeners();
    }
  }

  /// Set loading state
  /// Notifies listeners (deferred to next frame to avoid build phase conflicts)
  void _setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      // Always defer notification to avoid build phase conflicts
      // This is safe because loading state changes are not time-critical
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_isLoading == loading) {
          notifyListeners();
        }
      });
    }
  }

  /// Set error message
  void _setError(String error) {
    _errorMessage = error;
    notifyListeners();
  }

  /// Clear error message
  void _clearError() {
    _errorMessage = null;
  }

  /// OPTIMIZED: Notify listeners with debouncing to prevent excessive rebuilds
  /// Single notification call instead of triple notification (sync + async + post-frame)
  /// This reduces CPU usage and prevents unnecessary widget rebuilds
  void _notifyListenersImmediate() {
    // Cancel any pending debounce timer
    _notificationDebounceTimer?.cancel();

    // Use a short debounce to batch rapid updates
    _notificationDebounceTimer = Timer(_debounceDelay, () {
      notifyListeners();
      final currentBalance = _balance?.currentBalance ?? 0.0;
      if (kDebugMode) {
        Logger.debug(
          'WalletProvider: Balance updated - \$${currentBalance.toStringAsFixed(2)}',
          tag: 'WalletProvider',
        );
      }
    });
  }

  /// OPTIMIZED: Force notification of listeners immediately
  /// Single notification call instead of triple notification for better performance
  void forceNotifyListeners() {
    // Cancel any pending debounce to notify immediately
    _notificationDebounceTimer?.cancel();
    _notificationDebounceTimer = null;

    // Single immediate notification
    notifyListeners();

    if (kDebugMode) {
      Logger.debug(
        'WalletProvider: forceNotifyListeners called - Balance: \$${currentBalance.toStringAsFixed(2)}',
        tag: 'WalletProvider',
      );
    }
  }

  @override
  void dispose() {
    _notificationDebounceTimer?.cancel();
    _notificationDebounceTimer = null;
    super.dispose();
  }

  /// Check if balance was recently updated (within last N seconds)
  /// Useful for preventing race conditions
  bool wasRecentlyUpdated({int seconds = 3}) {
    if (_lastBalanceUpdateTime == null) return false;
    final timeSinceUpdate = DateTime.now().difference(_lastBalanceUpdateTime!);
    return timeSinceUpdate.inSeconds < seconds;
  }

  /// Withdraw amount from wallet balance
  /// Processes withdrawal/transfer to external payment methods
  ///
  /// Flow: Withdrawal Request → API Processing → Balance Updated → UI Updated
  ///
  /// Supported methods: KPay, AYA Pay, Wave Pay, Bank Transfer
  Future<WithdrawalResult> withdrawFromBalance(
    WithdrawalRequest request,
  ) async {
    if (_currentUserId == null) {
      Logger.warning(
        'withdrawFromBalance called but user not authenticated',
        tag: 'WalletProvider',
      );
      return WithdrawalResult.failure(
        message: 'User not authenticated',
        errorCode: 'NOT_AUTHENTICATED',
        request: request,
      );
    }

    // Validate user ID matches
    if (request.userId != _currentUserId) {
      Logger.warning(
        'User ID mismatch. Request userId: ${request.userId}, Current userId: $_currentUserId',
        tag: 'WalletProvider',
      );
      return WithdrawalResult.failure(
        message: 'User ID mismatch',
        errorCode: 'USER_MISMATCH',
        request: request,
      );
    }

    // Ensure balance is loaded
    if (_balance == null || !_hasLoadedForCurrentUser) {
      Logger.info(
        'Balance not loaded yet, loading first for user: $_currentUserId',
        tag: 'WalletProvider',
      );
      await loadBalance(_currentUserId!, forceRefresh: true);

      if (_balance == null) {
        Logger.warning('Balance still null after load', tag: 'WalletProvider');
        return WithdrawalResult.failure(
          message: 'Unable to load wallet balance. Please try again.',
          errorCode: 'BALANCE_LOAD_FAILED',
          request: request,
        );
      }
    }

    // Validate sufficient balance
    final currentBalance = _balance!.currentBalance;
    if (currentBalance < request.amount) {
      Logger.warning(
        'Insufficient balance. Current: \$${currentBalance.toStringAsFixed(2)}, Requested: \$${request.amount.toStringAsFixed(2)}',
        tag: 'WalletProvider',
      );
      return WithdrawalResult.failure(
        message:
            'Insufficient balance. Available: \$${currentBalance.toStringAsFixed(2)}',
        errorCode: 'INSUFFICIENT_BALANCE',
        request: request,
      );
    }

    final previousBalance = currentBalance;
    Logger.info(
      'Processing withdrawal: \$${request.amount.toStringAsFixed(2)} via ${request.method.displayName}. Current balance: \$${previousBalance.toStringAsFixed(2)}',
      tag: 'WalletProvider',
    );

    _isLoading = true;
    _clearError();
    _notifyListenersImmediate(); // Notify loading state

    try {
      // Process withdrawal via service
      final result = await WithdrawalService.requestWithdrawal(request);

      if (result.success) {
        // Calculate new balance (subtract withdrawal amount)
        final newBalanceValue = previousBalance - request.amount;

        // Update balance if API returned new balance, otherwise use calculated value
        final updatedBalance = WalletBalance(
          userId: _currentUserId!,
          currentBalance: result.newBalance ?? newBalanceValue,
          currency: _balance!.currency,
          lastUpdated: DateTime.now(),
        );

        _balance = updatedBalance;
        _hasLoadedForCurrentUser = true;
        _isLoading = false;
        _lastBalanceUpdateTime = DateTime.now();

        // Save to cache
        await WalletService.saveBalanceToStorage(updatedBalance);

        // Immediate notification for UI update
        _notifyListenersImmediate();

        Logger.info(
          '✅ Withdrawal processed successfully: \$${request.amount.toStringAsFixed(2)} via ${request.method.displayName}. New balance: \$${updatedBalance.currentBalance.toStringAsFixed(2)} (was \$${previousBalance.toStringAsFixed(2)})',
          tag: 'WalletProvider',
        );

        // Return result with updated balance
        return WithdrawalResult.success(
          message: result.message,
          transactionId: result.transactionId,
          newBalance: updatedBalance.currentBalance,
          processedAt: result.processedAt,
          request: request,
        );
      } else {
        // Withdrawal failed
        _isLoading = false;
        _setError(result.message);
        notifyListeners();

        Logger.warning(
          '❌ Withdrawal failed: ${result.message} (Error code: ${result.errorCode})',
          tag: 'WalletProvider',
        );

        return result;
      }
    } catch (e, stackTrace) {
      Logger.error(
        'Error processing withdrawal: $e',
        tag: 'WalletProvider',
        error: e,
        stackTrace: stackTrace,
      );

      _isLoading = false;
      final errorMsg = 'Failed to process withdrawal. Please try again.';
      _setError(errorMsg);
      notifyListeners();

      return WithdrawalResult.failure(
        message: errorMsg,
        errorCode: 'EXCEPTION',
        request: request,
      );
    }
  }

  /// Check withdrawal eligibility
  /// Validates if user can withdraw the specified amount
  Future<Map<String, dynamic>> checkWithdrawalEligibility(double amount) async {
    if (_currentUserId == null) {
      return {'eligible': false, 'message': 'User not authenticated'};
    }

    // Check current balance
    if (_balance == null || !_hasLoadedForCurrentUser) {
      await loadBalance(_currentUserId!, forceRefresh: true);
    }

    final currentBalance = _balance?.currentBalance ?? 0.0;

    if (currentBalance < amount) {
      return {
        'eligible': false,
        'message':
            'Insufficient balance. Available: \$${currentBalance.toStringAsFixed(2)}',
      };
    }

    if (amount < WithdrawalService.minWithdrawalAmount) {
      return {
        'eligible': false,
        'message':
            'Minimum withdrawal amount is \$${WithdrawalService.minWithdrawalAmount.toStringAsFixed(2)}',
      };
    }

    if (amount > WithdrawalService.maxWithdrawalAmount) {
      return {
        'eligible': false,
        'message':
            'Maximum withdrawal amount is \$${WithdrawalService.maxWithdrawalAmount.toStringAsFixed(2)} per transaction',
      };
    }

    // Check with service for additional eligibility criteria
    final eligibility = await WithdrawalService.checkWithdrawalEligibility(
      _currentUserId!,
      amount,
    );

    return eligibility;
  }

  /// Get withdrawal history
  Future<List<WithdrawalHistoryEntry>> getWithdrawalHistory() async {
    if (_currentUserId == null) {
      Logger.warning(
        'getWithdrawalHistory called but user not authenticated',
        tag: 'WalletProvider',
      );
      return [];
    }

    try {
      return await WithdrawalService.getWithdrawalHistory(_currentUserId!);
    } catch (e, stackTrace) {
      Logger.error(
        'Error fetching withdrawal history: $e',
        tag: 'WalletProvider',
        error: e,
        stackTrace: stackTrace,
      );
      return [];
    }
  }
}
