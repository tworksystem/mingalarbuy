class RegisterRequest {
  final String username;
  final String password;
  final String? email;
  final String firstName;
  final String lastName;
  final String? phone;

  /// Placeholder domain for WooCommerce accounts created without a real email.
  static const String autoEmailDomain = 'noreply.planetmm.com';

  /// Default last name for accounts registered without a display name.
  static const String defaultLastName = 'Level 1';

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

  /// WooCommerce requires a first name; default to username when omitted.
  String get resolvedFirstName {
    final provided = firstName.trim();
    if (provided.isNotEmpty) return provided;
    return username.trim();
  }

  /// Default tier label when last name is not provided at registration.
  String get resolvedLastName {
    final provided = lastName.trim();
    if (provided.isNotEmpty) return provided;
    return defaultLastName;
  }

  /// Resolve display first name for an existing user record.
  static String resolveFirstNameForUser({
    required String username,
    String firstName = '',
  }) {
    final provided = firstName.trim();
    if (provided.isNotEmpty) return provided;
    final trimmedUsername = username.trim();
    if (trimmedUsername.isNotEmpty) return trimmedUsername;
    return 'Customer';
  }

  /// Resolve display last name for an existing user record.
  static String resolveLastNameForUser({String lastName = ''}) {
    final provided = lastName.trim();
    if (provided.isNotEmpty) return provided;
    return defaultLastName;
  }

  Map<String, dynamic> toJson() {
    return {
      'email': resolvedEmail,
      'password': password,
      'first_name': resolvedFirstName,
      'last_name': resolvedLastName,
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
    final digitsOnly = phone!.replaceAll(RegExp(r'[^\d]'), '');
    return digitsOnly.isNotEmpty && digitsOnly.length <= 15;
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
      errors.add('လျို့ဝှက်နံပါတ် ထည့်ရန် လိုအပ်ပါတယ်');
    }

    if (!isValidPhone) {
      errors.add('Please enter a valid phone number');
    }

    return errors;
  }
}
