class WooCommerceOrder {
  final int? id;
  final String status;
  final String currency;
  final String dateCreated;
  final String dateModified;
  final double total;
  final double subtotal;
  final double totalTax;
  final double shippingTotal;
  final double discountTotal;
  final List<WooCommerceOrderItem> lineItems;
  final WooCommerceBillingAddress billing;
  final WooCommerceShippingAddress shipping;
  final WooCommercePaymentDetails paymentDetails;
  final String? customerNote;
  final Map<String, dynamic>? metaData;

  WooCommerceOrder({
    this.id,
    required this.status,
    required this.currency,
    required this.dateCreated,
    required this.dateModified,
    required this.total,
    required this.subtotal,
    required this.totalTax,
    required this.shippingTotal,
    required this.discountTotal,
    required this.lineItems,
    required this.billing,
    required this.shipping,
    required this.paymentDetails,
    this.customerNote,
    this.metaData,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'status': status,
      'currency': currency,
      'date_created': dateCreated,
      'date_modified': dateModified,
      'total': total.toString(),
      'subtotal': subtotal.toString(),
      'total_tax': totalTax.toString(),
      'shipping_total': shippingTotal.toString(),
      'discount_total': discountTotal.toString(),
      'line_items': lineItems.map((item) => item.toJson()).toList(),
      'billing': billing.toJson(),
      'shipping': shipping.toJson(),
      'payment_method': paymentDetails.paymentMethod,
      'payment_method_title': paymentDetails.paymentMethodTitle,
      if (customerNote != null) 'customer_note': customerNote,
    };

    // Add customer_id if available in metadata
    if (metaData != null && metaData!.containsKey('customer_id')) {
      json['customer_id'] = metaData!['customer_id'];
    }

    // Add other metadata (excluding customer_id as it's handled above)
    // WooCommerce allows meta_data to be omitted or an array, but if included must be array
    if (metaData != null && metaData!.isNotEmpty) {
      final otherMetaData = Map<String, dynamic>.from(metaData!)
        ..remove('customer_id');
      if (otherMetaData.isNotEmpty) {
        json['meta_data'] = otherMetaData.entries
            .map((e) => {
                  'key': e.key,
                  'value': e.value,
                })
            .toList();
      }
      // If only customer_id was in metadata, don't include meta_data (it's optional at order level)
    }

    return json;
  }

  factory WooCommerceOrder.fromJson(Map<String, dynamic> json) {
    return WooCommerceOrder(
      id: json['id'],
      status: json['status'] ?? 'pending',
      currency: json['currency'] ?? 'USD',
      dateCreated: json['date_created'] ?? DateTime.now().toIso8601String(),
      dateModified: json['date_modified'] ?? DateTime.now().toIso8601String(),
      total: double.tryParse(json['total']?.toString() ?? '0') ?? 0.0,
      subtotal: double.tryParse(json['subtotal']?.toString() ?? '0') ?? 0.0,
      totalTax: double.tryParse(json['total_tax']?.toString() ?? '0') ?? 0.0,
      shippingTotal:
          double.tryParse(json['shipping_total']?.toString() ?? '0') ?? 0.0,
      discountTotal:
          double.tryParse(json['discount_total']?.toString() ?? '0') ?? 0.0,
      lineItems: (json['line_items'] as List<dynamic>?)
              ?.map((item) => WooCommerceOrderItem.fromJson(item))
              .toList() ??
          [],
      billing: WooCommerceBillingAddress.fromJson(json['billing'] ?? {}),
      shipping: WooCommerceShippingAddress.fromJson(json['shipping'] ?? {}),
      paymentDetails: WooCommercePaymentDetails.fromJson(json),
      customerNote: json['customer_note'],
      metaData: json['meta_data'] != null && json['meta_data'] is Map
          ? Map<String, dynamic>.from(json['meta_data'])
          : null,
    );
  }
}

class WooCommerceOrderItem {
  final int? id;
  final String name;
  final int productId;
  final int variationId;
  final int quantity;
  final String taxClass;
  final double subtotal;
  final double subtotalTax;
  final double total;
  final double totalTax;
  final String? sku;
  final double price;
  final Map<String, dynamic>? metaData;

  WooCommerceOrderItem({
    this.id,
    required this.name,
    required this.productId,
    this.variationId = 0,
    required this.quantity,
    this.taxClass = '',
    required this.subtotal,
    required this.subtotalTax,
    required this.total,
    required this.totalTax,
    this.sku,
    required this.price,
    this.metaData,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'name': name,
      'product_id': productId,
      'variation_id': variationId,
      'quantity': quantity,
      'tax_class': taxClass,
      'subtotal': subtotal.toString(),
      'subtotal_tax': subtotalTax.toString(),
      'total': total.toString(),
      'total_tax': totalTax.toString(),
      'sku': sku ?? '', // Ensure SKU is always a string, never null
      'price': price.toString(),
    };

    // WooCommerce requires meta_data to be an array, not null
    // If metaData is null or empty, send empty array
    if (metaData != null && metaData!.isNotEmpty) {
      json['meta_data'] = metaData!.entries
          .map((e) => {
                'key': e.key,
                'value': e.value,
              })
          .toList();
    } else {
      // Send empty array instead of null to satisfy WooCommerce API requirements
      json['meta_data'] = <Map<String, dynamic>>[];
    }

    return json;
  }

  factory WooCommerceOrderItem.fromJson(Map<String, dynamic> json) {
    return WooCommerceOrderItem(
      id: json['id'],
      name: json['name'] ?? '',
      productId: json['product_id'] ?? 0,
      variationId: json['variation_id'] ?? 0,
      quantity: json['quantity'] ?? 0,
      taxClass: json['tax_class'] ?? '',
      subtotal: double.tryParse(json['subtotal']?.toString() ?? '0') ?? 0.0,
      subtotalTax:
          double.tryParse(json['subtotal_tax']?.toString() ?? '0') ?? 0.0,
      total: double.tryParse(json['total']?.toString() ?? '0') ?? 0.0,
      totalTax: double.tryParse(json['total_tax']?.toString() ?? '0') ?? 0.0,
      sku: json['sku'],
      price: double.tryParse(json['price']?.toString() ?? '0') ?? 0.0,
      metaData: json['meta_data'] != null && json['meta_data'] is Map
          ? Map<String, dynamic>.from(json['meta_data'])
          : null,
    );
  }
}

class WooCommerceBillingAddress {
  final String firstName;
  final String lastName;
  final String company;
  final String address1;
  final String address2;
  final String city;
  final String state;
  final String postcode;
  final String country;
  final String email;
  final String phone;

  WooCommerceBillingAddress({
    required this.firstName,
    required this.lastName,
    this.company = '',
    required this.address1,
    this.address2 = '',
    required this.city,
    required this.state,
    required this.postcode,
    required this.country,
    required this.email,
    required this.phone,
  });

  Map<String, dynamic> toJson() {
    return {
      'first_name': firstName,
      'last_name': lastName,
      'company': company,
      'address_1': address1,
      'address_2': address2,
      'city': city,
      'state': state,
      'postcode': postcode,
      'country': country,
      'email': email,
      'phone': phone,
    };
  }

  factory WooCommerceBillingAddress.fromJson(Map<String, dynamic> json) {
    return WooCommerceBillingAddress(
      firstName: json['first_name'] ?? '',
      lastName: json['last_name'] ?? '',
      company: json['company'] ?? '',
      address1: json['address_1'] ?? '',
      address2: json['address_2'] ?? '',
      city: json['city'] ?? '',
      state: json['state'] ?? '',
      postcode: json['postcode'] ?? '',
      country: json['country'] ?? 'US',
      email: json['email'] ?? '',
      phone: json['phone'] ?? '',
    );
  }
}

class WooCommerceShippingAddress {
  final String firstName;
  final String lastName;
  final String company;
  final String address1;
  final String address2;
  final String city;
  final String state;
  final String postcode;
  final String country;

  WooCommerceShippingAddress({
    required this.firstName,
    required this.lastName,
    this.company = '',
    required this.address1,
    this.address2 = '',
    required this.city,
    required this.state,
    required this.postcode,
    required this.country,
  });

  Map<String, dynamic> toJson() {
    return {
      'first_name': firstName,
      'last_name': lastName,
      'company': company,
      'address_1': address1,
      'address_2': address2,
      'city': city,
      'state': state,
      'postcode': postcode,
      'country': country,
    };
  }

  factory WooCommerceShippingAddress.fromJson(Map<String, dynamic> json) {
    return WooCommerceShippingAddress(
      firstName: json['first_name'] ?? '',
      lastName: json['last_name'] ?? '',
      company: json['company'] ?? '',
      address1: json['address_1'] ?? '',
      address2: json['address_2'] ?? '',
      city: json['city'] ?? '',
      state: json['state'] ?? '',
      postcode: json['postcode'] ?? '',
      country: json['country'] ?? 'US',
    );
  }
}

class WooCommercePaymentDetails {
  final String paymentMethod;
  final String paymentMethodTitle;
  final bool paid;

  WooCommercePaymentDetails({
    required this.paymentMethod,
    required this.paymentMethodTitle,
    this.paid = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'payment_method': paymentMethod,
      'payment_method_title': paymentMethodTitle,
      'paid': paid,
    };
  }

  factory WooCommercePaymentDetails.fromJson(Map<String, dynamic> json) {
    return WooCommercePaymentDetails(
      paymentMethod: json['payment_method'] ?? 'cod',
      paymentMethodTitle: json['payment_method_title'] ?? 'Cash on Delivery',
      paid: json['paid'] ?? false,
    );
  }
}
