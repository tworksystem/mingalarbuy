import 'package:flutter/foundation.dart';

/// Loud console traces for Home **My PNP** balance (poll result / win / deduct).
class MyPnpBalanceDebug {
  MyPnpBalanceDebug._();

  static const String tag = '💰 My PNP';

  static void ok(String message) => _emit('✅', message);

  static void waiting(String message) => _emit('⏳', message);

  static void blocked(String message) => _emit('🛑', message);

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
