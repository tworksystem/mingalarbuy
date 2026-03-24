import 'package:ecommerce_int2/models/product.dart';

class WishlistItem {
  final String id;
  final String userId;
  final Product product;
  final DateTime addedAt;
  final String? notes;
  final Map<String, dynamic>? metadata;

  WishlistItem({
    required this.id,
    required this.userId,
    required this.product,
    required this.addedAt,
    this.notes,
    this.metadata,
  });

  // Get formatted date
  String get formattedDate {
    final now = DateTime.now();
    final difference = now.difference(addedAt);

    if (difference.inDays > 365) {
      final years = (difference.inDays / 365).floor();
      return '$years year${years > 1 ? 's' : ''} ago';
    } else if (difference.inDays > 30) {
      final months = (difference.inDays / 30).floor();
      return '$months month${months > 1 ? 's' : ''} ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
    } else {
      return 'Just now';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'product': {
        'image': product.image,
        'name': product.name,
        'description': product.description,
        'price': product.price,
      },
      'addedAt': addedAt.toIso8601String(),
      'notes': notes,
      'metadata': metadata,
    };
  }

  factory WishlistItem.fromJson(Map<String, dynamic> json) {
    final productData = json['product'] as Map<String, dynamic>;
    final product = Product(
      productData['image'],
      productData['name'],
      productData['description'],
      productData['price'].toDouble(),
    );

    return WishlistItem(
      id: json['id'],
      userId: json['userId'],
      product: product,
      addedAt: DateTime.parse(json['addedAt']),
      notes: json['notes'],
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'])
          : null,
    );
  }

  WishlistItem copyWith({
    String? id,
    String? userId,
    Product? product,
    DateTime? addedAt,
    String? notes,
    Map<String, dynamic>? metadata,
  }) {
    return WishlistItem(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      product: product ?? this.product,
      addedAt: addedAt ?? this.addedAt,
      notes: notes ?? this.notes,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WishlistItem &&
        other.id == id &&
        other.userId == userId &&
        other.product.name == product.name &&
        other.product.price == product.price;
  }

  @override
  int get hashCode => id.hashCode ^ userId.hashCode ^ product.name.hashCode;

  @override
  String toString() {
    return 'WishlistItem(id: $id, product: ${product.name}, addedAt: $addedAt)';
  }
}
