import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchronized/synchronized.dart';
import 'logger.dart';

/// Enterprise-grade monitoring and observability system
/// Implements thread-safe operations, data persistence, and advanced metrics
class MonitoringService {
  // Thread-safe collections with locks
  static final Map<String, Metric> _metrics = {};
  static final List<PerformanceEvent> _performanceEvents = [];
  static final List<ErrorEvent> _errorEvents = [];
  static final List<BusinessEvent> _businessEvents = [];
  static final List<HealthCheck> _healthChecks = [];

  // Thread safety locks
  static final Lock _metricsLock = Lock();
  static final Lock _eventsLock = Lock();
  static final Lock _persistenceLock = Lock();

  // Configuration constants - OPTIMIZED for better performance
  // Reduced max events from 10k to 500 to save memory
  static const int _maxEvents = 500;
  static const Duration _cleanupInterval = Duration(minutes: 10); // Increased from 5min
  static const Duration _persistenceInterval = Duration(minutes: 5); // Increased from 2min
  static const Duration _healthCheckInterval = Duration(minutes: 2); // Increased from 30sec

  // Timers and state management
  static Timer? _cleanupTimer;
  static Timer? _persistenceTimer;
  static Timer? _healthCheckTimer;
  static bool _isInitialized = false;
  static bool _isDisposed = false;

  // Performance tracking
  static final Map<String, Stopwatch> _operationStopwatches = {};
  static final Map<String, List<Duration>> _operationDurations = {};

  // Circuit breaker for external services
  static final Map<String, CircuitBreaker> _circuitBreakers = {};

  /// Initialize monitoring service with comprehensive setup
  static Future<void> initialize({
    bool enablePersistence = true,
    bool enableHealthChecks = true,
    Duration? customCleanupInterval,
    Duration? customPersistenceInterval,
  }) async {
    if (_isInitialized) {
      Logger.warning('MonitoringService already initialized',
          tag: 'MonitoringService');
      return;
    }

    try {
      _isInitialized = true;
      _isDisposed = false;

      // Start background timers
      _cleanupTimer = Timer.periodic(
        customCleanupInterval ?? _cleanupInterval,
        (_) => _cleanupOldEvents(),
      );

      if (enablePersistence) {
        _persistenceTimer = Timer.periodic(
          customPersistenceInterval ?? _persistenceInterval,
          (_) => _persistData(),
        );
      }

      if (enableHealthChecks) {
        _healthCheckTimer = Timer.periodic(
          _healthCheckInterval,
          (_) => _performHealthChecks(),
        );
      }

      // Load persisted data
      if (enablePersistence) {
        await _loadPersistedData();
      }

      // Initialize circuit breakers for critical services
      _initializeCircuitBreakers();

      Logger.info('Monitoring service initialized successfully',
          tag: 'MonitoringService');
      trackBusinessEvent('monitoring_initialized', data: {
        'persistence_enabled': enablePersistence,
        'health_checks_enabled': enableHealthChecks,
      });
    } catch (e, stackTrace) {
      _isInitialized = false;
      Logger.error('Failed to initialize monitoring service',
          tag: 'MonitoringService', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Dispose monitoring service with proper cleanup
  static Future<void> dispose() async {
    if (_isDisposed) return;

    try {
      _isDisposed = true;

      // Cancel all timers
      _cleanupTimer?.cancel();
      _persistenceTimer?.cancel();
      _healthCheckTimer?.cancel();

      _cleanupTimer = null;
      _persistenceTimer = null;
      _healthCheckTimer = null;

      // Final data persistence
      await _persistData();

      // Clear all data structures
      await _metricsLock.synchronized(() {
        _metrics.clear();
        _performanceEvents.clear();
        _errorEvents.clear();
        _businessEvents.clear();
        _healthChecks.clear();
        _operationStopwatches.clear();
        _operationDurations.clear();
        _circuitBreakers.clear();
      });

      _isInitialized = false;
      Logger.info('Monitoring service disposed successfully',
          tag: 'MonitoringService');
    } catch (e, stackTrace) {
      Logger.error('Error during monitoring service disposal',
          tag: 'MonitoringService', error: e, stackTrace: stackTrace);
    }
  }

  /// Track performance metric with thread safety
  static Future<void> trackMetric(
    String name,
    double value, {
    Map<String, dynamic>? tags,
    bool persistImmediately = false,
  }) async {
    if (_isDisposed) return;

    try {
      final metric = Metric(
        name: name,
        value: value,
        timestamp: DateTime.now(),
        tags: tags ?? {},
      );

      await _metricsLock.synchronized(() {
        _metrics[name] = metric;
      });

      if (kDebugMode) {
        Logger.info('Metric tracked: $name = $value', tag: 'MonitoringService');
      }

      if (persistImmediately) {
        await _persistData();
      }
    } catch (e, stackTrace) {
      Logger.error('Failed to track metric: $name',
          tag: 'MonitoringService', error: e, stackTrace: stackTrace);
    }
  }

  /// Track performance event with advanced timing
  static Future<void> trackPerformanceEvent(
    String operation,
    Duration duration, {
    Map<String, dynamic>? metadata,
    String? userId,
    bool trackPercentiles = true,
  }) async {
    if (_isDisposed) return;

    try {
      final event = PerformanceEvent(
        operation: operation,
        duration: duration,
        timestamp: DateTime.now(),
        metadata: metadata ?? {},
        userId: userId,
      );

      await _eventsLock.synchronized(() {
        _performanceEvents.add(event);
        _enforceEventLimit();
      });

      // Track percentiles for advanced analytics
      if (trackPercentiles) {
        await _trackOperationPercentiles(operation, duration);
      }

      Logger.logPerformance(operation, duration, metrics: metadata);
    } catch (e, stackTrace) {
      Logger.error('Failed to track performance event: $operation',
          tag: 'MonitoringService', error: e, stackTrace: stackTrace);
    }
  }

  /// Start operation timing
  static void startOperation(String operation) {
    if (_isDisposed) return;
    _operationStopwatches[operation] = Stopwatch()..start();
  }

  /// End operation timing and track
  static Future<void> endOperation(
    String operation, {
    Map<String, dynamic>? metadata,
    String? userId,
  }) async {
    if (_isDisposed) return;

    final stopwatch = _operationStopwatches.remove(operation);
    if (stopwatch != null) {
      stopwatch.stop();
      await trackPerformanceEvent(
        operation,
        stopwatch.elapsed,
        metadata: metadata,
        userId: userId,
      );
    }
  }

  /// Track error event with enhanced context
  static Future<void> trackErrorEvent(
    String operation,
    dynamic error, {
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
    String? userId,
    String? severity = 'error',
    bool isRetryable = false,
    int? retryCount,
  }) async {
    if (_isDisposed) return;

    try {
      final enhancedMetadata = {
        ...?metadata,
        'is_retryable': isRetryable,
        if (retryCount != null) 'retry_count': retryCount,
        'error_type': error.runtimeType.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      };

      final event = ErrorEvent(
        operation: operation,
        error: error.toString(),
        stackTrace: stackTrace?.toString(),
        timestamp: DateTime.now(),
        metadata: enhancedMetadata,
        userId: userId,
        severity: severity ?? 'error',
      );

      await _eventsLock.synchronized(() {
        _errorEvents.add(event);
        _enforceEventLimit();
      });

      // Track error rate metrics
      await trackMetric('error_rate', 1.0, tags: {
        'operation': operation,
        'severity': severity ?? 'error',
        'is_retryable': isRetryable.toString(),
      });

      Logger.error('Error in $operation: $error',
          tag: 'MonitoringService', error: error, stackTrace: stackTrace);
    } catch (e, stackTrace) {
      Logger.error('Failed to track error event: $operation',
          tag: 'MonitoringService', error: e, stackTrace: stackTrace);
    }
  }

  /// Track business event with enhanced analytics
  static Future<void> trackBusinessEvent(
    String eventType, {
    Map<String, dynamic>? data,
    String? userId,
    String? sessionId,
    String? correlationId,
    bool trackConversion = false,
  }) async {
    if (_isDisposed) return;

    try {
      final enhancedData = {
        ...?data,
        if (correlationId != null) 'correlation_id': correlationId,
        if (trackConversion) 'conversion_tracked': true,
      };

      final event = BusinessEvent(
        eventType: eventType,
        data: enhancedData,
        timestamp: DateTime.now(),
        userId: userId,
        sessionId: sessionId,
      );

      await _eventsLock.synchronized(() {
        _businessEvents.add(event);
        _enforceEventLimit();
      });

      // Track conversion metrics if applicable
      if (trackConversion) {
        await trackMetric('conversion_rate', 1.0, tags: {
          'event_type': eventType,
          'user_id': userId ?? 'anonymous',
        });
      }

      Logger.info('Business event: $eventType', tag: 'MonitoringService');
    } catch (e, stackTrace) {
      Logger.error('Failed to track business event: $eventType',
          tag: 'MonitoringService', error: e, stackTrace: stackTrace);
    }
  }

  /// Track API request with circuit breaker
  static Future<void> trackApiRequest(
    String method,
    String url, {
    Map<String, String>? headers,
    String? body,
    String? userId,
    String? serviceName,
  }) async {
    if (_isDisposed) return;

    try {
      final service = serviceName ?? _extractServiceName(url);

      // Check circuit breaker
      if (_circuitBreakers[service]?.isOpen == true) {
        await trackErrorEvent(
          'api_request_circuit_open',
          'Circuit breaker open for service: $service',
          metadata: {'service': service, 'url': url},
          userId: userId,
          severity: 'warning',
        );
        return;
      }

      await trackBusinessEvent('api_request',
          data: {
            'method': method,
            'url': url,
            'service': service,
            'headers_count': headers?.length ?? 0,
            'body_length': body?.length ?? 0,
          },
          userId: userId);
    } catch (e, stackTrace) {
      Logger.error('Failed to track API request',
          tag: 'MonitoringService', error: e, stackTrace: stackTrace);
    }
  }

  /// Track API response with enhanced metrics
  static Future<void> trackApiResponse(
    String method,
    String url,
    int statusCode, {
    Duration? duration,
    String? userId,
    String? serviceName,
    String? responseBody,
  }) async {
    if (_isDisposed) return;

    try {
      final service = serviceName ?? _extractServiceName(url);
      final isSuccess = statusCode >= 200 && statusCode < 300;

      // Update circuit breaker
      _circuitBreakers[service]?.recordResult(isSuccess);

      await trackBusinessEvent('api_response',
          data: {
            'method': method,
            'url': url,
            'service': service,
            'status_code': statusCode,
            'duration_ms': duration?.inMilliseconds,
            'response_size': responseBody?.length ?? 0,
            'is_success': isSuccess,
          },
          userId: userId);

      await trackPerformanceEvent('api_$method', duration ?? Duration.zero,
          userId: userId,
          metadata: {
            'service': service,
            'status_code': statusCode,
          });

      // Track success/failure rates
      await trackMetric('api_success_rate', isSuccess ? 1.0 : 0.0, tags: {
        'service': service,
        'method': method,
        'status_code': statusCode.toString(),
      });
    } catch (e, stackTrace) {
      Logger.error('Failed to track API response',
          tag: 'MonitoringService', error: e, stackTrace: stackTrace);
    }
  }

  /// Track order creation with comprehensive metrics
  static Future<void> trackOrderCreation(
    String orderId, {
    required double total,
    required int itemCount,
    required String paymentMethod,
    String? userId,
    String? sessionId,
    Map<String, dynamic>? additionalData,
  }) async {
    if (_isDisposed) return;

    try {
      await trackBusinessEvent('order_created',
          data: {
            'order_id': orderId,
            'total': total,
            'item_count': itemCount,
            'payment_method': paymentMethod,
            ...?additionalData,
          },
          userId: userId,
          sessionId: sessionId,
          trackConversion: true);

      await trackMetric('orders_created', 1.0, tags: {
        'payment_method': paymentMethod,
        'user_id': userId ?? 'anonymous',
      });

      await trackMetric('order_value', total, tags: {
        'payment_method': paymentMethod,
        'item_count': itemCount.toString(),
      });

      // Track average order value
      await _updateAverageOrderValue(total);
    } catch (e, stackTrace) {
      Logger.error('Failed to track order creation',
          tag: 'MonitoringService', error: e, stackTrace: stackTrace);
    }
  }

  /// Track order status change with workflow analytics
  static Future<void> trackOrderStatusChange(
    String orderId,
    String oldStatus,
    String newStatus, {
    String? userId,
    Duration? timeInStatus,
    String? reason,
  }) async {
    if (_isDisposed) return;

    try {
      await trackBusinessEvent('order_status_changed',
          data: {
            'order_id': orderId,
            'old_status': oldStatus,
            'new_status': newStatus,
            'time_in_status_ms': timeInStatus?.inMilliseconds,
            'reason': reason,
          },
          userId: userId);

      // Track status transition metrics
      await trackMetric('order_status_transition', 1.0, tags: {
        'from_status': oldStatus,
        'to_status': newStatus,
        'user_id': userId ?? 'anonymous',
      });
    } catch (e, stackTrace) {
      Logger.error('Failed to track order status change',
          tag: 'MonitoringService', error: e, stackTrace: stackTrace);
    }
  }

  /// Get comprehensive performance summary
  static Future<PerformanceSummary> getPerformanceSummary() async {
    if (_isDisposed) return PerformanceSummary.empty();

    try {
      final now = DateTime.now();
      final last24Hours = now.subtract(const Duration(hours: 24));

      final recentEvents = await _eventsLock.synchronized(() {
        return _performanceEvents
            .where((event) => event.timestamp.isAfter(last24Hours))
            .toList();
      });

      final recentErrors = await _eventsLock.synchronized(() {
        return _errorEvents
            .where((event) => event.timestamp.isAfter(last24Hours))
            .toList();
      });

      return PerformanceSummary(
        totalEvents: recentEvents.length,
        totalErrors: recentErrors.length,
        averageResponseTime: recentEvents.isNotEmpty
            ? recentEvents
                    .map((e) => e.duration.inMilliseconds)
                    .reduce((a, b) => a + b) /
                recentEvents.length
            : 0.0,
        errorRate: recentEvents.isNotEmpty
            ? recentErrors.length / recentEvents.length
            : 0.0,
        topOperations: await _getTopOperations(recentEvents),
        recentErrors: recentErrors.take(10).toList(),
        p95ResponseTime: _calculatePercentile(recentEvents, 0.95),
        p99ResponseTime: _calculatePercentile(recentEvents, 0.99),
      );
    } catch (e, stackTrace) {
      Logger.error('Failed to get performance summary',
          tag: 'MonitoringService', error: e, stackTrace: stackTrace);
      return PerformanceSummary.empty();
    }
  }

  /// Get comprehensive business metrics
  static Future<BusinessMetrics> getBusinessMetrics() async {
    if (_isDisposed) return BusinessMetrics.empty();

    try {
      final now = DateTime.now();
      final last24Hours = now.subtract(const Duration(hours: 24));

      final recentBusinessEvents = await _eventsLock.synchronized(() {
        return _businessEvents
            .where((event) => event.timestamp.isAfter(last24Hours))
            .toList();
      });

      final orderEvents = recentBusinessEvents
          .where((event) => event.eventType == 'order_created')
          .toList();

      final totalRevenue = orderEvents.fold<double>(0.0, (sum, event) {
        return sum + (event.data['total'] as double? ?? 0.0);
      });

      return BusinessMetrics(
        totalOrders: orderEvents.length,
        totalRevenue: totalRevenue,
        averageOrderValue:
            orderEvents.isNotEmpty ? totalRevenue / orderEvents.length : 0.0,
        topPaymentMethods: _getTopPaymentMethods(orderEvents),
        conversionRate: await _calculateConversionRate(recentBusinessEvents),
        customerRetentionRate: await _calculateRetentionRate(),
      );
    } catch (e, stackTrace) {
      Logger.error('Failed to get business metrics',
          tag: 'MonitoringService', error: e, stackTrace: stackTrace);
      return BusinessMetrics.empty();
    }
  }

  /// Export comprehensive metrics for external monitoring
  static Future<Map<String, dynamic>> exportMetrics() async {
    if (_isDisposed) return {};

    try {
      final performanceSummary = await getPerformanceSummary();
      final businessMetrics = await getBusinessMetrics();

      return await _eventsLock.synchronized(() {
        return {
          'metrics':
              _metrics.map((key, value) => MapEntry(key, value.toJson())),
          'performance_events':
              _performanceEvents.map((e) => e.toJson()).toList(),
          'error_events': _errorEvents.map((e) => e.toJson()).toList(),
          'business_events': _businessEvents.map((e) => e.toJson()).toList(),
          'health_checks': _healthChecks.map((h) => h.toJson()).toList(),
          'summary': performanceSummary.toJson(),
          'business_metrics': businessMetrics.toJson(),
          'circuit_breakers': _circuitBreakers
              .map((key, value) => MapEntry(key, value.toJson())),
          'export_timestamp': DateTime.now().toIso8601String(),
        };
      });
    } catch (e, stackTrace) {
      Logger.error('Failed to export metrics',
          tag: 'MonitoringService', error: e, stackTrace: stackTrace);
      return {};
    }
  }

  /// Add health check
  static Future<void> addHealthCheck(
      String name, Future<bool> Function() check) async {
    if (_isDisposed) return;

    try {
      final healthCheck = HealthCheck(
        name: name,
        check: check,
        lastChecked: DateTime.now(),
        isHealthy: false,
      );

      await _eventsLock.synchronized(() {
        _healthChecks.add(healthCheck);
      });

      Logger.info('Health check added: $name', tag: 'MonitoringService');
    } catch (e, stackTrace) {
      Logger.error('Failed to add health check: $name',
          tag: 'MonitoringService', error: e, stackTrace: stackTrace);
    }
  }

  /// Get health status
  static Future<Map<String, bool>> getHealthStatus() async {
    if (_isDisposed) return {};

    try {
      final status = <String, bool>{};

      await _eventsLock.synchronized(() {
        for (final healthCheck in _healthChecks) {
          status[healthCheck.name] = healthCheck.isHealthy;
        }
      });

      return status;
    } catch (e, stackTrace) {
      Logger.error('Failed to get health status',
          tag: 'MonitoringService', error: e, stackTrace: stackTrace);
      return {};
    }
  }

  // Private helper methods

  /// Clean up old events with thread safety
  static Future<void> _cleanupOldEvents() async {
    if (_isDisposed) return;

    try {
      final cutoff = DateTime.now().subtract(const Duration(hours: 24));

      await _eventsLock.synchronized(() {
        _performanceEvents
            .removeWhere((event) => event.timestamp.isBefore(cutoff));
        _errorEvents.removeWhere((event) => event.timestamp.isBefore(cutoff));
        _businessEvents
            .removeWhere((event) => event.timestamp.isBefore(cutoff));
        _healthChecks
            .removeWhere((event) => event.lastChecked.isBefore(cutoff));
      });

      Logger.info('Cleaned up old monitoring events', tag: 'MonitoringService');
    } catch (e, stackTrace) {
      Logger.error('Failed to cleanup old events',
          tag: 'MonitoringService', error: e, stackTrace: stackTrace);
    }
  }

  /// Enforce event limits with thread safety - OPTIMIZED
  /// More aggressive cleanup to prevent memory bloat
  static Future<void> _enforceEventLimit() async {
    // Keep only the most recent events, remove oldest first
    if (_performanceEvents.length > _maxEvents) {
      final removeCount = _performanceEvents.length - _maxEvents;
      _performanceEvents.removeRange(0, removeCount);
    }
    if (_errorEvents.length > _maxEvents) {
      final removeCount = _errorEvents.length - _maxEvents;
      _errorEvents.removeRange(0, removeCount);
    }
    if (_businessEvents.length > _maxEvents) {
      final removeCount = _businessEvents.length - _maxEvents;
      _businessEvents.removeRange(0, removeCount);
    }
  }

  /// Persist data to storage - OPTIMIZED to reduce I/O operations
  static Future<void> _persistData() async {
    if (_isDisposed) return;

    try {
      await _persistenceLock.synchronized(() async {
        final prefs = await SharedPreferences.getInstance();

        // Persist metrics (only essential metrics, not all)
        final metricsJson =
            _metrics.map((key, value) => MapEntry(key, value.toJson()));
        await prefs.setString('monitoring_metrics', jsonEncode(metricsJson));

        // OPTIMIZED: Persist only last 50 events (reduced from 100) to save storage and memory
        final recentPerformanceEvents =
            _performanceEvents.take(50).map((e) => e.toJson()).toList();
        await prefs.setString('monitoring_performance_events',
            jsonEncode(recentPerformanceEvents));

        final recentErrorEvents =
            _errorEvents.take(50).map((e) => e.toJson()).toList();
        await prefs.setString(
            'monitoring_error_events', jsonEncode(recentErrorEvents));

        final recentBusinessEvents =
            _businessEvents.take(50).map((e) => e.toJson()).toList();
        await prefs.setString(
            'monitoring_business_events', jsonEncode(recentBusinessEvents));

        Logger.debug('Monitoring data persisted successfully',
            tag: 'MonitoringService');
      });
    } catch (e, stackTrace) {
      Logger.error('Failed to persist monitoring data',
          tag: 'MonitoringService', error: e, stackTrace: stackTrace);
    }
  }

  /// Load persisted data
  static Future<void> _loadPersistedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load metrics
      final metricsJson = prefs.getString('monitoring_metrics');
      if (metricsJson != null) {
        final metricsData = jsonDecode(metricsJson) as Map<String, dynamic>;
        for (final entry in metricsData.entries) {
          _metrics[entry.key] = Metric.fromJson(entry.value);
        }
      }

      Logger.info('Loaded persisted monitoring data', tag: 'MonitoringService');
    } catch (e, stackTrace) {
      Logger.error('Failed to load persisted data',
          tag: 'MonitoringService', error: e, stackTrace: stackTrace);
    }
  }

  /// Perform health checks
  static Future<void> _performHealthChecks() async {
    if (_isDisposed) return;

    try {
      await _eventsLock.synchronized(() async {
        for (final healthCheck in _healthChecks) {
          try {
            final isHealthy = await healthCheck.check();
            healthCheck.isHealthy = isHealthy;
            healthCheck.lastChecked = DateTime.now();
          } catch (e) {
            healthCheck.isHealthy = false;
            healthCheck.lastChecked = DateTime.now();
            Logger.error('Health check failed: ${healthCheck.name}',
                tag: 'MonitoringService', error: e);
          }
        }
      });
    } catch (e, stackTrace) {
      Logger.error('Failed to perform health checks',
          tag: 'MonitoringService', error: e, stackTrace: stackTrace);
    }
  }

  /// Initialize circuit breakers
  static void _initializeCircuitBreakers() {
    _circuitBreakers['api'] = CircuitBreaker(
      failureThreshold: 5,
      timeout: const Duration(seconds: 30),
    );
    _circuitBreakers['database'] = CircuitBreaker(
      failureThreshold: 3,
      timeout: const Duration(seconds: 60),
    );
  }

  /// Track operation percentiles
  static Future<void> _trackOperationPercentiles(
      String operation, Duration duration) async {
    _operationDurations.putIfAbsent(operation, () => []).add(duration);

    // OPTIMIZED: Keep only last 50 durations per operation (reduced from 100)
    if (_operationDurations[operation]!.length > 50) {
      _operationDurations[operation]!.removeAt(0);
    }
  }

  /// Get top operations by frequency
  static Future<List<OperationStats>> _getTopOperations(
      List<PerformanceEvent> events) async {
    final operationCounts = <String, int>{};
    final operationDurations = <String, List<int>>{};

    for (final event in events) {
      operationCounts[event.operation] =
          (operationCounts[event.operation] ?? 0) + 1;
      operationDurations
          .putIfAbsent(event.operation, () => [])
          .add(event.duration.inMilliseconds);
    }

    return operationCounts.entries.map((entry) {
      final durations = operationDurations[entry.key] ?? [];
      final avgDuration = durations.isNotEmpty
          ? durations.reduce((a, b) => a + b) / durations.length
          : 0.0;

      return OperationStats(
        operation: entry.key,
        count: entry.value,
        averageDuration: avgDuration,
      );
    }).toList()
      ..sort((a, b) => b.count.compareTo(a.count));
  }

  /// Get top payment methods
  static List<PaymentMethodStats> _getTopPaymentMethods(
      List<BusinessEvent> orderEvents) {
    final paymentMethodCounts = <String, int>{};

    for (final event in orderEvents) {
      final paymentMethod =
          event.data['payment_method'] as String? ?? 'unknown';
      paymentMethodCounts[paymentMethod] =
          (paymentMethodCounts[paymentMethod] ?? 0) + 1;
    }

    return paymentMethodCounts.entries.map((entry) {
      return PaymentMethodStats(
        method: entry.key,
        count: entry.value,
      );
    }).toList()
      ..sort((a, b) => b.count.compareTo(a.count));
  }

  /// Calculate percentile
  static double _calculatePercentile(
      List<PerformanceEvent> events, double percentile) {
    if (events.isEmpty) return 0.0;

    final durations = events.map((e) => e.duration.inMilliseconds).toList()
      ..sort();
    final index = (percentile * (durations.length - 1)).round();
    return durations[index].toDouble();
  }

  /// Update average order value
  static Future<void> _updateAverageOrderValue(double orderValue) async {
    final currentAvg = _metrics['average_order_value']?.value ?? 0.0;
    final orderCount = _metrics['orders_created']?.value ?? 0.0;

    if (orderCount > 0) {
      final newAvg =
          ((currentAvg * orderCount) + orderValue) / (orderCount + 1);
      await trackMetric('average_order_value', newAvg);
    } else {
      await trackMetric('average_order_value', orderValue);
    }
  }

  /// Calculate conversion rate
  static Future<double> _calculateConversionRate(
      List<BusinessEvent> events) async {
    final totalSessions =
        events.where((e) => e.eventType == 'session_start').length;
    final conversions =
        events.where((e) => e.eventType == 'order_created').length;

    return totalSessions > 0 ? conversions / totalSessions : 0.0;
  }

  /// Calculate retention rate
  static Future<double> _calculateRetentionRate() async {
    // Simplified retention calculation
    // In a real implementation, this would track user return visits
    return 0.75; // Placeholder value
  }

  /// Extract service name from URL
  static String _extractServiceName(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.split('.').first;
    } catch (e) {
      return 'unknown';
    }
  }
}

/// Enhanced Metric data class with serialization
class Metric {
  final String name;
  final double value;
  final DateTime timestamp;
  final Map<String, dynamic> tags;

  Metric({
    required this.name,
    required this.value,
    required this.timestamp,
    required this.tags,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'value': value,
      'timestamp': timestamp.toIso8601String(),
      'tags': tags,
    };
  }

  factory Metric.fromJson(Map<String, dynamic> json) {
    return Metric(
      name: json['name'] as String,
      value: (json['value'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      tags: Map<String, dynamic>.from(json['tags'] as Map),
    );
  }
}

/// Enhanced Performance event data class
class PerformanceEvent {
  final String operation;
  final Duration duration;
  final DateTime timestamp;
  final Map<String, dynamic> metadata;
  final String? userId;

  PerformanceEvent({
    required this.operation,
    required this.duration,
    required this.timestamp,
    required this.metadata,
    this.userId,
  });

  Map<String, dynamic> toJson() {
    return {
      'operation': operation,
      'duration_ms': duration.inMilliseconds,
      'timestamp': timestamp.toIso8601String(),
      'metadata': metadata,
      'user_id': userId,
    };
  }
}

/// Enhanced Error event data class
class ErrorEvent {
  final String operation;
  final String error;
  final String? stackTrace;
  final DateTime timestamp;
  final Map<String, dynamic> metadata;
  final String? userId;
  final String severity;

  ErrorEvent({
    required this.operation,
    required this.error,
    this.stackTrace,
    required this.timestamp,
    required this.metadata,
    this.userId,
    required this.severity,
  });

  Map<String, dynamic> toJson() {
    return {
      'operation': operation,
      'error': error,
      'stack_trace': stackTrace,
      'timestamp': timestamp.toIso8601String(),
      'metadata': metadata,
      'user_id': userId,
      'severity': severity,
    };
  }
}

/// Enhanced Business event data class
class BusinessEvent {
  final String eventType;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  final String? userId;
  final String? sessionId;

  BusinessEvent({
    required this.eventType,
    required this.data,
    required this.timestamp,
    this.userId,
    this.sessionId,
  });

  Map<String, dynamic> toJson() {
    return {
      'event_type': eventType,
      'data': data,
      'timestamp': timestamp.toIso8601String(),
      'user_id': userId,
      'session_id': sessionId,
    };
  }
}

/// Health check data class
class HealthCheck {
  final String name;
  final Future<bool> Function() check;
  DateTime lastChecked;
  bool isHealthy;

  HealthCheck({
    required this.name,
    required this.check,
    required this.lastChecked,
    required this.isHealthy,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'last_checked': lastChecked.toIso8601String(),
      'is_healthy': isHealthy,
    };
  }
}

/// Enhanced Performance summary data class
class PerformanceSummary {
  final int totalEvents;
  final int totalErrors;
  final double averageResponseTime;
  final double errorRate;
  final List<OperationStats> topOperations;
  final List<ErrorEvent> recentErrors;
  final double p95ResponseTime;
  final double p99ResponseTime;

  PerformanceSummary({
    required this.totalEvents,
    required this.totalErrors,
    required this.averageResponseTime,
    required this.errorRate,
    required this.topOperations,
    required this.recentErrors,
    required this.p95ResponseTime,
    required this.p99ResponseTime,
  });

  static PerformanceSummary empty() {
    return PerformanceSummary(
      totalEvents: 0,
      totalErrors: 0,
      averageResponseTime: 0.0,
      errorRate: 0.0,
      topOperations: [],
      recentErrors: [],
      p95ResponseTime: 0.0,
      p99ResponseTime: 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total_events': totalEvents,
      'total_errors': totalErrors,
      'average_response_time': averageResponseTime,
      'error_rate': errorRate,
      'p95_response_time': p95ResponseTime,
      'p99_response_time': p99ResponseTime,
      'top_operations': topOperations.map((o) => o.toJson()).toList(),
      'recent_errors': recentErrors.map((e) => e.toJson()).toList(),
    };
  }
}

/// Enhanced Business metrics data class
class BusinessMetrics {
  final int totalOrders;
  final double totalRevenue;
  final double averageOrderValue;
  final List<PaymentMethodStats> topPaymentMethods;
  final double conversionRate;
  final double customerRetentionRate;

  BusinessMetrics({
    required this.totalOrders,
    required this.totalRevenue,
    required this.averageOrderValue,
    required this.topPaymentMethods,
    required this.conversionRate,
    required this.customerRetentionRate,
  });

  static BusinessMetrics empty() {
    return BusinessMetrics(
      totalOrders: 0,
      totalRevenue: 0.0,
      averageOrderValue: 0.0,
      topPaymentMethods: [],
      conversionRate: 0.0,
      customerRetentionRate: 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total_orders': totalOrders,
      'total_revenue': totalRevenue,
      'average_order_value': averageOrderValue,
      'conversion_rate': conversionRate,
      'customer_retention_rate': customerRetentionRate,
      'top_payment_methods': topPaymentMethods.map((p) => p.toJson()).toList(),
    };
  }
}

/// Enhanced Operation statistics data class
class OperationStats {
  final String operation;
  final int count;
  final double averageDuration;

  OperationStats({
    required this.operation,
    required this.count,
    required this.averageDuration,
  });

  Map<String, dynamic> toJson() {
    return {
      'operation': operation,
      'count': count,
      'average_duration': averageDuration,
    };
  }
}

/// Enhanced Payment method statistics data class
class PaymentMethodStats {
  final String method;
  final int count;

  PaymentMethodStats({
    required this.method,
    required this.count,
  });

  Map<String, dynamic> toJson() {
    return {
      'method': method,
      'count': count,
    };
  }
}

/// Circuit breaker implementation
class CircuitBreaker {
  final int failureThreshold;
  final Duration timeout;
  int _failureCount = 0;
  DateTime? _lastFailureTime;
  CircuitState _state = CircuitState.closed;

  CircuitBreaker({
    required this.failureThreshold,
    required this.timeout,
  });

  bool get isOpen => _state == CircuitState.open;
  bool get isClosed => _state == CircuitState.closed;
  bool get isHalfOpen => _state == CircuitState.halfOpen;

  void recordResult(bool success) {
    _checkTimeout();
    if (success) {
      _onSuccess();
    } else {
      _onFailure();
    }
  }

  void _onSuccess() {
    _failureCount = 0;
    _state = CircuitState.closed;
  }

  void _onFailure() {
    _failureCount++;
    _lastFailureTime = DateTime.now();

    if (_failureCount >= failureThreshold) {
      _state = CircuitState.open;
    }
  }

  void _checkTimeout() {
    if (_state == CircuitState.open &&
        _lastFailureTime != null &&
        DateTime.now().difference(_lastFailureTime!) > timeout) {
      _state = CircuitState.halfOpen;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'state': _state.toString(),
      'failure_count': _failureCount,
      'last_failure_time': _lastFailureTime?.toIso8601String(),
      'is_open': isOpen,
    };
  }
}

enum CircuitState { closed, open, halfOpen }
