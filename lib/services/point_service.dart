import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api_service.dart';
import '../models/point_transaction.dart';
import '../utils/app_config.dart';
import '../utils/logger.dart';
import '../utils/network_utils.dart';
import 'point_sync_telemetry.dart';
import 'offline_queue_service.dart';
import 'secure_prefs.dart';
import '../providers/point_provider.dart';

/// Emitted when [PointService] mutates local point balance without UI context,
/// so global listeners (e.g. [PointProvider]) can refresh Home "My PNP" in real time.
class PointSyncBroadcast {
  final String userId;
  final int newBalance;
  final String source;

  const PointSyncBroadcast({
    required this.userId,
    required this.newBalance,
    required this.source,
  });
}

/// Point service for managing user points
/// Handles API calls and local storage for offline support
class PointService {
  static const String _balanceKey = 'user_point_balance';
  static const String _transactionsKey = 'user_point_transactions';

  /// Above this UTF-16 length, JSON is decoded in a worker [Isolate] to reduce
  /// main-isolate jank / ANR risk for huge transaction payloads.
  static const int _jsonDecodeIsolateMinChars = 32768;
  static bool _queueRegistered = false;
  static final SecurePrefs _securePrefs = SecurePrefs.instance;
  static int? _lastPointBalanceStatusCode;
  static String? _lastPointBalanceFailureMessage;
  static String? _lastPointBalanceUrl;

  static int? get lastPointBalanceStatusCode => _lastPointBalanceStatusCode;
  static String? get lastPointBalanceFailureMessage =>
      _lastPointBalanceFailureMessage;
  static String? get lastPointBalanceUrl => _lastPointBalanceUrl;

  static void _clearPointBalanceFailure() {
    _lastPointBalanceStatusCode = null;
    _lastPointBalanceFailureMessage = null;
    _lastPointBalanceUrl = null;
  }

  static void _recordPointBalanceFailure({
    int? statusCode,
    required String url,
    required String reason,
  }) {
    _lastPointBalanceStatusCode = statusCode;
    _lastPointBalanceFailureMessage = reason;
    _lastPointBalanceUrl = url;
  }

  /// Parses large transaction JSON off the UI isolate when the body exceeds
  /// [_jsonDecodeIsolateMinChars].
  static Future<dynamic> _decodePointApiJsonString(String raw) async {
    if (raw.length < _jsonDecodeIsolateMinChars) {
      return json.decode(raw);
    }
    return Isolate.run(() => json.decode(raw));
  }

  // Broadcast stream for context-free sync (FCM helpers, isolates, future callers).
  static final StreamController<PointSyncBroadcast>
  _pointSyncBroadcastController =
      StreamController<PointSyncBroadcast>.broadcast();

  /// Listen from [PointProvider] (or tests) to apply cache/server-aligned balance globally.
  static Stream<PointSyncBroadcast> get pointSyncBroadcast =>
      _pointSyncBroadcastController.stream;

  /// Publishes a balance snapshot after local persistence (e.g. earn path).
  static void notifyPointBalanceBroadcast({
    required String userId,
    required int newBalance,
    String source = 'point_service',
  }) {
    if (_pointSyncBroadcastController.isClosed) return;
    _pointSyncBroadcastController.add(
      PointSyncBroadcast(
        userId: userId,
        newBalance: newBalance,
        source: source,
      ),
    );
  }

  /// Request throttling to prevent duplicate/subsequent exchange requests
  /// Key: userId, Value: last request timestamp
  static final Map<String, DateTime> _lastExchangeRequestTimestamps = {};
  static const Duration _exchangeRequestThrottleDuration = Duration(seconds: 3);

  // Point earning rates (configurable)
  static const double pointsPerDollar = 1.0; // 1 point per $1 spent
  static const int signupBonus = 100; // Points for signing up
  static const int reviewBonus = 50; // Points for leaving a review
  static const int referralBonus = 500; // Points for referring a friend
  static const int birthdayBonus = 200; // Points for birthday

  // Point redemption rates
  static const double pointsPerDollarDiscount =
      100.0; // 100 points = $1 discount

  // Point redemption limits
  static const int minRedemptionPoints = 100; // Minimum points to redeem
  static const int maxRedemptionPercent =
      50; // Max 50% of order total can be paid with points

  // Point expiration settings
  static const int pointsExpirationDays = 365; // Points expire after 1 year
  static const int expirationWarningDays =
      30; // Warn when expiring within 30 days

  // ---- Point sync retry policy (Phase 1) ----
  //
  // IMPORTANT:
  // - We intentionally avoid nested retries (ApiService.executeWithRetry + our own retry)
  //   because it multiplies latency in user-facing flows.
  // - Point sync retry is now owned by PointService only.
  static const _PointSyncRetryProfile _blockingSyncProfile =
      _PointSyncRetryProfile(
        maxAttempts: 2,
        perAttemptTimeout: Duration(seconds: 10),
        initialBackoff: Duration(seconds: 1),
        backoffMultiplier: 1.0,
      );

  static const _PointSyncRetryProfile _backgroundSyncProfile =
      _PointSyncRetryProfile(
        maxAttempts: 4,
        perAttemptTimeout: Duration(seconds: 30),
        initialBackoff: Duration(seconds: 2),
        backoffMultiplier: 2.0,
      );

  static Map<String, dynamic> _requestHeaders() {
    // OLD CODE:
    // return const <String, dynamic>{
    //   'Content-Type': 'application/json',
    //   'Accept': 'application/json',
    //   'User-Agent':
    //       'Mozilla/5.0 (Linux; Android 10; SM-G981B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/80.0.3987.162 Mobile Safari/537.36',
    // };
    return <String, dynamic>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': AppConfig.defaultUserAgent,
    };
  }

  /// Parse balance from API response — handles num, String (e.g. "18200"), and null
  static int _parseBalanceInt(Map<String, dynamic> data, String key) {
    final v = data[key];
    if (v == null) return 0;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? 0;
    return int.tryParse(v.toString()) ?? 0;
  }

  /// Safe [num] → [int] for ledger fields (shields huge/out-of-range server values).
  static int? _tryCoerceMandatoryBalanceNum(num v, String fieldKey) {
    try {
      return v.toInt();
    } on RangeError catch (_) {
      Logger.warning(
        'Mandatory balance field "$fieldKey" numeric out of int range — refusing',
        tag: 'PointService',
      );
      return null;
    }
  }

  static bool _isRefusedNegativeMandatoryBalance(int value, String fieldKey) {
    if (value >= 0) return false;
    Logger.warning(
      'Mandatory balance field "$fieldKey" is negative ($value) — refusing',
      tag: 'PointService',
    );
    return true;
  }

  /// Optional non-negative int for embedded ledger rows (transaction list).
  static int? _parseOptionalNonNegativeInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v < 0 ? null : v;
    if (v is num) {
      final i = v.toInt();
      return i < 0 ? null : i;
    }
    final p = int.tryParse(v.toString().trim());
    return (p != null && p >= 0) ? p : null;
  }

  /// Max running balance from embedded transaction previews when headline `current_balance` lags
  /// (e.g. poll winner row shows [new_balance] 450000 while summary field still 442000).
  static int? _maxRunningBalanceFromEmbeddedTransactions(
    Map<String, dynamic> data,
  ) {
    final raw =
        data['transactions'] ??
        data['recent_transactions'] ??
        data['ledger_preview'];
    if (raw is! List || raw.isEmpty) return null;
    int? maxBal;
    for (var i = 0; i < raw.length; i++) {
      final e = raw[i];
      try {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        for (final k in const [
          'new_balance',
          'points_balance',
          'balance_after',
          'running_balance',
          'current_balance',
        ]) {
          if (!m.containsKey(k)) continue;
          final n = _parseOptionalNonNegativeInt(m[k]);
          if (n != null && (maxBal == null || n > maxBal)) {
            maxBal = n;
          }
        }
      } catch (e, st) {
        Logger.warning(
          'Skipping malformed embedded ledger row at index=$i: $e',
          tag: 'PointService',
          error: e,
          stackTrace: st,
        );
      }
    }
    return maxBal;
  }

  /*
  Old Code: single private coalesce helper only — no shared API for embedded preview rule.
  */
  /// Same merge as [getPointBalance]: `max(headline current_balance, embedded row hints)`.
  /// [PointProvider.loadBalance] applies balances produced by [getPointBalance], which uses this.
  static int coalesceHeadlineWithEmbeddedLedgerPreview(
    Map<String, dynamic> data,
    int headlineBalance,
  ) {
    final hint = _maxRunningBalanceFromEmbeddedTransactions(data);
    if (hint == null) return headlineBalance;
    if (hint > headlineBalance) {
      Logger.info(
        'Point balance coalesce: headline=$headlineBalance embeddedMax=$hint '
        '(using embedded snapshot)',
        tag: 'PointService',
      );
      return hint;
    }
    return headlineBalance;
  }

  /// Authoritative ledger field: missing key ⇒ treat as unreadable payload (not zero).
  static int? _tryParseMandatoryCurrentBalance(Map<String, dynamic> data) {
    for (final key in const ['current_balance', 'currentBalance']) {
      if (!data.containsKey(key)) continue;
      final v = data[key];
      if (v == null) {
        Logger.warning(
          'Mandatory balance field "$key" is null — refusing to coerce to 0',
          tag: 'PointService',
        );
        return null;
      }
      if (v is num) {
        final coerced = _tryCoerceMandatoryBalanceNum(v, key);
        if (coerced == null) return null;
        if (_isRefusedNegativeMandatoryBalance(coerced, key)) return null;
        return coerced;
      }
      if (v is String) {
        final parsed = int.tryParse(v.trim());
        if (parsed != null) {
          if (_isRefusedNegativeMandatoryBalance(parsed, key)) return null;
          return parsed;
        }
        Logger.warning(
          'Mandatory balance field "$key" not parseable as int: $v',
          tag: 'PointService',
        );
        return null;
      }
      final parsed = int.tryParse(v.toString());
      if (parsed != null) {
        if (_isRefusedNegativeMandatoryBalance(parsed, key)) return null;
        return parsed;
      }
      Logger.warning(
        'Mandatory balance field "$key" not parseable as int: $v',
        tag: 'PointService',
      );
      return null;
    }
    return null;
  }

  /// Backend may send malformed timestamps — never fail balance hydration on parse alone.
  static DateTime _parseLastUpdatedOrNow(Object? raw) {
    if (raw == null) return DateTime.now();
    try {
      return DateTime.parse(raw.toString());
    } catch (_) {
      return DateTime.now();
    }
  }

  /// Get WooCommerce authentication query parameters
  ///
  /// We send WooCommerce API credentials as query parameters instead of using
  /// the Authorization header to avoid conflicts with JSON Basic
  /// Authentication plugins (which also use Basic auth for WordPress users).
  static Map<String, String> _getWooCommerceAuthQueryParams() {
    return {
      'consumer_key': AppConfig.consumerKey,
      'consumer_secret': AppConfig.consumerSecret,
    };
  }

  /// Get user's point balance from API
  ///
  /// When [persistToStorage] is false, the response is not written to disk
  /// (used while poll-win smart polling may still see a stale ledger).
  static Future<PointBalance?> getPointBalance(
    String userId, {
    int? cacheBypassTimestampMs,
    bool persistToStorage = true,
  }) async {
    try {
      // Use custom WordPress REST endpoint
      final uri =
          Uri.parse(
            AppConfig.tworkEndpoint(
              '${AppConfig.tworkPointsBalancePath}/$userId',
            ),
          ).replace(
            queryParameters: {
              ..._getWooCommerceAuthQueryParams(),
              // Use explicit `t` nonce to bypass intermediary cache layers.
              't':
                  (cacheBypassTimestampMs ??
                          DateTime.now().millisecondsSinceEpoch)
                      .toString(),
            },
          );
      final requestUrl = uri.toString();
      final hasTimestampBypass = uri.queryParameters.containsKey('t');
      Logger.info(
        'Point balance request prepared: url=$requestUrl, has_t=$hasTimestampBypass',
        tag: 'PointService',
      );

      final Response<dynamic>? response = await ApiService.executeWithRetry(
        () => ApiService.get(
          uri.path,
          queryParameters: uri.queryParameters,
          skipAuth: false,
          headers: _requestHeaders(),
        ),
        context: 'getPointBalance',
      );

      final responseStatus = response?.statusCode;
      Logger.info(
        'Point balance response received: status=$responseStatus, url=$requestUrl',
        tag: 'PointService',
      );

      if (NetworkUtils.isValidDioResponse(response)) {
        final Map<String, dynamic>? raw = ApiService.responseAsJsonMap(
          response,
        );
        if (raw == null) {
          final body = ApiService.responseBodyString(response);
          Logger.error(
            'Point balance response parse failed: status=$responseStatus, '
            'url=$requestUrl, body=$body',
            tag: 'PointService',
          );
          _recordPointBalanceFailure(
            statusCode: responseStatus,
            url: requestUrl,
            reason: 'Response parse failed: body=$body',
          );
          return null;
        }
        Logger.info(
          'Point balance response keys: ${raw.keys.toList()}',
          tag: 'PointService',
        );
        // Handle wrapped response: { "data": { "current_balance": 18200 } } or direct
        final Map<String, dynamic> data;
        if (raw.containsKey('data') && raw['data'] is Map) {
          data = Map<String, dynamic>.from(raw['data'] as Map);
        } else {
          data = raw;
        }

        /*
        Old Code:
        (no merge — headline-only balance)
        */
        // Merge embedded lists from root when wrapper omits them from inner `data`.
        if (!data.containsKey('transactions') && raw['transactions'] is List) {
          data['transactions'] = raw['transactions'];
        }
        if (!data.containsKey('recent_transactions') &&
            raw['recent_transactions'] is List) {
          data['recent_transactions'] = raw['recent_transactions'];
        }
        if (!data.containsKey('ledger_preview') &&
            raw['ledger_preview'] is List) {
          data['ledger_preview'] = raw['ledger_preview'];
        }

        final int? mandatoryBalance = _tryParseMandatoryCurrentBalance(data);
        if (mandatoryBalance == null) {
          Logger.error(
            'Point balance response missing or invalid current_balance / currentBalance '
            '— not applying (userId=$userId, keys=${data.keys.toList()})',
            tag: 'PointService',
          );
          _recordPointBalanceFailure(
            statusCode: responseStatus,
            url: requestUrl,
            reason: 'Missing or invalid current_balance in JSON',
          );
          return null;
        }

        /*
        Old Code:
        final balance = PointBalance(
          userId: userId,
          currentBalance: mandatoryBalance,
          lifetimeEarned: _parseBalanceInt(data, 'lifetime_earned'),
          lifetimeRedeemed: _parseBalanceInt(data, 'lifetime_redeemed'),
          lifetimeExpired: _parseBalanceInt(data, 'lifetime_expired'),
          lastUpdated: _parseLastUpdatedOrNow(data['last_updated']),
        );
        */
        int resolvedBalance = mandatoryBalance;
        try {
          resolvedBalance = coalesceHeadlineWithEmbeddedLedgerPreview(
            data,
            mandatoryBalance,
          );
        } catch (e, st) {
          Logger.warning(
            'Point balance embedded coalesce failed; using headline balance only '
            '(userId=$userId): $e',
            tag: 'PointService',
            error: e,
            stackTrace: st,
          );
        }

        final balance = PointBalance(
          userId: userId,
          currentBalance: resolvedBalance,
          lifetimeEarned: _parseBalanceInt(data, 'lifetime_earned'),
          lifetimeRedeemed: _parseBalanceInt(data, 'lifetime_redeemed'),
          lifetimeExpired: _parseBalanceInt(data, 'lifetime_expired'),
          lastUpdated: _parseLastUpdatedOrNow(data['last_updated']),
        );

        if (persistToStorage) {
          await _saveBalanceToStorage(balance);
        }

        Logger.info(
          'Point balance loaded from API: ${balance.currentBalance} points',
          tag: 'PointService',
        );
        _clearPointBalanceFailure();
        return balance;
      }

      // Log actionable diagnostics for easier debugging.
      final status = response?.statusCode;
      final body = ApiService.responseBodyString(response);
      Logger.error(
        'Point balance invalid response: status=$status, url=$requestUrl, body=$body',
        tag: 'PointService',
      );
      _recordPointBalanceFailure(
        statusCode: status,
        url: requestUrl,
        reason: 'Invalid API response: status=$status, body=$body',
      );

      return null;
    } catch (e, stackTrace) {
      Logger.error(
        'Error getting point balance: $e',
        tag: 'PointService',
        error: e,
        stackTrace: stackTrace,
      );
      _recordPointBalanceFailure(
        statusCode: null,
        url: AppConfig.tworkEndpoint(
          '${AppConfig.tworkPointsBalancePath}/$userId',
        ),
        reason: 'Exception during point balance fetch: $e',
      );
      // Server is source of truth for explicit refresh; do not mask failures with cache.
      return null;
    }
  }

  /// Get ALL point transactions from API by loading all pages
  /// This is useful for getting all unique transaction types for filter chips
  static Future<List<PointTransaction>> getAllPointTransactions(
    String userId,
  ) async {
    try {
      final allTransactions = <PointTransaction>[];
      int? totalPages;
      const int perPage = 100; // Load 100 per page for efficiency

      // First, load page 1 to get total_pages info
      Logger.info(
        'Loading first page to get total pages count for user $userId',
        tag: 'PointService',
      );

      // Make direct API call to get pagination info
      // CRITICAL FIX: Request transactions sorted by date (newest first)
      final queryParams = {
        ..._getWooCommerceAuthQueryParams(),
        'page': '1',
        'per_page': perPage.toString(),
        'orderby': 'created_at', // Request sorting by creation date
        'order': 'DESC', // Descending order (newest first)
      };

      final uri = Uri.parse(
        AppConfig.tworkEndpoint(
          '${AppConfig.tworkPointsTransactionsPath}/$userId',
        ),
      ).replace(queryParameters: queryParams);

      final Response<dynamic>? firstResponse =
          await ApiService.executeWithRetry(
            () => ApiService.get(
              uri.path,
              queryParameters: uri.queryParameters,
              skipAuth: false,
              headers: _requestHeaders(),
            ),
            context: 'getAllPointTransactions',
          );

      Map<String, dynamic>? firstData;
      if (NetworkUtils.isValidDioResponse(firstResponse)) {
        final Object? rd = firstResponse!.data;
        if (rd is Map<String, dynamic>) {
          firstData = rd;
        } else if (rd is Map) {
          firstData = Map<String, dynamic>.from(rd);
        } else {
          final bodyStr = ApiService.responseBodyString(firstResponse);
          if (bodyStr.isNotEmpty) {
            final Object? decoded = await _decodePointApiJsonString(bodyStr);
            if (decoded is Map<String, dynamic>) {
              firstData = decoded;
            } else if (decoded is Map) {
              firstData = Map<String, dynamic>.from(decoded);
            }
          }
        }
      }
      if (firstData != null) {
        totalPages = firstData['total_pages'] as int? ?? 1;
        final firstTransactionsData =
            firstData['transactions'] as List<dynamic>? ?? [];

        final firstTransactions = <PointTransaction>[];
        for (final item in firstTransactionsData) {
          try {
            if (item is Map<String, dynamic>) {
              firstTransactions.add(PointTransaction.fromJson(item));
            } else if (item is Map) {
              firstTransactions.add(
                PointTransaction.fromJson(Map<String, dynamic>.from(item)),
              );
            } else {
              Logger.warning(
                'getAllPointTransactions page1: skip non-Map item '
                '${item.runtimeType}',
                tag: 'PointService',
              );
            }
          } catch (e, stackTrace) {
            Logger.error(
              'getAllPointTransactions page1: transaction parse error: $e '
              'item=$item',
              tag: 'PointService',
              error: e,
              stackTrace: stackTrace,
            );
          }
        }

        // CRITICAL FIX: Sort first page transactions by date (newest first)
        firstTransactions.sort((a, b) => b.createdAt.compareTo(a.createdAt));

        allTransactions.addAll(firstTransactions);

        Logger.info(
          'Page 1: Loaded ${firstTransactions.length} transactions. Total pages: $totalPages',
          tag: 'PointService',
        );

        // If we have more pages, load them
        if (totalPages > 1) {
          for (int page = 2; page <= totalPages; page++) {
            Logger.info(
              'Loading transactions page $page of $totalPages for user $userId',
              tag: 'PointService',
            );

            // CRITICAL: getPointTransactions already includes orderby/order params
            // But we need to ensure it's called with the same parameters
            final pageResult = await getPointTransactions(
              userId,
              page: page,
              perPage: perPage,
            );
            final pageTransactions = pageResult.transactions;

            // CRITICAL FIX: Sort each page by date (newest first) as defensive measure
            // Even though API should return sorted, we ensure it here
            pageTransactions.sort((a, b) => b.createdAt.compareTo(a.createdAt));

            if (pageTransactions.isEmpty) {
              Logger.warning(
                'Page $page returned empty, stopping load',
                tag: 'PointService',
              );
              break;
            }

            allTransactions.addAll(pageTransactions);

            // Safety limit to prevent infinite loops
            if (page > 100) {
              Logger.warning(
                'Reached safety limit of 100 pages, stopping transaction load',
                tag: 'PointService',
              );
              break;
            }
          }
        }
      } else {
        // Fallback: use getPointTransactions which handles errors
        Logger.warning(
          'Failed to get pagination info, loading single page as fallback',
          tag: 'PointService',
        );
        final fallbackResult = await getPointTransactions(
          userId,
          page: 1,
          perPage: perPage,
        );
        allTransactions.addAll(fallbackResult.transactions);
      }

      // CRITICAL FIX: Sort all transactions by date (newest first) after loading all pages
      // This ensures consistent ordering even if API returns pages in wrong order
      allTransactions.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      Logger.info(
        'Loaded ${allTransactions.length} total transactions across all pages',
        tag: 'PointService',
      );

      // Log date range for debugging
      if (allTransactions.isNotEmpty) {
        final newest = allTransactions.first;
        final oldest = allTransactions.last;
        Logger.info(
          'All transactions date range: Newest: ${newest.createdAt.toString()} (ID: ${newest.id}), Oldest: ${oldest.createdAt.toString()} (ID: ${oldest.id})',
          tag: 'PointService',
        );
        final now = DateTime.now();
        final newestDiff = newest.createdAt.difference(now).inDays;
        Logger.info(
          'Newest transaction is $newestDiff days ${newestDiff > 0
              ? "in the future"
              : newestDiff < 0
              ? "ago"
              : "today"}',
          tag: 'PointService',
        );
      }

      // Get unique types for logging
      final uniqueTypes = allTransactions.map((t) => t.type).toSet();
      Logger.info(
        'Found ${uniqueTypes.length} unique transaction types: ${uniqueTypes.map((t) => t.toValue()).join(", ")}',
        tag: 'PointService',
      );

      // Log count per type
      for (final type in uniqueTypes) {
        final count = allTransactions.where((t) => t.type == type).length;
        Logger.info(
          '  - ${type.toValue()}: $count transactions',
          tag: 'PointService',
        );
      }

      return allTransactions;
    } catch (e, stackTrace) {
      Logger.error(
        'Error getting all point transactions: $e',
        tag: 'PointService',
        error: e,
        stackTrace: stackTrace,
      );
      // Fallback to cached transactions
      return await getCachedTransactions(userId);
    }
  }

  /// Get point transactions from API
  static Future<PointTransactionHistoryResult> getPointTransactions(
    String userId, {
    int page = 1,
    int perPage = 20,
    int rangeDays = 90,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    try {
      // Use custom WordPress REST endpoint
      // CRITICAL FIX: Request transactions sorted by date (newest first)
      // Add orderby parameter to ensure API returns newest transactions first
      final queryParams = {
        ..._getWooCommerceAuthQueryParams(),
        'page': page.toString(),
        'per_page': perPage.toString(),
        'range_days': rangeDays.toString(),
        'orderby': 'created_at', // Request sorting by creation date
        'order': 'DESC', // Descending order (newest first)
        if (dateFrom != null) 'date_from': _formatHistoryDate(dateFrom),
        if (dateTo != null) 'date_to': _formatHistoryDate(dateTo),
      };

      final uri = Uri.parse(
        AppConfig.tworkEndpoint(
          '${AppConfig.tworkPointsTransactionsPath}/$userId',
        ),
      ).replace(queryParameters: queryParams);

      Logger.info(
        'Requesting transactions with orderby=created_at, order=DESC (newest first)',
        tag: 'PointService',
      );

      Logger.info(
        'Fetching transactions for user $userId (page: $page, perPage: $perPage)',
        tag: 'PointService',
      );
      Logger.info('API URL: $uri', tag: 'PointService');

      final Response<dynamic>? response = await ApiService.executeWithRetry(
        () => ApiService.get(
          uri.path,
          queryParameters: uri.queryParameters,
          skipAuth: false,
          headers: _requestHeaders(),
        ),
        context: 'getPointTransactions',
      );

      final String bodyStr = ApiService.responseBodyString(response);
      // DEBUG: Log response status and body BEFORE validation
      Logger.info(
        'API Response Status: ${response?.statusCode}, Body length: ${bodyStr.length}',
        tag: 'PointService',
      );

      if (response != null && bodyStr.isNotEmpty) {
        Logger.info(
          'Raw API response (first 500 chars): ${bodyStr.substring(0, bodyStr.length > 500 ? 500 : bodyStr.length)}',
          tag: 'PointService',
        );
      }

      if (NetworkUtils.isValidDioResponse(response)) {
        try {
          final Object? rawPayload = response!.data;
          final dynamic data = (rawPayload is Map || rawPayload is List)
              ? rawPayload
              : await _decodePointApiJsonString(bodyStr);

          // DEBUG: Log parsed data structure
          Logger.info(
            'Parsed data type: ${data.runtimeType}',
            tag: 'PointService',
          );
          if (data is Map) {
            Logger.info(
              'Parsed data keys: ${data.keys.toList()}',
              tag: 'PointService',
            );
          } else if (data is List) {
            Logger.info(
              'Parsed data list length: ${data.length}',
              tag: 'PointService',
            );
          }

          // CRITICAL FIX: Handle different response formats
          // Some APIs might return transactions directly as a list, others wrap in 'data' or 'transactions'
          List<dynamic> transactionsData;
          if (data is List) {
            // Response is directly a list of transactions
            transactionsData = data;
            Logger.info(
              'Response is a direct list of ${transactionsData.length} transactions',
              tag: 'PointService',
            );
          } else if (data is Map<String, dynamic>) {
            // Response is an object - check for 'transactions' key first
            if (data.containsKey('transactions')) {
              transactionsData = data['transactions'] as List<dynamic>? ?? [];
            } else if (data.containsKey('data')) {
              // Some APIs wrap in 'data'
              final dataWrapper = data['data'];
              if (dataWrapper is List) {
                transactionsData = dataWrapper;
              } else if (dataWrapper is Map &&
                  dataWrapper.containsKey('transactions')) {
                transactionsData =
                    dataWrapper['transactions'] as List<dynamic>? ?? [];
              } else {
                transactionsData = [];
              }
            } else {
              transactionsData = [];
            }
          } else {
            Logger.warning(
              'Unexpected response format: ${data.runtimeType}',
              tag: 'PointService',
            );
            transactionsData = [];
          }

          final total = (data is Map<String, dynamic>)
              ? (data['total'] as int? ?? 0)
              : transactionsData.length;
          final totalPages = (data is Map<String, dynamic>)
              ? (data['total_pages'] as int? ?? 1)
              : 1;

          Logger.info(
            'Transactions data count: ${transactionsData.length}, Total: $total, Total Pages: $totalPages',
            tag: 'PointService',
          );

          if (transactionsData.isEmpty) {
            Logger.warning(
              'API returned empty transactions list for user $userId',
              tag: 'PointService',
            );
            // SAFETY:
            // Only cache "empty" when the API explicitly indicates there are zero transactions.
            // This prevents wiping a previously-good cache due to a transient backend issue.
            if (page == 1 && total == 0) {
              await _cacheTransactions(userId, []);
              return PointTransactionHistoryResult(
                transactions: const [],
                total: 0,
                page: page,
                perPage: perPage,
                totalPages: 1,
              );
            }

            // Otherwise, fall back to cache (best UX) instead of showing blank history.
            return PointTransactionHistoryResult(
              transactions: await getCachedTransactions(userId),
              total: total,
              page: page,
              perPage: perPage,
              totalPages: totalPages,
            );
          }

          final transactions = <PointTransaction>[];
          for (final item in transactionsData) {
            try {
              if (item is Map<String, dynamic>) {
                final txn = PointTransaction.fromJson(item);
                transactions.add(txn);
                Logger.debug(
                  'Parsed transaction: ${txn.id}, type: ${txn.type}, points: ${txn.points}, status: ${txn.status}, orderId: ${txn.orderId}',
                  tag: 'PointService',
                );
              } else {
                Logger.warning(
                  'Skipping invalid transaction item (not a Map): ${item.runtimeType}',
                  tag: 'PointService',
                );
              }
            } catch (e, stackTrace) {
              Logger.error(
                'Error parsing transaction: $e, data: $item',
                tag: 'PointService',
                error: e,
                stackTrace: stackTrace,
              );
              // Continue parsing other transactions instead of failing completely
            }
          }

          // If API returned items but we couldn't parse any, do NOT overwrite cache with empty.
          // This usually indicates a schema/type mismatch (e.g., points coming as string).
          if (transactions.isEmpty && transactionsData.isNotEmpty) {
            Logger.error(
              'API returned ${transactionsData.length} transactions but 0 parsed successfully. Falling back to cache.',
              tag: 'PointService',
            );
            return PointTransactionHistoryResult(
              transactions: await getCachedTransactions(userId),
              total: total,
              page: page,
              perPage: perPage,
              totalPages: totalPages,
            );
          }

          // Merge API payload with cached details before caching to prevent
          // null poll_details from overwriting previously-enriched rows.
          final cachedBeforeWrite = await getCachedTransactions(userId);
          final mergedForCache = mergeTransactionsPreservingPollDetails(
            existing: cachedBeforeWrite,
            incoming: transactions,
          );
          await _cacheTransactions(userId, mergedForCache);

          Logger.info(
            'Successfully loaded ${transactions.length} point transactions from API (${transactionsData.length} raw items, ${transactionsData.length - transactions.length} failed to parse)',
            tag: 'PointService',
          );
          return PointTransactionHistoryResult(
            transactions: mergedForCache,
            total: total,
            page: page,
            perPage: perPage,
            totalPages: totalPages,
          );
        } catch (parseError, parseStackTrace) {
          Logger.error(
            'Error parsing API response: $parseError',
            tag: 'PointService',
            error: parseError,
            stackTrace: parseStackTrace,
          );
          Logger.error(
            'Response body: ${ApiService.responseBodyString(response)}',
            tag: 'PointService',
          );
          // Fall through to return cached transactions
        }
      }

      // BEST PRACTICE:
      // If the API response is non-2xx, fall back to cache only when cache has data.
      // If cache is empty, propagate an actionable error so UI doesn't show a silent empty state.
      final cached = await getCachedTransactions(userId);
      if (cached.isNotEmpty) {
        Logger.warning(
          'Invalid response from API, using cached transactions (${cached.length})',
          tag: 'PointService',
        );
        return PointTransactionHistoryResult(
          transactions: cached,
          total: cached.length,
          page: page,
          perPage: perPage,
          totalPages: 1,
        );
      }

      final status = response?.statusCode;
      final statusMessage = status != null
          ? '${status} ${NetworkUtils.getStatusMessage(status)}'
          : 'No response';

      String backendMessage = '';
      try {
        final String errBody = ApiService.responseBodyString(response);
        if (errBody.isNotEmpty) {
          final decoded = json.decode(errBody);
          if (decoded is Map) {
            backendMessage =
                (decoded['message']?.toString() ??
                        decoded['error']?.toString() ??
                        decoded['msg']?.toString() ??
                        '')
                    .trim();
          }
        }
      } catch (_) {
        // Ignore body parsing errors here; we'll use status message only.
      }

      final details = backendMessage.isNotEmpty ? ' - $backendMessage' : '';
      throw Exception('Failed to load transactions ($statusMessage)$details');
    } catch (e, stackTrace) {
      Logger.error(
        'Error getting point transactions: $e',
        tag: 'PointService',
        error: e,
        stackTrace: stackTrace,
      );
      final cached = await getCachedTransactions(userId);
      return PointTransactionHistoryResult(
        transactions: cached,
        total: cached.length,
        page: page,
        perPage: perPage,
        totalPages: 1,
      );
    }
  }

  static String _formatHistoryDate(DateTime value) {
    final normalized = DateTime(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
      value.second,
    );
    final two = (int v) => v.toString().padLeft(2, '0');
    return '${normalized.year}-${two(normalized.month)}-${two(normalized.day)} ${two(normalized.hour)}:${two(normalized.minute)}:${two(normalized.second)}';
  }

  /// Earn points (e.g., on purchase, signup, review)
  /// When [waitForSync] is true, waits for backend sync (for poll win etc.).
  static Future<bool> earnPoints({
    required String userId,
    required int points,
    required PointTransactionType type,
    String? description,
    String? orderId,
    DateTime? expiresAt,
    PointTransactionStatus status = PointTransactionStatus.approved,
    bool waitForSync = false,
  }) async {
    try {
      // Local duplicate: non-blocking earn aborts; blocking (poll) still POSTs so server can credit
      // if prior sync failed, but we must not double-count local balance/storage.
      var skipLocalPersist = false;
      if (orderId != null && type == PointTransactionType.earn) {
        final existingTransactions = await getCachedTransactions(userId);
        final now = DateTime.now();
        final fiveMinutesAgo = now.subtract(Duration(minutes: 5));

        final duplicateExists = existingTransactions.any((t) {
          return t.type == PointTransactionType.earn &&
              t.orderId == orderId &&
              t.points == points &&
              t.createdAt.isAfter(fiveMinutesAgo);
        });

        if (duplicateExists) {
          if (waitForSync) {
            skipLocalPersist = true;
            Logger.info(
              'Local duplicate for $orderId — retrying backend sync only (no local double credit)',
              tag: 'PointService',
            );
          } else {
            Logger.warning(
              'Duplicate point earning prevented for order: $orderId',
              tag: 'PointService',
            );
            return false;
          }
        }
      }

      // Create transaction
      final transaction = PointTransaction(
        id: '${DateTime.now().millisecondsSinceEpoch}',
        userId: userId,
        type: type,
        points: points,
        description: description,
        orderId: orderId,
        createdAt: DateTime.now(),
        expiresAt: expiresAt,
        status: status,
      );

      if (!skipLocalPersist) {
        // Save transaction locally first
        await _saveTransactionToStorage(transaction);

        /*
        // Old Code: update balance locally when approved (manual cache += points; use API canonical instead).
        if (status == PointTransactionStatus.approved) {
          final currentBalance = await getCachedBalance(userId);
          if (currentBalance != null) {
            final updatedBalance = PointBalance(
              userId: userId,
              currentBalance: currentBalance.currentBalance + points,
              lifetimeEarned: currentBalance.lifetimeEarned + points,
              lifetimeRedeemed: currentBalance.lifetimeRedeemed,
              lifetimeExpired: currentBalance.lifetimeExpired,
              lastUpdated: DateTime.now(),
            );
            await _saveBalanceToStorage(updatedBalance);
          }
        }
        */
      }

      // Sync with backend
      bool syncSuccess = false;
      if (waitForSync) {
        PointSyncTelemetry.emitUserMessage(
          transaction: transaction,
          context: 'earnPoints',
          message: 'Syncing points...',
        );
        try {
          syncSuccess = await _syncPointsToBackendSync(userId, transaction);
          if (!syncSuccess) {
            Logger.warning(
              'Backend sync failed for point earning, queuing for retry',
              tag: 'PointService',
            );
            await _enqueuePointAdjustment(userId, transaction);
            PointSyncTelemetry.emitUserMessage(
              transaction: transaction,
              context: 'earnPoints',
              message: 'Sync taking longer; queued for retry',
            );
          }
        } catch (e) {
          Logger.error(
            'Error syncing points to backend (blocking): $e',
            tag: 'PointService',
            error: e,
          );
          await _enqueuePointAdjustment(userId, transaction);
          PointSyncTelemetry.emitUserMessage(
            transaction: transaction,
            context: 'earnPoints',
            message: 'Sync taking longer; queued for retry',
          );
        }
      } else {
        _syncPointsToBackend(userId, transaction).catchError((e) {
          Logger.error(
            'Error syncing points to backend: $e',
            tag: 'PointService',
            error: e,
          );
        });
        syncSuccess = true; // Non-blocking: assume will succeed
      }

      Logger.info(
        'Points earned: $points points (backend: ${syncSuccess ? "ok" : "queued"})',
        tag: 'PointService',
      );

      // Notify global listeners (PointProvider) so My PNP updates without context.
      if (type == PointTransactionType.earn) {
        try {
          final broadcastBalance = await getCachedBalance(userId);
          if (broadcastBalance != null) {
            notifyPointBalanceBroadcast(
              userId: userId,
              newBalance: broadcastBalance.currentBalance,
              source: 'earn_points',
            );
          }
        } catch (e, stackTrace) {
          Logger.warning(
            'Point balance broadcast after earn skipped: $e',
            tag: 'PointService',
            error: e,
            stackTrace: stackTrace,
          );
        }
      }

      return waitForSync ? syncSuccess : true;
    } catch (e, stackTrace) {
      Logger.error(
        'Error earning points: $e',
        tag: 'PointService',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Redeem points (e.g., for discount)
  /// If waitForSync is true, waits for backend sync to complete (important for order creation)
  static Future<bool> redeemPoints({
    required String userId,
    required int points,
    String? description,
    String? orderId,
    bool waitForSync = false,
  }) async {
    try {
      // Check if user has enough points
      final currentBalance = await getCachedBalance(userId);
      if (currentBalance == null || currentBalance.currentBalance < points) {
        Logger.warning(
          'Insufficient points for redemption. Current: ${currentBalance?.currentBalance ?? 0}, Required: $points',
          tag: 'PointService',
        );
        return false;
      }

      // Create transaction
      final transaction = PointTransaction(
        id: '${DateTime.now().millisecondsSinceEpoch}',
        userId: userId,
        type: PointTransactionType.redeem,
        points: points,
        description: description,
        orderId: orderId,
        createdAt: DateTime.now(),
      );

      // If orderId is provided and waitForSync is true, sync to backend first
      // This ensures points are deducted on server before order completion
      if (orderId != null && waitForSync) {
        PointSyncTelemetry.emitUserMessage(
          transaction: transaction,
          context: 'redeemPoints',
          message: 'Syncing points...',
        );
        try {
          final syncSuccess = await _syncPointsToBackendSync(
            userId,
            transaction,
          );
          if (!syncSuccess) {
            Logger.warning(
              'Backend sync failed for point redemption, but continuing with local update',
              tag: 'PointService',
            );
            await _enqueuePointAdjustment(userId, transaction);
            PointSyncTelemetry.emitUserMessage(
              transaction: transaction,
              context: 'redeemPoints',
              message: 'Sync taking longer; queued for retry',
            );
            // Continue with local update even if sync fails
          }
        } catch (e) {
          Logger.error(
            'Error syncing points to backend (blocking): $e',
            tag: 'PointService',
            error: e,
          );
          await _enqueuePointAdjustment(userId, transaction);
          PointSyncTelemetry.emitUserMessage(
            transaction: transaction,
            context: 'redeemPoints',
            message: 'Sync taking longer; queued for retry',
          );
          // Continue with local update
        }
      }

      // Save transaction locally
      await _saveTransactionToStorage(transaction);

      // Update balance locally
      final updatedBalance = PointBalance(
        userId: userId,
        currentBalance: currentBalance.currentBalance - points,
        lifetimeEarned: currentBalance.lifetimeEarned,
        lifetimeRedeemed: currentBalance.lifetimeRedeemed + points,
        lifetimeExpired: currentBalance.lifetimeExpired,
        lastUpdated: DateTime.now(),
      );
      await _saveBalanceToStorage(updatedBalance);

      // Sync with backend (non-blocking if not already synced)
      if (!(orderId != null && waitForSync)) {
        _syncPointsToBackend(userId, transaction).catchError((e) {
          Logger.error(
            'Error syncing points to backend: $e',
            tag: 'PointService',
            error: e,
          );
        });
      }

      Logger.info(
        'Points redeemed: $points points (Order: ${orderId ?? "N/A"})',
        tag: 'PointService',
      );
      return true;
    } catch (e, stackTrace) {
      Logger.error(
        'Error redeeming points: $e',
        tag: 'PointService',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Create a point exchange / claim request.
  /// This does NOT immediately change the local balance; the request will be
  /// reviewed and approved from the WordPress dashboard.
  ///
  /// PROFESSIONAL: Includes request throttling to prevent duplicate requests
  static Future<bool> createClaimRequest({
    required String userId,
    required int points,
    required String phone,
    String? note,
  }) async {
    // PROFESSIONAL: Request throttling to prevent duplicate requests
    final now = DateTime.now();
    final lastRequestTime = _lastExchangeRequestTimestamps[userId];
    if (lastRequestTime != null) {
      final timeSinceLastRequest = now.difference(lastRequestTime);
      if (timeSinceLastRequest < _exchangeRequestThrottleDuration) {
        Logger.warning(
          'Exchange request throttled: Last request was ${timeSinceLastRequest.inMilliseconds}ms ago (minimum ${_exchangeRequestThrottleDuration.inSeconds}s required). User: $userId, Points: $points',
          tag: 'PointService',
        );
        return false;
      }
    }
    _lastExchangeRequestTimestamps[userId] = now;

    try {
      final uri = Uri.parse(
        '${AppConfig.backendUrl}/wp-json/twork/v1/rewards/exchange-request',
      ).replace(queryParameters: _getWooCommerceAuthQueryParams());

      final Map<String, dynamic> bodyMap = <String, dynamic>{
        'user_id': int.tryParse(userId) ?? 0,
        'type': 'points',
        'points_value': points.toString(),
        'phone': phone,
        if (note != null && note.isNotEmpty) 'note': note,
      };

      final Response<dynamic>? response = await ApiService.executeWithRetry(
        () => ApiService.post(
          uri.path,
          queryParameters: uri.queryParameters,
          skipAuth: false,
          headers: const <String, dynamic>{'Content-Type': 'application/json'},
          data: bodyMap,
        ),
        context: 'createClaimRequest',
      );

      final String respStr = ApiService.responseBodyString(response);
      // Log response for debugging
      Logger.info(
        'Exchange request response - Status: ${response?.statusCode}, Body: $respStr',
        tag: 'PointService',
      );

      if (response == null) {
        Logger.error(
          'Exchange request failed: No response from server',
          tag: 'PointService',
        );
        return false;
      }

      // CRITICAL: Always parse the response body first to check for success flag
      Map<String, dynamic> data;
      try {
        if (respStr.isEmpty) {
          if (!NetworkUtils.isValidDioResponse(response)) {
            Logger.error(
              'Exchange request failed: Empty response body and invalid status code ${response.statusCode}',
              tag: 'PointService',
            );
            return false;
          }
          Logger.warning(
            'Exchange request: Empty response body but status code ${response.statusCode} is valid. Treating as success.',
            tag: 'PointService',
          );
          return true;
        }

        final Map<String, dynamic>? asMap = ApiService.responseAsJsonMap(
          response,
        );
        final Object? decodedRaw = asMap ?? json.decode(respStr);
        final Map<String, dynamic>? decoded = decodedRaw is Map<String, dynamic>
            ? decodedRaw
            : decodedRaw is Map
            ? Map<String, dynamic>.from(decodedRaw)
            : null;

        if (decoded == null) {
          Logger.error(
            'Exchange request response is not a JSON object. Type: ${decodedRaw.runtimeType}',
            tag: 'PointService',
          );
          Logger.error('Response body: $respStr', tag: 'PointService');
          if (NetworkUtils.isValidDioResponse(response)) {
            Logger.warning(
              'Exchange request: Invalid JSON but status code ${response.statusCode} is valid. Treating as success.',
              tag: 'PointService',
            );
            return true;
          }
          return false;
        }

        data = decoded;

        Logger.info(
          'Exchange request parsed response: $data',
          tag: 'PointService',
        );
      } catch (e, stackTrace) {
        Logger.warning(
          'Failed to parse exchange request response: $e',
          tag: 'PointService',
        );

        if (NetworkUtils.isValidDioResponse(response)) {
          Logger.warning(
            'Exchange request: JSON parse error but status code ${response.statusCode} is valid. Treating as success.',
            tag: 'PointService',
          );
          return true;
        }

        Logger.error(
          'Exchange request failed: JSON parse error and invalid status code ${response.statusCode}',
          tag: 'PointService',
          error: e,
          stackTrace: stackTrace,
        );
        Logger.error('Response body (raw): $respStr', tag: 'PointService');
        return false;
      }

      // Check success flag - handle different possible formats
      // Backend returns: { "success": true, "message": "...", ... }
      // Be more strict about success check to avoid false positives
      final successValue = data['success'];
      final success =
          successValue == true ||
          successValue == 'true' ||
          (successValue is int && successValue == 1);

      final message =
          data['message']?.toString() ?? data['msg']?.toString() ?? '';

      if (success) {
        Logger.info(
          'Exchange request submitted successfully for $points points. Message: $message',
          tag: 'PointService',
        );
        Logger.info(
          'Request ID: ${data['request_id']}, Status: ${data['status']}',
          tag: 'PointService',
        );
        // Do not update local balance here; it will update once the
        // backend approves the request and the app refreshes balance.
        return true;
      } else {
        // Log detailed error information
        final errorMessage = message.isNotEmpty
            ? message
            : 'Exchange request failed without error message';
        Logger.warning(
          'Exchange request API responded with success=false. Message: $errorMessage',
          tag: 'PointService',
        );
        Logger.warning('Full response data: $data', tag: 'PointService');
        Logger.warning(
          'Success value type: ${successValue.runtimeType}, value: $successValue',
          tag: 'PointService',
        );
        return false;
      }
    } catch (e, stackTrace) {
      Logger.error(
        'Error submitting claim request: $e',
        tag: 'PointService',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Sync points to backend synchronously (blocks until complete)
  /// Returns true if sync was successful
  static Future<bool> _syncPointsToBackendSync(
    String userId,
    PointTransaction transaction,
  ) async {
    return _syncPointsWithRetry(
      userId: userId,
      transaction: transaction,
      context: 'syncPointsToBackendSync',
      profile: _blockingSyncProfile,
    );
  }

  /// Sync transaction to backend synchronously (public method for immediate sync)
  static Future<bool> syncTransactionToBackendSync({
    required String userId,
    required PointTransaction transaction,
  }) async {
    return _syncPointsWithRetry(
      userId: userId,
      transaction: transaction,
      context: 'syncTransactionToBackendSync',
      profile: _blockingSyncProfile,
    );
  }

  /// Save transaction locally only (without balance update)
  static Future<void> saveTransactionLocally(
    PointTransaction transaction,
  ) async {
    await _saveTransactionToStorage(transaction);
  }

  /// Record a poll vote deduction transaction locally with rich poll details.
  /// This is UI enrichment for history rendering and does not alter server truth.
  static Future<void> recordPollTransaction({
    required String userId,
    required int pollId,
    required List<Map<String, dynamic>> selectedOptions,
    required int totalBetPnp,
    required int newBalance,
    String? sessionId,
    String? pollTitle,
    String? orderId,
    String? description,
  }) async {
    try {
      if (userId.trim().isEmpty || pollId <= 0) return;
      if (selectedOptions.isEmpty || totalBetPnp <= 0) return;

      final normalizedSelected = <PollOptionSnapshot>[];
      int parseIntLoose(dynamic value) {
        if (value == null) return 0;
        if (value is int) return value;
        if (value is num) return value.toInt();
        return int.tryParse(value.toString().trim()) ??
            (double.tryParse(value.toString().trim())?.toInt() ?? 0);
      }

      // Old Code: fallbackPerOptionFromTotal via ~/ (averaging) when betPnp missing.
      // New Code: trust UI-supplied betPnp / parse only — no synthetic split.

      for (final option in selectedOptions) {
        final idx = option['index'];
        final labelRaw = option['label'];
        final betPnpRaw =
            option['betPnp'] ?? option['bet_pnp'] ?? option['amount'];
        final betUnitsRaw = option['betUnits'];
        final parsedIndex = idx is int ? idx : int.tryParse('$idx');
        // Old Code:
        // final parsedBetPnp = betPnpRaw is int
        //     ? betPnpRaw
        //     : int.tryParse('${betPnpRaw ?? ''}') ?? 0;
        // final parsedBetUnits = betUnitsRaw is int
        //     ? betUnitsRaw
        //     : int.tryParse('${betUnitsRaw ?? ''}') ?? 0;
        //
        // New Code: robust numeric parsing; map exact values into PollOptionSnapshot.
        final parsedBetPnp = parseIntLoose(betPnpRaw);
        final parsedBetUnits = parseIntLoose(betUnitsRaw);
        if (parsedIndex == null || parsedIndex < 0) continue;
        normalizedSelected.add(
          PollOptionSnapshot(
            index: parsedIndex,
            label: (labelRaw?.toString() ?? '').trim(),
            betUnits: parsedBetUnits > 0 ? parsedBetUnits : 1,
            betPnp: parsedBetPnp,
          ),
        );
      }
      if (normalizedSelected.isEmpty) return;

      final normalizedSelectedSorted = List<PollOptionSnapshot>.from(
        normalizedSelected,
      )..sort((a, b) => a.index.compareTo(b.index));
      final optionSignature = normalizedSelectedSorted
          .map((o) => '${o.index}:${o.betUnits}:${o.betPnp}')
          .join('|');
      final normalizedSession =
          (sessionId != null && sessionId.trim().isNotEmpty)
          ? sessionId.trim()
          : 'default';

      // Old Code: fallback orderId used timestamp, which weakens retry dedupe.
      // New Code: deterministic id from poll/user/session/options/spent for idempotent local records.
      final deterministicOrderId =
          'engagement:poll:$pollId:$userId:$normalizedSession:$totalBetPnp:$optionSignature';
      // Old Code:
      // final canonicalOrderId = (orderId != null && orderId.trim().isNotEmpty)
      //     ? orderId.trim()
      //     : deterministicOrderId;
      //
      // New Code: always prefer deterministic id for robust retry dedupe.
      final canonicalOrderId = deterministicOrderId;

      // Prevent accidental duplicate local inserts for same poll session/order.
      final cached = await getCachedTransactions(userId);
      final duplicateExists = cached.any((t) {
        if (t.orderId != canonicalOrderId) return false;
        if (t.type != PointTransactionType.redeem) return false;
        final createdDiff = DateTime.now().difference(t.createdAt).inMinutes;
        return createdDiff <= 5;
      });
      if (duplicateExists) {
        Logger.info(
          'Skipped duplicate poll transaction local record for orderId=$canonicalOrderId',
          tag: 'PointService',
        );
        return;
      }

      final safeDeducted = totalBetPnp < 0 ? 0 : totalBetPnp;

      // Old Code:
      // final safeNewBalance = newBalance < 0 ? 0 : newBalance;
      // final originalBalance = safeNewBalance + safeDeducted;
      //
      // New Code: balance resolution chain with telemetry.
      final cachedBalance = await getCachedBalance(userId);
      final canonicalCachedBalance = cachedBalance?.currentBalance;
      int safeNewBalance;
      int originalBalance;
      String balanceSource;

      if (newBalance >= 0) {
        safeNewBalance = newBalance;
        originalBalance = safeNewBalance + safeDeducted;
        balanceSource = 'server_new_balance';
      } else if (canonicalCachedBalance != null &&
          canonicalCachedBalance >= 0) {
        // Fallback A: canonical balance snapshot from local persisted state.
        safeNewBalance = canonicalCachedBalance;
        originalBalance = safeNewBalance + safeDeducted;
        balanceSource = 'canonical_cached_balance';
      } else {
        // Fallback B: previousBalance - spent (clamp >= 0).
        final previousBalance = (canonicalCachedBalance ?? 0).clamp(0, 1 << 30);
        final computed = (previousBalance - safeDeducted)
            .clamp(0, 1 << 30)
            .toInt();
        safeNewBalance = computed;
        originalBalance = previousBalance.toInt();
        balanceSource = 'computed_previous_minus_spent';
      }
      Logger.info(
        'recordPollTransaction balance source=$balanceSource userId=$userId pollId=$pollId '
        'resolvedNew=$safeNewBalance totalBet=$safeDeducted',
        tag: 'PointService',
      );

      final transaction = PointTransaction(
        id: '${DateTime.now().millisecondsSinceEpoch}',
        userId: userId,
        type: PointTransactionType.redeem,
        points: safeDeducted,
        originalBalance: originalBalance,
        amountAdded: 0,
        amountDeducted: safeDeducted,
        currentBalance: safeNewBalance,
        description: (description != null && description.trim().isNotEmpty)
            ? description.trim()
            : 'Poll vote submitted',
        orderId: canonicalOrderId,
        pollDetails: PollTransactionDetails(
          pollId: pollId,
          pollTitle: (pollTitle != null && pollTitle.trim().isNotEmpty)
              ? pollTitle.trim()
              : null,
          sessionId: (sessionId != null && sessionId.trim().isNotEmpty)
              ? sessionId.trim()
              : null,
          resultStatus: 'pending',
          totalBetPnp: safeDeducted,
          selectedOptions: normalizedSelectedSorted,
        ),
        createdAt: DateTime.now(),
        status: PointTransactionStatus.approved,
      );
      await _saveTransactionToStorage(transaction);
    } catch (e, stackTrace) {
      Logger.warning(
        'Failed to record local poll transaction: $e',
        tag: 'PointService',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Enqueue transaction for later sync
  static Future<void> enqueueTransactionForSync(
    String userId,
    PointTransaction transaction,
  ) async {
    await _enqueuePointAdjustment(userId, transaction);
  }

  /// Calculate points earned from order total ([multiplier] for promotions/campaigns).
  static int calculatePointsFromOrder(
    double orderTotal, {
    double multiplier = 1.0,
  }) {
    return ((orderTotal * pointsPerDollar) * multiplier).round();
  }

  /// Calculate maximum points that can be redeemed for an order
  static int calculateMaxRedeemablePoints(double orderTotal) {
    final maxDiscount = orderTotal * (maxRedemptionPercent / 100);
    return calculatePointsForDiscount(maxDiscount);
  }

  /// Calculate points needed for discount amount
  static int calculatePointsForDiscount(double discountAmount) {
    return (discountAmount * pointsPerDollarDiscount).round();
  }

  /// Validate redemption amount
  static bool isValidRedemptionAmount(
    int points,
    double orderTotal,
    int currentBalance,
  ) {
    if (points < minRedemptionPoints) return false;
    if (points > currentBalance) return false;
    final maxPoints = calculateMaxRedeemablePoints(orderTotal);
    if (points > maxPoints) return false;
    return true;
  }

  /// Calculate discount from points
  static double calculateDiscountFromPoints(int points) {
    return (points / pointsPerDollarDiscount);
  }

  /// Check for expired points and mark them
  static Future<int> checkAndMarkExpiredPoints(String userId) async {
    try {
      final transactions = await getCachedTransactions(userId);
      final now = DateTime.now();
      int expiredCount = 0;
      int totalExpiredPoints = 0;

      // Check for expired points that haven't been marked yet
      final expiredTransactions = transactions.where((transaction) {
        return transaction.expiresAt != null &&
            !transaction.isExpired &&
            transaction.type == PointTransactionType.earn &&
            now.isAfter(transaction.expiresAt!);
      }).toList();

      if (expiredTransactions.isEmpty) {
        return 0;
      }

      // Calculate total expired points
      totalExpiredPoints = expiredTransactions.fold(
        0,
        (sum, t) => sum + t.points,
      );

      if (totalExpiredPoints > 0) {
        // Create expire transaction (points will be subtracted in redeemPoints logic)
        final expireTransaction = PointTransaction(
          id: '${DateTime.now().millisecondsSinceEpoch}',
          userId: userId,
          type: PointTransactionType.expire,
          points: totalExpiredPoints,
          description:
              'Points expired (${expiredTransactions.length} transaction(s))',
          createdAt: DateTime.now(),
        );

        // Update balance locally by subtracting expired points
        final currentBalance = await getCachedBalance(userId);
        if (currentBalance != null) {
          final updatedBalance = PointBalance(
            userId: userId,
            currentBalance: currentBalance.currentBalance - totalExpiredPoints,
            lifetimeEarned: currentBalance.lifetimeEarned,
            lifetimeRedeemed: currentBalance.lifetimeRedeemed,
            lifetimeExpired:
                currentBalance.lifetimeExpired + totalExpiredPoints,
            lastUpdated: DateTime.now(),
          );
          await _saveBalanceToStorage(updatedBalance);
        }

        // Save expire transaction
        await _saveTransactionToStorage(expireTransaction);

        // Try to sync with backend
        _syncPointsToBackend(userId, expireTransaction).catchError((e) {
          Logger.error(
            'Error syncing expired points to backend: $e',
            tag: 'PointService',
            error: e,
          );
        });

        expiredCount = expiredTransactions.length;
      }

      return expiredCount;
    } catch (e) {
      Logger.error(
        'Error checking expired points: $e',
        tag: 'PointService',
        error: e,
      );
      return 0;
    }
  }

  /// Get points expiring soon
  static Future<List<PointTransaction>> getPointsExpiringSoon(
    String userId,
  ) async {
    try {
      final transactions = await getCachedTransactions(userId);
      final now = DateTime.now();
      final warningDate = now.add(Duration(days: expirationWarningDays));

      return transactions.where((transaction) {
        if (transaction.expiresAt == null || transaction.isExpired) {
          return false;
        }
        if (transaction.type != PointTransactionType.earn) return false;
        return transaction.expiresAt!.isBefore(warningDate) &&
            transaction.expiresAt!.isAfter(now);
      }).toList();
    } catch (e) {
      Logger.error(
        'Error getting expiring points: $e',
        tag: 'PointService',
        error: e,
      );
      return [];
    }
  }

  /// Award referral bonus
  static Future<bool> awardReferralBonus({
    required String userId,
    required String referredUserId,
  }) async {
    return await earnPoints(
      userId: userId,
      points: referralBonus,
      type: PointTransactionType.referral,
      description: 'Referral bonus for referring user #$referredUserId',
      expiresAt: DateTime.now().add(Duration(days: pointsExpirationDays)),
    );
  }

  /// Award birthday bonus
  static Future<bool> awardBirthdayBonus(String userId) async {
    // Check if already awarded this year
    final transactions = await getCachedTransactions(userId);
    final thisYear = DateTime.now().year;
    final alreadyAwarded = transactions.any((t) {
      return t.type == PointTransactionType.birthday &&
          t.createdAt.year == thisYear;
    });

    if (alreadyAwarded) {
      Logger.warning(
        'Birthday bonus already awarded this year',
        tag: 'PointService',
      );
      return false;
    }

    return await earnPoints(
      userId: userId,
      points: birthdayBonus,
      type: PointTransactionType.birthday,
      description: 'Birthday bonus',
      expiresAt: DateTime.now().add(Duration(days: pointsExpirationDays)),
    );
  }

  /// Refund points for cancelled order
  static Future<bool> refundPointsForOrder({
    required String userId,
    required String orderId,
    required int pointsToRefund,
  }) async {
    return await earnPoints(
      userId: userId,
      points: pointsToRefund,
      type: PointTransactionType.refund,
      description: 'Points refunded for cancelled order #$orderId',
      orderId: orderId,
      expiresAt: DateTime.now().add(Duration(days: pointsExpirationDays)),
    );
  }

  /// Get transactions filtered by type
  static Future<List<PointTransaction>> getTransactionsByType(
    String userId,
    PointTransactionType type,
  ) async {
    final transactions = await getCachedTransactions(userId);
    return transactions.where((t) => t.type == type).toList();
  }

  /// Get transactions filtered by date range
  static Future<List<PointTransaction>> getTransactionsByDateRange(
    String userId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final transactions = await getCachedTransactions(userId);
    return transactions.where((t) {
      return t.createdAt.isAfter(startDate) && t.createdAt.isBefore(endDate);
    }).toList();
  }

  /// Get cached balance from local storage
  static Future<PointBalance?> getCachedBalance(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedValue = prefs.getString('$_balanceKey$userId');

      if (storedValue != null) {
        final decrypted = await _securePrefs.maybeDecrypt(storedValue);
        if (decrypted == null) {
          await prefs.remove('$_balanceKey$userId');
          Logger.warning(
            'Cached point balance removed — decrypt failed or invalid ciphertext '
            '(userId=$userId)',
            tag: 'PointService',
          );
          return null;
        }
        final balanceData = json.decode(decrypted) as Map<String, dynamic>;
        return PointBalance.fromJson(balanceData);
      }

      return null;
    } catch (e) {
      Logger.error(
        'Error getting cached balance: $e',
        tag: 'PointService',
        error: e,
      );
      return null;
    }
  }

  /// Get cached transactions from local storage
  static Future<List<PointTransaction>> getCachedTransactions(
    String userId,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedValue = prefs.getString('$_transactionsKey$userId');

      if (storedValue != null) {
        final decrypted = await _securePrefs.maybeDecrypt(storedValue);
        if (decrypted == null) {
          await prefs.remove('$_transactionsKey$userId');
          Logger.warning(
            'Cached point transactions removed — decrypt failed or invalid ciphertext '
            '(userId=$userId)',
            tag: 'PointService',
          );
          return [];
        }
        final transactionsData = json.decode(decrypted) as List<dynamic>;
        final transactions = <PointTransaction>[];
        for (final item in transactionsData) {
          try {
            if (item is Map<String, dynamic>) {
              transactions.add(PointTransaction.fromJson(item));
            } else if (item is Map) {
              transactions.add(
                PointTransaction.fromJson(Map<String, dynamic>.from(item)),
              );
            } else {
              Logger.warning(
                'Cached transaction row skipped (not a Map): ${item.runtimeType}',
                tag: 'PointService',
              );
            }
          } catch (e, stackTrace) {
            Logger.error(
              'Error parsing cached transaction row: $e',
              tag: 'PointService',
              error: e,
              stackTrace: stackTrace,
            );
          }
        }

        // CRITICAL FIX: Always sort by date (newest first) when loading from cache
        // This ensures consistent ordering even if cache was stored in wrong order
        transactions.sort((a, b) => b.createdAt.compareTo(a.createdAt));

        // Log date range for debugging
        if (transactions.isNotEmpty) {
          Logger.info(
            'Cached transactions date range: Newest: ${transactions.first.createdAt.toString()}, Oldest: ${transactions.last.createdAt.toString()}',
            tag: 'PointService',
          );
        }

        return transactions;
      }

      return [];
    } catch (e) {
      Logger.error(
        'Error getting cached transactions: $e',
        tag: 'PointService',
        error: e,
      );
      return [];
    }
  }

  static Future<void> clearTransactionsCache(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_transactionsKey$userId');
      Logger.info(
        'Cleared point transaction cache for user $userId',
        tag: 'PointService',
      );
    } catch (e) {
      Logger.error(
        'Error clearing transactions cache: $e',
        tag: 'PointService',
        error: e,
      );
    }
  }

  /// True when [pollDetails] carries a concrete spend (total or per-option).
  static bool _pollDetailsHasMeaningfulBetData(PollTransactionDetails? p) {
    if (p == null) return false;
    if (p.totalBetPnp > 0) return true;
    for (final o in p.selectedOptions) {
      if (o.betPnp > 0) return true;
    }
    return false;
  }

  /// Prefer local rows that still have per-option [betPnp] when API strips them.
  static bool _pollDetailsHasPerOptionBetPnp(PollTransactionDetails? p) {
    if (p == null) return false;
    for (final o in p.selectedOptions) {
      if (o.betPnp > 0) return true;
    }
    return false;
  }

  /// Merges API transactions with disk cache so enriched local [pollDetails]
  /// (exact option bets) are not overwritten by API rows missing that data.
  ///
  /// Old Code: matched by [PointTransaction.id] only; incoming row with non-null
  /// pollDetails always replaced cache even when poorer than local.
  ///
  /// New Code: also match by [orderId]; if local has meaningful bet data and
  /// incoming does not (or lacks per-option bets), preserve local pollDetails.
  static List<PointTransaction> mergeTransactionsPreservingPollDetails({
    required List<PointTransaction> existing,
    required List<PointTransaction> incoming,
  }) {
    final existingById = <String, PointTransaction>{
      for (final tx in existing) tx.id: tx,
    };

    final existingByOrderId = <String, PointTransaction>{};
    for (final tx in existing) {
      final oid = tx.orderId?.trim();
      if (oid == null || oid.isEmpty) continue;
      final prev = existingByOrderId[oid];
      if (prev == null) {
        existingByOrderId[oid] = tx;
      } else if (_pollDetailsHasPerOptionBetPnp(prev.pollDetails) &&
          !_pollDetailsHasPerOptionBetPnp(tx.pollDetails)) {
        existingByOrderId[oid] = prev;
      } else if (!_pollDetailsHasPerOptionBetPnp(prev.pollDetails) &&
          _pollDetailsHasPerOptionBetPnp(tx.pollDetails)) {
        existingByOrderId[oid] = tx;
      } else {
        existingByOrderId[oid] = tx;
      }
    }

    return incoming.map((tx) {
      PointTransaction? old = existingById[tx.id];
      final oid = tx.orderId?.trim();
      if (old == null &&
          oid != null &&
          oid.isNotEmpty &&
          existingByOrderId.containsKey(oid)) {
        old = existingByOrderId[oid];
      }
      if (old == null) return tx;

      if (_pollDetailsHasPerOptionBetPnp(old.pollDetails) &&
          !_pollDetailsHasPerOptionBetPnp(tx.pollDetails)) {
        return tx.copyWith(pollDetails: old.pollDetails);
      }
      if (_pollDetailsHasMeaningfulBetData(old.pollDetails) &&
          !_pollDetailsHasMeaningfulBetData(tx.pollDetails)) {
        return tx.copyWith(pollDetails: old.pollDetails);
      }
      if (tx.pollDetails != null) return tx;
      if (old.pollDetails == null) return tx;
      return tx.copyWith(pollDetails: old.pollDetails);
    }).toList();
  }

  /// Same persisted semantics as disk: compare balance + lifetime stats + expiry.
  /// [lastUpdated] is intentionally ignored — API rows often differ only by timestamps.
  static bool cachedBalanceMatchesForPersistence(
    PointBalance? cached,
    PointBalance incoming,
  ) {
    if (cached == null) return false;
    return cached.userId == incoming.userId &&
        cached.currentBalance == incoming.currentBalance &&
        cached.lifetimeEarned == incoming.lifetimeEarned &&
        cached.lifetimeRedeemed == incoming.lifetimeRedeemed &&
        cached.lifetimeExpired == incoming.lifetimeExpired &&
        cached.pointsExpireAt == incoming.pointsExpireAt;
  }

  /// Persists a full [PointBalance] row from a trusted fetch (e.g. smart poll).
  static Future<void> persistFetchedBalance(PointBalance balance) async {
    await _saveBalanceToStorage(balance);
  }

  /// Overwrite SharedPreferences balance so cold start matches canonical truth.
  static Future<void> saveCanonicalBalance({
    required String userId,
    required int currentBalance,
  }) async {
    try {
      final existing = await getCachedBalance(userId);
      final balance = PointBalance(
        userId: userId,
        currentBalance: currentBalance,
        lifetimeEarned: existing?.lifetimeEarned ?? 0,
        lifetimeRedeemed: existing?.lifetimeRedeemed ?? 0,
        lifetimeExpired: existing?.lifetimeExpired ?? 0,
        lastUpdated: DateTime.now(),
        pointsExpireAt: existing?.pointsExpireAt,
      );
      if (cachedBalanceMatchesForPersistence(existing, balance)) {
        Logger.debug(
          'saveCanonicalBalance: skip redundant write (balance=$currentBalance '
          'userId=$userId)',
          tag: 'PointService',
        );
        return;
      }
      await _saveBalanceToStorage(balance);
      Logger.info(
        'Canonical balance persisted to disk: $currentBalance (userId=$userId)',
        tag: 'PointService',
      );
    } catch (e, stackTrace) {
      Logger.error(
        'Error saving canonical balance: $e',
        tag: 'PointService',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Save balance to local storage
  static Future<void> _saveBalanceToStorage(PointBalance balance) async {
    try {
      final existing = await getCachedBalance(balance.userId);
      if (cachedBalanceMatchesForPersistence(existing, balance)) {
        Logger.debug(
          '_saveBalanceToStorage: skip redundant write (userId=${balance.userId}, '
          'balance=${balance.currentBalance})',
          tag: 'PointService',
        );
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final balanceJson = json.encode(balance.toJson());
      final encrypted = await _securePrefs.encrypt(balanceJson);
      await prefs.setString('$_balanceKey${balance.userId}', encrypted);
    } catch (e) {
      Logger.error(
        'Error saving balance to storage: $e',
        tag: 'PointService',
        error: e,
      );
    }
  }

  /// Save transaction to local storage
  static Future<void> _saveTransactionToStorage(
    PointTransaction transaction,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final transactions = await getCachedTransactions(transaction.userId);

      // Add new transaction
      transactions.insert(0, transaction);

      // Keep only last 100 transactions
      final limitedTransactions = transactions.take(100).toList();

      final transactionsJson = json.encode(
        limitedTransactions.map((t) => t.toJson()).toList(),
      );
      final encrypted = await _securePrefs.encrypt(transactionsJson);
      await prefs.setString(
        '$_transactionsKey${transaction.userId}',
        encrypted,
      );
    } catch (e) {
      Logger.error(
        'Error saving transaction to storage: $e',
        tag: 'PointService',
        error: e,
      );
    }
  }

  /// Sync points to backend (non-blocking)
  static Future<void> _syncPointsToBackend(
    String userId,
    PointTransaction transaction,
  ) async {
    final success = await _syncPointsWithRetry(
      userId: userId,
      transaction: transaction,
      context: 'syncPointsToBackend',
      profile: _backgroundSyncProfile,
    );
    if (!success) {
      await _enqueuePointAdjustment(userId, transaction);
    }
  }

  /// Cache transactions locally
  /// CRITICAL FIX: Always sort transactions by date (newest first) before caching
  /// This ensures cache is always in correct order
  static Future<void> _cacheTransactions(
    String userId,
    List<PointTransaction> transactions,
  ) async {
    try {
      // CRITICAL: Sort by date (newest first) before caching
      // Create a copy to avoid modifying the original list
      final sortedTransactions = List<PointTransaction>.from(transactions)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      final prefs = await SharedPreferences.getInstance();
      final transactionsJson = json.encode(
        sortedTransactions.map((t) => t.toJson()).toList(),
      );
      final encrypted = await _securePrefs.encrypt(transactionsJson);
      await prefs.setString('$_transactionsKey$userId', encrypted);

      Logger.info(
        'Cached ${sortedTransactions.length} transactions (newest: ${sortedTransactions.isNotEmpty ? sortedTransactions.first.createdAt.toString() : "N/A"})',
        tag: 'PointService',
      );
    } catch (e) {
      Logger.error(
        'Error caching transactions: $e',
        tag: 'PointService',
        error: e,
      );
    }
  }

  /// Sync all local transactions to backend
  static Future<bool> syncAllTransactions(String userId) async {
    try {
      final localTransactions = await getCachedTransactions(userId);

      if (localTransactions.isEmpty) {
        return true;
      }

      // Get existing transactions from backend to avoid duplicates
      final existingTransactionsResult = await getPointTransactions(
        userId,
        page: 1,
        perPage: 100,
      );
      final existingTransactions = existingTransactionsResult.transactions;
      final existingOrderIds = existingTransactions
          .where(
            (t) => t.orderId != null && t.type == PointTransactionType.earn,
          )
          .map((t) => t.orderId!)
          .toSet();

      // Filter out transactions that already exist on backend
      final transactionsToSync = localTransactions.where((localT) {
        // Skip if this transaction already exists on backend
        if (localT.orderId != null &&
            localT.type == PointTransactionType.earn) {
          if (existingOrderIds.contains(localT.orderId)) {
            Logger.info(
              'Skipping duplicate transaction for order: ${localT.orderId}',
              tag: 'PointService',
            );
            return false;
          }
        }
        return true;
      }).toList();

      if (transactionsToSync.isEmpty) {
        Logger.info('No new transactions to sync', tag: 'PointService');
        return true;
      }

      // Route harmonization:
      // Some backends no longer expose `/points/sync`; replay each transaction
      // through the active earn/redeem route instead.
      var syncedCount = 0;
      for (final transaction in transactionsToSync) {
        final ok = await _syncPointsWithRetry(
          userId: userId,
          transaction: transaction,
          context: 'syncAllTransactions',
          profile: _backgroundSyncProfile,
        );
        if (ok) {
          syncedCount++;
        }
      }

      Logger.info(
        'Synced $syncedCount/${transactionsToSync.length} transactions via earn/redeem routes',
        tag: 'PointService',
      );
      return syncedCount == transactionsToSync.length;
    } catch (e) {
      Logger.error(
        'Error syncing all transactions: $e',
        tag: 'PointService',
        error: e,
      );
      return false;
    }
  }

  static Future<bool> _syncPointsWithRetry({
    required String userId,
    required PointTransaction transaction,
    required String context,
    required _PointSyncRetryProfile profile,
  }) async {
    Duration backoff = profile.initialBackoff;
    for (int attempt = 1; attempt <= profile.maxAttempts; attempt++) {
      try {
        await _sendPointsToBackendHttp(
          userId: userId,
          transaction: transaction,
          context: context,
          timeout: profile.perAttemptTimeout,
        );
        PointSyncTelemetry.recordSuccess(
          transaction: transaction,
          attempt: attempt,
          context: context,
        );
        Logger.info(
          'Points synced to backend: ${transaction.type} ${transaction.points} points (attempt $attempt)',
          tag: 'PointService',
        );
        return true;
      } catch (e, stackTrace) {
        final isFinalAttempt = attempt == profile.maxAttempts;
        await PointSyncTelemetry.recordFailure(
          transaction: transaction,
          attempt: attempt,
          backoff: isFinalAttempt ? Duration.zero : backoff,
          context: context,
          error: e,
          finalAttempt: isFinalAttempt,
        );
        Logger.error(
          'Error syncing points to backend (attempt $attempt/${profile.maxAttempts}): $e',
          tag: 'PointService',
          error: e,
          stackTrace: stackTrace,
        );

        if (!isFinalAttempt) {
          await Future.delayed(backoff);
          backoff = profile.nextBackoff(backoff);
        }
      }
    }

    return false;
  }

  static Future<void> _sendPointsToBackendHttp({
    required String userId,
    required PointTransaction transaction,
    required String context,
    required Duration timeout,
  }) async {
    final endpointPath = transaction.type == PointTransactionType.redeem
        ? AppConfig.tworkPointsRedeemEndpoint
        : AppConfig.tworkPointsEarnEndpoint;
    final endpoint = AppConfig.tworkEndpoint(endpointPath);
    final uri = Uri.parse(
      endpoint,
    ).replace(queryParameters: _getWooCommerceAuthQueryParams());

    // Phase 1: Avoid nested retry stacks by issuing a single HTTP attempt here.
    // Retry policy is owned by `_syncPointsWithRetry` above.
    final Future<Response<dynamic>> request = ApiService.post(
      uri.path,
      queryParameters: uri.queryParameters,
      skipAuth: false,
      headers: const <String, dynamic>{'Content-Type': 'application/json'},
      data: <String, dynamic>{
        'user_id': userId,
        'points': transaction.points,
        'type': transaction.type.toValue(),
        'description': transaction.description ?? '',
        'order_id': transaction.orderId ?? '',
        if (transaction.expiresAt != null)
          'expires_at': transaction.expiresAt!.toIso8601String(),
        'status': transaction.status.toValue(),
      },
    );

    Response<dynamic> response;
    try {
      response = await request.timeout(timeout);
    } on TimeoutException catch (e) {
      throw Exception('Point sync timed out after ${timeout.inSeconds}s: $e');
    }

    if (!NetworkUtils.isValidDioResponse(response)) {
      String msg =
          'Invalid response while syncing points (status: ${response.statusCode})';
      final String b = ApiService.responseBodyString(response);
      if (b.isNotEmpty) {
        try {
          final Object? body = json.decode(b);
          if (body is Map && body['message'] != null) {
            msg = body['message'].toString();
          }
        } catch (_) {}
      }
      throw Exception(msg);
    }
    try {
      final Map<String, dynamic>? body = ApiService.responseAsJsonMap(response);
      if (body != null && body['success'] == false) {
        final msg = body['message']?.toString() ?? 'Duplicate or failed';
        throw Exception('Backend did not credit points: $msg');
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Failed to parse earn response: $e');
    }
  }

  static Future<void> _enqueuePointAdjustment(
    String userId,
    PointTransaction transaction,
  ) async {
    final queue = OfflineQueueService();
    final payload = <String, dynamic>{
      'user_id': userId,
      'transaction': transaction.toJson(),
    };

    await queue.addToQueue(
      OfflineQueueItemType.pointAdjustment,
      payload,
      dedupeKey: 'point-${transaction.id}',
    );

    Logger.info(
      'Queued point transaction for later sync',
      tag: 'PointService',
      metadata: {'transactionId': transaction.id},
    );
  }

  static void registerOfflineQueueHandler() {
    if (_queueRegistered) {
      return;
    }
    _queueRegistered = true;
    final queue = OfflineQueueService();
    queue.setPointAdjustmentCallback(_processQueuedPointAdjustment);
    /*
    Old Code: no listener — UI balance stayed stale until user navigated / pulled refresh
    after offline point queue replay succeeded.
    */
    // New Code: silent force-refresh so My PNP matches server after each successful replay.
    queue.setPointAdjustmentSyncedListener((String userId) async {
      if (userId.isEmpty) return;
      try {
        await PointProvider.instance.loadBalance(userId, forceRefresh: true);
      } catch (e, stackTrace) {
        Logger.warning(
          'Post offline point-queue balance refresh failed: $e',
          tag: 'PointService',
          error: e,
          stackTrace: stackTrace,
        );
      }
    });
    // Endpoint harmonization: revive previously failed point sync items so they
    // retry against the updated earn/redeem route flow.
    unawaited(queue.resetPointAdjustmentRetriesAndSync());
  }

  static Future<bool> syncQueuedPointTransaction(
    String userId,
    PointTransaction transaction,
  ) {
    return _syncPointsWithRetry(
      userId: userId,
      transaction: transaction,
      context: 'offlineQueue',
      profile: _backgroundSyncProfile,
    );
  }

  static Future<bool> _processQueuedPointAdjustment(
    Map<String, dynamic> payload,
  ) async {
    try {
      if (!payload.containsKey('transaction')) {
        Logger.warning(
          'Queued point adjustment missing payload',
          tag: 'PointService',
        );
        return false;
      }

      final transactionJson = Map<String, dynamic>.from(
        payload['transaction'] as Map,
      );
      final transaction = PointTransaction.fromJson(transactionJson);
      final userId = (payload['user_id']?.toString().trim().isNotEmpty ?? false)
          ? payload['user_id'].toString()
          : transaction.userId;

      Logger.info(
        'Replaying queued point transaction',
        tag: 'PointService',
        metadata: {'transactionId': transaction.id},
      );

      return await syncQueuedPointTransaction(userId, transaction);
    } catch (e, stackTrace) {
      Logger.error(
        'Failed to process queued point adjustment: $e',
        tag: 'PointService',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }
}

class _PointSyncRetryProfile {
  final int maxAttempts;
  final Duration perAttemptTimeout;
  final Duration initialBackoff;
  final double backoffMultiplier;

  const _PointSyncRetryProfile({
    required this.maxAttempts,
    required this.perAttemptTimeout,
    required this.initialBackoff,
    required this.backoffMultiplier,
  });

  Duration nextBackoff(Duration current) {
    if (backoffMultiplier <= 1.0) {
      return current;
    }
    final int ms = (current.inMilliseconds * backoffMultiplier).round();
    return Duration(milliseconds: ms);
  }
}
