import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product.dart';
import '../woocommerce_service.dart';
import '../utils/logger.dart';

/// Professional search service
/// Handles search history, autocomplete, and search suggestions
class SearchService {
  static const String _recentSearchesKey = 'recent_searches';
  static const int _maxRecentSearches = 10;
  static const int _maxSuggestions = 5;

  /// Get recent searches
  static Future<List<String>> getRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final searchesJson = prefs.getString(_recentSearchesKey);
      
      if (searchesJson != null) {
        final List<dynamic> searches = json.decode(searchesJson);
        return searches.map((s) => s.toString()).toList();
      }
      
      return [];
    } catch (e) {
      Logger.error('Error getting recent searches: $e', tag: 'SearchService', error: e);
      return [];
    }
  }

  /// Save search query to recent searches
  static Future<void> saveSearchQuery(String query) async {
    if (query.trim().isEmpty) return;

    try {
      final recentSearches = await getRecentSearches();
      
      // Remove if already exists
      recentSearches.remove(query.trim());
      
      // Add to beginning
      recentSearches.insert(0, query.trim());
      
      // Limit to max recent searches
      if (recentSearches.length > _maxRecentSearches) {
        recentSearches.removeRange(_maxRecentSearches, recentSearches.length);
      }
      
      // Save to storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_recentSearchesKey, json.encode(recentSearches));
      
      Logger.info('Saved search query: $query', tag: 'SearchService');
    } catch (e) {
      Logger.error('Error saving search query: $e', tag: 'SearchService', error: e);
    }
  }

  /// Clear recent searches
  static Future<void> clearRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_recentSearchesKey);
      Logger.info('Cleared recent searches', tag: 'SearchService');
    } catch (e) {
      Logger.error('Error clearing recent searches: $e', tag: 'SearchService', error: e);
    }
  }

  /// Get search suggestions (autocomplete)
  static Future<List<String>> getSearchSuggestions(String query) async {
    if (query.trim().isEmpty) {
      // Return recent searches if query is empty
      return await getRecentSearches();
    }

    try {
      // Get products matching query
      final products = await WooCommerceService.searchProducts(query, perPage: _maxSuggestions);
      
      // Extract product names as suggestions
      final suggestions = products
          .map((product) => product.name)
          .where((name) => name.toLowerCase().contains(query.toLowerCase()))
          .take(_maxSuggestions)
          .toList();
      
      return suggestions;
    } catch (e) {
      Logger.error('Error getting search suggestions: $e', tag: 'SearchService', error: e);
      return [];
    }
  }

  /// Search products with filters
  static Future<List<Product>> searchProducts({
    required String query,
    int perPage = 20,
    int page = 1,
    List<String>? categories,
    PriceRange? priceRange,
    SortOption? sortBy,
  }) async {
    try {
      // Save to recent searches
      await saveSearchQuery(query);

      // Get products from WooCommerce
      final wooProducts = await WooCommerceService.searchProducts(query, perPage: perPage);
      var products = wooProducts.map((woo) => woo.toProduct()).toList();

      // Apply client-side filters
      if (categories != null && categories.isNotEmpty) {
        // Filter by categories (would need category info in Product model)
      }

      if (priceRange != null) {
        products = products.where((product) {
          final price = product.price;
          if (priceRange.min != null && price < priceRange.min!) return false;
          if (priceRange.max != null && price > priceRange.max!) return false;
          return true;
        }).toList();
      }

      // Apply sorting
      if (sortBy != null) {
        switch (sortBy.field) {
          case 'price':
            products.sort((a, b) {
              final comparison = a.price.compareTo(b.price);
              return sortBy.order == 'asc' ? comparison : -comparison;
            });
            break;
          // Add more sorting options as needed
        }
      }

      return products;
    } catch (e, stackTrace) {
      Logger.error('Error searching products: $e',
          tag: 'SearchService', error: e, stackTrace: stackTrace);
      return [];
    }
  }
}

/// Price range helper
class PriceRange {
  final double? min;
  final double? max;

  PriceRange({this.min, this.max});
}

/// Sort option helper
class SortOption {
  final String field;
  final String order;

  SortOption({required this.field, this.order = 'desc'});
}

