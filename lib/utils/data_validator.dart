import 'package:ecommerce_int2/models/address.dart';
import 'package:ecommerce_int2/models/cart_item.dart';
import 'package:ecommerce_int2/models/product.dart';
import 'package:ecommerce_int2/models/order.dart';

/// Enterprise-grade data validation layer
class DataValidator {
  /// Validate email address
  static ValidationResult validateEmail(String email) {
    if (email.isEmpty) {
      return ValidationResult.error('Email is required');
    }

    final emailRegex =
        RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    if (!emailRegex.hasMatch(email)) {
      return ValidationResult.error('Invalid email format');
    }

    if (email.length > 254) {
      return ValidationResult.error('Email is too long');
    }

    return ValidationResult.success();
  }

  /// Validate phone number
  static ValidationResult validatePhone(String phone) {
    if (phone.isEmpty) {
      return ValidationResult.error('Phone number is required');
    }

    // Remove all non-digit characters
    final digitsOnly = phone.replaceAll(RegExp(r'[^\d]'), '');

    if (digitsOnly.length < 10) {
      return ValidationResult.error('Phone number must be at least 10 digits');
    }

    if (digitsOnly.length > 15) {
      return ValidationResult.error('Phone number is too long');
    }

    return ValidationResult.success();
  }

  /// Validate address
  static ValidationResult validateAddress(Address address) {
    final errors = <String>[];

    if (address.firstName.trim().isEmpty) {
      errors.add('First name is required');
    }

    if (address.lastName.trim().isEmpty) {
      errors.add('Last name is required');
    }

    if (address.addressLine1.trim().isEmpty) {
      errors.add('Address line 1 is required');
    }

    if (address.city.trim().isEmpty) {
      errors.add('City is required');
    }

    if (address.state.trim().isEmpty) {
      errors.add('State is required');
    }

    if (address.postalCode.trim().isEmpty) {
      errors.add('Postal code is required');
    }

    if (address.country.trim().isEmpty) {
      errors.add('Country is required');
    }

    final phoneResult = validatePhone(address.phone);
    if (!phoneResult.isValid) {
      errors.add(phoneResult.errorMessage!);
    }

    if (address.email.isNotEmpty) {
      final emailResult = validateEmail(address.email);
      if (!emailResult.isValid) {
        errors.add(emailResult.errorMessage!);
      }
    }

    if (errors.isNotEmpty) {
      return ValidationResult.error(errors.join(', '));
    }

    return ValidationResult.success();
  }

  /// Validate cart items
  static ValidationResult validateCartItems(List<CartItem> cartItems) {
    if (cartItems.isEmpty) {
      return ValidationResult.error('Cart is empty');
    }

    final errors = <String>[];

    for (int i = 0; i < cartItems.length; i++) {
      final item = cartItems[i];
      final itemErrors = <String>[];

      if (item.quantity <= 0) {
        itemErrors.add('Quantity must be greater than 0');
      }

      if (item.quantity > 100) {
        itemErrors.add('Quantity cannot exceed 100');
      }

      if (item.product.price <= 0) {
        itemErrors.add('Product price must be greater than 0');
      }

      if (item.product.name.trim().isEmpty) {
        itemErrors.add('Product name is required');
      }

      if (itemErrors.isNotEmpty) {
        errors.add('Item ${i + 1}: ${itemErrors.join(', ')}');
      }
    }

    if (errors.isNotEmpty) {
      return ValidationResult.error(errors.join('; '));
    }

    return ValidationResult.success();
  }

  /// Validate order data
  static ValidationResult validateOrderData({
    required String userId,
    required List<CartItem> cartItems,
    required Address shippingAddress,
    required Address billingAddress,
    required PaymentMethod paymentMethod,
    double shippingCost = 0.0,
    double tax = 0.0,
    double discount = 0.0,
  }) {
    final errors = <String>[];

    // Validate user ID
    if (userId.trim().isEmpty) {
      errors.add('User ID is required');
    }

    // Validate cart items
    final cartResult = validateCartItems(cartItems);
    if (!cartResult.isValid) {
      errors.add('Cart validation failed: ${cartResult.errorMessage}');
    }

    // Validate shipping address
    final shippingResult = validateAddress(shippingAddress);
    if (!shippingResult.isValid) {
      errors.add(
          'Shipping address validation failed: ${shippingResult.errorMessage}');
    }

    // Validate billing address
    final billingResult = validateAddress(billingAddress);
    if (!billingResult.isValid) {
      errors.add(
          'Billing address validation failed: ${billingResult.errorMessage}');
    }

    // Validate financial data
    if (shippingCost < 0) {
      errors.add('Shipping cost cannot be negative');
    }

    if (tax < 0) {
      errors.add('Tax cannot be negative');
    }

    if (discount < 0) {
      errors.add('Discount cannot be negative');
    }

    if (discount > 100) {
      errors.add('Discount cannot exceed 100%');
    }

    if (errors.isNotEmpty) {
      return ValidationResult.error(errors.join('; '));
    }

    return ValidationResult.success();
  }

  /// Sanitize string input
  static String sanitizeString(String input, {int maxLength = 255}) {
    final trimmed = input.trim();
    final cleaned = trimmed.replaceAll(
        RegExp(r'''[<>"']'''), ''); // Remove potentially dangerous characters
    final maxLen = trimmed.length > maxLength ? maxLength : trimmed.length;
    return cleaned.substring(0, maxLen);
  }

  /// Sanitize email
  static String sanitizeEmail(String email) {
    return email.trim().toLowerCase();
  }

  /// Sanitize phone number
  static String sanitizePhone(String phone) {
    return phone.replaceAll(RegExp(r'[^\d+\-\(\)\s]'), '');
  }

  /// Validate and sanitize address
  static Address sanitizeAddress(Address address) {
    return address.copyWith(
      firstName: sanitizeString(address.firstName, maxLength: 50),
      lastName: sanitizeString(address.lastName, maxLength: 50),
      company: sanitizeString(address.company, maxLength: 100),
      addressLine1: sanitizeString(address.addressLine1, maxLength: 200),
      addressLine2: sanitizeString(address.addressLine2, maxLength: 200),
      city: sanitizeString(address.city, maxLength: 100),
      state: sanitizeString(address.state, maxLength: 100),
      postalCode: sanitizeString(address.postalCode, maxLength: 20),
      country: sanitizeString(address.country, maxLength: 100),
      phone: sanitizePhone(address.phone),
      email: address.email.isNotEmpty ? sanitizeEmail(address.email) : '',
    );
  }
}

/// Validation result class
class ValidationResult {
  final bool isValid;
  final String? errorMessage;
  final List<String>? errors;

  ValidationResult._(this.isValid, this.errorMessage, this.errors);

  factory ValidationResult.success() {
    return ValidationResult._(true, null, null);
  }

  factory ValidationResult.error(String message, [List<String>? errors]) {
    return ValidationResult._(false, message, errors);
  }

  /// Get all error messages
  List<String> get allErrors {
    final allErrors = <String>[];
    if (errorMessage != null) allErrors.add(errorMessage!);
    if (errors != null) allErrors.addAll(errors!);
    return allErrors;
  }
}

/// Data sanitization utilities
class DataSanitizer {
  /// Sanitize order data before sending to WooCommerce
  static Map<String, dynamic> sanitizeOrderForWooCommerce({
    required String customerId,
    required List<CartItem> cartItems,
    required Address shippingAddress,
    required Address billingAddress,
    required PaymentMethod paymentMethod,
    double shippingCost = 0.0,
    double tax = 0.0,
    double discount = 0.0,
    String? notes,
    Map<String, dynamic>? metadata,
  }) {
    // Sanitize addresses
    final sanitizedShipping = DataValidator.sanitizeAddress(shippingAddress);
    final sanitizedBilling = DataValidator.sanitizeAddress(billingAddress);

    // Sanitize cart items
    final sanitizedCartItems = cartItems.map((item) {
      return CartItem(
        product: Product(
          sanitizeString(item.product.image, maxLength: 500),
          sanitizeString(item.product.name, maxLength: 200),
          sanitizeString(item.product.description, maxLength: 1000),
          item.product.price
              .clamp(0.0, 999999.99), // Clamp price to reasonable range
        ),
        quantity:
            item.quantity.clamp(1, 100), // Clamp quantity to reasonable range
      );
    }).toList();

    // Sanitize financial data
    final sanitizedShippingCost = shippingCost.clamp(0.0, 9999.99);
    final sanitizedTax = tax.clamp(0.0, 9999.99);
    final sanitizedDiscount = discount.clamp(0.0, 100.0);

    // Sanitize notes
    final sanitizedNotes = notes != null
        ? DataValidator.sanitizeString(notes, maxLength: 1000)
        : null;

    // Sanitize metadata
    final sanitizedMetadata = metadata?.map((key, value) {
      final sanitizedKey = DataValidator.sanitizeString(key, maxLength: 100);
      final sanitizedValue = value is String
          ? DataValidator.sanitizeString(value, maxLength: 500)
          : value;
      return MapEntry(sanitizedKey, sanitizedValue);
    });

    return {
      'customerId': DataValidator.sanitizeString(customerId, maxLength: 50),
      'cartItems': sanitizedCartItems,
      'shippingAddress': sanitizedShipping,
      'billingAddress': sanitizedBilling,
      'paymentMethod': paymentMethod,
      'shippingCost': sanitizedShippingCost,
      'tax': sanitizedTax,
      'discount': sanitizedDiscount,
      'notes': sanitizedNotes,
      'metadata': sanitizedMetadata,
    };
  }

  /// Sanitize string with length limit
  static String sanitizeString(String input, {int maxLength = 255}) {
    return DataValidator.sanitizeString(input, maxLength: maxLength);
  }
}
