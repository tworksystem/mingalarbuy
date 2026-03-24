import 'package:flutter/material.dart';

class Category {
  Color begin;
  Color end;
  String category;
  String image;
  int? id; // WooCommerce category ID
  String? slug; // WooCommerce category slug
  String? description; // Category description
  int? productCount; // Number of products in category

  Category(
    this.begin,
    this.end,
    this.category,
    this.image, {
    this.id,
    this.slug,
    this.description,
    this.productCount,
  });

  /// Create from JSON for caching
  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      Color(json['begin'] as int),
      Color(json['end'] as int),
      json['category'] as String,
      json['image'] as String,
      id: json['id'] as int?,
      slug: json['slug'] as String?,
      description: json['description'] as String?,
      productCount: json['productCount'] as int?,
    );
  }

  /// Convert to JSON for caching
  Map<String, dynamic> toJson() {
    return {
      'begin': begin.value,
      'end': end.value,
      'category': category,
      'image': image,
      'id': id,
      'slug': slug,
      'description': description,
      'productCount': productCount,
    };
  }
}