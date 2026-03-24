import 'dart:convert';
import 'dart:math';

import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Lightweight helper for encrypting values stored in SharedPreferences.
///
/// Secrets are stored in [FlutterSecureStorage] and used to encrypt values
/// written to the otherwise plaintext preferences file.
class SecurePrefs {
  SecurePrefs._internal();

  static final SecurePrefs instance = SecurePrefs._internal();

  static const _encryptionKeyStorageKey = 'secure_prefs_encryption_key';
  static const _storage = FlutterSecureStorage();

  encrypt_lib.Key? _key;
  Future<void>? _initializing;

  Future<void> _ensureInitialized() async {
    if (_key != null) {
      return;
    }

    if (_initializing != null) {
      return _initializing!;
    }

    _initializing = _loadOrCreateKey();
    await _initializing;
    _initializing = null;
  }

  Future<void> _loadOrCreateKey() async {
    final existing = await _storage.read(key: _encryptionKeyStorageKey);
    if (existing != null) {
      _key = encrypt_lib.Key(base64Decode(existing));
      return;
    }

    final secureRandom = Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(32, (_) => secureRandom.nextInt(256)),
    );
    final encoded = base64Encode(bytes);
    await _storage.write(key: _encryptionKeyStorageKey, value: encoded);
    _key = encrypt_lib.Key(bytes);
  }

  /// Encrypts [plainText] and returns an encoded payload safe for storage.
  Future<String> encrypt(String plainText) async {
    await _ensureInitialized();
    final iv = encrypt_lib.IV.fromSecureRandom(16);
    final encrypter = encrypt_lib.Encrypter(
      encrypt_lib.AES(_key!, mode: encrypt_lib.AESMode.cbc),
    );
    final encrypted = encrypter.encrypt(plainText, iv: iv);
    return '${iv.base64}:${encrypted.base64}';
  }

  /// Attempts to decrypt [payload]. Throws if payload is invalid.
  Future<String> decrypt(String payload) async {
    await _ensureInitialized();
    final parts = payload.split(':');
    if (parts.length != 2) {
      throw const FormatException('Invalid encrypted payload');
    }
    final iv = encrypt_lib.IV.fromBase64(parts[0]);
    final cipherText = encrypt_lib.Encrypted.fromBase64(parts[1]);
    final encrypter = encrypt_lib.Encrypter(
      encrypt_lib.AES(_key!, mode: encrypt_lib.AESMode.cbc),
    );
    return encrypter.decrypt(cipherText, iv: iv);
  }

  /// Attempts to decrypt [payload], returning `null` when it is not encrypted.
  Future<String?> maybeDecrypt(String payload) async {
    try {
      return await decrypt(payload);
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            'SecurePrefs: failed to decrypt payload, assuming plaintext.');
      }
      return null;
    }
  }
}
