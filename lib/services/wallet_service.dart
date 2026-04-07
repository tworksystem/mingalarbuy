import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api_service.dart';
import '../utils/app_config.dart';
import '../utils/logger.dart';
import '../utils/network_utils.dart';
import 'secure_prefs.dart';

/// Wallet service for managing user wallet balance
/// Handles API calls and local storage for wallet balance
class WalletService {
  static const String _balanceKey = 'user_wallet_balance';
  static final SecurePrefs _securePrefs = SecurePrefs.instance;

  /// Get WooCommerce authentication query parameters
  static Map<String, String> _getWooCommerceAuthQueryParams() {
    return {
      'consumer_key': AppConfig.consumerKey,
      'consumer_secret': AppConfig.consumerSecret,
    };
  }

  /// Get user's wallet balance from API
  static Future<WalletBalance?> getWalletBalance(String userId) async {
    try {
      final uri = Uri.parse(
        '${AppConfig.backendUrl}/wp-json/twork/v1/wallet/balance/$userId',
      ).replace(queryParameters: _getWooCommerceAuthQueryParams());

      final Response<dynamic>? response = await ApiService.executeWithRetry(
        () => ApiService.get(
          uri.path,
          queryParameters: uri.queryParameters,
          skipAuth: false,
          headers: const <String, dynamic>{
            'Content-Type': 'application/json',
          },
        ),
        context: 'getWalletBalance',
      );

      if (NetworkUtils.isValidDioResponse(response)) {
        final Map<String, dynamic>? data = ApiService.responseAsJsonMap(response);
        if (data == null) {
          return null;
        }

        final balance = WalletBalance(
          userId: userId,
          currentBalance: (data['current_balance'] as num?)?.toDouble() ?? 0.0,
          currency: data['currency']?.toString() ?? 'USD',
          lastUpdated: data['last_updated'] != null
              ? DateTime.parse(data['last_updated'])
              : DateTime.now(),
        );

        // Cache balance locally
        await saveBalanceToStorage(balance);

        Logger.info(
            'Wallet balance loaded from API: \$${balance.currentBalance}',
            tag: 'WalletService');
        return balance;
      }

      return null;
    } catch (e, stackTrace) {
      Logger.error('Error getting wallet balance: $e',
          tag: 'WalletService', error: e, stackTrace: stackTrace);
      // Return cached balance on error
      return await getCachedBalance(userId);
    }
  }

  /// Add amount to wallet balance
  /// Returns updated balance if successful, or null if failed
  static Future<WalletUpdateResult> addToWalletBalance(
      String userId, double amount, String description) async {
    try {
      // Validate inputs
      if (userId.isEmpty) {
        Logger.error('Invalid userId: empty string', tag: 'WalletService');
        return WalletUpdateResult(
          success: false,
          message: 'Invalid user ID',
        );
      }

      if (amount <= 0) {
        Logger.error('Invalid amount: $amount', tag: 'WalletService');
        return WalletUpdateResult(
          success: false,
          message: 'Invalid amount. Amount must be greater than 0.',
        );
      }

      Logger.info(
          'Adding \$${amount.toStringAsFixed(2)} to wallet for user: $userId',
          tag: 'WalletService');

      final uri = Uri.parse(
        '${AppConfig.backendUrl}/wp-json/twork/v1/wallet/add',
      ).replace(queryParameters: _getWooCommerceAuthQueryParams());

      final Response<dynamic>? response = await ApiService.executeWithRetry(
        () => ApiService.post(
          uri.path,
          queryParameters: uri.queryParameters,
          skipAuth: false,
          headers: const <String, dynamic>{
            'Content-Type': 'application/json',
          },
          data: <String, dynamic>{
            'user_id': userId,
            'amount': amount,
            'description': description,
          },
        ),
        context: 'addToWalletBalance',
      );

      if (NetworkUtils.isValidDioResponse(response)) {
        final Map<String, dynamic>? data = ApiService.responseAsJsonMap(response);
        if (data == null) {
          Logger.warning('Invalid API response or network error',
              tag: 'WalletService');
          return WalletUpdateResult(
            success: false,
            message: 'Failed to update balance. Please try again.',
          );
        }

        Logger.info(
            'API response: success=${data['success']}, new_balance=${data['new_balance']}',
            tag: 'WalletService');

        if (data['success'] == true) {
          final newBalanceValue = (data['new_balance'] as num?)?.toDouble();

          // Validate the response has a balance value
          if (newBalanceValue == null) {
            Logger.error('API returned success=true but new_balance is null',
                tag: 'WalletService');
            return WalletUpdateResult(
              success: false,
              message: 'Invalid response from server: missing balance',
            );
          }

          // Validate balance is not negative
          if (newBalanceValue < 0) {
            Logger.error('API returned negative balance: $newBalanceValue',
                tag: 'WalletService');
            return WalletUpdateResult(
              success: false,
              message: 'Invalid balance returned from server',
            );
          }

          final newBalance = WalletBalance(
            userId: userId,
            currentBalance: newBalanceValue,
            currency: data['currency']?.toString() ?? 'USD',
            lastUpdated: DateTime.now(),
          );

          // Update cache
          await saveBalanceToStorage(newBalance);

          Logger.info(
              '✅ Wallet balance updated via API: \$${newBalanceValue.toStringAsFixed(2)}',
              tag: 'WalletService');

          return WalletUpdateResult(
            success: true,
            message:
                data['message']?.toString() ?? 'Balance updated successfully',
            newBalance: newBalance,
            transactionId: data['transaction_id']?.toString(),
          );
        } else {
          final errorMessage =
              data['message']?.toString() ?? 'Failed to update balance';
          Logger.warning('API returned success=false: $errorMessage',
              tag: 'WalletService');
          return WalletUpdateResult(
            success: false,
            message: errorMessage,
          );
        }
      }

      Logger.warning('Invalid API response or network error',
          tag: 'WalletService');
      return WalletUpdateResult(
        success: false,
        message: 'Failed to update balance. Please try again.',
      );
    } catch (e, stackTrace) {
      Logger.error('Error adding to wallet balance: $e',
          tag: 'WalletService', error: e, stackTrace: stackTrace);
      return WalletUpdateResult(
        success: false,
        message: 'Network error. Please check your connection.',
      );
    }
  }

  /// Get cached wallet balance
  static Future<WalletBalance?> getCachedBalance(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedValue = prefs.getString('$_balanceKey$userId');

      if (storedValue != null) {
        final decrypted =
            await _securePrefs.maybeDecrypt(storedValue) ?? storedValue;
        final balanceData = json.decode(decrypted);
        final balance = WalletBalance.fromJson(balanceData);
        if (balance.userId == userId) {
          Logger.info(
              'Cached wallet balance loaded: \$${balance.currentBalance}',
              tag: 'WalletService');
          return balance;
        }
      }
    } catch (e) {
      Logger.error('Error loading cached wallet balance: $e',
          tag: 'WalletService', error: e);
    }
    return null;
  }

  /// Save balance to secure storage (public for provider use)
  static Future<void> saveBalanceToStorage(WalletBalance balance) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final balanceJson = json.encode(balance.toJson());
      final encrypted = await _securePrefs.encrypt(balanceJson);
      await prefs.setString('$_balanceKey${balance.userId}', encrypted);
      Logger.info('Wallet balance cached to secure storage',
          tag: 'WalletService');
    } catch (e) {
      Logger.error('Error caching wallet balance: $e',
          tag: 'WalletService', error: e);
    }
  }
}

/// Wallet balance model
class WalletBalance {
  final String userId;
  final double currentBalance;
  final String currency;
  final DateTime lastUpdated;

  WalletBalance({
    required this.userId,
    required this.currentBalance,
    this.currency = 'USD',
    required this.lastUpdated,
  });

  factory WalletBalance.fromJson(Map<String, dynamic> json) {
    return WalletBalance(
      userId: json['user_id']?.toString() ?? json['userId']?.toString() ?? '',
      currentBalance: (json['current_balance'] as num?)?.toDouble() ??
          (json['currentBalance'] as num?)?.toDouble() ??
          0.0,
      currency: json['currency']?.toString() ?? 'USD',
      lastUpdated: json['last_updated'] != null
          ? DateTime.parse(json['last_updated'])
          : json['lastUpdated'] != null
              ? DateTime.parse(json['lastUpdated'])
              : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'current_balance': currentBalance,
      'currency': currency,
      'last_updated': lastUpdated.toIso8601String(),
    };
  }

  String get formattedBalance {
    return '${currentBalance.toStringAsFixed(2)} Ks';
  }

  String get formattedBalanceWithoutSymbol {
    return currentBalance.toStringAsFixed(2);
  }
}

/// Wallet update result
class WalletUpdateResult {
  final bool success;
  final String message;
  final WalletBalance? newBalance;
  final String? transactionId;

  WalletUpdateResult({
    required this.success,
    required this.message,
    this.newBalance,
    this.transactionId,
  });
}
