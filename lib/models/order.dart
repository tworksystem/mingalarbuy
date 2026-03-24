import 'package:ecommerce_int2/models/product.dart';
import 'package:ecommerce_int2/models/address.dart';
import 'package:ecommerce_int2/utils/json_parser_helper.dart';

enum OrderStatus {
  pending,
  confirmed,
  processing,
  shipped,
  delivered,
  cancelled,
  refunded,
}

enum PaymentStatus {
  pending,
  paid,
  failed,
  refunded,
}

enum PaymentMethod {
  creditCard,
  debitCard,
  mobilePayment,
  bankTransfer,
  cashOnDelivery,
}

class OrderItem {
  final Product product;
  final int quantity;
  final double unitPrice;
  final double totalPrice;

  OrderItem({
    required this.product,
    required this.quantity,
    required this.unitPrice,
  }) : totalPrice = unitPrice * quantity;

  // Get formatted total price
  String get formattedTotalPrice => '${totalPrice.toStringAsFixed(2)} Ks';

  Map<String, dynamic> toJson() {
    return {
      'product': {
        'image': product.image,
        'name': product.name,
        'description': product.description,
        'price': product.price,
      },
      'quantity': quantity,
      'unitPrice': unitPrice,
      'totalPrice': totalPrice,
    };
  }

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    final productData = json['product'] as Map<String, dynamic>;
    final product = Product(
      JsonParserHelper.safeParseString(productData['image']),
      JsonParserHelper.safeParseString(productData['name']),
      JsonParserHelper.safeParseString(productData['description']),
      JsonParserHelper.safeParseDouble(productData['price']),
    );

    return OrderItem(
      product: product,
      quantity: JsonParserHelper.safeParseInt(json['quantity']),
      unitPrice: JsonParserHelper.safeParseDouble(json['unitPrice']),
    );
  }
}

class Order {
  final String id;
  final String userId;
  final List<OrderItem> items;
  final Address shippingAddress;
  final Address billingAddress;
  final double subtotal;
  final double shippingCost;
  final double tax;
  final double discount;
  final double total;
  final OrderStatus status;
  final PaymentStatus paymentStatus;
  final PaymentMethod paymentMethod;
  final String? paymentId;
  final String? trackingNumber;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? shippedAt;
  final DateTime? deliveredAt;
  final String? notes;
  final Map<String, dynamic>? metadata;

  Order({
    required this.id,
    required this.userId,
    required this.items,
    required this.shippingAddress,
    required this.billingAddress,
    required this.subtotal,
    required this.shippingCost,
    required this.tax,
    required this.discount,
    required this.total,
    required this.status,
    required this.paymentStatus,
    required this.paymentMethod,
    this.paymentId,
    this.trackingNumber,
    required this.createdAt,
    this.updatedAt,
    this.shippedAt,
    this.deliveredAt,
    this.notes,
    this.metadata,
  });

  // Calculate total items count
  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);

  // Get formatted total price
  String get formattedTotal => '${total.toStringAsFixed(2)} Ks';

  // Get formatted subtotal
  String get formattedSubtotal => '${subtotal.toStringAsFixed(2)} Ks';

  // Get status display text
  String get statusText {
    switch (status) {
      case OrderStatus.pending:
        return 'Pending';
      case OrderStatus.confirmed:
        return 'Confirmed';
      case OrderStatus.processing:
        return 'Processing';
      case OrderStatus.shipped:
        return 'Shipped';
      case OrderStatus.delivered:
        return 'Delivered';
      case OrderStatus.cancelled:
        return 'Cancelled';
      case OrderStatus.refunded:
        return 'Refunded';
    }
  }

  // Get payment status display text
  String get paymentStatusText {
    switch (paymentStatus) {
      case PaymentStatus.pending:
        return 'Payment Pending';
      case PaymentStatus.paid:
        return 'Paid';
      case PaymentStatus.failed:
        return 'Payment Failed';
      case PaymentStatus.refunded:
        return 'Refunded';
    }
  }

  // Get payment method display text
  String get paymentMethodText {
    switch (paymentMethod) {
      case PaymentMethod.creditCard:
        return 'Credit Card';
      case PaymentMethod.debitCard:
        return 'Debit Card';
      case PaymentMethod.mobilePayment:
        return 'Mobile Payment';
      case PaymentMethod.bankTransfer:
        return 'Bank Transfer';
      case PaymentMethod.cashOnDelivery:
        return 'Cash on Delivery';
    }
  }

  // Check if order can be cancelled
  bool get canCancel =>
      status == OrderStatus.pending || status == OrderStatus.confirmed;

  // Check if order is completed
  bool get isCompleted => status == OrderStatus.delivered;

  // Check if order is active
  bool get isActive => !isCompleted && status != OrderStatus.cancelled;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'items': items.map((item) => item.toJson()).toList(),
      'shippingAddress': shippingAddress.toJson(),
      'billingAddress': billingAddress.toJson(),
      'subtotal': subtotal,
      'shippingCost': shippingCost,
      'tax': tax,
      'discount': discount,
      'total': total,
      'status': status.name,
      'paymentStatus': paymentStatus.name,
      'paymentMethod': paymentMethod.name,
      'paymentId': paymentId,
      'trackingNumber': trackingNumber,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'shippedAt': shippedAt?.toIso8601String(),
      'deliveredAt': deliveredAt?.toIso8601String(),
      'notes': notes,
      'metadata': metadata,
    };
  }

  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      id: json['id'],
      userId: json['userId'],
      items: (json['items'] as List)
          .map((item) => OrderItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      shippingAddress:
          Address.fromJson(json['shippingAddress'] as Map<String, dynamic>),
      billingAddress:
          Address.fromJson(json['billingAddress'] as Map<String, dynamic>),
      subtotal: JsonParserHelper.safeParseDouble(json['subtotal']),
      shippingCost: JsonParserHelper.safeParseDouble(json['shippingCost']),
      tax: JsonParserHelper.safeParseDouble(json['tax']),
      discount: JsonParserHelper.safeParseDouble(json['discount']),
      total: JsonParserHelper.safeParseDouble(json['total']),
      status: OrderStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => OrderStatus.pending,
      ),
      paymentStatus: PaymentStatus.values.firstWhere(
        (e) => e.name == json['paymentStatus'],
        orElse: () => PaymentStatus.pending,
      ),
      paymentMethod: PaymentMethod.values.firstWhere(
        (e) => e.name == json['paymentMethod'],
        orElse: () => PaymentMethod.cashOnDelivery,
      ),
      paymentId: json['paymentId'],
      trackingNumber: json['trackingNumber'],
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt:
          json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
      shippedAt:
          json['shippedAt'] != null ? DateTime.parse(json['shippedAt']) : null,
      deliveredAt: json['deliveredAt'] != null
          ? DateTime.parse(json['deliveredAt'])
          : null,
      notes: json['notes'],
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'])
          : null,
    );
  }

  Order copyWith({
    String? id,
    String? userId,
    List<OrderItem>? items,
    Address? shippingAddress,
    Address? billingAddress,
    double? subtotal,
    double? shippingCost,
    double? tax,
    double? discount,
    double? total,
    OrderStatus? status,
    PaymentStatus? paymentStatus,
    PaymentMethod? paymentMethod,
    String? paymentId,
    String? trackingNumber,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? shippedAt,
    DateTime? deliveredAt,
    String? notes,
    Map<String, dynamic>? metadata,
  }) {
    return Order(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      items: items ?? this.items,
      shippingAddress: shippingAddress ?? this.shippingAddress,
      billingAddress: billingAddress ?? this.billingAddress,
      subtotal: subtotal ?? this.subtotal,
      shippingCost: shippingCost ?? this.shippingCost,
      tax: tax ?? this.tax,
      discount: discount ?? this.discount,
      total: total ?? this.total,
      status: status ?? this.status,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentId: paymentId ?? this.paymentId,
      trackingNumber: trackingNumber ?? this.trackingNumber,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      shippedAt: shippedAt ?? this.shippedAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      notes: notes ?? this.notes,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  String toString() {
    return 'Order(id: $id, status: $status, total: $total, itemCount: $itemCount)';
  }
}
