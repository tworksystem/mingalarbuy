/// Point transaction model
/// Represents a single point transaction (earn, redeem, expire)
class PointTransaction {
  final String id;
  final String userId;
  final PointTransactionType type;
  final int points;
  final int originalBalance;
  final int amountAdded;
  final int amountDeducted;
  final int currentBalance;
  final String? description;
  final String? orderId;
  final PollTransactionDetails? pollDetails;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final bool isExpired;
  final PointTransactionStatus status;

  PointTransaction({
    required this.id,
    required this.userId,
    required this.type,
    required this.points,
    this.originalBalance = 0,
    this.amountAdded = 0,
    this.amountDeducted = 0,
    this.currentBalance = 0,
    this.description,
    this.orderId,
    this.pollDetails,
    required this.createdAt,
    this.expiresAt,
    this.isExpired = false,
    this.status = PointTransactionStatus.approved,
  });

  /// INTERNAL: Get current Myanmar time (UTC+06:30) as a local DateTime
  static DateTime _getCurrentMyanmarTime() {
    final utcNow = DateTime.now().toUtc();
    // Convert UTC to Myanmar time (UTC+06:30 = +390 minutes)
    const myanmarOffsetMinutes = 390; // 6 hours 30 minutes
    final myanmarTime = utcNow.add(Duration(minutes: myanmarOffsetMinutes));

    // Create a local DateTime with Myanmar time values (not UTC)
    // This ensures consistency with how transaction dates are stored
    return DateTime(
      myanmarTime.year,
      myanmarTime.month,
      myanmarTime.day,
      myanmarTime.hour,
      myanmarTime.minute,
      myanmarTime.second,
      myanmarTime.millisecond,
      myanmarTime.microsecond,
    );
  }

  /// INTERNAL: Parse server datetime string into Myanmar time (UTC+06:30).
  ///
  /// Backend (WordPress/PHP) typically sends timestamps in UTC without timezone info
  /// (e.g. "2025-12-25 02:55:00"). To ensure consistent Myanmar time display:
  /// - Parse the string as UTC if no timezone info is present
  /// - Convert UTC to Myanmar timezone (UTC+06:30) properly
  /// - Return DateTime that represents Myanmar local time
  static DateTime _parseServerDateTime(dynamic value) {
    if (value == null) {
      return _getCurrentMyanmarTime();
    }

    final str = value.toString().trim();
    if (str.isEmpty) {
      return _getCurrentMyanmarTime();
    }

    try {
      DateTime utcDateTime;

      // Check if the string already has timezone information
      // Look for 'Z' suffix, or timezone offset like '+06:30' or '-05:00'
      final hasTimezone =
          str.contains('Z') ||
          (str.contains('+') && str.length > 19) ||
          (str.contains('-', 10) && str.length > 19 && !str.startsWith('-'));

      if (hasTimezone) {
        // Already has timezone info, parse as-is and convert to UTC
        final parsed = DateTime.parse(str);
        utcDateTime = parsed.isUtc ? parsed : parsed.toUtc();
      } else {
        // PROFESSIONAL FIX: No timezone info - assume server sends UTC time
        // Parse by creating UTC DateTime explicitly using DateTime.utc() constructor
        // Handle formats like "2025-12-25 02:55:00" or "2025-12-25T02:55:00"
        final normalizedStr = str.replaceAll(' ', 'T');

        // Extract date and time components manually for precise UTC creation
        final parts = normalizedStr.split('T');
        if (parts.length == 2) {
          final datePart = parts[0];
          final timePart = parts[1].split(
            '.',
          )[0]; // Remove milliseconds if present
          final timeComponents = timePart.split(':');

          if (timeComponents.length >= 3) {
            final dateComponents = datePart.split('-');
            if (dateComponents.length == 3) {
              final year = int.parse(dateComponents[0]);
              final month = int.parse(dateComponents[1]);
              final day = int.parse(dateComponents[2]);
              final hour = int.parse(timeComponents[0]);
              final minute = int.parse(timeComponents[1]);
              final second = int.parse(timeComponents[2]);

              // CRITICAL: Create UTC DateTime explicitly using DateTime.utc()
              // This ensures we're treating the server time as UTC, not device local time
              utcDateTime = DateTime.utc(
                year,
                month,
                day,
                hour,
                minute,
                second,
              );
            } else {
              // Invalid date format, fallback
              utcDateTime = DateTime.parse('${normalizedStr}Z').toUtc();
            }
          } else {
            // Invalid time format, fallback
            utcDateTime = DateTime.parse('${normalizedStr}Z').toUtc();
          }
        } else {
          // Invalid format, fallback: try parsing as-is and assume UTC
          utcDateTime = DateTime.parse('${normalizedStr}Z').toUtc();
        }
      }

      // PROFESSIONAL FIX: Convert UTC to Myanmar time (UTC+06:30 = +390 minutes)
      // Myanmar time is 6 hours and 30 minutes ahead of UTC
      const myanmarOffsetMinutes = 390; // 6 hours 30 minutes
      final myanmarTime = utcDateTime.add(
        Duration(minutes: myanmarOffsetMinutes),
      );

      // CRITICAL: Create a local DateTime with Myanmar time values
      // We create a local DateTime (not UTC) so it's not affected by device timezone conversion
      // The DateTime values represent Myanmar time, and when formatted, they display correctly
      // Do NOT use DateTime.utc() as that would cause issues when formatting
      final myanmarLocalDateTime = DateTime(
        myanmarTime.year,
        myanmarTime.month,
        myanmarTime.day,
        myanmarTime.hour,
        myanmarTime.minute,
        myanmarTime.second,
        myanmarTime.millisecond,
        myanmarTime.microsecond,
      );

      return myanmarLocalDateTime;
    } catch (e) {
      // If parsing fails, return current Myanmar time (not device local time)
      return _getCurrentMyanmarTime();
    }
  }

  /// Create from JSON
  factory PointTransaction.fromJson(Map<String, dynamic> json) {
    PollTransactionDetails? parsedPollDetails;
    // Support legacy flat keys from backend and normalize into PollTransactionDetails.
    if (json['poll_details'] is Map<String, dynamic>) {
      parsedPollDetails = PollTransactionDetails.fromJson(
        json['poll_details'] as Map<String, dynamic>,
      );
    } else if (json['pollDetails'] is Map<String, dynamic>) {
      parsedPollDetails = PollTransactionDetails.fromJson(
        json['pollDetails'] as Map<String, dynamic>,
      );
    } else if (json.containsKey('selected_option') ||
        json.containsKey('bet_amount') ||
        json.containsKey('winning_option') ||
        json.containsKey('won_amount')) {
      parsedPollDetails = PollTransactionDetails.fromLegacyFlatJson(json);
    }

    // Bulletproof FIX: betPnp သည် 0 ဖြစ်နေပြီး Transaction တွင် အမှန်တကယ် နှုတ်ထားသော Point ရှိနေပါက ထို Point ဖြင့် Override လုပ်မည်
    final int actualPoints =
        _parseInt(json['points'] ?? json['amount_deducted']).abs();
    if (parsedPollDetails != null &&
        parsedPollDetails.totalBetPnp <= 0 &&
        actualPoints > 0) {
      final opts = parsedPollDetails.selectedOptions;
      if (opts.isNotEmpty) {
        final avgPnp = actualPoints ~/ opts.length;
        final remainder = actualPoints % opts.length; // အကြွင်းကို ယူမည်

        final newOpts = <PollOptionSnapshot>[];
        for (int i = 0; i < opts.length; i++) {
          final e = opts[i];
          final extra = (i == opts.length - 1) ? remainder : 0; // နောက်ဆုံး Option တွင် အကြွင်းကို ထည့်ပေါင်းမည်
          newOpts.add(
            PollOptionSnapshot(
              index: e.index,
              label: e.label,
              betUnits: e.betUnits,
              betPnp: e.betPnp <= 0 ? (avgPnp + extra) : e.betPnp,
            ),
          );
        }

        parsedPollDetails = PollTransactionDetails(
          pollId: parsedPollDetails.pollId,
          pollTitle: parsedPollDetails.pollTitle,
          sessionId: parsedPollDetails.sessionId,
          resultStatus: parsedPollDetails.resultStatus,
          totalBetPnp: actualPoints,
          wonAmountPnp: parsedPollDetails.wonAmountPnp,
          netAmountPnp: parsedPollDetails.netAmountPnp,
          winningOption: parsedPollDetails.winningOption,
          selectedOptions: newOpts,
        );
      }
    }

    return PointTransaction(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? json['userId']?.toString() ?? '',
      type: PointTransactionTypeExtension.fromString(
        json['type']?.toString() ?? 'earn',
      ),
      // Backend may send points as int, double, or string depending on DB schema.
      points: _parseInt(json['points']),
      originalBalance: _parseInt(
        json['original_balance'] ?? json['originalBalance'],
      ),
      amountAdded: _parseInt(json['amount_added'] ?? json['amountAdded']),
      amountDeducted: _parseInt(
        json['amount_deducted'] ?? json['amountDeducted'],
      ),
      currentBalance: _parseInt(
        json['current_balance'] ?? json['currentBalance'],
      ),
      description: json['description']?.toString(),
      orderId: json['order_id']?.toString() ?? json['orderId']?.toString(),
      pollDetails: parsedPollDetails,
      createdAt: json['created_at'] != null
          ? _parseServerDateTime(json['created_at'])
          : json['createdAt'] != null
          ? _parseServerDateTime(json['createdAt'])
          : DateTime.now(),
      expiresAt: json['expires_at'] != null
          ? _parseServerDateTime(json['expires_at'])
          : json['expiresAt'] != null
          ? _parseServerDateTime(json['expiresAt'])
          : null,
      // Safe bool parsing from bool/int/string payloads.
      isExpired: _parseBool(json['is_expired'] ?? json['isExpired']),
      status: PointTransactionStatusExtension.fromString(
        json['status']?.toString() ?? 'approved',
      ),
    );
  }

  PointTransaction copyWith({
    String? id,
    String? userId,
    PointTransactionType? type,
    int? points,
    int? originalBalance,
    int? amountAdded,
    int? amountDeducted,
    int? currentBalance,
    String? description,
    String? orderId,
    PollTransactionDetails? pollDetails,
    DateTime? createdAt,
    DateTime? expiresAt,
    bool? isExpired,
    PointTransactionStatus? status,
  }) {
    return PointTransaction(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      points: points ?? this.points,
      originalBalance: originalBalance ?? this.originalBalance,
      amountAdded: amountAdded ?? this.amountAdded,
      amountDeducted: amountDeducted ?? this.amountDeducted,
      currentBalance: currentBalance ?? this.currentBalance,
      description: description ?? this.description,
      orderId: orderId ?? this.orderId,
      pollDetails: pollDetails ?? this.pollDetails,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      isExpired: isExpired ?? this.isExpired,
      status: status ?? this.status,
    );
  }

  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    final str = value.toString().trim();
    if (str.isEmpty) return 0;
    // Handle values like "123", "-20", "123.0"
    final asInt = int.tryParse(str);
    if (asInt != null) return asInt;
    final asDouble = double.tryParse(str);
    if (asDouble != null) return asDouble.toInt();
    return 0;
  }

  static bool _parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value == null) return false;
    final s = value.toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }

  /// Convert Myanmar time back to UTC for storage
  /// This ensures consistency - we always store UTC in cache, then convert to Myanmar when loading
  static DateTime _myanmarTimeToUtc(DateTime myanmarTime) {
    // Myanmar time is UTC+06:30, so to convert back to UTC, subtract 390 minutes
    const myanmarOffsetMinutes = 390; // 6 hours 30 minutes
    final utcTime = myanmarTime.subtract(
      Duration(minutes: myanmarOffsetMinutes),
    );
    // Return as UTC DateTime
    return DateTime.utc(
      utcTime.year,
      utcTime.month,
      utcTime.day,
      utcTime.hour,
      utcTime.minute,
      utcTime.second,
      utcTime.millisecond,
      utcTime.microsecond,
    );
  }

  /// Convert to JSON
  /// PROFESSIONAL FIX: Store datetime as UTC in cache for consistency
  /// When loading from cache, we convert UTC back to Myanmar time
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'type': type.toValue(),
      'points': points,
      'original_balance': originalBalance,
      'amount_added': amountAdded,
      'amount_deducted': amountDeducted,
      'current_balance': currentBalance,
      'description': description,
      'order_id': orderId,
      if (pollDetails != null) 'poll_details': pollDetails!.toJson(),
      // Convert Myanmar time back to UTC for storage
      // This ensures when we load from cache, we can convert it to Myanmar time again
      'created_at': _myanmarTimeToUtc(createdAt).toIso8601String(),
      'expires_at': expiresAt != null
          ? _myanmarTimeToUtc(expiresAt!).toIso8601String()
          : null,
      'is_expired': isExpired,
      'status': status.toValue(),
    };
  }

  /// Check if transaction is expired
  bool get expired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  /// Get formatted points (with + or - sign)
  /// PROFESSIONAL FIX: Handle negative adjustments properly
  /// For adjust type, check if points value is negative to show correct sign
  String get formattedPoints {
    // For redeem, expire, refund - always show negative
    if (type == PointTransactionType.redeem ||
        type == PointTransactionType.expire ||
        type == PointTransactionType.refund) {
      return '-$points';
    }

    // For adjust type - check if points value is negative
    if (type == PointTransactionType.adjust) {
      if (points < 0) {
        // Negative adjustment - show without double negative
        return '${points}'; // points is already negative, so just return it
      } else {
        // Positive adjustment
        return '+$points';
      }
    }

    // For all other types (earn, referral, birthday) - always show positive
    return '+$points';
  }

  /// Get days until expiration (if applicable)
  int? get daysUntilExpiration {
    if (expiresAt == null || expired) return null;
    final now = DateTime.now();
    return expiresAt!.difference(now).inDays;
  }

  /// Check if transaction is expiring soon (within 30 days)
  bool get isExpiringSoon {
    final days = daysUntilExpiration;
    return days != null && days <= 30 && days > 0;
  }

  /// Check if transaction is pending
  bool get isPending => status == PointTransactionStatus.pending;

  /// Check if transaction is approved
  bool get isApproved => status == PointTransactionStatus.approved;

  /// Check if transaction is rejected
  bool get isRejected => status == PointTransactionStatus.rejected;
}

class PointTransactionHistoryResult {
  final List<PointTransaction> transactions;
  final int total;
  final int page;
  final int perPage;
  final int totalPages;

  const PointTransactionHistoryResult({
    required this.transactions,
    this.total = 0,
    this.page = 1,
    this.perPage = 20,
    this.totalPages = 1,
  });

  factory PointTransactionHistoryResult.fromJson(Map<String, dynamic> json) {
    final transactionsRaw = json['transactions'];
    final transactions = transactionsRaw is List
        ? transactionsRaw
              .whereType<Map>()
              .map(
                (item) =>
                    PointTransaction.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList()
        : <PointTransaction>[];

    return PointTransactionHistoryResult(
      transactions: transactions,
      total: PointTransaction._parseInt(json['total']),
      page: PointTransaction._parseInt(json['page']),
      perPage: PointTransaction._parseInt(json['per_page'] ?? json['perPage']),
      totalPages: PointTransaction._parseInt(
        json['total_pages'] ?? json['totalPages'],
      ),
    );
  }
}

class PollTransactionDetails {
  final int? pollId;
  final String? pollTitle;
  final String? sessionId;
  final String? resultStatus; // won / lost / pending
  final int totalBetPnp;
  final int wonAmountPnp;
  final int netAmountPnp;
  final PollOptionSnapshot? winningOption;
  final List<PollOptionSnapshot> selectedOptions;

  PollTransactionDetails({
    this.pollId,
    this.pollTitle,
    this.sessionId,
    this.resultStatus,
    this.totalBetPnp = 0,
    this.wonAmountPnp = 0,
    this.netAmountPnp = 0,
    this.winningOption,
    this.selectedOptions = const [],
  });

  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    final s = value.toString().trim();
    if (s.isEmpty) return 0;
    return int.tryParse(s) ?? (double.tryParse(s)?.toInt() ?? 0);
  }

  factory PollTransactionDetails.fromJson(Map<String, dynamic> json) {
    final selectedRaw = json['selected_options'];
    final List<PollOptionSnapshot> selected;
    if (selectedRaw is List) {
      selected = selectedRaw
          .whereType<Map>()
          .map((e) => PollOptionSnapshot.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } else {
      selected = const [];
    }

    final winningRaw = json['winning_option'];
    final PollOptionSnapshot? winning = winningRaw is Map
        ? PollOptionSnapshot.fromJson(Map<String, dynamic>.from(winningRaw))
        : null;

    return PollTransactionDetails(
      pollId: json['poll_id'] == null ? null : _parseInt(json['poll_id']),
      pollTitle: json['poll_title']?.toString(),
      sessionId: json['session_id']?.toString(),
      resultStatus: json['result_status']?.toString(),
      // Old Code:
      // totalBetPnp: _parseInt(json['total_bet_pnp']),
      //
      // New Code: [String] payloads from backend are safe via _parseInt.
      totalBetPnp: _parseInt(json['total_bet_pnp'] ?? json['bet_amount']),
      wonAmountPnp: _parseInt(json['won_amount_pnp']),
      netAmountPnp: _parseInt(json['net_amount_pnp']),
      winningOption: winning,
      selectedOptions: selected,
    );
  }

  factory PollTransactionDetails.fromLegacyFlatJson(Map<String, dynamic> json) {
    final selectedRaw = json['selected_option']?.toString() ?? '';

    // Bulletproof FIX: bet_amount မရှိလျှင် Transaction ၏ 'points' သို့မဟုတ် 'amount_deducted' ကို အတင်းဆွဲယူမည်
    int betUnits = _parseInt(json['bet_amount']);
    if (betUnits <= 0) {
      betUnits = _parseInt(json['points'] ?? json['amount_deducted']).abs();
    }

    final selected = <PollOptionSnapshot>[];
    if (selectedRaw.trim().isNotEmpty) {
      final parts = selectedRaw.split(',');
      // Division by zero မဖြစ်အောင် ကာကွယ်ခြင်းနှင့် အကြွင်းရှာခြင်း
      final avgPnp = parts.isNotEmpty ? (betUnits ~/ parts.length) : betUnits;
      final remainder = parts.isNotEmpty ? (betUnits % parts.length) : 0;

      for (int i = 0; i < parts.length; i++) {
        final idx = _parseInt(parts[i].trim());
        // နောက်ဆုံး Option တွင် အကြွင်းကို ထည့်ပေါင်းမည်
        final extra = (i == parts.length - 1) ? remainder : 0;
        selected.add(
          PollOptionSnapshot(
            index: idx,
            label: 'Option ${idx + 1}',
            betUnits: betUnits,
            betPnp: avgPnp + extra,
          ),
        );
      }
    }

    final winningRaw = json['winning_option'];
    PollOptionSnapshot? winning;
    if (winningRaw != null && winningRaw.toString().trim().isNotEmpty) {
      if (winningRaw is Map<String, dynamic>) {
        winning = PollOptionSnapshot.fromJson(winningRaw);
      } else {
        final idx = _parseInt(winningRaw);
        winning = PollOptionSnapshot(index: idx, label: 'Option ${idx + 1}');
      }
    }

    final won = _parseInt(json['won_amount']);

    return PollTransactionDetails(
      resultStatus: won > 0 ? 'won' : 'pending',
      totalBetPnp: betUnits,
      wonAmountPnp: won,
      netAmountPnp: won,
      winningOption: winning,
      selectedOptions: selected.isEmpty
          ? [
              PollOptionSnapshot(
                index: 0,
                label: 'Unknown Option',
                betUnits: betUnits,
                betPnp: betUnits,
              ),
            ]
          : selected,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'poll_id': pollId,
      'poll_title': pollTitle,
      'session_id': sessionId,
      'result_status': resultStatus,
      'total_bet_pnp': totalBetPnp,
      'won_amount_pnp': wonAmountPnp,
      'net_amount_pnp': netAmountPnp,
      'winning_option': winningOption?.toJson(),
      'selected_options': selectedOptions.map((e) => e.toJson()).toList(),
    };
  }
}

class PollOptionSnapshot {
  final int index;
  final String label;
  final int betUnits;
  final int betPnp;

  PollOptionSnapshot({
    required this.index,
    required this.label,
    this.betUnits = 0,
    this.betPnp = 0,
  });

  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    final s = value.toString().trim();
    if (s.isEmpty) return 0;
    return int.tryParse(s) ?? (double.tryParse(s)?.toInt() ?? 0);
  }

  factory PollOptionSnapshot.fromJson(Map<String, dynamic> json) {
    final betUnits = _parseInt(json['bet_units'] ?? json['bet_amount']);
    // Bulletproof: 0 PNP / missing bet_pnp — use stake fields from same snapshot
    var betPnp = _parseInt(json['bet_pnp']);
    if (betPnp <= 0) {
      betPnp = _parseInt(json['bet_amount'] ?? json['amount']);
    }
    if (betPnp <= 0) {
      betPnp = betUnits;
    }
    return PollOptionSnapshot(
      index: _parseInt(json['index']),
      label: json['label']?.toString() ?? '',
      betUnits: betUnits,
      betPnp: betPnp,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'index': index,
      'label': label,
      'bet_units': betUnits,
      'bet_pnp': betPnp,
    };
  }
}

/// Point transaction types
enum PointTransactionType {
  earn, // Earned points (purchase, signup, review, etc.)
  redeem, // Redeemed points (used for discount)
  expire, // Expired points
  adjust, // Manual adjustment by admin
  referral, // Referral bonus
  birthday, // Birthday bonus
  refund, // Refunded points (order cancellation)
}

/// Point transaction status
enum PointTransactionStatus {
  pending, // Pending approval
  approved, // Approved and active
  rejected, // Rejected
}

/// Extension for PointTransactionStatus
extension PointTransactionStatusExtension on PointTransactionStatus {
  /// Convert from string
  static PointTransactionStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'pending':
        return PointTransactionStatus.pending;
      case 'approved':
        return PointTransactionStatus.approved;
      case 'rejected':
        return PointTransactionStatus.rejected;
      default:
        return PointTransactionStatus.approved;
    }
  }

  /// Convert to string
  String toValue() {
    switch (this) {
      case PointTransactionStatus.pending:
        return 'pending';
      case PointTransactionStatus.approved:
        return 'approved';
      case PointTransactionStatus.rejected:
        return 'rejected';
    }
  }
}

/// Extension for PointTransactionType
extension PointTransactionTypeExtension on PointTransactionType {
  /// Convert from string
  static PointTransactionType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'earn':
      case 'earned':
        return PointTransactionType.earn;
      case 'redeem':
      case 'redeemed':
        return PointTransactionType.redeem;
      case 'expire':
      case 'expired':
        return PointTransactionType.expire;
      case 'adjust':
      case 'adjustment':
        return PointTransactionType.adjust;
      case 'referral':
      case 'refer':
        return PointTransactionType.referral;
      case 'birthday':
      case 'birthday_bonus':
        return PointTransactionType.birthday;
      case 'refund':
      case 'refunded':
        return PointTransactionType.refund;
      default:
        return PointTransactionType.earn;
    }
  }

  /// Convert to string
  String toValue() {
    switch (this) {
      case PointTransactionType.earn:
        return 'earn';
      case PointTransactionType.redeem:
        return 'redeem';
      case PointTransactionType.expire:
        return 'expire';
      case PointTransactionType.adjust:
        return 'adjust';
      case PointTransactionType.referral:
        return 'referral';
      case PointTransactionType.birthday:
        return 'birthday';
      case PointTransactionType.refund:
        return 'refund';
    }
  }
}

/// Point balance model
/// Represents user's current point balance and statistics
class PointBalance {
  final String userId;
  final int currentBalance;
  final int lifetimeEarned;
  final int lifetimeRedeemed;
  final int lifetimeExpired;
  final DateTime lastUpdated;
  final DateTime? pointsExpireAt; // When points will expire next

  PointBalance({
    required this.userId,
    required this.currentBalance,
    this.lifetimeEarned = 0,
    this.lifetimeRedeemed = 0,
    this.lifetimeExpired = 0,
    required this.lastUpdated,
    this.pointsExpireAt,
  });

  /// Parse balance from JSON — handles num, String (e.g. "18200")
  static int _parseBalance(
    Map<String, dynamic> json,
    String key,
    String altKey,
  ) {
    final v = json[key] ?? json[altKey];
    if (v == null) return 0;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? 0;
    return int.tryParse(v.toString()) ?? 0;
  }

  /// Create from JSON
  factory PointBalance.fromJson(Map<String, dynamic> json) {
    return PointBalance(
      userId: json['user_id']?.toString() ?? json['userId']?.toString() ?? '',
      currentBalance: _parseBalance(json, 'current_balance', 'currentBalance'),
      lifetimeEarned: _parseBalance(json, 'lifetime_earned', 'lifetimeEarned'),
      lifetimeRedeemed: _parseBalance(
        json,
        'lifetime_redeemed',
        'lifetimeRedeemed',
      ),
      lifetimeExpired: _parseBalance(
        json,
        'lifetime_expired',
        'lifetimeExpired',
      ),
      lastUpdated: json['last_updated'] != null
          ? DateTime.parse(json['last_updated'])
          : json['lastUpdated'] != null
          ? DateTime.parse(json['lastUpdated'])
          : DateTime.now(),
      pointsExpireAt: json['points_expire_at'] != null
          ? DateTime.parse(json['points_expire_at'])
          : json['pointsExpireAt'] != null
          ? DateTime.parse(json['pointsExpireAt'])
          : null,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'current_balance': currentBalance,
      'lifetime_earned': lifetimeEarned,
      'lifetime_redeemed': lifetimeRedeemed,
      'lifetime_expired': lifetimeExpired,
      'last_updated': lastUpdated.toIso8601String(),
      'points_expire_at': pointsExpireAt?.toIso8601String(),
    };
  }

  /// Get formatted balance
  String get formattedBalance => '$currentBalance points';

  /// Check if user has enough points
  bool hasEnoughPoints(int requiredPoints) {
    return currentBalance >= requiredPoints;
  }

  /// Get next expiration date from available points
  DateTime? get nextExpirationDate {
    // This would be calculated from transactions
    // For now, return null - will be implemented in service
    return pointsExpireAt;
  }

  /// Get points expiring soon count
  int get pointsExpiringSoon {
    // This would be calculated from transactions
    // For now, return 0 - will be implemented in service
    return 0;
  }
}
