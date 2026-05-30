import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Shared secure storage for auth tokens and encrypted prefs keys.
///
/// [encryptedSharedPreferences] improves reliability on Android release builds.
class SecureStorageConfig {
  SecureStorageConfig._();

  static const FlutterSecureStorage instance = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );
}
