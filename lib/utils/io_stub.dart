/// Minimal dart:io stubs for web compilation (app download paths only).
class Platform {
  static bool get isAndroid => false;
  static bool get isIOS => false;
  static bool get isWindows => false;
  static bool get isMacOS => false;
  static bool get isLinux => false;
}

class SocketException implements Exception {
  SocketException(this.message, {this.osError});
  final String message;
  final Object? osError;
  @override
  String toString() => 'SocketException: $message';
}

class HttpException implements Exception {
  HttpException(this.message);
  final String message;
  @override
  String toString() => 'HttpException: $message';
}

class InternetAddress {
  InternetAddress(this.address);
  final String address;
  List<int> get rawAddress => const <int>[];

  static Future<List<InternetAddress>> lookup(
    String host, {
    int type = 0,
  }) async =>
      <InternetAddress>[];
}

class File {
  File(this.path);
  final String path;

  Future<bool> exists() async => false;
  Future<int> length() async => 0;
  Future<String> readAsString() async => '';
  Future<void> delete({bool recursive = false}) async {}
}

class Directory {
  Directory(this.path);
  final String path;

  Future<bool> exists() async => false;
  Future<Directory> create({bool recursive = false}) async => this;
}
