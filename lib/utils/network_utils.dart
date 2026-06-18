import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api_service.dart';
import '../config/web_config.dart';
import 'network_error_utils.dart';

/// Professional network utilities for robust API communication
class NetworkUtils {
  static const Duration _defaultTimeout = Duration(seconds: 30);
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 2);

  /// Execute a [Dio] request (typically via [ApiService]) with retry logic.
  static Future<Response<dynamic>?> executeRequest(
    Future<Response<dynamic>> Function() request, {
    Duration timeout = _defaultTimeout,
    int maxRetries = _maxRetries,
    String? context,
  }) async {
    int attempts = 0;
    Object? lastError;

    while (attempts < maxRetries) {
      try {
        final Response<dynamic> response = await request().timeout(timeout);

        if (kDebugMode) {
          print('🌐 Network request successful (attempt ${attempts + 1})');
        }

        return response;
      } on TimeoutException catch (e) {
        lastError = e;
        if (kDebugMode) {
          print('⏱️ Timeout (attempt ${attempts + 1}): $e');
        }
      } on DioException catch (e) {
        final DioExceptionType t = e.type;
        if (t == DioExceptionType.connectionTimeout ||
            t == DioExceptionType.sendTimeout ||
            t == DioExceptionType.receiveTimeout ||
            t == DioExceptionType.connectionError) {
          lastError = e;
          if (kDebugMode) {
            print('🔌 Dio connection error (attempt ${attempts + 1}): $e');
          }
        } else {
          rethrow;
        }
      } on Exception catch (e) {
        if (NetworkErrorUtils.isSocketLikeError(e) ||
            NetworkErrorUtils.isHttpLikeError(e)) {
          lastError = e;
          if (kDebugMode) {
            print('🌐 Network error (attempt ${attempts + 1}): $e');
          }
        } else {
          rethrow;
        }
      }

      attempts++;
      if (attempts < maxRetries) {
        if (kDebugMode) {
          print('🔄 Retrying in ${_retryDelay.inSeconds} seconds...');
        }
        await Future.delayed(_retryDelay);
      }
    }

    if (kDebugMode) {
      print('💥 Network request failed after $maxRetries attempts');
      if (context != null) {
        print('📍 Context: $context');
      }
      if (lastError != null) {
        print('📍 Last error: $lastError');
      }
    }

    return null;
  }

  /// Check network connectivity (web-safe).
  static Future<bool> isConnected() async {
    try {
      if (kIsWeb) {
        final List<ConnectivityResult> results =
            await Connectivity().checkConnectivity();
        return !results.contains(ConnectivityResult.none);
      }

      final Response<dynamic>? response = await ApiService.executeWithRetry(
        () => ApiService.headUri(
          Uri.parse('https://www.google.com'),
          skipAuth: true,
        ),
        context: 'networkUtils.isConnected',
        timeout: const Duration(seconds: 5),
        maxRetries: 1,
      );
      return response != null && ApiService.isSuccessResponse(response);
    } catch (_) {
      return false;
    }
  }

  /// Message when [ApiService.executeWithRetry] returns null (timeout / unreachable).
  static String unreachableMessage() => WebConfig.webConnectionErrorMessage;

  /// Get user-friendly error message
  static String getErrorMessage(dynamic error) {
    if (NetworkErrorUtils.isSocketLikeError(error)) {
      if (WebConfig.isLikelyCorsBlock) {
        return WebConfig.webConnectionErrorMessage;
      }
      return 'No internet connection. Please check your network settings.';
    } else if (error is TimeoutException) {
      return 'Request timeout. Server may be busy. Please try again.';
    } else if (error is DioException) {
      final DioExceptionType t = error.type;
      if (t == DioExceptionType.connectionTimeout ||
          t == DioExceptionType.sendTimeout ||
          t == DioExceptionType.receiveTimeout) {
        return 'Request timeout. Server may be busy. Please try again.';
      }
      if (t == DioExceptionType.connectionError) {
        if (WebConfig.isLikelyCorsBlock) {
          return WebConfig.webConnectionErrorMessage;
        }
        return 'No internet connection. Please check your network settings.';
      }
      return error.message ?? 'Network error. Please try again.';
    } else if (NetworkErrorUtils.isHttpLikeError(error)) {
      return 'Server error. Please try again later.';
    } else if (error is FormatException) {
      return 'Data format error. Please try again.';
    } else if (error is Exception &&
        error.toString().toLowerCase().contains('timeout')) {
      return 'Request timeout. Server may be busy. Please try again.';
    } else {
      return 'An unexpected error occurred. Please try again.';
    }
  }

  /// Validate [Dio] response (2xx). Prefer [isValidDioResponse] for new code.
  static bool isValidResponse(Response<dynamic>? response) {
    return isValidDioResponse(response);
  }

  /// Validate Dio response (central [ApiService] client).
  static bool isValidDioResponse(Response<dynamic>? response) {
    return ApiService.isSuccessResponse(response);
  }

  /// Get response status message
  static String getStatusMessage(int statusCode) {
    switch (statusCode) {
      case 200:
        return 'Success';
      case 400:
        return 'Bad Request';
      case 401:
        return 'Unauthorized';
      case 403:
        return 'Forbidden';
      case 404:
        return 'Not Found';
      case 500:
        return 'Internal Server Error';
      case 502:
        return 'Bad Gateway';
      case 503:
        return 'Service Unavailable';
      default:
        return 'Unknown Error ($statusCode)';
    }
  }
}

/// Network status indicator widget
class NetworkStatusIndicator extends StatelessWidget {
  final bool isConnected;
  final Widget child;

  const NetworkStatusIndicator({
    super.key,
    required this.isConnected,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (!isConnected)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: Colors.red[600],
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.wifi_off, color: Colors.white, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'No internet connection',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
