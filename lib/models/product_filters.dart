/// Product filter options
class ProductFilters {
  final String? searchQuery;
  final List<String>? categories;
  final PriceRange? priceRange;
  final SortOption? sortBy;
  final bool? inStock;
  final bool? featured;
  final double? minRating;
  final Map<String, dynamic>? customFilters;

  ProductFilters({
    this.searchQuery,
    this.categories,
    this.priceRange,
    this.sortBy,
    this.inStock,
    this.featured,
    this.minRating,
    this.customFilters,
  });

  /// Check if any filters are applied
  bool get hasFilters =>
      (searchQuery != null && searchQuery!.isNotEmpty) ||
      (categories != null && categories!.isNotEmpty) ||
      priceRange != null ||
      sortBy != null ||
      inStock != null ||
      featured != null ||
      minRating != null;

  /// Create a copy with updated values
  ProductFilters copyWith({
    String? searchQuery,
    List<String>? categories,
    PriceRange? priceRange,
    SortOption? sortBy,
    bool? inStock,
    bool? featured,
    double? minRating,
    Map<String, dynamic>? customFilters,
  }) {
    return ProductFilters(
      searchQuery: searchQuery ?? this.searchQuery,
      categories: categories ?? this.categories,
      priceRange: priceRange ?? this.priceRange,
      sortBy: sortBy ?? this.sortBy,
      inStock: inStock ?? this.inStock,
      featured: featured ?? this.featured,
      minRating: minRating ?? this.minRating,
      customFilters: customFilters ?? this.customFilters,
    );
  }

  /// Clear all filters
  ProductFilters clear() {
    return ProductFilters();
  }

  /// Convert to query parameters for API
  Map<String, String> toQueryParams() {
    final params = <String, String>{};

    if (searchQuery != null && searchQuery!.isNotEmpty) {
      params['search'] = searchQuery!;
    }

    if (categories != null && categories!.isNotEmpty) {
      params['category'] = categories!.join(',');
    }

    if (featured != null) {
      params['featured'] = featured.toString();
    }

    if (priceRange != null) {
      if (priceRange!.min != null) {
        params['min_price'] = priceRange!.min.toString();
      }
      if (priceRange!.max != null) {
        params['max_price'] = priceRange!.max.toString();
      }
    }

    if (sortBy != null) {
      params['orderby'] = sortBy!.field;
      params['order'] = sortBy!.order;
    }

    if (minRating != null) {
      params['min_rating'] = minRating.toString();
    }

    if (customFilters != null) {
      customFilters!.forEach((key, value) {
        params[key] = value.toString();
      });
    }

    return params;
  }

  @override
  String toString() {
    return 'ProductFilters(searchQuery: $searchQuery, categories: $categories, priceRange: $priceRange, sortBy: $sortBy, inStock: $inStock, featured: $featured, minRating: $minRating)';
  }
}

/// Price range filter
class PriceRange {
  final double? min;
  final double? max;

  PriceRange({this.min, this.max});

  bool get isValid => min != null || max != null;

  @override
  String toString() => 'PriceRange(min: $min, max: $max)';
}

/// Sort option
class SortOption {
  final String field; // 'date', 'price', 'popularity', 'rating'
  final String order; // 'asc' or 'desc'

  const SortOption({
    required this.field,
    this.order = 'desc',
  });

  static const SortOption newest = SortOption(field: 'date', order: 'desc');
  static const SortOption oldest = SortOption(field: 'date', order: 'asc');
  static const SortOption priceLowToHigh = SortOption(field: 'price', order: 'asc');
  static const SortOption priceHighToLow = SortOption(field: 'price', order: 'desc');
  static const SortOption popularity = SortOption(field: 'popularity', order: 'desc');
  static const SortOption rating = SortOption(field: 'rating', order: 'desc');

  static const List<SortOption> allOptions = [
    newest,
    oldest,
    priceLowToHigh,
    priceHighToLow,
    popularity,
    rating,
  ];

  String get displayName {
    switch (this) {
      case newest:
        return 'Newest';
      case oldest:
        return 'Oldest';
      case priceLowToHigh:
        return 'Price: Low to High';
      case priceHighToLow:
        return 'Price: High to Low';
      case popularity:
        return 'Most Popular';
      case rating:
        return 'Highest Rated';
      default:
        return 'Custom';
    }
  }

  @override
  String toString() => 'SortOption(field: $field, order: $order)';
}

