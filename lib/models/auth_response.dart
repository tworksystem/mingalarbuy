import 'auth_user.dart';

class AuthResponse {
  final bool success;
  final String message;
  final AuthUser? user;
  final String? token;
  final Map<String, dynamic>? errors;

  AuthResponse({
    required this.success,
    required this.message,
    this.user,
    this.token,
    this.errors,
  });

  factory AuthResponse.success({
    required String message,
    AuthUser? user,
    String? token,
  }) {
    return AuthResponse(
      success: true,
      message: message,
      user: user,
      token: token,
    );
  }

  factory AuthResponse.error({
    required String message,
    Map<String, dynamic>? errors,
  }) {
    return AuthResponse(
      success: false,
      message: message,
      errors: errors,
    );
  }

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      success: json['success'] ?? false,
      message: json['message'] ?? '',
      user: json['user'] != null ? AuthUser.fromJson(json['user']) : null,
      token: json['token'],
      errors: json['errors'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'message': message,
      'user': user?.toJson(),
      'token': token,
      'errors': errors,
    };
  }
}
