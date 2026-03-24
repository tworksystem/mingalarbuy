import 'package:ecommerce_int2/utils/price_formatter.dart';

import 'product.dart';

class CartItem {
  final Product product;
  int quantity;
  final DateTime addedAt;

  CartItem({
    required this.product,
    this.quantity = 1,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  // Calculate total price for this cart item
  double get totalPrice => product.price * quantity;

  // Get formatted total price
  String get formattedTotalPrice => PriceFormatter.format(totalPrice);

  // Create a copy with updated quantity
  CartItem copyWith({
    Product? product,
    int? quantity,
    DateTime? addedAt,
  }) {
    return CartItem(
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  // Convert to JSON for persistence
  Map<String, dynamic> toJson() => {
        'product': product.toJson(),
        'quantity': quantity,
        'addedAt': addedAt.toIso8601String(),
      };

  // Create from JSON
  factory CartItem.fromJson(Map<String, dynamic> json) {
    final productData = json['product'] as Map<String, dynamic>;
    final product = Product.fromJson(productData);

    return CartItem(
      product: product,
      quantity: json['quantity'],
      addedAt: DateTime.parse(json['addedAt']),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CartItem &&
        other.product.name == product.name &&
        other.product.price == product.price;
  }

  @override
  int get hashCode => product.name.hashCode ^ product.price.hashCode;

  @override
  String toString() {
    return 'CartItem(product: ${product.name}, quantity: $quantity)';
  }
}
