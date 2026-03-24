enum AddressType {
  home,
  work,
  other,
}

class Address {
  final String id;
  final String userId;
  final String firstName;
  final String lastName;
  final String company;
  final String addressLine1;
  final String addressLine2;
  final String city;
  final String state;
  final String postalCode;
  final String country;
  final String phone;
  final String email;
  final AddressType type;
  final bool isDefault;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? notes;
  final Map<String, dynamic>? metadata;

  Address({
    required this.id,
    required this.userId,
    required this.firstName,
    required this.lastName,
    required this.addressLine1,
    required this.city,
    required this.state,
    required this.postalCode,
    required this.country,
    required this.phone,
    this.company = '',
    this.addressLine2 = '',
    this.email = '',
    this.type = AddressType.home,
    this.isDefault = false,
    required this.createdAt,
    this.updatedAt,
    this.notes,
    this.metadata,
  });

  // Get full name
  String get fullName => '$firstName $lastName';

  // Get formatted address
  String get formattedAddress {
    String address = addressLine1;
    if (addressLine2.isNotEmpty) {
      address += ', $addressLine2';
    }
    address += ', $city, $state $postalCode, $country';
    return address;
  }

  // Get short address for display
  String get shortAddress {
    return '$city, $state';
  }

  // Get complete address for shipping
  String get completeAddress {
    String address = '$fullName\n';
    if (company.isNotEmpty) {
      address += '$company\n';
    }
    address += addressLine1;
    if (addressLine2.isNotEmpty) {
      address += '\n$addressLine2';
    }
    address += '\n$city, $state $postalCode\n$country';
    if (phone.isNotEmpty) {
      address += '\nPhone: $phone';
    }
    if (email.isNotEmpty) {
      address += '\nEmail: $email';
    }
    return address;
  }

  // Get address type display text
  String get typeText {
    switch (type) {
      case AddressType.home:
        return 'Home';
      case AddressType.work:
        return 'Work';
      case AddressType.other:
        return 'Other';
    }
  }

  // Validate address
  bool get isValid {
    return firstName.isNotEmpty &&
        lastName.isNotEmpty &&
        addressLine1.isNotEmpty &&
        city.isNotEmpty &&
        state.isNotEmpty &&
        postalCode.isNotEmpty &&
        country.isNotEmpty &&
        phone.isNotEmpty;
  }

  // Get validation errors
  List<String> get validationErrors {
    List<String> errors = [];
    if (firstName.isEmpty) errors.add('First name is required');
    if (lastName.isEmpty) errors.add('Last name is required');
    if (addressLine1.isEmpty) errors.add('Address line 1 is required');
    if (city.isEmpty) errors.add('City is required');
    if (state.isEmpty) errors.add('State is required');
    if (postalCode.isEmpty) errors.add('Postal code is required');
    if (country.isEmpty) errors.add('Country is required');
    if (phone.isEmpty) errors.add('Phone number is required');
    return errors;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'firstName': firstName,
      'lastName': lastName,
      'company': company,
      'addressLine1': addressLine1,
      'addressLine2': addressLine2,
      'city': city,
      'state': state,
      'postalCode': postalCode,
      'country': country,
      'phone': phone,
      'email': email,
      'type': type.name,
      'isDefault': isDefault,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'notes': notes,
      'metadata': metadata,
    };
  }

  factory Address.fromJson(Map<String, dynamic> json) {
    return Address(
      id: json['id'],
      userId: json['userId'],
      firstName: json['firstName'],
      lastName: json['lastName'],
      company: json['company'] ?? '',
      addressLine1: json['addressLine1'],
      addressLine2: json['addressLine2'] ?? '',
      city: json['city'],
      state: json['state'],
      postalCode: json['postalCode'],
      country: json['country'],
      phone: json['phone'],
      email: json['email'] ?? '',
      type: AddressType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => AddressType.home,
      ),
      isDefault: json['isDefault'] ?? false,
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt:
          json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
      notes: json['notes'],
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'])
          : null,
    );
  }

  Address copyWith({
    String? id,
    String? userId,
    String? firstName,
    String? lastName,
    String? company,
    String? addressLine1,
    String? addressLine2,
    String? city,
    String? state,
    String? postalCode,
    String? country,
    String? phone,
    String? email,
    AddressType? type,
    bool? isDefault,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? notes,
    Map<String, dynamic>? metadata,
  }) {
    return Address(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      company: company ?? this.company,
      addressLine1: addressLine1 ?? this.addressLine1,
      addressLine2: addressLine2 ?? this.addressLine2,
      city: city ?? this.city,
      state: state ?? this.state,
      postalCode: postalCode ?? this.postalCode,
      country: country ?? this.country,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      type: type ?? this.type,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      notes: notes ?? this.notes,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Address &&
        other.id == id &&
        other.userId == userId &&
        other.firstName == firstName &&
        other.lastName == lastName &&
        other.addressLine1 == addressLine1 &&
        other.city == city &&
        other.state == state &&
        other.postalCode == postalCode &&
        other.country == country;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        userId.hashCode ^
        firstName.hashCode ^
        lastName.hashCode ^
        addressLine1.hashCode ^
        city.hashCode ^
        state.hashCode ^
        postalCode.hashCode ^
        country.hashCode;
  }

  @override
  String toString() {
    return 'Address(id: $id, fullName: $fullName, city: $city, state: $state)';
  }
}
