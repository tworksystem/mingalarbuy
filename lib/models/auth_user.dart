class AuthUser {
  final int id;
  final String email;
  final String firstName;
  final String lastName;
  final String username;
  final String? avatar;
  final String? phone;
  final String? billingAddress;
  final String? billingCity;
  final String? billingCountry;
  final String? shippingAddress;
  final DateTime? dateCreated;
  final bool isEmailVerified;
  final List<String> roles;
  final Map<String, String> customFields;

  AuthUser({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.username,
    this.avatar,
    this.phone,
    this.billingAddress,
    this.shippingAddress,
    this.billingCity,
    this.billingCountry,
    this.dateCreated,
    this.isEmailVerified = false,
    this.roles = const ['customer'],
    this.customFields = const {},
  });

  String get fullName => ('$firstName $lastName').trim();
  String get displayName => fullName.isNotEmpty ? fullName : username;

  /// Best label for profile headers when WP/WAF returns sparse `users/me` data.
  String get profileDisplayLabel {
    if (displayName.isNotEmpty) return displayName;
    if (email.trim().isNotEmpty) return email.trim();
    if (username.trim().isNotEmpty) return username.trim();
    final phoneLabel = phone?.trim();
    if (phoneLabel != null && phoneLabel.isNotEmpty) return phoneLabel;
    if (id > 0) return 'User #$id';
    return 'User';
  }

  static String? _trimmedNonEmpty(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final dynamic metaDynamic = json['meta'];
    String? metaPhone;
    if (metaDynamic is Map<String, dynamic>) {
      metaPhone = metaDynamic['billing_phone'] as String?;
    } else if (metaDynamic is List) {
      // Some WP setups return meta as a list of key/value pairs; attempt to find billing_phone
      try {
        for (final item in metaDynamic) {
          if (item is Map && item.containsKey('billing_phone')) {
            final val = item['billing_phone'];
            if (val is String) {
              metaPhone = val;
              break;
            }
          }
        }
      } catch (_) {}
    }

    final Map<String, dynamic>? billingMap = json['billing'] is Map
        ? (json['billing'] as Map).cast<String, dynamic>()
        : null;
    final Map<String, dynamic>? shippingMap = json['shipping'] is Map
        ? (json['shipping'] as Map).cast<String, dynamic>()
        : null;

    // Extract custom fields from meta or custom_fields
    Map<String, String> customFields = {};

    // DEBUG: Log raw API response for custom_fields
    print(
        'DEBUG AuthUser.fromJson - json[\'custom_fields\']: ${json['custom_fields']}');
    print(
        'DEBUG AuthUser.fromJson - json[\'custom_fields\'] type: ${json['custom_fields'].runtimeType}');

    // Priority 1: Check for top-level fields exposed via register_rest_field
    // These are added by the backend plugin using register_rest_field()
    if (json.containsKey('points_balance') && json['points_balance'] != null) {
      customFields['points_balance'] = json['points_balance'].toString();
      print(
          'DEBUG AuthUser.fromJson - Added points_balance from top-level: "${json['points_balance']}"');
    }
    if (json.containsKey('wallet_balance') && json['wallet_balance'] != null) {
      customFields['wallet_balance'] = json['wallet_balance'].toString();
      print(
          'DEBUG AuthUser.fromJson - Added wallet_balance from top-level: "${json['wallet_balance']}"');
    }

    // Priority 2: Check custom_fields array
    if (json['custom_fields'] is Map) {
      final customFieldsMap = json['custom_fields'] as Map;
      customFieldsMap.forEach((key, value) {
        if (value != null) {
          final keyStr = key.toString();
          final valueStr = value.toString();
          // Don't override top-level fields
          if (!customFields.containsKey(keyStr)) {
            customFields[keyStr] = valueStr;
            print(
                'DEBUG AuthUser.fromJson - Added custom field: $keyStr = "$valueStr"');
          }
        }
      });
    }

    // Priority 3: Check meta for custom fields (fallback)
    if (metaDynamic is Map<String, dynamic>) {
      // Check for custom fields in meta data with custom_field_ prefix
      metaDynamic.forEach((key, value) {
        if (key.startsWith('custom_field_') && value != null) {
          final cleanKey = key.replaceFirst('custom_field_', '');
          // Only add if not already in customFields
          if (!customFields.containsKey(cleanKey)) {
            customFields[cleanKey] = value.toString();
            print(
                'DEBUG AuthUser.fromJson - Added custom field from meta: $cleanKey = "${value.toString()}"');
          }
        }
      });
      // Also check for points_balance directly in meta (fallback)
      if (metaDynamic.containsKey('points_balance') &&
          metaDynamic['points_balance'] != null &&
          !customFields.containsKey('points_balance')) {
        customFields['points_balance'] =
            metaDynamic['points_balance'].toString();
        print(
            'DEBUG AuthUser.fromJson - Added points_balance from meta: "${metaDynamic['points_balance']}"');
      }
    }

    print('DEBUG AuthUser.fromJson - Final customFields: $customFields');

    var firstName = _trimmedNonEmpty(json['first_name']) ?? '';
    var lastName = _trimmedNonEmpty(json['last_name']) ?? '';
    if (firstName.isEmpty && lastName.isEmpty) {
      firstName = _trimmedNonEmpty(billingMap?['first_name']) ?? '';
      lastName = _trimmedNonEmpty(billingMap?['last_name']) ?? '';
    }
    if (firstName.isEmpty && lastName.isEmpty) {
      final combinedName = _trimmedNonEmpty(json['name']);
      if (combinedName != null) {
        final parts =
            combinedName.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
        final list = parts.toList();
        if (list.length == 1) {
          firstName = list.first;
        } else if (list.isNotEmpty) {
          firstName = list.first;
          lastName = list.sublist(1).join(' ');
        }
      }
    }

    var username = _trimmedNonEmpty(json['username']) ?? '';
    if (username.isEmpty) {
      username = _trimmedNonEmpty(json['nickname']) ??
          _trimmedNonEmpty(json['slug']) ??
          '';
    }

    final email = _trimmedNonEmpty(json['email']) ?? '';

    // Note: Activity status is tracked on backend only, not exposed to app
    // Backend tracks activity for admin purposes but does not send to mobile app

    return AuthUser(
      id: json['id'] ?? 0,
      email: email,
      firstName: firstName,
      lastName: lastName,
      username: username,
      avatar: json['avatar_url'],
      phone: billingMap?['phone'] ?? shippingMap?['phone'] ?? metaPhone,
      billingAddress: _formatAddress(billingMap),
      shippingAddress: _formatAddress(shippingMap),
      dateCreated: json['date_created'] != null &&
              json['date_created'] is String &&
              (json['date_created'] as String).isNotEmpty
          ? DateTime.parse(json['date_created'])
          : null,
      isEmailVerified: json['is_paying_customer'] ?? false,
      roles: json['role'] != null ? [json['role']] : ['customer'],
      billingCity: billingMap?['city'] as String?,
      billingCountry: billingMap?['country'] as String?,
      customFields: customFields,
    );
  }

  static String? _formatAddress(Map<String, dynamic>? address) {
    if (address == null) return null;

    List<String> parts = [];
    if (address['address_1']?.isNotEmpty == true) {
      parts.add(address['address_1']);
    }
    if (address['address_2']?.isNotEmpty == true) {
      parts.add(address['address_2']);
    }
    if (address['city']?.isNotEmpty == true) parts.add(address['city']);
    if (address['state']?.isNotEmpty == true) parts.add(address['state']);
    if (address['postcode']?.isNotEmpty == true) parts.add(address['postcode']);
    if (address['country']?.isNotEmpty == true) parts.add(address['country']);

    return parts.isNotEmpty ? parts.join(', ') : null;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'first_name': firstName,
      'last_name': lastName,
      'username': username,
      'avatar_url': avatar,
      'billing': {
        'phone': phone,
        'city': billingCity,
        'country': billingCountry,
      },
      'shipping': {
        'phone': phone,
      },
      'meta': {
        'billing_phone': phone,
      },
      'date_created': dateCreated?.toIso8601String(),
      'is_paying_customer': isEmailVerified,
      'role': roles.isNotEmpty ? roles.first : 'customer',
      if (customFields.isNotEmpty) 'custom_fields': customFields,
      if (customFields.containsKey('points_balance'))
        'points_balance': customFields['points_balance'],
      if (customFields.containsKey('wallet_balance'))
        'wallet_balance': customFields['wallet_balance'],
    };
  }

  AuthUser copyWith({
    int? id,
    String? email,
    String? firstName,
    String? lastName,
    String? username,
    String? avatar,
    String? phone,
    String? billingAddress,
    String? billingCity,
    String? billingCountry,
    String? shippingAddress,
    DateTime? dateCreated,
    bool? isEmailVerified,
    List<String>? roles,
    Map<String, String>? customFields,
  }) {
    return AuthUser(
      id: id ?? this.id,
      email: email ?? this.email,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      username: username ?? this.username,
      avatar: avatar ?? this.avatar,
      phone: phone, // Allow null values to be set
      billingAddress: billingAddress ?? this.billingAddress,
      billingCity: billingCity ?? this.billingCity,
      billingCountry: billingCountry ?? this.billingCountry,
      shippingAddress: shippingAddress ?? this.shippingAddress,
      dateCreated: dateCreated ?? this.dateCreated,
      isEmailVerified: isEmailVerified ?? this.isEmailVerified,
      roles: roles ?? this.roles,
      customFields: customFields ?? this.customFields,
    );
  }
}
