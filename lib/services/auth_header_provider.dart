import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Builds [Authorization] headers for REST calls without depending on [AuthService]
/// (avoids circular imports with [ApiService]).
class AuthHeaderProvider {
  AuthHeaderProvider._();

  static const String _tokenKey = 'auth_token';
  static final FlutterSecureStorage _storage = FlutterSecureStorage();

  /// Same semantics as [AuthService.getAuthorizationHeaders].
  static Future<Map<String, String>> buildHeaders() async {
    final token = await _storage.read(key: _tokenKey);
    if (token == null || token.isEmpty) {
      return {};
    }
    if (_looksLikeJwt(token)) {
      return {'Authorization': 'Bearer $token'};
    }
    return {'Authorization': 'Basic $token'};
  }

  static bool _looksLikeJwt(String token) {
    final parts = token.split('.');
    return parts.length == 3 &&
        parts[0].isNotEmpty &&
        parts[1].isNotEmpty &&
        parts[2].isNotEmpty;
  }
}
