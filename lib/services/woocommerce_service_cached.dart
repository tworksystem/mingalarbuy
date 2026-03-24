import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/woocommerce_config.dart';
import '../models/woocommerce_product.dart';
import '../models/cached_product.dart';
import 'cache_service.dart';
import 'connectivity_service.dart';

/// WooCommerce API Service with Offline Caching
/// This service prioritizes fresh data but falls back to cache when offline
class WooCommerceServiceCached {
  /// Fetch products from WooCommerce with caching
  ///
  /// Strategy:
  /// 1. Check network connectivity
  /// 2. If online: Fetch from API and update cache
  /// 3. If offline: Return cached data
  /// 4. If cache expired and offline: Return expired cache with warning
  static Future<List<WooCommerceProduct>> getProducts({
    int page = 1,
    int perPage = 10,
    int? category,
    bool? featured,
    bool? onSale,
    String orderBy = 'date',
    String order = 'desc',
    String? search,
    bool forceRefresh = false,
  }) async {
    final cacheKey = _buildCacheKey(
      'products',
      page: page,
      perPage: perPage,
      category: category,
      featured: featured,
      onSale: onSale,
      orderBy: orderBy,
      order: order,
      search: search,
    );

    // Check connectivity
    final connectivity = ConnectivityService();
    await connectivity.initialize();
    final hasConnection = await connectivity.checkConnectivity();

    // If offline or force refresh is false, try cache first
    if (!hasConnection || !forceRefresh) {
      final cachedProducts = await CacheService.getCachedProducts(cacheKey);
      if (cachedProducts.isNotEmpty) {
        print('📦 Using cached products (${cachedProducts.length} items)');
        return _convertCachedToWooProducts(cachedProducts);
      }
    }

    // Fetch from API if online
    if (hasConnection) {
      try {
        final queryParams = {
          'page': page.toString(),
          'per_page': perPage.toString(),
          'orderby': orderBy,
          'order': order,
          if (category != null) 'category': category.toString(),
          if (featured != null) 'featured': featured.toString(),
          if (onSale != null) 'on_sale': onSale.toString(),
          if (search != null && search.isNotEmpty) 'search': search,
        };

        final url = WooCommerceConfig.buildAuthUrl(
          WooCommerceConfig.productsEndpoint,
          queryParameters: queryParams,
        );

        print('🌐 Fetching products from API...');

        final response = await http.get(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ).timeout(
          const Duration(seconds: 30),
        );

        if (response.statusCode == 200) {
          final List<dynamic> data = json.decode(response.body);
          final products = data
              .map((product) => WooCommerceProduct.fromJson(product))
              .toList();

          // Cache the results
          await CacheService.cacheProducts(cacheKey, products);
          print(
              '✅ Successfully fetched and cached ${products.length} products');

          return products;
        } else {
          throw Exception('Failed to load products: ${response.statusCode}');
        }
      } catch (e) {
        print('❌ API Error: $e');
        // Try cache as fallback
        final cachedProducts = await CacheService.getCachedProducts(
          cacheKey,
          maxAge: const Duration(days: 7), // Accept older cache on error
        );
        if (cachedProducts.isNotEmpty) {
          print('⚠️ Using cached products due to API error');
          return _convertCachedToWooProducts(cachedProducts);
        }
        rethrow;
      }
    } else {
      // Offline and no cache
      throw Exception('No internet connection and no cached data available');
    }
  }

  /// Get a single product by ID with caching
  static Future<WooCommerceProduct> getProduct(int productId) async {
    final cacheKey = 'product_$productId';

    final connectivityService = ConnectivityService();
    await connectivityService.initialize();
    final hasConnection = await connectivityService.checkConnectivity();

    // Try cache first
    final cachedProducts = await CacheService.getCachedProducts(cacheKey);
    if (cachedProducts.isNotEmpty && !hasConnection) {
      print('📦 Using cached product (ID: $productId)');
      return _convertCachedToWooProducts(cachedProducts).first;
    }

    // Fetch from API if online
    if (hasConnection) {
      try {
        final url = WooCommerceConfig.buildAuthUrl(
          '${WooCommerceConfig.productsEndpoint}/$productId',
        );

        final response = await http.get(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ).timeout(
          const Duration(seconds: 30),
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final product = WooCommerceProduct.fromJson(data);

          // Cache the result
          await CacheService.cacheProducts(cacheKey, [product]);

          return product;
        } else {
          throw Exception('Failed to load product: ${response.statusCode}');
        }
      } catch (e) {
        print('❌ API Error: $e');
        if (cachedProducts.isNotEmpty) {
          print('⚠️ Using cached product due to API error');
          return _convertCachedToWooProducts(cachedProducts).first;
        }
        rethrow;
      }
    } else {
      throw Exception('No internet connection and no cached data available');
    }
  }

  /// Get featured products with caching
  static Future<List<WooCommerceProduct>> getFeaturedProducts({
    int perPage = 10,
    bool forceRefresh = false,
  }) async {
    return getProducts(
      perPage: perPage,
      featured: true,
      orderBy: 'popularity',
      forceRefresh: forceRefresh,
    );
  }

  /// Get products on sale with caching
  static Future<List<WooCommerceProduct>> getOnSaleProducts({
    int perPage = 10,
    bool forceRefresh = false,
  }) async {
    return getProducts(
      perPage: perPage,
      onSale: true,
      forceRefresh: forceRefresh,
    );
  }

  /// Get products by category with caching
  static Future<List<WooCommerceProduct>> getProductsByCategory(
    int categoryId, {
    int perPage = 10,
    int page = 1,
    bool forceRefresh = false,
  }) async {
    return getProducts(
      category: categoryId,
      perPage: perPage,
      page: page,
      forceRefresh: forceRefresh,
    );
  }

  /// Search products with caching
  static Future<List<WooCommerceProduct>> searchProducts(
    String keyword, {
    int perPage = 10,
    bool forceRefresh = false,
  }) async {
    return getProducts(
      search: keyword,
      perPage: perPage,
      forceRefresh: forceRefresh,
    );
  }

  /// Get product categories (not cached as they change rarely)
  static Future<List<Map<String, dynamic>>> getCategories({
    int page = 1,
    int perPage = 100,
  }) async {
    final connectivityService = ConnectivityService();
    await connectivityService.initialize();
    final hasConnection = await connectivityService.checkConnectivity();

    if (!hasConnection) {
      throw Exception('No internet connection available');
    }

    try {
      final queryParams = {
        'page': page.toString(),
        'per_page': perPage.toString(),
        'hide_empty': 'true',
      };

      final url = WooCommerceConfig.buildAuthUrl(
        WooCommerceConfig.categoriesEndpoint,
        queryParameters: queryParams,
      );

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ).timeout(
        const Duration(seconds: 30),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      } else {
        throw Exception('Failed to load categories: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error fetching categories: $e');
      rethrow;
    }
  }

  /// Check API connection
  static Future<bool> checkConnection() async {
    final connectivityService = ConnectivityService();
    await connectivityService.initialize();
    final hasConnection = await connectivityService.checkConnectivity();
    if (!hasConnection) return false;

    try {
      await getProducts(perPage: 1);
      return true;
    } catch (e) {
      print('Connection check failed: $e');
      return false;
    }
  }

  /// Clear all cached products
  static Future<void> clearCache() async {
    await CacheService.clearAllCache();
  }

  /// Get cache statistics
  static Future<Map<String, dynamic>> getCacheStats() async {
    return await CacheService.getCacheStats();
  }

  /// Build cache key from parameters
  static String _buildCacheKey(
    String prefix, {
    int? page,
    int? perPage,
    int? category,
    bool? featured,
    bool? onSale,
    String? orderBy,
    String? order,
    String? search,
  }) {
    final parts = [prefix];
    if (page != null) parts.add('p$page');
    if (perPage != null) parts.add('pp$perPage');
    if (category != null) parts.add('c$category');
    if (featured == true) parts.add('featured');
    if (onSale == true) parts.add('sale');
    if (orderBy != null) parts.add('ob$orderBy');
    if (order != null) parts.add('o$order');
    if (search != null && search.isNotEmpty) parts.add('s${search.hashCode}');

    return parts.join('_');
  }

  /// Convert cached products to WooCommerce products
  static List<WooCommerceProduct> _convertCachedToWooProducts(
    List<CachedProduct> cachedProducts,
  ) {
    return cachedProducts.map((cached) {
      return WooCommerceProduct.fromJson(cached.toJson());
    }).toList();
  }
}
