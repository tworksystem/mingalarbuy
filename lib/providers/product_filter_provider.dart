import 'package:flutter/foundation.dart';
import '../models/product_filters.dart';
import '../models/product.dart';
import '../woocommerce_service.dart';
import '../utils/logger.dart';

/// Product filter provider
/// Manages product filtering, sorting, and search state
class ProductFilterProvider with ChangeNotifier {
  ProductFilters _filters = ProductFilters();
  List<Product> _filteredProducts = [];
  List<Product> _allProducts = [];
  bool _isLoading = false;
  String? _errorMessage;

  // Getters
  ProductFilters get filters => _filters;
  List<Product> get filteredProducts => List.unmodifiable(_filteredProducts);
  List<Product> get allProducts => List.unmodifiable(_allProducts);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasFilters => _filters.hasFilters;
  int get productCount => _filteredProducts.length;

  /// Apply filters and reload products
  Future<void> applyFilters(ProductFilters filters) async {
    _filters = filters;
    _setLoading(true);
    _clearError();

    try {
      await _loadFilteredProducts();
    } catch (e, stackTrace) {
      Logger.error('Error applying filters: $e',
          tag: 'ProductFilterProvider', error: e, stackTrace: stackTrace);
      _setError('Failed to apply filters. Please try again.');
    } finally {
      _setLoading(false);
    }
  }

  /// Update search query
  Future<void> updateSearchQuery(String? query) async {
    _filters = _filters.copyWith(searchQuery: query);
    await applyFilters(_filters);
  }

  /// Update categories filter
  Future<void> updateCategories(List<String>? categories) async {
    _filters = _filters.copyWith(categories: categories);
    await applyFilters(_filters);
  }

  /// Update price range filter
  Future<void> updatePriceRange(PriceRange? priceRange) async {
    _filters = _filters.copyWith(priceRange: priceRange);
    await applyFilters(_filters);
  }

  /// Update sort option
  Future<void> updateSortOption(SortOption? sortBy) async {
    _filters = _filters.copyWith(sortBy: sortBy);
    await applyFilters(_filters);
  }

  /// Update stock filter
  Future<void> updateStockFilter(bool? inStock) async {
    _filters = _filters.copyWith(inStock: inStock);
    await applyFilters(_filters);
  }

  /// Update featured filter
  Future<void> updateFeaturedFilter(bool? featured) async {
    _filters = _filters.copyWith(featured: featured);
    await applyFilters(_filters);
  }

  /// Update rating filter
  Future<void> updateRatingFilter(double? minRating) async {
    _filters = _filters.copyWith(minRating: minRating);
    await applyFilters(_filters);
  }

  /// Clear all filters
  Future<void> clearFilters() async {
    _filters = ProductFilters();
    await applyFilters(_filters);
  }

  /// Load filtered products from backend
  Future<void> _loadFilteredProducts() async {
    try {
      // Get products from WooCommerce
      List<Product> products = [];

      if (_filters.searchQuery != null && _filters.searchQuery!.isNotEmpty) {
        // Use search endpoint
        final wooProducts = await WooCommerceService.searchProducts(
          _filters.searchQuery!,
          perPage: 50,
        );
        products = wooProducts.map((woo) => woo.toProduct()).toList();
      } else if (_filters.categories != null && _filters.categories!.isNotEmpty) {
        // Get products by category
        for (final categoryId in _filters.categories!) {
          final wooProducts = await WooCommerceService.getProductsByCategory(
            categoryId,
            perPage: 50,
          );
          products.addAll(wooProducts.map((woo) => woo.toProduct()));
        }
      } else {
        // Get all products with filters
        final wooProducts = await WooCommerceService.getProducts(
          perPage: 50,
          category: _filters.categories?.join(','),
          featured: _filters.featured,
          search: _filters.searchQuery,
        );
        products = wooProducts.map((woo) => woo.toProduct()).toList();
      }

      // Apply client-side filters (price range, stock, rating)
      products = _applyClientSideFilters(products);

      // Apply sorting
      products = _applySorting(products);

      _filteredProducts = products;
      _allProducts = products;
      notifyListeners();

      Logger.info('Loaded ${products.length} filtered products',
          tag: 'ProductFilterProvider');
    } catch (e, stackTrace) {
      Logger.error('Error loading filtered products: $e',
          tag: 'ProductFilterProvider', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Apply client-side filters (price range, stock, rating)
  List<Product> _applyClientSideFilters(List<Product> products) {
    var filtered = List<Product>.from(products);

    // Filter by price range
    if (_filters.priceRange != null) {
      final priceRange = _filters.priceRange!;
      filtered = filtered.where((product) {
        final price = product.price;
        if (priceRange.min != null && price < priceRange.min!) return false;
        if (priceRange.max != null && price > priceRange.max!) return false;
        return true;
      }).toList();
    }

    // Filter by stock (if available in product model)
    if (_filters.inStock != null) {
      // This would require stock information in Product model
      // For now, we'll skip this filter
    }

    // Filter by rating (if available in product model)
    if (_filters.minRating != null) {
      // This would require rating information in Product model
      // For now, we'll skip this filter
    }

    return filtered;
  }

  /// Apply sorting
  List<Product> _applySorting(List<Product> products) {
    if (_filters.sortBy == null) return products;

    final sorted = List<Product>.from(products);
    final sortOption = _filters.sortBy!;

    switch (sortOption.field) {
      case 'price':
        sorted.sort((a, b) {
          final comparison = a.price.compareTo(b.price);
          return sortOption.order == 'asc' ? comparison : -comparison;
        });
        break;
      case 'date':
        // Date sorting would require date field in Product model
        // For now, keep original order
        break;
      case 'popularity':
        // Popularity sorting would require popularity field
        // For now, keep original order
        break;
      case 'rating':
        // Rating sorting would require rating field
        // For now, keep original order
        break;
    }

    return sorted;
  }

  /// Refresh products
  Future<void> refresh() async {
    await applyFilters(_filters);
  }

  /// Private helper methods
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String error) {
    _errorMessage = error;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}

