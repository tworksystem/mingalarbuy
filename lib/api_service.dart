import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'models/user.dart';
import 'providers/auth_provider.dart';
import 'screens/auth/welcome_back_page.dart';
import 'services/auth_header_provider.dart';
import 'services/global_keys.dart';
import 'utils/app_config.dart';
import 'utils/logger.dart';

/// Enterprise HTTP client for the WooCommerce / T-Work backend.
///
/// - Injects [Authorization] from [AuthService] via Dio interceptors.
/// - Use [skipAuth: true] for public routes (FAQ, About, page-content) so
///   missing tokens never break requests.
/// - On **401** or **403** when auth was sent, clears the session and sends
///   the user to [WelcomeBackPage].
class ApiService {
  ApiService._();

  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.backendUrl,
      connectTimeout: AppConfig.networkTimeout,
      receiveTimeout: AppConfig.networkTimeout,
      headers: <String, dynamic>{
        Headers.contentTypeHeader: Headers.jsonContentType,
        Headers.acceptHeader: Headers.jsonContentType,
      },
      validateStatus: (status) =>
          status != null && status >= 200 && status < 600,
    ),
  );

  static bool _interceptorsReady = false;
  static bool _handlingAuthFailure = false;

  /// Shared [Dio] instance (interceptors configured on first access).
  static Dio get dio {
    _ensureInterceptors();
    return _dio;
  }

  static void _ensureInterceptors() {
    if (_interceptorsReady) {
      return;
    }
    _interceptorsReady = true;

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) async {
          options.extra['sentAuth'] = false;
          final bool skipAuth = options.extra['skipAuth'] == true;
          if (!skipAuth) {
            final Map<String, String> auth = await _getAuthHeaders();
            if (auth.isNotEmpty) {
              options.headers.addAll(auth);
              options.extra['sentAuth'] = true;
            }
          }
          handler.next(options);
        },
        onResponse: (Response<dynamic> response, ResponseInterceptorHandler handler) async {
          final int? code = response.statusCode;
          if (code == 401 || code == 403) {
            await _onUnauthorized(response.requestOptions, code!);
          }
          handler.next(response);
        },
        onError: (DioException err, ErrorInterceptorHandler handler) async {
          final int? code = err.response?.statusCode;
          if (code == 401 || code == 403) {
            await _onUnauthorized(err.requestOptions, code!);
          }
          handler.next(err);
        },
      ),
    );
  }

  /// Authorization map for the current session (empty when logged out).
  static Future<Map<String, String>> _getAuthHeaders() async {
    return AuthHeaderProvider.buildHeaders();
  }

  /// Retries transient failures (same policy as [NetworkUtils.executeRequest]).
  static Future<Response<dynamic>?> executeWithRetry(
    Future<Response<dynamic>> Function() request, {
    Duration timeout = AppConfig.networkTimeout,
    int maxRetries = AppConfig.maxRetries,
    Duration retryDelay = AppConfig.retryDelay,
    String? context,
  }) async {
    int attempts = 0;
    Object? lastError;
    while (attempts < maxRetries) {
      try {
        return await request().timeout(timeout);
      } on SocketException catch (e) {
        lastError = e;
      } on TimeoutException catch (e) {
        lastError = e;
      } on DioException catch (e) {
        final DioExceptionType t = e.type;
        if (t == DioExceptionType.connectionTimeout ||
            t == DioExceptionType.sendTimeout ||
            t == DioExceptionType.receiveTimeout ||
            t == DioExceptionType.connectionError) {
          lastError = e;
        } else {
          rethrow;
        }
      } catch (e) {
        lastError = e;
      }
      attempts++;
      if (attempts < maxRetries) {
        await Future<void>.delayed(retryDelay);
      }
    }
    if (context != null) {
      Logger.warning(
        'ApiService.executeWithRetry failed after $maxRetries attempts ($context): $lastError',
        tag: 'ApiService',
      );
    }
    return null;
  }

  /// JSON array from [Response.data] (List or JSON string).
  static List<dynamic>? responseAsJsonList(Response<dynamic>? response) {
    final Object? data = response?.data;
    if (data is List<dynamic>) {
      return data;
    }
    if (data is List) {
      return List<dynamic>.from(data);
    }
    if (data is String) {
      try {
        final Object? decoded = json.decode(data);
        if (decoded is List) {
          return List<dynamic>.from(decoded);
        }
      } catch (_) {}
    }
    return null;
  }

  static bool isSuccessResponse(Response<dynamic>? response) {
    final int? code = response?.statusCode;
    return code != null && code >= 200 && code < 300;
  }

  /// JSON object from [Response.data] (Map or JSON string).
  static Map<String, dynamic>? responseAsJsonMap(Response<dynamic>? response) {
    final Object? data = response?.data;
    if (data == null) {
      return null;
    }
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    if (data is String) {
      try {
        final Object? decoded = json.decode(data);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }
    return null;
  }

  /// String body for logging or fallback decode (when data is not a Map).
  static String responseBodyString(Response<dynamic>? response) {
    final Object? data = response?.data;
    if (data == null) {
      return '';
    }
    if (data is String) {
      return data;
    }
    try {
      return json.encode(data);
    } catch (_) {
      return data.toString();
    }
  }

  static Future<void> _onUnauthorized(RequestOptions options, int statusCode) async {
    if (options.extra['skipAuth'] == true) {
      return;
    }
    if (options.extra['sentAuth'] != true) {
      return;
    }

    if (_handlingAuthFailure) {
      return;
    }
    _handlingAuthFailure = true;

    try {
      Logger.warning(
        'ApiService: HTTP $statusCode on authenticated request — clearing session',
        tag: 'ApiService',
      );
      await AuthProvider().logout();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          final BuildContext? ctx = AppKeys.navigatorKey.currentContext;
          if (ctx != null && ctx.mounted) {
            Navigator.of(ctx).pushAndRemoveUntil<void>(
              MaterialPageRoute<void>(
                builder: (_) => const WelcomeBackPage(),
              ),
              (Route<dynamic> route) => false,
            );
          }
        } catch (e, st) {
          Logger.error(
            'ApiService: navigation after auth failure failed: $e',
            tag: 'ApiService',
            error: e,
            stackTrace: st,
          );
        } finally {
          _handlingAuthFailure = false;
        }
      });
    } catch (e, st) {
      Logger.error(
        'ApiService: logout after auth failure failed: $e',
        tag: 'ApiService',
        error: e,
        stackTrace: st,
      );
      _handlingAuthFailure = false;
    }
  }

  // ——— Convenience wrappers (merge caller headers; respect skipAuth) ———

  static Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    bool skipAuth = false,
    Options? options,
  }) async {
    return dio.get<dynamic>(
      path,
      queryParameters: queryParameters,
      options: _options(skipAuth: skipAuth, headers: headers, merge: options),
    );
  }

  static Future<Response<dynamic>> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    bool skipAuth = false,
    Options? options,
  }) async {
    return dio.post<dynamic>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: _options(skipAuth: skipAuth, headers: headers, merge: options),
    );
  }

  static Future<Response<dynamic>> put(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    bool skipAuth = false,
    Options? options,
  }) async {
    return dio.put<dynamic>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: _options(skipAuth: skipAuth, headers: headers, merge: options),
    );
  }

  static Future<Response<dynamic>> patch(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    bool skipAuth = false,
    Options? options,
  }) async {
    return dio.patch<dynamic>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: _options(skipAuth: skipAuth, headers: headers, merge: options),
    );
  }

  static Future<Response<dynamic>> delete(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    bool skipAuth = false,
    Options? options,
  }) async {
    return dio.delete<dynamic>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: _options(skipAuth: skipAuth, headers: headers, merge: options),
    );
  }

  /// Full [uri] (e.g. WooCommerce `https://…/wc/v3/...`) on the shared [dio].
  /// Use [skipAuth: true] when you set your own `Authorization` (e.g. Basic for WC).
  static Future<Response<dynamic>> getUri(
    Uri uri, {
    Map<String, dynamic>? headers,
    bool skipAuth = false,
    Options? options,
  }) async {
    return dio.getUri<dynamic>(
      uri,
      options: _options(skipAuth: skipAuth, headers: headers, merge: options),
    );
  }

  static Future<Response<dynamic>> headUri(
    Uri uri, {
    Map<String, dynamic>? headers,
    bool skipAuth = true,
    Options? options,
  }) async {
    return dio.headUri<dynamic>(
      uri,
      options: _options(skipAuth: skipAuth, headers: headers, merge: options),
    );
  }

  static Future<Response<dynamic>> postUri(
    Uri uri, {
    dynamic data,
    Map<String, dynamic>? headers,
    bool skipAuth = false,
    Options? options,
  }) async {
    return dio.postUri<dynamic>(
      uri,
      data: data,
      options: _options(skipAuth: skipAuth, headers: headers, merge: options),
    );
  }

  static Future<Response<dynamic>> putUri(
    Uri uri, {
    dynamic data,
    Map<String, dynamic>? headers,
    bool skipAuth = false,
    Options? options,
  }) async {
    return dio.putUri<dynamic>(
      uri,
      data: data,
      options: _options(skipAuth: skipAuth, headers: headers, merge: options),
    );
  }

  static Options _options({
    required bool skipAuth,
    Map<String, dynamic>? headers,
    Options? merge,
  }) {
    final Map<String, Object?> extra = <String, Object?>{'skipAuth': skipAuth};
    if (merge?.extra != null) {
      extra.addAll(merge!.extra!);
    }
    final Map<String, dynamic> mergedHeaders = <String, dynamic>{};
    if (merge?.headers != null) {
      mergedHeaders.addAll(merge!.headers!);
    }
    if (headers != null) {
      mergedHeaders.addAll(headers);
    }
    return Options(
      extra: extra,
      headers: mergedHeaders.isEmpty ? null : mergedHeaders,
      responseType: merge?.responseType,
      followRedirects: merge?.followRedirects,
      validateStatus: merge?.validateStatus,
      receiveDataWhenStatusError: merge?.receiveDataWhenStatusError,
      sendTimeout: merge?.sendTimeout,
      receiveTimeout: merge?.receiveTimeout,
    );
  }

  // ——— Legacy demo helper (unchanged consumers in wallet / send-money flows) ———

  static String url(int nrResults) {
    return 'https://randomuser.me/api/?results=$nrResults';
  }

  static Future<List<User>> getUsers({int nrUsers = 1}) async {
    try {
      final Uri uri = Uri.parse(url(nrUsers));
      final Response<dynamic> response = await dio.getUri<dynamic>(
        uri,
        options: Options(
          extra: const <String, Object?>{'skipAuth': true},
          headers: const <String, dynamic>{
            Headers.contentTypeHeader: Headers.jsonContentType,
          },
        ),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic>? data = responseAsJsonMap(response);
        if (data == null) {
          debugPrint('getUsers: response is not JSON object');
          return <User>[];
        }
        final Object? results = data['results'];
        if (results is! Iterable<dynamic>) {
          return <User>[];
        }
        return results
            .map((dynamic l) => User.fromJson(l as Map<String, dynamic>))
            .toList();
      } else {
        debugPrint(responseBodyString(response));
        return <User>[];
      }
    } catch (e) {
      debugPrint('$e');
      return <User>[];
    }
  }
}
