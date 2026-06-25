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

  // Password validation — optional length; any characters accepted (1+ chars)
  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'လျို့ဝှက်နံပါတ် ထည့်ရန် လိုအပ်ပါတယ်';
    }

    return null;
  }

  // Confirm password validation
  static String? validateConfirmPassword(String? value, String? password) {
    if (value == null || value.isEmpty) {
      return 'လျို့ဝှက်နံပါတ် အတည်ပြုချက် ထည့်ရန် လိုအပ်ပါတယ်';
    }

    if (value != password) {
      return 'လျို့ဝှက်နံပါတ် မတူညီပါ';
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

  // Phone validation — optional; any digit length (1–15) accepted
  static String? validatePhone(String? value) {
    if (value == null || value.isEmpty) {
      return null; // Phone is optional
    }

    final digitsOnly = value.replaceAll(RegExp(r'[^\d]'), '');

    if (digitsOnly.isEmpty) {
      return 'Please enter a valid phone number';
    }

    if (digitsOnly.length > 15) {
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
      return 'အသုံးပြုသူအမည် ထည့်ရန် လိုအပ်ပါတယ်';
    }

    if (value.length < 3) {
      return 'အသုံးပြုသူအမည် အနည်းဆုံး အက္ခရာ ၃ လုံးဖြစ်ရမယ်';
    }

    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value)) {
      return 'အက္ခရာ၊ နံပါတ်နှင့် _ သာ သုံးနိုင်ပါတယ်';
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
