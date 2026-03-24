import 'package:flutter/material.dart';
import 'category.dart';

/// WooCommerce Category Model
/// Represents a category from WooCommerce API
class WooCommerceCategory {
  final int id;
  final String name;
  final String slug;
  final int? parent;
  final String? description;
  final String? display;
  final WooCommerceCategoryImage? image;
  final int menuOrder;
  final int count;

  WooCommerceCategory({
    required this.id,
    required this.name,
    required this.slug,
    this.parent,
    this.description,
    this.display,
    this.image,
    this.menuOrder = 0,
    this.count = 0,
  });

  /// Create from JSON
  factory WooCommerceCategory.fromJson(Map<String, dynamic> json) {
    return WooCommerceCategory(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      parent: json['parent'] as int?,
      description: json['description'] as String?,
      display: json['display'] as String?,
      image: json['image'] != null
          ? WooCommerceCategoryImage.fromJson(json['image'] as Map<String, dynamic>)
          : null,
      menuOrder: json['menu_order'] as int? ?? 0,
      count: json['count'] as int? ?? 0,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'slug': slug,
      'parent': parent,
      'description': description,
      'display': display,
      'image': image?.toJson(),
      'menu_order': menuOrder,
      'count': count,
    };
  }

  /// Convert to app Category model
  Category toCategory({Color? begin, Color? end}) {
    // Use provided colors or generate from category name
    final colors = begin != null && end != null
        ? [begin, end]
        : _generateColorsFromName(name);
    
    return Category(
      colors[0],
      colors[1],
      name,
      image?.src ?? 'assets/jeans_5.png', // Fallback to default image
      id: id,
      slug: slug,
      description: description,
      productCount: count,
    );
  }

  /// Generate consistent colors from category name
  List<Color> _generateColorsFromName(String name) {
    // Create a hash from the name to generate consistent colors
    int hash = name.hashCode;
    
    // Predefined color palette for gradients
    final colorPairs = [
      [Color(0xffFCE183), Color(0xffF68D7F)], // Yellow to Coral
      [Color(0xffF749A2), Color(0xffFF7375)], // Pink to Red
      [Color(0xff00E9DA), Color(0xff5189EA)], // Cyan to Blue
      [Color(0xffAF2D68), Color(0xff632376)], // Pink to Purple
      [Color(0xff36E892), Color(0xff33B2B9)], // Green to Teal
      [Color(0xffF123C4), Color(0xff668CEA)], // Pink to Blue
      [Color(0xffFF6B6B), Color(0xff4ECDC4)], // Red to Teal
      [Color(0xff95E1D3), Color(0xffF38181)], // Mint to Coral
      [Color(0xffA8E6CF), Color(0xffFFD3B6)], // Mint to Peach
      [Color(0xffFFAAA5), Color(0xffFFD3A5)], // Coral to Peach
      [Color(0xffA8CABA), Color(0xff5D4E75)], // Mint to Purple
      [Color(0xffFFB6B9), Color(0xffFEC8C8)], // Light Pink
      [Color(0xffB5EAEA), Color(0xffEDF6E5)], // Light Blue to Mint
      [Color(0xffFFBCBC), Color(0xffFFEAA7)], // Pink to Yellow
      [Color(0xffDDA15E), Color(0xffBC6C25)], // Orange
    ];
    
    // Use hash to select a color pair consistently
    final index = hash.abs() % colorPairs.length;
    return colorPairs[index];
  }
}

/// WooCommerce Category Image Model
class WooCommerceCategoryImage {
  final int id;
  final String src;
  final String? name;
  final String? alt;

  WooCommerceCategoryImage({
    required this.id,
    required this.src,
    this.name,
    this.alt,
  });

  /// Create from JSON
  factory WooCommerceCategoryImage.fromJson(Map<String, dynamic> json) {
    return WooCommerceCategoryImage(
      id: json['id'] as int? ?? 0,
      src: json['src'] as String? ?? '',
      name: json['name'] as String?,
      alt: json['alt'] as String?,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'src': src,
      'name': name,
      'alt': alt,
    };
  }
}

