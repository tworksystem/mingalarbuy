import 'package:ecommerce_int2/utils/price_formatter.dart';
import 'package:ecommerce_int2/utils/json_parser_helper.dart';

import 'product.dart';

class WooCommerceProduct {
  final int id;
  final String name;
  final String slug;
  final String permalink;
  final String dateCreated;
  final String dateModified;
  final String type;
  final String status;
  final bool featured;
  final String catalogVisibility;
  final String description;
  final String shortDescription;
  final String sku;
  final String price;
  final String regularPrice;
  final String salePrice;
  final bool onSale;
  final bool purchasable;
  final int totalSales;
  final bool virtual;
  final bool downloadable;
  final String taxStatus;
  final String taxClass;
  final bool manageStock;
  final int? stockQuantity;
  final String backorders;
  final bool backordersAllowed;
  final bool backordered;
  final bool soldIndividually;
  final String weight;
  final Dimensions dimensions;
  final bool shippingRequired;
  final bool shippingTaxable;
  final String shippingClass;
  final int shippingClassId;
  final bool reviewsAllowed;
  final String averageRating;
  final int ratingCount;
  final List<int> upsellIds;
  final List<int> crossSellIds;
  final int parentId;
  final String purchaseNote;
  final List<Category> categories;
  final List<dynamic> brands;
  final List<dynamic> tags;
  final List<WooCommerceImage> images;
  final List<dynamic> attributes;
  final List<dynamic> defaultAttributes;
  final List<dynamic> variations;
  final List<dynamic> groupedProducts;
  final int menuOrder;
  final String priceHtml;
  final List<int> relatedIds;
  final List<MetaData> metaData;
  final String stockStatus;
  final bool hasOptions;
  final String postPassword;
  final String globalUniqueId;

  WooCommerceProduct({
    required this.id,
    required this.name,
    required this.slug,
    required this.permalink,
    required this.dateCreated,
    required this.dateModified,
    required this.type,
    required this.status,
    required this.featured,
    required this.catalogVisibility,
    required this.description,
    required this.shortDescription,
    required this.sku,
    required this.price,
    required this.regularPrice,
    required this.salePrice,
    required this.onSale,
    required this.purchasable,
    required this.totalSales,
    required this.virtual,
    required this.downloadable,
    required this.taxStatus,
    required this.taxClass,
    required this.manageStock,
    this.stockQuantity,
    required this.backorders,
    required this.backordersAllowed,
    required this.backordered,
    required this.soldIndividually,
    required this.weight,
    required this.dimensions,
    required this.shippingRequired,
    required this.shippingTaxable,
    required this.shippingClass,
    required this.shippingClassId,
    required this.reviewsAllowed,
    required this.averageRating,
    required this.ratingCount,
    required this.upsellIds,
    required this.crossSellIds,
    required this.parentId,
    required this.purchaseNote,
    required this.categories,
    required this.brands,
    required this.tags,
    required this.images,
    required this.attributes,
    required this.defaultAttributes,
    required this.variations,
    required this.groupedProducts,
    required this.menuOrder,
    required this.priceHtml,
    required this.relatedIds,
    required this.metaData,
    required this.stockStatus,
    required this.hasOptions,
    required this.postPassword,
    required this.globalUniqueId,
  });

  factory WooCommerceProduct.fromJson(Map<String, dynamic> json) {
    // Professional safe parsing with type coercion
    // Handles cases where API returns String instead of num or vice versa
    return WooCommerceProduct(
      id: JsonParserHelper.safeParseInt(json['id']),
      name: JsonParserHelper.safeParseString(json['name']),
      slug: JsonParserHelper.safeParseString(json['slug']),
      permalink: JsonParserHelper.safeParseString(json['permalink']),
      dateCreated: JsonParserHelper.safeParseString(json['date_created']),
      dateModified: JsonParserHelper.safeParseString(json['date_modified']),
      type: JsonParserHelper.safeParseString(json['type']),
      status: JsonParserHelper.safeParseString(json['status']),
      featured: JsonParserHelper.safeParseBool(json['featured']),
      catalogVisibility: JsonParserHelper.safeParseString(json['catalog_visibility']),
      description: JsonParserHelper.safeParseString(json['description']),
      shortDescription: JsonParserHelper.safeParseString(json['short_description']),
      sku: JsonParserHelper.safeParseString(json['sku']),
      price: JsonParserHelper.safeParseString(json['price']),
      regularPrice: JsonParserHelper.safeParseString(json['regular_price']),
      salePrice: JsonParserHelper.safeParseString(json['sale_price']),
      onSale: JsonParserHelper.safeParseBool(json['on_sale']),
      purchasable: JsonParserHelper.safeParseBool(json['purchasable']),
      totalSales: JsonParserHelper.safeParseInt(json['total_sales']),
      virtual: JsonParserHelper.safeParseBool(json['virtual']),
      downloadable: JsonParserHelper.safeParseBool(json['downloadable']),
      taxStatus: JsonParserHelper.safeParseString(json['tax_status']),
      taxClass: JsonParserHelper.safeParseString(json['tax_class']),
      manageStock: JsonParserHelper.safeParseBool(json['manage_stock']),
      stockQuantity: JsonParserHelper.safeParseIntNullable(json['stock_quantity']),
      backorders: JsonParserHelper.safeParseString(json['backorders']),
      backordersAllowed: JsonParserHelper.safeParseBool(json['backorders_allowed']),
      backordered: JsonParserHelper.safeParseBool(json['backordered']),
      soldIndividually: JsonParserHelper.safeParseBool(json['sold_individually']),
      weight: JsonParserHelper.safeParseString(json['weight']),
      dimensions: Dimensions.fromJson(json['dimensions'] ?? {}),
      shippingRequired: JsonParserHelper.safeParseBool(json['shipping_required']),
      shippingTaxable: JsonParserHelper.safeParseBool(json['shipping_taxable']),
      shippingClass: JsonParserHelper.safeParseString(json['shipping_class']),
      shippingClassId: JsonParserHelper.safeParseInt(json['shipping_class_id']),
      reviewsAllowed: JsonParserHelper.safeParseBool(json['reviews_allowed']),
      averageRating: JsonParserHelper.safeParseString(json['average_rating'], defaultValue: '0.00'),
      ratingCount: JsonParserHelper.safeParseInt(json['rating_count']),
      upsellIds: JsonParserHelper.safeParseIntList(json['upsell_ids']),
      crossSellIds: JsonParserHelper.safeParseIntList(json['cross_sell_ids']),
      parentId: JsonParserHelper.safeParseInt(json['parent_id']),
      purchaseNote: JsonParserHelper.safeParseString(json['purchase_note']),
      categories: (json['categories'] as List?)
              ?.map((x) => Category.fromJson(x))
              .toList() ??
          [],
      brands: json['brands'] ?? [],
      tags: json['tags'] ?? [],
      images: (json['images'] as List?)
              ?.map((x) => WooCommerceImage.fromJson(x))
              .toList() ??
          [],
      attributes: json['attributes'] ?? [],
      defaultAttributes: json['default_attributes'] ?? [],
      variations: json['variations'] ?? [],
      groupedProducts: json['grouped_products'] ?? [],
      menuOrder: JsonParserHelper.safeParseInt(json['menu_order']),
      priceHtml: JsonParserHelper.safeParseString(json['price_html']),
      relatedIds: JsonParserHelper.safeParseIntList(json['related_ids']),
      metaData: (json['meta_data'] as List?)
              ?.map((x) => MetaData.fromJson(x))
              .toList() ??
          [],
      stockStatus: JsonParserHelper.safeParseString(json['stock_status']),
      hasOptions: JsonParserHelper.safeParseBool(json['has_options']),
      postPassword: JsonParserHelper.safeParseString(json['post_password']),
      globalUniqueId: JsonParserHelper.safeParseString(json['global_unique_id']),
    );
  }

  // Helper method to get display price
  String get displayPrice {
    if (onSale && salePrice.isNotEmpty) {
      return salePrice;
    } else if (regularPrice.isNotEmpty) {
      return regularPrice;
    } else if (price.isNotEmpty) {
      return price;
    }
    return '0.00';
  }

  // Helper method to get formatted price
  String get formattedPrice => PriceFormatter.formatFromString(displayPrice);

  // Helper method to get first image URL
  String get firstImageUrl {
    if (images.isNotEmpty) {
      return images.first.src;
    }
    return ''; // Return empty string if no images
  }

  // Alias for firstImageUrl for compatibility
  String get imageUrl => firstImageUrl;

  // Get formatted regular price
  String get formattedRegularPrice => PriceFormatter.formatFromString(regularPrice.isNotEmpty ? regularPrice : price);

  // Calculate discount percentage
  double get discountPercentage {
    if (!onSale || regularPrice.isEmpty || salePrice.isEmpty) {
      return 0.0;
    }
    try {
      final regular = double.tryParse(regularPrice) ?? 0.0;
      final sale = double.tryParse(salePrice) ?? 0.0;
      if (regular > 0) {
        return ((regular - sale) / regular * 100).roundToDouble();
      }
    } catch (e) {
      // Ignore parsing errors
    }
    return 0.0;
  }

  // Get rating value as double
  double get ratingValue {
    try {
      return double.tryParse(averageRating) ?? 0.0;
    } catch (e) {
      return 0.0;
    }
  }

  // Check if product is in stock
  bool get inStock {
    if (stockStatus == 'instock') return true;
    if (stockStatus == 'outofstock') return false;
    // Check stock quantity if available
    if (stockQuantity != null) {
      return stockQuantity! > 0;
    }
    // Default to true if status is not explicitly out of stock
    return stockStatus != 'outofstock';
  }

  // Helper method to get clean description
  String get cleanDescription {
    // Remove HTML tags and clean up the description
    String cleanDesc = description
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .trim();

    if (cleanDesc.isEmpty && shortDescription.isNotEmpty) {
      cleanDesc = shortDescription
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .replaceAll('&nbsp;', ' ')
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&quot;', '"')
          .trim();
    }

    return cleanDesc.isEmpty ? 'No description available' : cleanDesc;
  }

  // Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'slug': slug,
      'permalink': permalink,
      'date_created': dateCreated,
      'date_modified': dateModified,
      'type': type,
      'status': status,
      'featured': featured,
      'catalog_visibility': catalogVisibility,
      'description': description,
      'short_description': shortDescription,
      'sku': sku,
      'price': price,
      'regular_price': regularPrice,
      'sale_price': salePrice,
      'on_sale': onSale,
      'purchasable': purchasable,
      'total_sales': totalSales,
      'virtual': virtual,
      'downloadable': downloadable,
      'tax_status': taxStatus,
      'tax_class': taxClass,
      'manage_stock': manageStock,
      'stock_quantity': stockQuantity,
      'backorders': backorders,
      'backorders_allowed': backordersAllowed,
      'backordered': backordered,
      'sold_individually': soldIndividually,
      'weight': weight,
      'dimensions': {
        'length': dimensions.length,
        'width': dimensions.width,
        'height': dimensions.height,
      },
      'shipping_required': shippingRequired,
      'shipping_taxable': shippingTaxable,
      'shipping_class': shippingClass,
      'shipping_class_id': shippingClassId,
      'reviews_allowed': reviewsAllowed,
      'average_rating': averageRating,
      'rating_count': ratingCount,
      'upsell_ids': upsellIds,
      'cross_sell_ids': crossSellIds,
      'parent_id': parentId,
      'purchase_note': purchaseNote,
      'categories': categories.map((c) => {'id': c.id, 'name': c.name}).toList(),
      'images': images.map((img) => {'src': img.src, 'alt': img.alt}).toList(),
      'stock_status': stockStatus,
      'price_html': priceHtml,
    };
  }

  // Convert to the existing Product model for compatibility
  Product toProduct() {
    final productImage = firstImageUrl.isNotEmpty
        ? firstImageUrl
        : 'assets/headphones.png'; // Use existing asset as fallback

    final categoryIdList = categories.map((category) => category.id).toList();

    final additionalDetails = <String, dynamic>{
      'permalink': permalink,
      'priceHtml': priceHtml,
      'averageRating': averageRating,
      'ratingCount': ratingCount,
      'stockStatus': stockStatus,
      'type': type,
      'onSale': onSale,
      'currencyPrice': displayPrice,
      'attributes': attributes, // Include attributes for color extraction
      'categoryNames': categories.map((c) => c.name).toList(), // Include category names for title display
    };

    return Product(
      productImage,
      name,
      cleanDescription,
      double.tryParse(displayPrice) ?? 0.0,
      id: id,
      slug: slug,
      categoryIds: categoryIdList,
      extra: additionalDetails,
    );
  }
}

class Dimensions {
  final String length;
  final String width;
  final String height;

  Dimensions({
    required this.length,
    required this.width,
    required this.height,
  });

  factory Dimensions.fromJson(Map<String, dynamic> json) {
    return Dimensions(
      length: JsonParserHelper.safeParseString(json['length']),
      width: JsonParserHelper.safeParseString(json['width']),
      height: JsonParserHelper.safeParseString(json['height']),
    );
  }
}

class Category {
  final int id;
  final String name;
  final String slug;

  Category({
    required this.id,
    required this.name,
    required this.slug,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: JsonParserHelper.safeParseInt(json['id']),
      name: JsonParserHelper.safeParseString(json['name']),
      slug: JsonParserHelper.safeParseString(json['slug']),
    );
  }
}

class WooCommerceImage {
  final int id;
  final String src;
  final String name;
  final String alt;

  WooCommerceImage({
    required this.id,
    required this.src,
    required this.name,
    required this.alt,
  });

  factory WooCommerceImage.fromJson(Map<String, dynamic> json) {
    return WooCommerceImage(
      id: JsonParserHelper.safeParseInt(json['id']),
      src: JsonParserHelper.safeParseString(json['src']),
      name: JsonParserHelper.safeParseString(json['name']),
      alt: JsonParserHelper.safeParseString(json['alt']),
    );
  }
}

class MetaData {
  final int id;
  final String key;
  final dynamic value;

  MetaData({
    required this.id,
    required this.key,
    required this.value,
  });

  factory MetaData.fromJson(Map<String, dynamic> json) {
    return MetaData(
      id: JsonParserHelper.safeParseInt(json['id']),
      key: JsonParserHelper.safeParseString(json['key']),
      value: json['value'],
    );
  }
}
