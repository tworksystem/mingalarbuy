import '../models/order.dart';

class PaymentService {
  // TODO: Add payment gateway URLs when implementing real payment gateway
  // static const String _baseUrl = 'https://api.payment-gateway.com/v1';
  // static const String _apiKey = 'your_payment_gateway_api_key';
  // static const String _secretKey = 'your_payment_gateway_secret_key';

  /// Process payment for an order
  static Future<PaymentResult> processPayment({
    required String orderId,
    required double amount,
    required PaymentMethod paymentMethod,
    required Map<String, dynamic> paymentData,
    String? currency = 'USD',
  }) async {
    try {
      // Simulate API call delay
      await Future.delayed(Duration(seconds: 2));

      // Mock payment processing based on payment method
      switch (paymentMethod) {
        case PaymentMethod.creditCard:
          return await _processCreditCardPayment(orderId, amount, paymentData);
        case PaymentMethod.debitCard:
          return await _processDebitCardPayment(orderId, amount, paymentData);
        case PaymentMethod.mobilePayment:
          return await _processMobilePayment(orderId, amount, paymentData);
        case PaymentMethod.bankTransfer:
          return await _processBankTransfer(orderId, amount, paymentData);
        case PaymentMethod.cashOnDelivery:
          return await _processCashOnDelivery(orderId, amount);
      }
    } catch (e) {
      return PaymentResult.error(
        message: 'Payment processing failed: $e',
        errorCode: 'PAYMENT_ERROR',
      );
    }
  }

  /// Process credit card payment
  static Future<PaymentResult> _processCreditCardPayment(
    String orderId,
    double amount,
    Map<String, dynamic> paymentData,
  ) async {
    // Validate required fields
    final requiredFields = [
      'cardNumber',
      'expiryMonth',
      'expiryYear',
      'cvv',
      'cardholderName'
    ];
    for (final field in requiredFields) {
      if (!paymentData.containsKey(field) ||
          paymentData[field].toString().isEmpty) {
        return PaymentResult.error(
          message: 'Missing required field: $field',
          errorCode: 'MISSING_FIELD',
        );
      }
    }

    // Mock credit card validation
    final cardNumber = paymentData['cardNumber'].toString().replaceAll(' ', '');
    if (!_isValidCardNumber(cardNumber)) {
      return PaymentResult.error(
        message: 'Invalid card number',
        errorCode: 'INVALID_CARD',
      );
    }

    // Mock CVV validation
    final cvv = paymentData['cvv'].toString();
    if (cvv.length < 3 || cvv.length > 4) {
      return PaymentResult.error(
        message: 'Invalid CVV',
        errorCode: 'INVALID_CVV',
      );
    }

    // Mock expiry date validation
    final expiryMonth =
        int.tryParse(paymentData['expiryMonth'].toString()) ?? 0;
    final expiryYear = int.tryParse(paymentData['expiryYear'].toString()) ?? 0;
    final currentDate = DateTime.now();
    if (expiryYear < currentDate.year ||
        (expiryYear == currentDate.year && expiryMonth < currentDate.month)) {
      return PaymentResult.error(
        message: 'Card has expired',
        errorCode: 'EXPIRED_CARD',
      );
    }

    // Mock payment processing (90% success rate)
    final isSuccess = DateTime.now().millisecondsSinceEpoch % 10 != 0;

    if (isSuccess) {
      return PaymentResult.success(
        paymentId: 'PAY_${DateTime.now().millisecondsSinceEpoch}',
        transactionId: 'TXN_${DateTime.now().millisecondsSinceEpoch}',
        amount: amount,
        currency: 'USD',
        status: PaymentStatus.paid,
        message: 'Payment processed successfully',
      );
    } else {
      return PaymentResult.error(
        message: 'Payment declined by bank',
        errorCode: 'DECLINED',
      );
    }
  }

  /// Process debit card payment
  static Future<PaymentResult> _processDebitCardPayment(
    String orderId,
    double amount,
    Map<String, dynamic> paymentData,
  ) async {
    // Similar to credit card but with different validation rules
    return await _processCreditCardPayment(orderId, amount, paymentData);
  }

  /// Process mobile payment
  static Future<PaymentResult> _processMobilePayment(
    String orderId,
    double amount,
    Map<String, dynamic> paymentData,
  ) async {
    // Validate mobile payment data
    if (!paymentData.containsKey('phoneNumber') ||
        paymentData['phoneNumber'].toString().isEmpty) {
      return PaymentResult.error(
        message: 'Phone number is required for mobile payment',
        errorCode: 'MISSING_PHONE',
      );
    }

    // Mock mobile payment processing
    final isSuccess = DateTime.now().millisecondsSinceEpoch % 8 != 0;

    if (isSuccess) {
      return PaymentResult.success(
        paymentId: 'MOBILE_${DateTime.now().millisecondsSinceEpoch}',
        transactionId: 'TXN_${DateTime.now().millisecondsSinceEpoch}',
        amount: amount,
        currency: 'USD',
        status: PaymentStatus.paid,
        message: 'Mobile payment processed successfully',
      );
    } else {
      return PaymentResult.error(
        message: 'Mobile payment failed',
        errorCode: 'MOBILE_PAYMENT_FAILED',
      );
    }
  }

  /// Process bank transfer
  static Future<PaymentResult> _processBankTransfer(
    String orderId,
    double amount,
    Map<String, dynamic> paymentData,
  ) async {
    // Bank transfer is always successful (manual verification required)
    return PaymentResult.success(
      paymentId: 'BANK_${DateTime.now().millisecondsSinceEpoch}',
      transactionId: 'TXN_${DateTime.now().millisecondsSinceEpoch}',
      amount: amount,
      currency: 'USD',
      status: PaymentStatus.pending, // Pending until bank confirms
      message:
          'Bank transfer initiated. Payment will be confirmed within 1-2 business days.',
    );
  }

  /// Process cash on delivery
  static Future<PaymentResult> _processCashOnDelivery(
    String orderId,
    double amount,
  ) async {
    // Cash on delivery is always successful
    return PaymentResult.success(
      paymentId: 'COD_${DateTime.now().millisecondsSinceEpoch}',
      transactionId: 'TXN_${DateTime.now().millisecondsSinceEpoch}',
      amount: amount,
      currency: 'USD',
      status: PaymentStatus.pending, // Pending until delivery
      message:
          'Cash on delivery order confirmed. Payment will be collected upon delivery.',
    );
  }

  /// Validate card number using Luhn algorithm
  static bool _isValidCardNumber(String cardNumber) {
    if (cardNumber.length < 13 || cardNumber.length > 19) return false;

    // Remove spaces and non-digits
    final cleanNumber = cardNumber.replaceAll(RegExp(r'[^0-9]'), '');

    // Luhn algorithm
    int sum = 0;
    bool alternate = false;

    for (int i = cleanNumber.length - 1; i >= 0; i--) {
      int digit = int.parse(cleanNumber[i]);

      if (alternate) {
        digit *= 2;
        if (digit > 9) {
          digit = (digit % 10) + 1;
        }
      }

      sum += digit;
      alternate = !alternate;
    }

    return sum % 10 == 0;
  }

  /// Get payment methods available for user
  static List<PaymentMethod> getAvailablePaymentMethods() {
    return [
      PaymentMethod.mobilePayment,
      PaymentMethod.bankTransfer,
      PaymentMethod.cashOnDelivery,
    ];
  }

  /// Get payment method display info
  static PaymentMethodInfo getPaymentMethodInfo(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.creditCard:
        return PaymentMethodInfo(
          name: 'Credit Card',
          description: 'Pay with your credit card',
          icon: '💳',
          isAvailable: true,
        );
      case PaymentMethod.debitCard:
        return PaymentMethodInfo(
          name: 'Debit Card',
          description: 'Pay with your debit card',
          icon: '💳',
          isAvailable: true,
        );
      case PaymentMethod.mobilePayment:
        return PaymentMethodInfo(
          name: 'Mobile Payment',
          description: 'Pay with mobile money',
          icon: '📱',
          isAvailable: true,
        );
      case PaymentMethod.bankTransfer:
        return PaymentMethodInfo(
          name: 'Bank Transfer',
          description: 'Transfer from your bank account',
          icon: '🏦',
          isAvailable: true,
        );
      case PaymentMethod.cashOnDelivery:
        return PaymentMethodInfo(
          name: 'Cash on Delivery',
          description: 'Pay when your order arrives',
          icon: '💰',
          isAvailable: true,
        );
    }
  }

  /// Refund payment
  static Future<PaymentResult> refundPayment({
    required String paymentId,
    required double amount,
    String? reason,
  }) async {
    try {
      // Simulate API call delay
      await Future.delayed(Duration(seconds: 1));

      // Mock refund processing
      final isSuccess = DateTime.now().millisecondsSinceEpoch % 5 != 0;

      if (isSuccess) {
        return PaymentResult.success(
          paymentId: paymentId,
          transactionId: 'REFUND_${DateTime.now().millisecondsSinceEpoch}',
          amount: amount,
          currency: 'USD',
          status: PaymentStatus.refunded,
          message: 'Refund processed successfully',
        );
      } else {
        return PaymentResult.error(
          message: 'Refund failed',
          errorCode: 'REFUND_FAILED',
        );
      }
    } catch (e) {
      return PaymentResult.error(
        message: 'Refund processing failed: $e',
        errorCode: 'REFUND_ERROR',
      );
    }
  }
}

class PaymentResult {
  final bool success;
  final String? paymentId;
  final String? transactionId;
  final double? amount;
  final String? currency;
  final PaymentStatus? status;
  final String message;
  final String? errorCode;
  final Map<String, dynamic>? metadata;

  PaymentResult({
    required this.success,
    this.paymentId,
    this.transactionId,
    this.amount,
    this.currency,
    this.status,
    required this.message,
    this.errorCode,
    this.metadata,
  });

  factory PaymentResult.success({
    required String paymentId,
    required String transactionId,
    required double amount,
    required String currency,
    required PaymentStatus status,
    required String message,
    Map<String, dynamic>? metadata,
  }) {
    return PaymentResult(
      success: true,
      paymentId: paymentId,
      transactionId: transactionId,
      amount: amount,
      currency: currency,
      status: status,
      message: message,
      metadata: metadata,
    );
  }

  factory PaymentResult.error({
    required String message,
    String? errorCode,
    Map<String, dynamic>? metadata,
  }) {
    return PaymentResult(
      success: false,
      message: message,
      errorCode: errorCode,
      metadata: metadata,
    );
  }
}

class PaymentMethodInfo {
  final String name;
  final String description;
  final String icon;
  final bool isAvailable;

  PaymentMethodInfo({
    required this.name,
    required this.description,
    required this.icon,
    required this.isAvailable,
  });
}
