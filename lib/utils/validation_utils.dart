import 'package:email_validator/email_validator.dart';

class ValidationUtils {
  // Email validation
  static String? validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Email is required';
    }

    if (!EmailValidator.validate(value)) {
      return 'Please enter a valid email address';
    }

    return null;
  }

  // Password validation
  /// Accepts any password value (no length or complexity requirements)
  /// Only validates that password is not empty
  ///
  /// This allows maximum flexibility for user password choices
  /// while ensuring a password is provided
  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }

    // Accept any password - no length or complexity requirements
    // This provides maximum flexibility for user password choices
    return null;
  }

  // Confirm password validation
  static String? validateConfirmPassword(String? value, String? password) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password';
    }

    if (value != password) {
      return 'Passwords do not match';
    }

    return null;
  }

  // Name validation - accepts any characters (international names, numbers, etc.)
  static String? validateName(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }

    // Only check minimum length, accept any characters for international names
    if (value.trim().length < 2) {
      return '$fieldName must be at least 2 characters long';
    }

    // No character restrictions - accept any name format (letters, numbers, special chars)
    // This supports international names and various naming conventions
    return null;
  }

  // Phone validation
  static String? validatePhone(String? value) {
    if (value == null || value.isEmpty) {
      return null; // Phone is optional
    }

    // Remove all non-digit characters for validation
    final digitsOnly = value.replaceAll(RegExp(r'[^\d]'), '');

    if (digitsOnly.length < 10) {
      return 'Please enter a valid phone number';
    }

    return null;
  }

  // Email or Username validation
  static String? validateEmailOrUsername(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter email or username';
    }
    final v = value.trim();
    final emailRegex = RegExp(r'^.+@.+\..+$');
    if (emailRegex.hasMatch(v)) {
      return null; // valid email
    }
    // Username: 3-32 chars, letters, numbers, underscores, dots, hyphens
    final usernameRegex = RegExp(r'^[A-Za-z0-9._-]{3,32}$');
    if (!usernameRegex.hasMatch(v)) {
      return 'Enter a valid username or email';
    }
    return null;
  }

  // Username validation
  static String? validateUsername(String? value) {
    if (value == null || value.isEmpty) {
      return 'Username is required';
    }

    if (value.length < 3) {
      return 'Username must be at least 3 characters long';
    }

    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value)) {
      return 'Username can only contain letters, numbers, and underscores';
    }

    return null;
  }

  // OTP validation
  static String? validateOTP(String? value) {
    if (value == null || value.isEmpty) {
      return 'OTP is required';
    }

    if (value.length != 4) {
      return 'OTP must be 4 digits';
    }

    if (!RegExp(r'^\d{4}$').hasMatch(value)) {
      return 'OTP must contain only numbers';
    }

    return null;
  }

  // Generic required field validation
  static String? validateRequired(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  // URL validation
  static String? validateUrl(String? value) {
    if (value == null || value.isEmpty) {
      return null; // URL is optional
    }

    final urlPattern = RegExp(
        r'^https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)$');

    if (!urlPattern.hasMatch(value)) {
      return 'Please enter a valid URL';
    }

    return null;
  }

  // Credit card number validation (basic)
  static String? validateCreditCard(String? value) {
    if (value == null || value.isEmpty) {
      return 'Card number is required';
    }

    final digitsOnly = value.replaceAll(RegExp(r'[^\d]'), '');

    if (digitsOnly.length < 13 || digitsOnly.length > 19) {
      return 'Please enter a valid card number';
    }

    return null;
  }

  // CVV validation
  static String? validateCVV(String? value) {
    if (value == null || value.isEmpty) {
      return 'CVV is required';
    }

    if (!RegExp(r'^\d{3,4}$').hasMatch(value)) {
      return 'Please enter a valid CVV';
    }

    return null;
  }

  // Expiry date validation (MM/YY format)
  static String? validateExpiryDate(String? value) {
    if (value == null || value.isEmpty) {
      return 'Expiry date is required';
    }

    final expiryPattern = RegExp(r'^(0[1-9]|1[0-2])\/\d{2}$');
    if (!expiryPattern.hasMatch(value)) {
      return 'Please enter expiry date in MM/YY format';
    }

    final parts = value.split('/');
    final month = int.parse(parts[0]);
    final year = int.parse('20${parts[1]}');
    final now = DateTime.now();
    final expiryDate = DateTime(year, month + 1, 0); // Last day of the month

    if (expiryDate.isBefore(now)) {
      return 'Card has expired';
    }

    return null;
  }
}
