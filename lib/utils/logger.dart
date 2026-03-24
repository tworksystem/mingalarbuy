import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

typedef LogSink = void Function(LogEvent event);

/// Immutable representation of a log statement.
class LogEvent {
  const LogEvent({
    required this.level,
    required this.levelName,
    required this.tag,
    required this.message,
    required this.timestamp,
    this.error,
    this.stackTrace,
    this.metadata = const {},
  });

  final int level;
  final String levelName;
  final String tag;
  final String message;
  final DateTime timestamp;
  final dynamic error;
  final StackTrace? stackTrace;
  final Map<String, dynamic> metadata;
}

/// Professional logging system for the e-commerce app
class Logger {
  static const String _tag = 'PlanetMM';

  /// Log levels
  static const int VERBOSE = 0;
  static const int DEBUG = 1;
  static const int INFO = 2;
  static const int WARNING = 3;
  static const int ERROR = 4;
  static const int FATAL = 5;

  static int _currentLevel = kDebugMode ? DEBUG : INFO;

  /// Set log level
  static void setLevel(int level) {
    _currentLevel = level;
  }

  /// Verbose logging
  static final List<LogSink> _sinks = <LogSink>[];

  /// Register a sink that will receive every [LogEvent].
  static void addSink(LogSink sink) {
    if (!_sinks.contains(sink)) {
      _sinks.add(sink);
    }
  }

  /// Remove a previously registered sink.
  static void removeSink(LogSink sink) {
    _sinks.remove(sink);
  }

  /// Clears all registered sinks. Useful in tests.
  static void clearSinks() {
    _sinks.clear();
  }

  /// Verbose logging
  static void verbose(
    String message, {
    String? tag,
    dynamic error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
  }) {
    _log(
      VERBOSE,
      message,
      tag: tag,
      error: error,
      stackTrace: stackTrace,
      metadata: metadata,
    );
  }

  /// Debug logging
  static void debug(
    String message, {
    String? tag,
    dynamic error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
  }) {
    _log(
      DEBUG,
      message,
      tag: tag,
      error: error,
      stackTrace: stackTrace,
      metadata: metadata,
    );
  }

  /// Info logging
  static void info(
    String message, {
    String? tag,
    dynamic error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
  }) {
    _log(
      INFO,
      message,
      tag: tag,
      error: error,
      stackTrace: stackTrace,
      metadata: metadata,
    );
  }

  /// Warning logging
  static void warning(
    String message, {
    String? tag,
    dynamic error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
  }) {
    _log(
      WARNING,
      message,
      tag: tag,
      error: error,
      stackTrace: stackTrace,
      metadata: metadata,
    );
  }

  /// Error logging
  static void error(
    String message, {
    String? tag,
    dynamic error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
  }) {
    _log(
      ERROR,
      message,
      tag: tag,
      error: error,
      stackTrace: stackTrace,
      metadata: metadata,
    );
  }

  /// Fatal logging
  static void fatal(
    String message, {
    String? tag,
    dynamic error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
  }) {
    _log(
      FATAL,
      message,
      tag: tag,
      error: error,
      stackTrace: stackTrace,
      metadata: metadata,
    );
  }

  /// Internal logging method
  static void _log(
    int level,
    String message, {
    String? tag,
    dynamic error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
  }) {
    if (level < _currentLevel) return;

    final logTag = tag ?? _tag;
    final now = DateTime.now();
    final timestamp = now.toIso8601String();
    final levelName = _getLevelName(level);

    final logMessage = '[$timestamp] [$levelName] [$logTag] $message';

    if (kDebugMode) {
      print(logMessage);
      if (error != null) {
        print('Error: $error');
      }
      if (stackTrace != null) {
        print('Stack trace: $stackTrace');
      }
    }

    // Log to developer console
    developer.log(
      message,
      name: logTag,
      level: level,
      error: error,
      stackTrace: stackTrace,
    );

    if (_sinks.isNotEmpty) {
      final event = LogEvent(
        level: level,
        levelName: levelName,
        tag: logTag,
        message: message,
        timestamp: now,
        error: error,
        stackTrace: stackTrace,
        metadata: metadata ?? const {},
      );

      for (final sink in List<LogSink>.from(_sinks)) {
        try {
          sink(event);
        } catch (sinkError, sinkStack) {
          developer.log(
            'Log sink failure',
            name: 'Logger',
            level: ERROR,
            error: sinkError,
            stackTrace: sinkStack,
          );
        }
      }
    }
  }

  /// Get level name
  static String _getLevelName(int level) {
    switch (level) {
      case VERBOSE:
        return 'VERBOSE';
      case DEBUG:
        return 'DEBUG';
      case INFO:
        return 'INFO';
      case WARNING:
        return 'WARNING';
      case ERROR:
        return 'ERROR';
      case FATAL:
        return 'FATAL';
      default:
        return 'UNKNOWN';
    }
  }

  /// Log API requests
  static void logApiRequest(String method, String url,
      {Map<String, String>? headers, String? body}) {
    if (kDebugMode) {
      debug('API Request: $method $url', tag: 'API');
      if (headers != null) {
        debug('Headers: $headers', tag: 'API');
      }
      if (body != null) {
        debug('Body: $body', tag: 'API');
      }
    }
  }

  /// Log API responses
  static void logApiResponse(int statusCode, String body,
      {Duration? duration}) {
    if (kDebugMode) {
      final level = statusCode >= 200 && statusCode < 300 ? INFO : ERROR;
      final message =
          'API Response: $statusCode${duration != null ? ' (${duration.inMilliseconds}ms)' : ''}';
      _log(level, message, tag: 'API');
      if (body.isNotEmpty) {
        debug('Response body: $body', tag: 'API');
      }
    }
  }

  /// Log user actions
  static void logUserAction(String action, {Map<String, dynamic>? parameters}) {
    if (kDebugMode) {
      final message = 'User Action: $action';
      final params = parameters != null ? ' Parameters: $parameters' : '';
      info(message + params, tag: 'USER');
    }
  }

  /// Log performance metrics
  static void logPerformance(String operation, Duration duration,
      {Map<String, dynamic>? metrics}) {
    if (kDebugMode) {
      final message =
          'Performance: $operation took ${duration.inMilliseconds}ms';
      final metricsStr = metrics != null ? ' Metrics: $metrics' : '';
      info(message + metricsStr, tag: 'PERFORMANCE');
    }
  }

  /// Log navigation events
  static void logNavigation(String from, String to,
      {Map<String, dynamic>? parameters}) {
    if (kDebugMode) {
      final message = 'Navigation: $from -> $to';
      final params = parameters != null ? ' Parameters: $parameters' : '';
      debug(message + params, tag: 'NAVIGATION');
    }
  }

  /// Log errors with context
  static void logError(String context, dynamic error,
      {StackTrace? stackTrace, Map<String, dynamic>? contextData}) {
    final message = 'Error in $context: $error';
    final contextStr = contextData != null ? ' Context: $contextData' : '';
    error(message + contextStr,
        tag: 'ERROR', error: error, stackTrace: stackTrace);
  }

  /// Log memory usage
  static void logMemoryUsage(String context, {Map<String, dynamic>? metrics}) {
    if (kDebugMode) {
      final message = 'Memory usage in $context';
      final metricsStr = metrics != null ? ' Metrics: $metrics' : '';
      debug(message + metricsStr, tag: 'MEMORY');
    }
  }
}

/// Specialized loggers for different components
class ApiLogger {
  static void logRequest(String method, String url,
      {Map<String, String>? headers, String? body}) {
    Logger.logApiRequest(method, url, headers: headers, body: body);
  }

  static void logResponse(int statusCode, String body, {Duration? duration}) {
    Logger.logApiResponse(statusCode, body, duration: duration);
  }

  static void logError(String operation, dynamic error,
      {StackTrace? stackTrace}) {
    Logger.logError('API $operation', error, stackTrace: stackTrace);
  }
}

class UserLogger {
  static void logAction(String action, {Map<String, dynamic>? parameters}) {
    Logger.logUserAction(action, parameters: parameters);
  }

  static void logNavigation(String from, String to,
      {Map<String, dynamic>? parameters}) {
    Logger.logNavigation(from, to, parameters: parameters);
  }
}

class PerformanceLogger {
  static void logOperation(String operation, Duration duration,
      {Map<String, dynamic>? metrics}) {
    Logger.logPerformance(operation, duration, metrics: metrics);
  }

  static void logMemoryUsage(String context, {Map<String, dynamic>? metrics}) {
    Logger.logMemoryUsage(context, metrics: metrics);
  }
}
