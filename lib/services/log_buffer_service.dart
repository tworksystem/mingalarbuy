import 'package:ecommerce_int2/utils/logger.dart';

/// Captures the most recent log events emitted through the shared [Logger].
///
/// The buffer is useful for diagnostics (surface in crash reports, support
/// bundles, or developer tools) without having to trawl through the raw device
/// logcat output. The implementation keeps the last [_maxEvents] statements in
/// memory and can be queried synchronously.
class LogBufferService {
  LogBufferService._();

  static const int _maxEvents = 200;
  static final List<LogEvent> _events = <LogEvent>[];
  static bool _initialized = false;

  /// Attaches the service to the global [Logger] sink. Safe to call multiple
  /// times; initialization is idempotent.
  static void initialize() {
    if (_initialized) return;
    _initialized = true;
    Logger.addSink(_handleLogEvent);
  }

  /// Detaches the sink and clears the buffer. Primarily intended for test
  /// environments.
  static void dispose() {
    if (!_initialized) return;
    _initialized = false;
    Logger.removeSink(_handleLogEvent);
    _events.clear();
  }

  /// Returns the most recent captured log events (oldest first).
  static List<LogEvent> get events => List<LogEvent>.unmodifiable(_events);

  static void _handleLogEvent(LogEvent event) {
    _events.add(event);
    if (_events.length > _maxEvents) {
      _events.removeRange(0, _events.length - _maxEvents);
    }
  }
}

