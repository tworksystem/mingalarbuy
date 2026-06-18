class RegisterRequest {
  final String username;
  final String password;
  final String? email;
  final String firstName;
  final String lastName;
  final String? phone;

  /// Placeholder domain for WooCommerce accounts created without a real email.
  static const String autoEmailDomain = 'noreply.planetmm.com';

  RegisterRequest({
    required this.username,
    required this.password,
    this.email,
    this.firstName = '',
    this.lastName = '',
    this.phone,
  });

  /// WooCommerce requires an email; generate one from username when omitted.
  String get resolvedEmail {
    final provided = email?.trim();
    if (provided != null && provided.isNotEmpty) {
      return provided;
    }
    final safeUsername = username
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._-]'), '');
    return '$safeUsername@$autoEmailDomain';
  }

  Map<String, dynamic> toJson() {
    return {
      'email': resolvedEmail,
      'password': password,
      'first_name': firstName,
      'last_name': lastName,
      'phone': phone,
      'username': username.trim(),
    };
  }

  bool get isValidUsername {
    final value = username.trim();
    return value.length >= 3 &&
        RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(value);
  }

  /// Password validation - accepts any non-empty password
  bool get isValidPassword {
    return password.isNotEmpty;
  }

  bool get isValidPhone {
    if (phone == null || phone!.isEmpty) return true;
    return RegExp(r'^\+?[\d\s\-\(\)]{10,}$').hasMatch(phone!);
  }

  bool get isValid {
    return isValidUsername && isValidPassword && isValidPhone;
  }

  List<String> get validationErrors {
    final errors = <String>[];

    if (!isValidUsername) {
      errors.add('Username must be at least 3 characters');
    }

    if (!isValidPassword) {
      errors.add('Password is required');
    }

    if (!isValidPhone) {
      errors.add('Please enter a valid phone number');
    }

    return errors;
  }
}
