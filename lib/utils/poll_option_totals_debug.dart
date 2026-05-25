import 'package:flutter/foundation.dart';

/// Loud console traces for global poll option totals (timer strip).
/// Uses [print] so logs show in all Flutter run targets.
class PollOptionTotalsDebug {
  PollOptionTotalsDebug._();

  static const String tag = '📊 poll_option_totals';

  static void ok(String message) => _emit('✅', message);

  static void pending(String message) => _emit('⏳', message);

  static void fail(String message, {Object? error, StackTrace? stackTrace}) {
    final extra = error != null ? ' | cause: $error' : '';
    _emit('❌', '$message$extra');
    if (stackTrace != null && kDebugMode) {
      debugPrint('$tag 🧵 $stackTrace');
    }
  }

  static void info(String message) => _emit('ℹ️', message);

  static void warn(String message) => _emit('⚠️', message);

  static void _emit(String emoji, String message) {
    final line = '$emoji $tag $message';
    print(line);
    debugPrint(line);
  }
}
