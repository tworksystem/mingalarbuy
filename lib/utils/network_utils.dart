import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Professional network utilities for robust API communication
class NetworkUtils {
  static const Duration _defaultTimeout = Duration(seconds: 30);
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 2);

  /// Execute HTTP request with retry logic and error handling
  static Future<http.Response?> executeRequest(
    Future<http.Response> Function() request, {
    Duration timeout = _defaultTimeout,
    int maxRetries = _maxRetries,
    String? context,
  }) async {
    int attempts = 0;
    Exception? lastException;

    while (attempts < maxRetries) {
      try {
        final response = await request().timeout(timeout);

        if (kDebugMode) {
          print('🌐 Network request successful (attempt ${attempts + 1})');
        }

        return response;
      } on SocketException catch (e) {
        lastException = e;
        if (kDebugMode) {
          print('🔌 Socket error (attempt ${attempts + 1}): ${e.message}');
        }
      } on HttpException catch (e) {
        lastException = e;
        if (kDebugMode) {
          print('🌐 HTTP error (attempt ${attempts + 1}): ${e.message}');
        }
      } on Exception catch (e) {
        lastException = e;
        if (kDebugMode) {
          print('❌ Network error (attempt ${attempts + 1}): $e');
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
      if (lastException != null) {
        print('📍 Last error: $lastException');
      }
    }

    return null;
  }

  /// Check network connectivity
  static Future<bool> isConnected() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    }
  }

  /// Get user-friendly error message
  static String getErrorMessage(dynamic error) {
    if (error is SocketException) {
      return 'No internet connection. Please check your network settings.';
    } else if (error is TimeoutException) {
      return 'Request timeout. Server may be busy. Please try again.';
    } else if (error is HttpException) {
      return 'Server error. Please try again later.';
    } else if (error is FormatException) {
      return 'Data format error. Please try again.';
    } else if (error is Exception && error.toString().toLowerCase().contains('timeout')) {
      return 'Request timeout. Server may be busy. Please try again.';
    } else {
      return 'An unexpected error occurred. Please try again.';
    }
  }

  /// Validate HTTP response
  static bool isValidResponse(http.Response? response) {
    if (response == null) return false;

    return response.statusCode >= 200 && response.statusCode < 300;
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.wifi_off, color: Colors.white, size: 16),
                  const SizedBox(width: 8),
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
