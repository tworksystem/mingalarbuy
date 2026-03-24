class RegisterRequest {
  final String email;
  final String password;
  final String firstName;
  final String lastName;
  final String? phone;
  final String? username;

  RegisterRequest({
    required this.email,
    required this.password,
    required this.firstName,
    required this.lastName,
    this.phone,
    this.username,
  });

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'password': password,
      'first_name': firstName,
      'last_name': lastName,
      'phone': phone,
      'username': username ??
          email.split('@')[0], // Use email prefix as username if not provided
    };
  }

  // Validation methods
  bool get isValidEmail {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  /// Password validation - accepts any non-empty password
  /// No length or complexity requirements for maximum flexibility
  bool get isValidPassword {
    return password.isNotEmpty;
  }

  /// Name validation - accepts full name in firstName, lastName can be empty
  /// This supports single field name entry where full name is stored as-is
  bool get isValidName {
    return firstName.trim().isNotEmpty; // Only firstName (full name) is required
  }

  bool get isValidPhone {
    if (phone == null || phone!.isEmpty) return true; // Phone is optional
    return RegExp(r'^\+?[\d\s\-\(\)]{10,}$').hasMatch(phone!);
  }

  bool get isValid {
    return isValidEmail && isValidPassword && isValidName && isValidPhone;
  }

  List<String> get validationErrors {
    List<String> errors = [];

    if (!isValidEmail) {
      errors.add('Please enter a valid email address');
    }

    if (!isValidPassword) {
      errors.add('Password is required');
    }

    if (!isValidName) {
      errors.add('Full name is required');
    }

    if (!isValidPhone) {
      errors.add('Please enter a valid phone number');
    }

    return errors;
  }
}
