import 'dart:async';

import 'package:dio/dio.dart';

/// Platform-agnostic network error helpers (no dart:io).
class NetworkErrorUtils {
  NetworkErrorUtils._();

  static bool isSocketLikeError(Object? error) {
    if (error == null) return false;
    final String name = error.runtimeType.toString();
    if (name == 'SocketException') return true;
    if (error is DioException) {
      final DioExceptionType t = error.type;
      return t == DioExceptionType.connectionError ||
          t == DioExceptionType.connectionTimeout ||
          t == DioExceptionType.sendTimeout ||
          t == DioExceptionType.receiveTimeout;
    }
    if (error is TimeoutException) return true;
    final String lower = error.toString().toLowerCase();
    return lower.contains('socketexception') ||
        lower.contains('failed to fetch') ||
        lower.contains('network is unreachable');
  }

  static bool isHttpLikeError(Object? error) {
    if (error == null) return false;
    return error.runtimeType.toString() == 'HttpException';
  }
}
