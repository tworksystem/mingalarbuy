import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../utils/app_config.dart';
import '../utils/logger.dart';
import '../utils/network_utils.dart';

/// Prize code service for validating and claiming prize codes
/// Handles API calls for prize code redemption
class PrizeCodeService {
  /// Get WooCommerce authentication query parameters
  static Map<String, String> _getWooCommerceAuthQueryParams() {
    return {
      'consumer_key': AppConfig.consumerKey,
      'consumer_secret': AppConfig.consumerSecret,
    };
  }

  /// Test codes for development (only works in debug mode)
  static final Map<String, Map<String, dynamic>> _testCodes = {
    'TEST100': {
      'prize_value': 10.00,
      'description': 'Test Prize - 10 Ks',
    },
    'TEST500': {
      'prize_value': 50.00,
      'description': 'Test Prize - 50 Ks',
    },
    'TEST1000': {
      'prize_value': 100.00,
      'description': 'Test Prize - 100 Ks',
    },
    'WELCOME': {
      'prize_value': 5.00,
      'description': 'Welcome Bonus',
    },
    'PRIZE2024': {
      'prize_value': 25.00,
      'description': '2024 Special Prize',
    },
  };

  /// Validate prize code (check if code exists and is valid)
  /// Returns prize details if valid, null if invalid
  /// 
  /// Note: Prize codes ONLY affect wallet balance, NOT point system
  /// The prizeValue will be added to wallet balance in Profile → Wallet → Payment → Current account balance
  static Future<PrizeCodeValidationResult?> validatePrizeCode(
      String code) async {
    // Development mode: Use test codes if backend is not available
    if (kDebugMode && _testCodes.containsKey(code.toUpperCase())) {
      final testCode = _testCodes[code.toUpperCase()]!;
      Logger.info('Using test code: $code', tag: 'PrizeCodeService');
      return PrizeCodeValidationResult(
        isValid: true,
        code: code.toUpperCase(),
        prizeValue: testCode['prize_value'] as double,
        prizePoints: 0,
        description: testCode['description'] as String,
        message: 'Test code is valid',
      );
    }

    try {
      final uri = Uri.parse(
        '${AppConfig.backendUrl}/wp-json/twork/v1/prize/validate',
      ).replace(queryParameters: {
        ..._getWooCommerceAuthQueryParams(),
        'code': code,
      });

      final response = await NetworkUtils.executeRequest(
        () => http.get(
          uri,
          headers: const {
            'Content-Type': 'application/json',
          },
        ),
        context: 'validatePrizeCode',
      );

      if (NetworkUtils.isValidResponse(response)) {
        final data = json.decode(response!.body);

        if (data['valid'] == true) {
          return PrizeCodeValidationResult(
            isValid: true,
            code: code,
            prizeValue: (data['prize_value'] as num?)?.toDouble() ?? 0.0,
            prizePoints: (data['prize_points'] as num?)?.toInt() ?? 0,
            description:
                data['description']?.toString() ?? 'Prize code redeemed',
            message: data['message']?.toString() ?? 'Code is valid',
          );
        } else {
          return PrizeCodeValidationResult(
            isValid: false,
            code: code,
            message: data['message']?.toString() ?? 'Invalid code',
          );
        }
      }

      // Fallback to test codes in debug mode if API fails
      if (kDebugMode && _testCodes.containsKey(code.toUpperCase())) {
        final testCode = _testCodes[code.toUpperCase()]!;
        Logger.info('API failed, using test code: $code',
            tag: 'PrizeCodeService');
        return PrizeCodeValidationResult(
          isValid: true,
          code: code.toUpperCase(),
          prizeValue: testCode['prize_value'] as double,
          prizePoints: 0,
          description: testCode['description'] as String,
          message: 'Test code is valid (API unavailable)',
        );
      }

      return PrizeCodeValidationResult(
        isValid: false,
        code: code,
        message: 'Failed to validate code. Please try again.',
      );
    } catch (e, stackTrace) {
      Logger.error('Error validating prize code: $e',
          tag: 'PrizeCodeService', error: e, stackTrace: stackTrace);

      // Fallback to test codes in debug mode on error
      if (kDebugMode && _testCodes.containsKey(code.toUpperCase())) {
        final testCode = _testCodes[code.toUpperCase()]!;
        Logger.info('Network error, using test code: $code',
            tag: 'PrizeCodeService');
        return PrizeCodeValidationResult(
          isValid: true,
          code: code.toUpperCase(),
          prizeValue: testCode['prize_value'] as double,
          prizePoints: 0,
          description: testCode['description'] as String,
          message: 'Test code is valid (offline mode)',
        );
      }

      return PrizeCodeValidationResult(
        isValid: false,
        code: code,
        message: 'Network error. Please check your connection.',
      );
    }
  }

  /// Claim prize code for a user
  /// Returns claim result with new wallet balance if successful
  /// 
  /// Flow:
  /// 1. User enters code
  /// 2. Code is validated
  /// 3. Code is claimed
  /// 4. prizeValue is added to wallet balance ONLY (NOT points)
  /// 5. Wallet balance updates in Profile → Wallet → Payment → Current account balance
  /// 
  /// Note: This method ONLY affects wallet balance, never the point system
  static Future<PrizeCodeClaimResult> claimPrizeCode(
      String userId, String code) async {
    // Development mode: Use test codes if backend is not available
    if (kDebugMode && _testCodes.containsKey(code.toUpperCase())) {
      final testCode = _testCodes[code.toUpperCase()]!;
      final prizeValue = testCode['prize_value'] as double;

      Logger.info('Claiming test code: $code for user: $userId',
          tag: 'PrizeCodeService');

      // Simulate API delay
      await Future.delayed(const Duration(milliseconds: 500));

      return PrizeCodeClaimResult(
        success: true,
        message: 'Test prize claimed successfully!',
        prizeValue: prizeValue,
        prizePoints: 0,
        newWalletBalance: null, // Will be updated by wallet service
        transactionId: 'TEST-${DateTime.now().millisecondsSinceEpoch}',
      );
    }

    try {
      final uri = Uri.parse(
        '${AppConfig.backendUrl}/wp-json/twork/v1/prize/claim',
      ).replace(queryParameters: _getWooCommerceAuthQueryParams());

      final response = await NetworkUtils.executeRequest(
        () => http.post(
          uri,
          headers: const {
            'Content-Type': 'application/json',
          },
          body: json.encode({
            'user_id': userId,
            'code': code,
          }),
        ),
        context: 'claimPrizeCode',
      );

      if (NetworkUtils.isValidResponse(response)) {
        final data = json.decode(response!.body);

        if (data['success'] == true) {
          return PrizeCodeClaimResult(
            success: true,
            message:
                data['message']?.toString() ?? 'Prize claimed successfully!',
            prizeValue: (data['prize_value'] as num?)?.toDouble() ?? 0.0,
            prizePoints: (data['prize_points'] as num?)?.toInt() ?? 0,
            newWalletBalance:
                (data['new_wallet_balance'] as num?)?.toDouble() ?? 0.0,
            transactionId: data['transaction_id']?.toString(),
          );
        } else {
          return PrizeCodeClaimResult(
            success: false,
            message: data['message']?.toString() ?? 'Failed to claim prize',
          );
        }
      }

      // Fallback to test codes in debug mode if API fails
      if (kDebugMode && _testCodes.containsKey(code.toUpperCase())) {
        final testCode = _testCodes[code.toUpperCase()]!;
        final prizeValue = testCode['prize_value'] as double;

        Logger.info('API failed, claiming test code: $code',
            tag: 'PrizeCodeService');

        return PrizeCodeClaimResult(
          success: true,
          message: 'Test prize claimed successfully! (API unavailable)',
          prizeValue: prizeValue,
          prizePoints: 0,
          newWalletBalance: null,
          transactionId: 'TEST-${DateTime.now().millisecondsSinceEpoch}',
        );
      }

      return PrizeCodeClaimResult(
        success: false,
        message: 'Failed to claim prize. Please try again.',
      );
    } catch (e, stackTrace) {
      Logger.error('Error claiming prize code: $e',
          tag: 'PrizeCodeService', error: e, stackTrace: stackTrace);

      // Fallback to test codes in debug mode on error
      if (kDebugMode && _testCodes.containsKey(code.toUpperCase())) {
        final testCode = _testCodes[code.toUpperCase()]!;
        final prizeValue = testCode['prize_value'] as double;

        Logger.info('Network error, claiming test code: $code',
            tag: 'PrizeCodeService');

        return PrizeCodeClaimResult(
          success: true,
          message: 'Test prize claimed successfully! (offline mode)',
          prizeValue: prizeValue,
          prizePoints: 0,
          newWalletBalance: null,
          transactionId: 'TEST-${DateTime.now().millisecondsSinceEpoch}',
        );
      }

      return PrizeCodeClaimResult(
        success: false,
        message: 'Network error. Please check your connection.',
      );
    }
  }
}

/// Prize code validation result
/// Note: prizePoints is kept for API backward compatibility only (always 0)
/// Prize codes only affect wallet balance, not point system
class PrizeCodeValidationResult {
  final bool isValid;
  final String code;
  final double? prizeValue; // Amount to add to wallet balance
  final int? prizePoints; // Always 0 - kept for API compatibility only
  final String? description;
  final String message;

  PrizeCodeValidationResult({
    required this.isValid,
    required this.code,
    this.prizeValue,
    this.prizePoints = 0, // Always 0 - prize codes don't affect points
    this.description,
    required this.message,
  });
}

/// Prize code claim result
/// Note: prizePoints is kept for API backward compatibility only (always 0)
/// Prize codes only affect wallet balance, not point system
class PrizeCodeClaimResult {
  final bool success;
  final String message;
  final double? prizeValue; // Amount added to wallet balance
  final int? prizePoints; // Always 0 - kept for API compatibility only
  final double? newWalletBalance; // Updated wallet balance after claim
  final String? transactionId;

  PrizeCodeClaimResult({
    required this.success,
    required this.message,
    this.prizeValue,
    this.prizePoints = 0, // Always 0 - prize codes don't affect points
    this.newWalletBalance,
    this.transactionId,
  });
}
