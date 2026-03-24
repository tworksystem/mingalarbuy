import 'package:ecommerce_int2/models/woocommerce_product.dart';
import 'package:ecommerce_int2/services/woocommerce_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Product Repository
///
/// Manages product data from WooCommerce API with caching,
/// state management, and offline support using Repository pattern.
class ProductRepository {
  final WooCommerceService _wooCommerceService;
  List<WooCommerceProduct> _cachedProducts = [];
  DateTime? _lastFetchTime;

  // Cache keys
  static const String _cacheKey = 'cached_woocommerce_products';
  static const String _cacheTimeKey = 'cached_products_timestamp';

  ProductRepository({WooCommerceService? wooCommerceService})
      : _wooCommerceService = wooCommerceService ?? WooCommerceService();

  /// Get products with caching
  ///
  /// Returns cached products if available and not expired,
  /// otherwise fetches from API and updates cache.
  Future<List<WooCommerceProduct>> getProducts({
    bool forceRefresh = false,
    int page = 1,
    int perPage = 20,
    bool? featured,
  }) async {
    try {
      // Check if we should use cache
      if (!forceRefresh && _isCacheValid() && _cachedProducts.isNotEmpty) {
        debugPrint('📦 Returning cached products (${_cachedProducts.length})');
        return _cachedProducts;
      }

      // Load from persistent cache if memory cache is empty
      if (!forceRefresh && _cachedProducts.isEmpty) {
        final cachedData = await _loadFromPersistentCache();
        if (cachedData != null && cachedData.isNotEmpty) {
          debugPrint(
              '💾 Loaded ${cachedData.length} products from persistent cache');
          _cachedProducts = cachedData;
          return _cachedProducts;
        }
      }

      // Fetch from API
      debugPrint('🌐 Fetching fresh products from API...');
      final products = await _wooCommerceService.fetchProducts(
        page: page,
        perPage: perPage,
        featured: featured,
      );

      // Update cache
      _cachedProducts = products;
      _lastFetchTime = DateTime.now();

      // Save to persistent cache
      await _saveToPersistentCache(products);

      return products;
    } catch (e) {
      debugPrint('❌ Error getting products: $e');

      // If we have cached data, return it even if expired
      if (_cachedProducts.isNotEmpty) {
        debugPrint('⚠️ Using stale cache due to error');
        return _cachedProducts;
      }

      // Try to load from persistent cache as last resort
      final cachedData = await _loadFromPersistentCache();
      if (cachedData != null && cachedData.isNotEmpty) {
        debugPrint(
            '💾 Loaded ${cachedData.length} products from persistent cache (fallback)');
        _cachedProducts = cachedData;
        return _cachedProducts;
      }

      rethrow;
    }
  }

  /// Get featured products
  Future<List<WooCommerceProduct>> getFeaturedProducts({
    bool forceRefresh = false,
  }) async {
    try {
      final products = await _wooCommerceService.fetchProducts(
        featured: true,
        perPage: 10,
      );
      return products;
    } catch (e) {
      debugPrint('❌ Error getting featured products: $e');

      // Return featured products from cache
      return _cachedProducts.where((p) => p.featured).toList();
    }
  }

  /// Get product by ID
  Future<WooCommerceProduct?> getProductById(int productId) async {
    try {
      // Check cache first
      final cachedProduct = _cachedProducts.firstWhere(
        (p) => p.id == productId,
        orElse: () => throw StateError('Not found'),
      );

      debugPrint('📦 Returning product from cache');
      return cachedProduct;
        } catch (_) {
      // Not in cache, fetch from API
    }

    return await _wooCommerceService.fetchProductById(productId);
  }

  /// Search products
  Future<List<WooCommerceProduct>> searchProducts(String query) async {
    if (query.isEmpty) return _cachedProducts;

    // Search in cache first for instant results
    final cacheResults = _cachedProducts.where((product) {
      final nameLower = product.name.toLowerCase();
      final queryLower = query.toLowerCase();
      return nameLower.contains(queryLower);
    }).toList();

    // Return cache results if available
    if (cacheResults.isNotEmpty) {
      return cacheResults;
    }

    // If no cache results, try API search
    try {
      return await _wooCommerceService.fetchProducts(
        search: query,
        perPage: 50,
      );
    } catch (e) {
      debugPrint('❌ Error searching products: $e');
      return cacheResults; // Return cache results even if empty
    }
  }

  /// Clear cache
  Future<void> clearCache() async {
    _cachedProducts = [];
    _lastFetchTime = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
    await prefs.remove(_cacheTimeKey);

    debugPrint('🗑️ Cache cleared');
  }

  /// Check if cache is valid
  bool _isCacheValid() {
    if (_lastFetchTime == null) return false;

    final now = DateTime.now();
    final difference = now.difference(_lastFetchTime!);

    return difference < const Duration(hours: 1);
  }

  /// Save products to persistent cache
  Future<void> _saveToPersistentCache(List<WooCommerceProduct> products) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = products.map((p) => p.toJson()).toList();
      final jsonString = json.encode(jsonList);

      await prefs.setString(_cacheKey, jsonString);
      await prefs.setString(_cacheTimeKey, DateTime.now().toIso8601String());

      debugPrint('💾 Saved ${products.length} products to persistent cache');
    } catch (e) {
      debugPrint('❌ Error saving to persistent cache: $e');
    }
  }

  /// Load products from persistent cache
  Future<List<WooCommerceProduct>?> _loadFromPersistentCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_cacheKey);
      final timeString = prefs.getString(_cacheTimeKey);

      if (jsonString == null || timeString == null) return null;

      // Check if cache is expired
      final cacheTime = DateTime.parse(timeString);
      final now = DateTime.now();
      if (now.difference(cacheTime) > const Duration(hours: 24)) {
        debugPrint('⚠️ Persistent cache expired');
        return null;
      }

      final List<dynamic> jsonList = json.decode(jsonString);
      final products =
          jsonList.map((json) => WooCommerceProduct.fromJson(json)).toList();

      _lastFetchTime = cacheTime;

      return products;
    } catch (e) {
      debugPrint('❌ Error loading from persistent cache: $e');
      return null;
    }
  }

  /// Test API connection
  Future<bool> testConnection() async {
    return await _wooCommerceService.testConnection();
  }

  /// Get cache info
  Map<String, dynamic> getCacheInfo() {
    return {
      'cachedProducts': _cachedProducts.length,
      'lastFetchTime': _lastFetchTime?.toIso8601String(),
      'isCacheValid': _isCacheValid(),
    };
  }
}
