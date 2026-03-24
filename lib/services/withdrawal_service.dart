import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/withdrawal.dart';
import '../utils/app_config.dart';
import '../utils/logger.dart';
import '../utils/network_utils.dart';

/// Withdrawal service for handling wallet withdrawals/transfers
/// Supports multiple payment methods: KPay, AYA Pay, Wave Pay, Bank Transfer
///
/// Architecture:
/// - API-first design ready for real backend integration
/// - Fallback to local simulation in debug/test mode
/// - Comprehensive error handling and validation
/// - Transaction history tracking
class WithdrawalService {
  /// Get WooCommerce authentication query parameters
  static Map<String, String> _getWooCommerceAuthQueryParams() {
    return {
      'consumer_key': AppConfig.consumerKey,
      'consumer_secret': AppConfig.consumerSecret,
    };
  }

  /// Minimum withdrawal amount (configurable)
  static const double minWithdrawalAmount = 1.0;

  /// Maximum withdrawal amount per transaction (configurable)
  static const double maxWithdrawalAmount = 10000.0;

  /// Request withdrawal/transfer from wallet
  ///
  /// Flow:
  /// 1. Validate request parameters
  /// 2. Call API to process withdrawal
  /// 3. Return result with updated balance
  ///
  /// Note: In test mode, simulates API call with delay
  static Future<WithdrawalResult> requestWithdrawal(
      WithdrawalRequest request) async {
    // Validate request
    final validationError = _validateRequest(request);
    if (validationError != null) {
      Logger.warning('Withdrawal request validation failed: $validationError',
          tag: 'WithdrawalService');
      return WithdrawalResult.failure(
        message: validationError,
        errorCode: 'INVALID_REQUEST',
        request: request,
      );
    }

    try {
      Logger.info(
          'Processing withdrawal request: \$${request.amount.toStringAsFixed(2)} via ${request.method.displayName} to ${request.accountNumber}',
          tag: 'WithdrawalService');

      // In debug mode, simulate API call for testing
      if (kDebugMode) {
        return await _simulateWithdrawal(request);
      }

      // Real API call
      return await _processWithdrawalApi(request);
    } catch (e, stackTrace) {
      Logger.error('Error processing withdrawal: $e',
          tag: 'WithdrawalService', error: e, stackTrace: stackTrace);

      // Fallback to simulation in debug mode on error
      if (kDebugMode) {
        Logger.info('API failed, simulating withdrawal in debug mode',
            tag: 'WithdrawalService');
        return await _simulateWithdrawal(request, isFallback: true);
      }

      return WithdrawalResult.failure(
        message: 'Network error. Please check your connection and try again.',
        errorCode: 'NETWORK_ERROR',
        request: request,
      );
    }
  }

  /// Process withdrawal via API
  static Future<WithdrawalResult> _processWithdrawalApi(
      WithdrawalRequest request) async {
    final uri = Uri.parse(
      '${AppConfig.backendUrl}/wp-json/twork/v1/wallet/withdraw',
    ).replace(queryParameters: _getWooCommerceAuthQueryParams());

    final response = await NetworkUtils.executeRequest(
      () => http.post(
        uri,
        headers: const {
          'Content-Type': 'application/json',
        },
        body: json.encode(request.toJson()),
      ),
      context: 'requestWithdrawal',
    );

    if (NetworkUtils.isValidResponse(response)) {
      final data = json.decode(response!.body);

      if (data['success'] == true) {
        return WithdrawalResult.success(
          message: data['message']?.toString() ??
              'Withdrawal request processed successfully',
          transactionId: data['transaction_id']?.toString(),
          newBalance: (data['new_balance'] as num?)?.toDouble(),
          processedAt: data['processed_at'] != null
              ? DateTime.parse(data['processed_at'])
              : DateTime.now(),
          request: request,
        );
      } else {
        return WithdrawalResult.failure(
          message: data['message']?.toString() ??
              'Failed to process withdrawal request',
          errorCode: data['error_code']?.toString(),
          request: request,
        );
      }
    }

    return WithdrawalResult.failure(
      message: 'Invalid response from server. Please try again.',
      errorCode: 'INVALID_RESPONSE',
      request: request,
    );
  }

  /// Simulate withdrawal for testing (debug mode only)
  static Future<WithdrawalResult> _simulateWithdrawal(
    WithdrawalRequest request, {
    bool isFallback = false,
  }) async {
    // Simulate API delay
    await Future.delayed(const Duration(milliseconds: 1500));

    // Simulate success (90% success rate in simulation)
    final isSuccess =
        !isFallback; // Always succeed in test mode unless fallback

    if (isSuccess) {
      Logger.info(
          '✅ Withdrawal simulated successfully: \$${request.amount.toStringAsFixed(2)} via ${request.method.displayName}',
          tag: 'WithdrawalService');

      // Generate mock transaction ID
      final transactionId =
          'WD-${DateTime.now().millisecondsSinceEpoch}-${request.method.code.toUpperCase()}';

      return WithdrawalResult.success(
        message: 'Withdrawal request submitted successfully. '
            'Processing may take 1-3 business days.',
        transactionId: transactionId,
        newBalance: null, // Will be updated by WalletProvider
        processedAt: DateTime.now(),
        request: request,
      );
    } else {
      // Simulate failure (rare cases)
      return WithdrawalResult.failure(
        message: 'Insufficient funds or service unavailable',
        errorCode: 'INSUFFICIENT_FUNDS',
        request: request,
      );
    }
  }

  /// Validate withdrawal request
  static String? _validateRequest(WithdrawalRequest request) {
    // Validate amount
    if (request.amount <= 0) {
      return 'Amount must be greater than 0';
    }

    if (request.amount < minWithdrawalAmount) {
      return 'Minimum withdrawal amount is \$${minWithdrawalAmount.toStringAsFixed(2)}';
    }

    if (request.amount > maxWithdrawalAmount) {
      return 'Maximum withdrawal amount is \$${maxWithdrawalAmount.toStringAsFixed(2)} per transaction';
    }

    // Validate account number
    if (request.accountNumber.trim().isEmpty) {
      return 'Account number is required';
    }

    // Validate account number format based on method
    final accountNumber = request.accountNumber.trim();
    switch (request.method) {
      // All mobile payment methods (except bank)
      case WithdrawalMethod.kpay:
      case WithdrawalMethod.ayaPay:
      case WithdrawalMethod.wavePay:
      case WithdrawalMethod.cbPay:
      case WithdrawalMethod.uabPay:
      case WithdrawalMethod.onepay:
      case WithdrawalMethod.trueMoney:
      case WithdrawalMethod.mpitesan:
      case WithdrawalMethod.yomaPay:
      case WithdrawalMethod.agdPay:
      case WithdrawalMethod.mabPay:
        // Mobile payment - should be phone number format
        if (accountNumber.length < 9 || accountNumber.length > 15) {
          return 'Please enter a valid phone number';
        }
        // Check if it's numeric
        if (!RegExp(r'^[0-9]+$').hasMatch(accountNumber)) {
          return 'Phone number should contain only digits';
        }
        break;
      case WithdrawalMethod.bank:
        // Bank transfer - validate bank name
        if (request.bankName == null || request.bankName!.trim().isEmpty) {
          return 'Bank name is required for bank transfers';
        }
        // Account number should be valid
        if (accountNumber.length < 8 || accountNumber.length > 20) {
          return 'Please enter a valid bank account number';
        }
        break;
    }

    return null; // Validation passed
  }

  /// Get withdrawal history for user
  ///
  /// Returns list of withdrawal transactions for the user
  static Future<List<WithdrawalHistoryEntry>> getWithdrawalHistory(
      String userId) async {
    try {
      final uri = Uri.parse(
        '${AppConfig.backendUrl}/wp-json/twork/v1/wallet/withdrawals/$userId',
      ).replace(queryParameters: _getWooCommerceAuthQueryParams());

      final response = await NetworkUtils.executeRequest(
        () => http.get(
          uri,
          headers: const {
            'Content-Type': 'application/json',
          },
        ),
        context: 'getWithdrawalHistory',
      );

      if (NetworkUtils.isValidResponse(response)) {
        final data = json.decode(response!.body);
        if (data is List) {
          return data
              .map((entry) => WithdrawalHistoryEntry.fromJson(entry))
              .toList();
        } else if (data['withdrawals'] is List) {
          return (data['withdrawals'] as List)
              .map((entry) => WithdrawalHistoryEntry.fromJson(entry))
              .toList();
        }
      }

      // Return empty list if API fails
      return [];
    } catch (e, stackTrace) {
      Logger.error('Error fetching withdrawal history: $e',
          tag: 'WithdrawalService', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  /// Check if withdrawal is allowed
  /// Validates minimum balance, daily limits, etc.
  static Future<Map<String, dynamic>> checkWithdrawalEligibility(
      String userId, double amount) async {
    try {
      final uri = Uri.parse(
        '${AppConfig.backendUrl}/wp-json/twork/v1/wallet/check-withdrawal',
      ).replace(queryParameters: {
        ..._getWooCommerceAuthQueryParams(),
        'user_id': userId,
        'amount': amount.toString(),
      });

      final response = await NetworkUtils.executeRequest(
        () => http.get(
          uri,
          headers: const {
            'Content-Type': 'application/json',
          },
        ),
        context: 'checkWithdrawalEligibility',
      );

      if (NetworkUtils.isValidResponse(response)) {
        final data = json.decode(response!.body);
        return {
          'eligible': data['eligible'] == true,
          'message': data['message']?.toString() ?? '',
          'remaining_daily_limit':
              (data['remaining_daily_limit'] as num?)?.toDouble(),
        };
      }

      // Default: allow if API unavailable (will be validated on actual withdrawal)
      return {
        'eligible': true,
        'message': '',
      };
    } catch (e) {
      Logger.warning('Error checking withdrawal eligibility: $e',
          tag: 'WithdrawalService');
      // Default: allow if API unavailable
      return {
        'eligible': true,
        'message': '',
      };
    }
  }
}
