import 'package:hive/hive.dart';

part 'cached_product.g.dart';

/// Cached Product Model for Hive Storage
/// This is a simplified version optimized for caching
@HiveType(typeId: 0)
class CachedProduct extends HiveObject {
  @HiveField(0)
  final int id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String slug;

  @HiveField(3)
  final String description;

  @HiveField(4)
  final String shortDescription;

  @HiveField(5)
  final String price;

  @HiveField(6)
  final String regularPrice;

  @HiveField(7)
  final String salePrice;

  @HiveField(8)
  final bool onSale;

  @HiveField(9)
  final bool featured;

  @HiveField(10)
  final List<String> imageUrls;

  @HiveField(11)
  final List<String> categoryNames;

  @HiveField(12)
  final double averageRating;

  @HiveField(13)
  final int ratingCount;

  @HiveField(14)
  final int stockQuantity;

  @HiveField(15)
  final String stockStatus;

  @HiveField(16)
  final DateTime cachedAt;

  CachedProduct({
    required this.id,
    required this.name,
    required this.slug,
    required this.description,
    required this.shortDescription,
    required this.price,
    required this.regularPrice,
    required this.salePrice,
    required this.onSale,
    required this.featured,
    required this.imageUrls,
    required this.categoryNames,
    required this.averageRating,
    required this.ratingCount,
    required this.stockQuantity,
    required this.stockStatus,
    required this.cachedAt,
  });

  /// Convert from WooCommerce Product
  factory CachedProduct.fromWooCommerceProduct(dynamic wooProduct) {
    return CachedProduct(
      id: wooProduct.id,
      name: wooProduct.name,
      slug: wooProduct.slug,
      description: wooProduct.description,
      shortDescription: wooProduct.shortDescription,
      price: wooProduct.price,
      regularPrice: wooProduct.regularPrice,
      salePrice: wooProduct.salePrice,
      onSale: wooProduct.onSale,
      featured: wooProduct.featured,
      imageUrls:
          wooProduct.images.map<String>((img) => img.src as String).toList(),
      categoryNames: wooProduct.categories
          .map<String>((cat) => cat.name as String)
          .toList(),
      averageRating: wooProduct.averageRating,
      ratingCount: wooProduct.ratingCount,
      stockQuantity: wooProduct.stockQuantity,
      stockStatus: wooProduct.stockStatus,
      cachedAt: DateTime.now(),
    );
  }

  /// Convert to Map for JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'slug': slug,
      'description': description,
      'short_description': shortDescription,
      'price': price,
      'regular_price': regularPrice,
      'sale_price': salePrice,
      'on_sale': onSale,
      'featured': featured,
      'images': imageUrls.map((url) => {'src': url}).toList(),
      'categories': categoryNames.map((name) => {'name': name}).toList(),
      'average_rating': averageRating.toString(),
      'rating_count': ratingCount,
      'stock_quantity': stockQuantity,
      'stock_status': stockStatus,
    };
  }

  /// Check if cache is expired (default 24 hours)
  bool isExpired({Duration maxAge = const Duration(hours: 24)}) {
    return DateTime.now().difference(cachedAt) > maxAge;
  }
}

/// Cache Metadata Model
@HiveType(typeId: 1)
class CacheMetadata extends HiveObject {
  @override
  @HiveField(0)
  final String key;

  @HiveField(1)
  final DateTime lastUpdated;

  @HiveField(2)
  final int itemCount;

  CacheMetadata({
    required this.key,
    required this.lastUpdated,
    required this.itemCount,
  });
}
