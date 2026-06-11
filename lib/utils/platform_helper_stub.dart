/// Web stub — no dart:io.
class PlatformHelper {
  PlatformHelper._();

  static bool get isAndroid => false;
  static bool get isIOS => false;
  static bool get isWindows => false;
  static bool get isMacOS => false;
  static bool get isLinux => false;
  static bool get isWeb => true;

  /// FCM / analytics platform label.
  static String get pushPlatformLabel => 'web';
}
