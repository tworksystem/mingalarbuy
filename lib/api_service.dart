import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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

  static const String _httpsOnlyError =
      'Insecure transport blocked: HTTPS is required for all API calls.';

  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.backendUrl,
      connectTimeout: AppConfig.networkTimeout,
      receiveTimeout: AppConfig.networkTimeout,
      // Old Code:
      // headers: <String, dynamic>{
      //   Headers.contentTypeHeader: Headers.jsonContentType,
      //   Headers.acceptHeader: Headers.jsonContentType,
      // },
      //
      // OLD CODE:
      // headers: <String, dynamic>{
      //   Headers.contentTypeHeader: Headers.jsonContentType,
      //   Headers.acceptHeader: Headers.jsonContentType,
      //   'Accept': 'application/json',
      //   'User-Agent': AppConfig.defaultUserAgent,
      // },
      headers: <String, dynamic>{
        ...AppConfig.defaultBrowserHeaders,
        'Accept-Encoding': 'identity', // ဤလိုင်းကို ထည့်ပါ
        Headers.contentTypeHeader: Headers.jsonContentType,
      },
      validateStatus: (status) =>
          status != null && status >= 200 && status < 600,
    ),
  );

  static bool _interceptorsReady = false;
  static bool _handlingAuthFailure = false;
  static Timer? _authFailureResetTimer;

  static const Duration _authFailureFlagSafetyTimeout = Duration(seconds: 3);

  /// Shared [Dio] instance (interceptors configured on first access).
  static Dio get dio {
    _ensureInterceptors();
    return _dio;
  }

  static void _ensureInterceptors() {
    if (_interceptorsReady) {
      return;
    }
    _enforceHttpsBaseUrl();
    _interceptorsReady = true;

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest:
            (RequestOptions options, RequestInterceptorHandler handler) async {
              if (!_isHttpsUri(options.uri)) {
                handler.reject(
                  DioException(
                    requestOptions: options,
                    type: DioExceptionType.connectionError,
                    error: _httpsOnlyError,
                  ),
                );
                return;
              }
              options.extra['sentAuth'] = false;
              final bool skipAuth = options.extra['skipAuth'] == true;
              if (!skipAuth) {
                final Map<String, String> auth = await _getAuthHeaders();
                if (auth.isNotEmpty) {
                  options.headers.addAll(auth);
                  options.extra['sentAuth'] = true;
                }
              }
              // GET/HEAD without body: avoid Content-Type: application/json (WAF / cache oddities).
              final String methodUpper = options.method.toUpperCase();
              if (methodUpper == 'GET' || methodUpper == 'HEAD') {
                options.headers.remove(Headers.contentTypeHeader);
                options.headers.remove('content-type');
                options.headers.remove('Content-Type');
              }
              handler.next(options);
            },
        onResponse:
            (
              Response<dynamic> response,
              ResponseInterceptorHandler handler,
            ) async {
              if (!_isHttpsUri(response.realUri)) {
                handler.reject(
                  DioException(
                    requestOptions: response.requestOptions,
                    response: response,
                    type: DioExceptionType.connectionError,
                    error: _httpsOnlyError,
                  ),
                );
                return;
              }
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

    // Runs after auth injection so logs reflect final outgoing headers.
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          // Optional noisy request logging (uncomment when debugging headers / routes).
          // print('🚀 [Dio Request] ${options.method} ${options.uri}');
          // print('📦 [Headers] ${options.headers}');
          handler.next(options);
        },
        onResponse: (Response response, ResponseInterceptorHandler handler) {
          // print('✅ [Dio Response] ${response.statusCode} - ${response.requestOptions.uri}');
          handler.next(response);
        },
        onError: (DioException err, ErrorInterceptorHandler handler) {
          // print('❌ [Dio Error] Status: ${err.response?.statusCode} - ${err.requestOptions.uri}');
          if (err.response?.data != null) {
            // Keep pre-parse / raw body capture + truncation for quick re-enable (JSON/plain issues).
            // ignore: unused_local_variable
            String rawError = err.response?.data.toString() ?? '';
            if (rawError.length > 500) {
              rawError = '${rawError.substring(0, 500)}... (truncated)';
            }
            // print('❌ [Dio Raw Error Body] $rawError');
          }
          handler.next(err);
        },
      ),
    );
  }

  static bool _isHttpsUri(Uri uri) => uri.scheme.toLowerCase() == 'https';

  static void _enforceHttpsBaseUrl() {
    final Uri? base = Uri.tryParse(AppConfig.backendUrl);
    if (base == null || !_isHttpsUri(base)) {
      throw StateError(
        'AppConfig.backendUrl must use HTTPS. Received: ${AppConfig.backendUrl}',
      );
    }
  }

  /// Authorization map for the current session (empty when logged out).
  static Future<Map<String, String>> _getAuthHeaders() async {
    return AuthHeaderProvider.buildHeaders();
  }

  /// Cap for exponential backoff between retries (excluding jitter).
  static const Duration _maxRetryBackoffCeiling = Duration(seconds: 32);

  /// Waits `(base × 2^(n-1))` capped, with multiplicative jitter in `[0.75, 1.25]` to
  /// spread retries under network flapping (avoids thundering herd / pseudo-DDoS).
  static Future<void> _delayBeforeRetryAttempt({
    required int failedAttemptsSoFar,
    required Duration baseDelay,
  }) async {
    if (failedAttemptsSoFar <= 0) return;
    final double exp = math.pow(2.0, failedAttemptsSoFar - 1).toDouble();
    double ms = baseDelay.inMilliseconds * exp;
    final cap = _maxRetryBackoffCeiling.inMilliseconds.toDouble();
    if (ms > cap) ms = cap;
    final jitter = 0.75 + math.Random().nextDouble() * 0.5;
    final waitMs = (ms * jitter).round().clamp(1, cap.round() * 2);
    await Future<void>.delayed(Duration(milliseconds: waitMs));
  }

  /// Retries transient failures with exponential backoff + jitter between attempts.
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
        try {
          await _delayBeforeRetryAttempt(
            failedAttemptsSoFar: attempts,
            baseDelay: retryDelay,
          );
        } catch (e, st) {
          Logger.warning(
            'executeWithRetry delay failed, continuing: $e',
            tag: 'ApiService',
            error: e,
            stackTrace: st,
          );
        }
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

  // OLD CODE:
  // static const int _apiParseBodyPreviewMaxChars = 500;
  //
  // /// Same string conversion as [responseBodyString] for parse diagnostics (kept
  // /// above that method so helpers can sit next to JSON parsers).
  // static String _fullRawBodyStringForApiParseLog(Response<dynamic>? response) {
  //   final Object? data = response?.data;
  //   if (data == null) {
  //     return '';
  //   }
  //   if (data is String) {
  //     return data;
  //   }
  //   try {
  //     return json.encode(data);
  //   } catch (_) {
  //     return data.toString();
  //   }
  // }
  //
  // static String _previewRawBodyForApiParseLog(Response<dynamic>? response) {
  //   final String full = _fullRawBodyStringForApiParseLog(response);
  //   if (full.length <= _apiParseBodyPreviewMaxChars) {
  //     return full;
  //   }
  //   return '${full.substring(0, _apiParseBodyPreviewMaxChars)}... (truncated, ${full.length} chars total)';
  // }
  //
  // static void _logApiParseFailure(
  //   Response<dynamic>? response, {
  //   required String helperName,
  //   required Object error,
  //   StackTrace? stackTrace,
  //   String? detail,
  // }) {
  //   final int? status = response?.statusCode;
  //   final String preview = _previewRawBodyForApiParseLog(response);
  //   final String detailPart = detail != null ? ' — $detail' : '';
  //   Logger.warning(
  //     'API Parse Error: $helperName — HTTP status=$status$detailPart — rawBodyPreview="$preview" — error=$error',
  //     tag: 'ApiService',
  //     error: error,
  //     stackTrace: stackTrace,
  //   );
  // }
  //
  // // OLD CODE:
  // // /// JSON array from [Response.data] (List or JSON string).
  // // static List<dynamic>? responseAsJsonList(Response<dynamic>? response) {
  // //   final Object? data = response?.data;
  // //   if (data is List<dynamic>) {
  // //     return data;
  // //   }
  // //   if (data is List) {
  // //     return List<dynamic>.from(data);
  // //   }
  // //   if (data is String) {
  // //     try {
  // //       final Object? decoded = json.decode(data);
  // //       if (decoded is List) {
  // //         return List<dynamic>.from(decoded);
  // //       }
  // //     } catch (_) {}
  // //   }
  // //   return null;
  // // }
  //
  // /// JSON array from [Response.data] (List or JSON string).
  // static List<dynamic>? responseAsJsonList(Response<dynamic>? response) {
  //   final Object? data = response?.data;
  //   if (data is List<dynamic>) {
  //     return data;
  //   }
  //   if (data is List) {
  //     return List<dynamic>.from(data);
  //   }
  //   if (data is String) {
  //     try {
  //       final Object? decoded = json.decode(data);
  //       if (decoded is List) {
  //         return List<dynamic>.from(decoded);
  //       }
  //       _logApiParseFailure(
  //         response,
  //         helperName: 'responseAsJsonList',
  //         error: 'Decoded JSON root is not a List',
  //         stackTrace: StackTrace.current,
  //         detail: decoded == null
  //             ? 'decoded=null'
  //             : 'decodedType=${decoded.runtimeType}',
  //       );
  //       return null;
  //     } on FormatException catch (e, st) {
  //       _logApiParseFailure(
  //         response,
  //         helperName: 'responseAsJsonList',
  //         error: e,
  //         stackTrace: st,
  //       );
  //       return null;
  //     } catch (e, st) {
  //       _logApiParseFailure(
  //         response,
  //         helperName: 'responseAsJsonList',
  //         error: e,
  //         stackTrace: st,
  //       );
  //       return null;
  //     }
  //   }
  //   return null;
  // }
  //
  // static bool isSuccessResponse(Response<dynamic>? response) {
  //   final int? code = response?.statusCode;
  //   return code != null && code >= 200 && code < 300;
  // }
  //
  // // OLD CODE:
  // // /// JSON object from [Response.data] (Map or JSON string).
  // // static Map<String, dynamic>? responseAsJsonMap(Response<dynamic>? response) {
  // //   final Object? data = response?.data;
  // //   if (data == null) {
  // //     return null;
  // //   }
  // //   if (data is Map<String, dynamic>) {
  // //     return data;
  // //   }
  // //   if (data is Map) {
  // //     return Map<String, dynamic>.from(data);
  // //   }
  // //   if (data is String) {
  // //     try {
  // //       final Object? decoded = json.decode(data);
  // //       if (decoded is Map<String, dynamic>) {
  // //         return decoded;
  // //       }
  // //       if (decoded is Map) {
  // //         return Map<String, dynamic>.from(decoded);
  // //       }
  // //     } catch (_) {}
  // //   }
  // //   return null;
  // // }
  //
  // /// JSON object from [Response.data] (Map or JSON string).
  // static Map<String, dynamic>? responseAsJsonMap(Response<dynamic>? response) {
  //   final Object? data = response?.data;
  //   if (data == null) {
  //     return null;
  //   }
  //   if (data is Map<String, dynamic>) {
  //     return data;
  //   }
  //   if (data is Map) {
  //     return Map<String, dynamic>.from(data);
  //   }
  //   if (data is String) {
  //     try {
  //       final Object? decoded = json.decode(data);
  //       if (decoded is Map<String, dynamic>) {
  //         return decoded;
  //       }
  //       if (decoded is Map) {
  //         return Map<String, dynamic>.from(decoded);
  //       }
  //       _logApiParseFailure(
  //         response,
  //         helperName: 'responseAsJsonMap',
  //         error: 'Decoded JSON root is not a Map',
  //         stackTrace: StackTrace.current,
  //         detail: decoded == null
  //             ? 'decoded=null'
  //             : 'decodedType=${decoded.runtimeType}',
  //       );
  //       return null;
  //     } on FormatException catch (e, st) {
  //       _logApiParseFailure(
  //         response,
  //         helperName: 'responseAsJsonMap',
  //         error: e,
  //         stackTrace: st,
  //       );
  //       return null;
  //     } catch (e, st) {
  //       _logApiParseFailure(
  //         response,
  //         helperName: 'responseAsJsonMap',
  //         error: e,
  //         stackTrace: st,
  //       );
  //       return null;
  //     }
  //   }
  //   return null;
  // }

  /// JSON array from [Response.data] (List or JSON string).
  static List<dynamic>? responseAsJsonList(Response<dynamic>? response) {
    final Object? data = response?.data;
    if (data == null) return null;

    if (data is List<dynamic>) return data;
    if (data is List) return List<dynamic>.from(data);

    if (data is String) {
      try {
        final Object? decoded = json.decode(data);
        if (decoded is List) return List<dynamic>.from(decoded);

        _logApiParseFailure(
          'responseAsJsonList (Type Mismatch)',
          response,
          FormatException('Expected List but got ${decoded.runtimeType}'),
          StackTrace.current,
        );
      } catch (e, st) {
        _logApiParseFailure('responseAsJsonList', response, e, st);
      }
    }
    return null;
  }

  /// HTML Error Page အရှည်ကြီးတွေ ပြန်လာရင် Console မှာ Memory မပြည့်အောင်
  /// ပထမဆုံး စာလုံး ၅၀၀ ကိုပဲ ဖြတ်ယူမယ့် Helper Function
  static String _previewRawBodyForApiParseLog(String rawBody) {
    if (rawBody.length <= 500) return rawBody;
    return '${rawBody.substring(0, 500)}... (truncated, ${rawBody.length} chars total)';
  }

  /// JSON Parse လုပ်လို့မရတဲ့ အခြေအနေတိုင်းမှာ သေချာ Log ထုတ်ပေးမယ့် Helper
  static void _logApiParseFailure(
    String helperName,
    Response<dynamic>? response,
    Object error,
    StackTrace stackTrace,
  ) {
    final int? statusCode = response?.statusCode;
    final String rawData = response?.data?.toString() ?? 'null';
    final String bodyPreview = _previewRawBodyForApiParseLog(rawData);

    Logger.warning(
      'API Parse Error: $helperName — HTTP status=$statusCode — rawBodyPreview="$bodyPreview"',
      tag: 'ApiService',
      error: error,
      stackTrace: stackTrace,
    );
  }

  static bool isSuccessResponse(Response<dynamic>? response) {
    final int? code = response?.statusCode;
    return code != null && code >= 200 && code < 300;
  }

  /// JSON object from [Response.data] (Map or JSON string).
  static Map<String, dynamic>? responseAsJsonMap(Response<dynamic>? response) {
    final Object? data = response?.data;
    if (data == null) return null;

    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);

    if (data is String) {
      try {
        final Object? decoded = json.decode(data);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);

        _logApiParseFailure(
          'responseAsJsonMap (Type Mismatch)',
          response,
          FormatException('Expected Map but got ${decoded.runtimeType}'),
          StackTrace.current,
        );
      } catch (e, st) {
        _logApiParseFailure('responseAsJsonMap', response, e, st);
      }
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

  static Future<void> _onUnauthorized(
    RequestOptions options,
    int statusCode,
  ) async {
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
    _authFailureResetTimer?.cancel();
    _authFailureResetTimer = Timer(_authFailureFlagSafetyTimeout, () {
      _authFailureResetTimer = null;
      if (_handlingAuthFailure) {
        Logger.warning(
          'ApiService: auth failure flag safety reset (timeout ${_authFailureFlagSafetyTimeout.inSeconds}s)',
          tag: 'ApiService',
        );
        _handlingAuthFailure = false;
      }
    });

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
              MaterialPageRoute<void>(builder: (_) => const WelcomeBackPage()),
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
        }
      });
    } catch (e, st) {
      Logger.error(
        'ApiService: logout after auth failure failed: $e',
        tag: 'ApiService',
        error: e,
        stackTrace: st,
      );
    } finally {
      _authFailureResetTimer?.cancel();
      _authFailureResetTimer = null;
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

    final Map<String, dynamic> mergedHeaders = <String, dynamic>{
      ...AppConfig.defaultBrowserHeaders,
    };

    // GZip Compression ကို ပိတ်ရန် (Server မှ compressed data ပို့ခြင်းကို တားဆီးရန်)
    mergedHeaders['Accept-Encoding'] = 'identity';

    if (merge?.headers != null) {
      mergedHeaders.addAll(merge!.headers!);
    }
    if (headers != null) {
      mergedHeaders.addAll(headers);
    }

    mergedHeaders.putIfAbsent('Accept', () => 'application/json');
    mergedHeaders.putIfAbsent('User-Agent', () => AppConfig.defaultUserAgent);

    return Options(
      extra: extra,
      headers: mergedHeaders.isEmpty ? null : mergedHeaders,
      // ဤနေရာတွင် ပြင်ဆင်ထားသည် (Dio အလိုအလျောက် Parse မလုပ်စေရန်)
      responseType: merge?.responseType ?? ResponseType.plain,
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
          // Old Code:
          // headers: const <String, dynamic>{
          //   Headers.contentTypeHeader: Headers.jsonContentType,
          // },
          //
          // OLD CODE:
          // headers: <String, dynamic>{
          //   Headers.contentTypeHeader: Headers.jsonContentType,
          //   'Accept': 'application/json',
          //   'User-Agent':
          //       'Mozilla/5.0 (Linux; Android 10; SM-G981B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/80.0.3987.162 Mobile Safari/537.36',
          // },
          // OLD CODE:
          // headers: <String, dynamic>{
          //   Headers.contentTypeHeader: Headers.jsonContentType,
          //   'Accept': 'application/json',
          //   'User-Agent': AppConfig.defaultUserAgent,
          // },
          /*
          // OLD CODE: GET carried Content-Type: application/json.
          // headers: <String, dynamic>{
          //   ...AppConfig.defaultBrowserHeaders,
          //   Headers.contentTypeHeader: Headers.jsonContentType,
          // },
          */
          headers: <String, dynamic>{...AppConfig.defaultBrowserHeaders},
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
