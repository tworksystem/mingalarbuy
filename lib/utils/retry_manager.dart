import 'dart:async';
import 'dart:math';
import 'logger.dart';

/// Enterprise-grade retry manager with exponential backoff
class RetryManager {
  static const int _maxRetries = 3;
  static const Duration _baseDelay = Duration(seconds: 1);
  static const Duration _maxDelay = Duration(seconds: 30);
  static const double _backoffMultiplier = 2.0;
  static const double _jitterFactor = 0.1;

  /// Execute function with retry logic
  static Future<T> executeWithRetry<T>(
    Future<T> Function() operation, {
    int maxRetries = _maxRetries,
    Duration baseDelay = _baseDelay,
    Duration? maxDelay,
    double backoffMultiplier = _backoffMultiplier,
    double jitterFactor = _jitterFactor,
    bool Function(dynamic error)? shouldRetry,
    String? context,
  }) async {
    maxDelay ??= _maxDelay;
    int attempt = 0;
    Exception? lastException;

    while (attempt <= maxRetries) {
      try {
        Logger.info(
          'Executing operation${context != null ? ' ($context)' : ''} - Attempt ${attempt + 1}/${maxRetries + 1}',
          tag: 'RetryManager',
        );

        final result = await operation();

        if (attempt > 0) {
          Logger.info(
            'Operation succeeded after ${attempt + 1} attempts${context != null ? ' ($context)' : ''}',
            tag: 'RetryManager',
          );
        }

        return result;
      } catch (e) {
        lastException = e is Exception ? e : Exception(e.toString());
        attempt++;

        // Check if we should retry this error
        if (shouldRetry != null && !shouldRetry(e)) {
          Logger.warning(
            'Error is not retryable: $e',
            tag: 'RetryManager',
          );
          rethrow;
        }

        if (attempt > maxRetries) {
          Logger.error(
            'Operation failed after $maxRetries retries${context != null ? ' ($context)' : ''}: $e',
            tag: 'RetryManager',
            error: e,
          );
          rethrow;
        }

        // Calculate delay with exponential backoff and jitter
        final delay = _calculateDelay(
          attempt,
          baseDelay,
          maxDelay,
          backoffMultiplier,
          jitterFactor,
        );

        Logger.warning(
          'Operation failed (attempt $attempt/$maxRetries), retrying in ${delay.inMilliseconds}ms: $e',
          tag: 'RetryManager',
        );

        await Future.delayed(delay);
      }
    }

    throw lastException!;
  }

  /// Calculate delay with exponential backoff and jitter
  static Duration _calculateDelay(
    int attempt,
    Duration baseDelay,
    Duration maxDelay,
    double backoffMultiplier,
    double jitterFactor,
  ) {
    // Exponential backoff
    final exponentialDelay = baseDelay * pow(backoffMultiplier, attempt - 1);

    // Cap at max delay
    final cappedDelay =
        exponentialDelay > maxDelay ? maxDelay : exponentialDelay;

    // Add jitter to prevent thundering herd
    final jitter = cappedDelay * jitterFactor * (Random().nextDouble() * 2 - 1);
    final finalDelay = cappedDelay + jitter;

    return finalDelay;
  }

  /// Retry with circuit breaker pattern
  static Future<T> executeWithCircuitBreaker<T>(
    Future<T> Function() operation, {
    int failureThreshold = 5,
    Duration timeout = const Duration(seconds: 30),
    Duration resetTimeout = const Duration(minutes: 1),
    String? context,
  }) async {
    return await _CircuitBreaker.execute(
      operation,
      failureThreshold: failureThreshold,
      timeout: timeout,
      resetTimeout: resetTimeout,
      context: context,
    );
  }
}

/// Circuit breaker implementation
class _CircuitBreaker {
  static final Map<String, _CircuitBreakerState> _states = {};

  static Future<T> execute<T>(
    Future<T> Function() operation, {
    required int failureThreshold,
    required Duration timeout,
    required Duration resetTimeout,
    String? context,
  }) async {
    final key = context ?? 'default';
    final state = _states[key] ??= _CircuitBreakerState(
      failureThreshold: failureThreshold,
      timeout: timeout,
      resetTimeout: resetTimeout,
    );

    return await state.execute(operation);
  }
}

class _CircuitBreakerState {
  final int failureThreshold;
  final Duration timeout;
  final Duration resetTimeout;

  int _failureCount = 0;
  DateTime? _lastFailureTime;
  CircuitBreakerState _state = CircuitBreakerState.closed;

  _CircuitBreakerState({
    required this.failureThreshold,
    required this.timeout,
    required this.resetTimeout,
  });

  Future<T> execute<T>(Future<T> Function() operation) async {
    if (_state == CircuitBreakerState.open) {
      if (_lastFailureTime != null &&
          DateTime.now().difference(_lastFailureTime!) > resetTimeout) {
        _state = CircuitBreakerState.halfOpen;
        Logger.info('Circuit breaker transitioning to half-open',
            tag: 'CircuitBreaker');
      } else {
        throw Exception('Circuit breaker is open');
      }
    }

    try {
      final result = await operation().timeout(timeout);

      if (_state == CircuitBreakerState.halfOpen) {
        _state = CircuitBreakerState.closed;
        _failureCount = 0;
        Logger.info('Circuit breaker closed after successful operation',
            tag: 'CircuitBreaker');
      }

      return result;
    } catch (e) {
      _failureCount++;
      _lastFailureTime = DateTime.now();

      if (_failureCount >= failureThreshold) {
        _state = CircuitBreakerState.open;
        Logger.error(
          'Circuit breaker opened after $failureThreshold failures',
          tag: 'CircuitBreaker',
          error: e,
        );
      }

      rethrow;
    }
  }
}

enum CircuitBreakerState {
  closed,
  open,
  halfOpen,
}

/// Retry policies for different scenarios
class RetryPolicies {
  /// Network operations retry policy
  static Future<T> networkOperation<T>(Future<T> Function() operation,
      {String? context}) {
    return RetryManager.executeWithRetry(
      operation,
      maxRetries: 3,
      baseDelay: const Duration(seconds: 1),
      shouldRetry: (error) {
        // Retry on network errors, timeouts, and 5xx server errors
        return error.toString().contains('timeout') ||
            error.toString().contains('network') ||
            error.toString().contains('500') ||
            error.toString().contains('502') ||
            error.toString().contains('503') ||
            error.toString().contains('504');
      },
      context: context,
    );
  }

  /// Database operations retry policy
  static Future<T> databaseOperation<T>(Future<T> Function() operation,
      {String? context}) {
    return RetryManager.executeWithRetry(
      operation,
      maxRetries: 2,
      baseDelay: const Duration(milliseconds: 500),
      shouldRetry: (error) {
        // Retry on database connection errors
        return error.toString().contains('connection') ||
            error.toString().contains('timeout') ||
            error.toString().contains('deadlock');
      },
      context: context,
    );
  }

  /// API operations retry policy
  static Future<T> apiOperation<T>(Future<T> Function() operation,
      {String? context}) {
    return RetryManager.executeWithRetry(
      operation,
      maxRetries: 3,
      baseDelay: const Duration(seconds: 2),
      shouldRetry: (error) {
        // Retry on API errors
        return error.toString().contains('timeout') ||
            error.toString().contains('network') ||
            error.toString().contains('500') ||
            error.toString().contains('502') ||
            error.toString().contains('503') ||
            error.toString().contains('504') ||
            error.toString().contains('429'); // Rate limiting
      },
      context: context,
    );
  }
}
