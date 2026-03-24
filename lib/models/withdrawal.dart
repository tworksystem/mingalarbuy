/// Withdrawal models for wallet transfer functionality
/// Supports multiple payment methods: All major Myanmar mobile payment services and Bank Transfer

/// Enumeration of supported withdrawal/transfer methods
/// Includes all major payment services available in Myanmar
enum WithdrawalMethod {
  // Major Mobile Payment Services
  kpay('kpay', 'KPay'),
  ayaPay('aya_pay', 'AYA Pay'),
  wavePay('wave_pay', 'Wave Pay'),
  cbPay('cb_pay', 'CB Pay'),
  uabPay('uab_pay', 'UAB Pay'),
  onepay('onepay', 'OnePay'),
  trueMoney('truemoney', 'TrueMoney'),
  mpitesan('mpitesan', 'M-Pitesan'),
  yomaPay('yoma_pay', 'Yoma Pay'),
  agdPay('agd_pay', 'AGD Pay'),
  mabPay('mab_pay', 'MAB Pay'),
  // Bank Transfer
  bank('bank', 'Bank Transfer');

  final String code;
  final String displayName;

  const WithdrawalMethod(this.code, this.displayName);

  /// Get method from code
  static WithdrawalMethod? fromCode(String code) {
    for (var method in WithdrawalMethod.values) {
      if (method.code.toLowerCase() == code.toLowerCase()) {
        return method;
      }
    }
    return null;
  }

  /// Check if this is a mobile payment method (not bank transfer)
  bool get isMobilePayment => this != WithdrawalMethod.bank;

  /// Get icon name for UI
  String get iconName {
    switch (this) {
      case WithdrawalMethod.kpay:
        return 'kpay';
      case WithdrawalMethod.ayaPay:
        return 'aya_pay';
      case WithdrawalMethod.wavePay:
        return 'wave_pay';
      case WithdrawalMethod.cbPay:
        return 'cb_pay';
      case WithdrawalMethod.uabPay:
        return 'uab_pay';
      case WithdrawalMethod.onepay:
        return 'onepay';
      case WithdrawalMethod.trueMoney:
        return 'truemoney';
      case WithdrawalMethod.mpitesan:
        return 'mpitesan';
      case WithdrawalMethod.yomaPay:
        return 'yoma_pay';
      case WithdrawalMethod.agdPay:
        return 'agd_pay';
      case WithdrawalMethod.mabPay:
        return 'mab_pay';
      case WithdrawalMethod.bank:
        return 'account_balance';
    }
  }
}

/// Withdrawal request model
class WithdrawalRequest {
  final String userId;
  final WithdrawalMethod method;
  final double amount;
  final String accountNumber; // Phone number for mobile payments, account number for bank
  final String? accountName; // Optional account holder name
  final String? bankName; // Required for bank transfers
  final String? notes; // Optional notes/description

  WithdrawalRequest({
    required this.userId,
    required this.method,
    required this.amount,
    required this.accountNumber,
    this.accountName,
    this.bankName,
    this.notes,
  }) : assert(amount > 0, 'Amount must be greater than 0'),
       assert(accountNumber.isNotEmpty, 'Account number is required'),
       assert(
         method != WithdrawalMethod.bank || (bankName != null && bankName.isNotEmpty),
         'Bank name is required for bank transfers',
       );

  /// Convert to JSON for API request
  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'method': method.code,
      'amount': amount,
      'account_number': accountNumber,
      if (accountName != null) 'account_name': accountName,
      if (bankName != null) 'bank_name': bankName,
      if (notes != null) 'notes': notes,
    };
  }

  /// Create from JSON
  factory WithdrawalRequest.fromJson(Map<String, dynamic> json) {
    final method = WithdrawalMethod.fromCode(json['method'] as String? ?? '');
    if (method == null) {
      throw ArgumentError('Invalid withdrawal method: ${json['method']}');
    }

    return WithdrawalRequest(
      userId: json['user_id']?.toString() ?? '',
      method: method,
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      accountNumber: json['account_number']?.toString() ?? '',
      accountName: json['account_name']?.toString(),
      bankName: json['bank_name']?.toString(),
      notes: json['notes']?.toString(),
    );
  }
}

/// Withdrawal result model
class WithdrawalResult {
  final bool success;
  final String message;
  final String? transactionId;
  final double? newBalance; // Updated wallet balance after withdrawal
  final DateTime? processedAt;
  final WithdrawalRequest? request; // Original request for reference
  final String? errorCode;

  WithdrawalResult({
    required this.success,
    required this.message,
    this.transactionId,
    this.newBalance,
    this.processedAt,
    this.request,
    this.errorCode,
  });

  /// Create successful result
  factory WithdrawalResult.success({
    required String message,
    String? transactionId,
    double? newBalance,
    DateTime? processedAt,
    WithdrawalRequest? request,
  }) {
    return WithdrawalResult(
      success: true,
      message: message,
      transactionId: transactionId,
      newBalance: newBalance,
      processedAt: processedAt ?? DateTime.now(),
      request: request,
    );
  }

  /// Create failed result
  factory WithdrawalResult.failure({
    required String message,
    String? errorCode,
    WithdrawalRequest? request,
  }) {
    return WithdrawalResult(
      success: false,
      message: message,
      errorCode: errorCode,
      request: request,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'message': message,
      if (transactionId != null) 'transaction_id': transactionId,
      if (newBalance != null) 'new_balance': newBalance,
      if (processedAt != null) 'processed_at': processedAt!.toIso8601String(),
      if (errorCode != null) 'error_code': errorCode,
    };
  }

  /// Create from JSON
  factory WithdrawalResult.fromJson(Map<String, dynamic> json) {
    return WithdrawalResult(
      success: json['success'] == true,
      message: json['message']?.toString() ?? '',
      transactionId: json['transaction_id']?.toString(),
      newBalance: (json['new_balance'] as num?)?.toDouble(),
      processedAt: json['processed_at'] != null
          ? DateTime.parse(json['processed_at'])
          : null,
      errorCode: json['error_code']?.toString(),
    );
  }
}

/// Withdrawal history entry
class WithdrawalHistoryEntry {
  final String transactionId;
  final WithdrawalMethod method;
  final double amount;
  final String accountNumber;
  final String status; // pending, processing, completed, failed
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? notes;
  final String? failureReason;

  WithdrawalHistoryEntry({
    required this.transactionId,
    required this.method,
    required this.amount,
    required this.accountNumber,
    required this.status,
    required this.createdAt,
    this.completedAt,
    this.notes,
    this.failureReason,
  });

  bool get isPending => status == 'pending';
  bool get isProcessing => status == 'processing';
  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'transaction_id': transactionId,
      'method': method.code,
      'amount': amount,
      'account_number': accountNumber,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      if (completedAt != null) 'completed_at': completedAt!.toIso8601String(),
      if (notes != null) 'notes': notes,
      if (failureReason != null) 'failure_reason': failureReason,
    };
  }

  /// Create from JSON
  factory WithdrawalHistoryEntry.fromJson(Map<String, dynamic> json) {
    final method = WithdrawalMethod.fromCode(json['method'] as String? ?? '');
    if (method == null) {
      throw ArgumentError('Invalid withdrawal method: ${json['method']}');
    }

    return WithdrawalHistoryEntry(
      transactionId: json['transaction_id']?.toString() ?? '',
      method: method,
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      accountNumber: json['account_number']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'])
          : null,
      notes: json['notes']?.toString(),
      failureReason: json['failure_reason']?.toString(),
    );
  }
}
