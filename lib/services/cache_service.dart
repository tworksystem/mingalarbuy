import 'package:hive_flutter/hive_flutter.dart';
import '../models/cached_product.dart';
import '../models/woocommerce_product.dart';

/// Professional Cache Service with expiry strategy
/// Handles all offline caching operations
class CacheService {
  static const String _productsBoxName = 'products_cache';
  static const String _metadataBoxName = 'cache_metadata';
  static const String _settingsBoxName = 'cache_settings';

  static Box<CachedProduct>? _productsBox;
  static Box<CacheMetadata>? _metadataBox;
  static Box? _settingsBox;

  static bool _isInitialized = false;

  /// Initialize Hive and open boxes
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await Hive.initFlutter();

      // Register adapters
      if (!Hive.isAdapterRegistered(0)) {
        Hive.registerAdapter(CachedProductAdapter());
      }
      if (!Hive.isAdapterRegistered(1)) {
        Hive.registerAdapter(CacheMetadataAdapter());
      }

      // Open boxes
      _productsBox = await Hive.openBox<CachedProduct>(_productsBoxName);
      _metadataBox = await Hive.openBox<CacheMetadata>(_metadataBoxName);
      _settingsBox = await Hive.openBox(_settingsBoxName);

      _isInitialized = true;
      print('✅ Cache Service initialized successfully');
    } catch (e) {
      print('❌ Cache Service initialization failed: $e');
      rethrow;
    }
  }

  /// Cache products with a specific key
  static Future<void> cacheProducts(
    String key,
    List<WooCommerceProduct> products,
  ) async {
    await _ensureInitialized();

    try {
      // Clear old products with this key
      await clearCacheByKey(key);

      // Store new products
      final cachedProducts =
          products.map((p) => CachedProduct.fromWooCommerceProduct(p)).toList();

      for (var product in cachedProducts) {
        await _productsBox!.put('${key}_${product.id}', product);
      }

      // Update metadata
      final metadata = CacheMetadata(
        key: key,
        lastUpdated: DateTime.now(),
        itemCount: products.length,
      );
      await _metadataBox!.put(key, metadata);

      print('✅ Cached ${products.length} products with key: $key');
    } catch (e) {
      print('❌ Error caching products: $e');
    }
  }

  /// Get cached products by key
  static Future<List<CachedProduct>> getCachedProducts(
    String key, {
    Duration maxAge = const Duration(hours: 24),
  }) async {
    await _ensureInitialized();

    try {
      // Check metadata
      final metadata = _metadataBox!.get(key);
      if (metadata == null) {
        print('ℹ️ No cache found for key: $key');
        return [];
      }

      // Check if cache is expired
      final cacheAge = DateTime.now().difference(metadata.lastUpdated);
      if (cacheAge > maxAge) {
        print('⚠️ Cache expired for key: $key (age: ${cacheAge.inHours}h)');
        await clearCacheByKey(key);
        return [];
      }

      // Get all products with this key
      final products = _productsBox!.values
          .where((p) => p.key?.toString().startsWith(key) ?? false)
          .toList();

      print('✅ Retrieved ${products.length} cached products for key: $key');
      return products;
    } catch (e) {
      print('❌ Error getting cached products: $e');
      return [];
    }
  }

  /// Clear cache by specific key
  static Future<void> clearCacheByKey(String key) async {
    await _ensureInitialized();

    try {
      // Delete all products with this key
      final keysToDelete = _productsBox!.keys
          .where((k) => k.toString().startsWith(key))
          .toList();

      for (var k in keysToDelete) {
        await _productsBox!.delete(k);
      }

      // Delete metadata
      await _metadataBox!.delete(key);

      print('✅ Cleared cache for key: $key');
    } catch (e) {
      print('❌ Error clearing cache: $e');
    }
  }

  /// Clear all cache
  static Future<void> clearAllCache() async {
    await _ensureInitialized();

    try {
      await _productsBox!.clear();
      await _metadataBox!.clear();
      print('✅ Cleared all cache');
    } catch (e) {
      print('❌ Error clearing all cache: $e');
    }
  }

  /// Get cache statistics
  static Future<Map<String, dynamic>> getCacheStats() async {
    await _ensureInitialized();

    try {
      final totalProducts = _productsBox!.length;
      final cacheKeys = _metadataBox!.values.map((m) => m.key).toList();

      final stats = {
        'total_products': totalProducts,
        'cache_keys': cacheKeys.length,
        'keys': cacheKeys,
        'size_kb': await _calculateCacheSize(),
      };

      // Add metadata for each key
      for (var metadata in _metadataBox!.values) {
        stats['${metadata.key}_last_updated'] = metadata.lastUpdated.toString();
        stats['${metadata.key}_count'] = metadata.itemCount;
      }

      return stats;
    } catch (e) {
      print('❌ Error getting cache stats: $e');
      return {};
    }
  }

  /// Calculate approximate cache size in KB
  static Future<double> _calculateCacheSize() async {
    try {
      // Rough estimation based on number of items
      // Each cached product is approximately 2-5 KB
      final productCount = _productsBox!.length;
      return productCount * 3.5; // Average 3.5 KB per product
    } catch (e) {
      return 0;
    }
  }

  /// Check if cache exists for key
  static Future<bool> hasCacheForKey(String key) async {
    await _ensureInitialized();
    return _metadataBox!.containsKey(key);
  }

  /// Get cache age for key
  static Future<Duration?> getCacheAge(String key) async {
    await _ensureInitialized();

    final metadata = _metadataBox!.get(key);
    if (metadata == null) return null;

    return DateTime.now().difference(metadata.lastUpdated);
  }

  /// Enable/disable auto cache clearing on app start
  static Future<void> setAutoClearOnStart(bool enabled) async {
    await _ensureInitialized();
    await _settingsBox!.put('auto_clear_on_start', enabled);
  }

  static Future<bool> getAutoClearOnStart() async {
    await _ensureInitialized();
    return _settingsBox!.get('auto_clear_on_start', defaultValue: false)
        as bool;
  }

  /// Set custom cache expiry duration (in hours)
  static Future<void> setCacheExpiryHours(int hours) async {
    await _ensureInitialized();
    await _settingsBox!.put('cache_expiry_hours', hours);
  }

  static Future<int> getCacheExpiryHours() async {
    await _ensureInitialized();
    return _settingsBox!.get('cache_expiry_hours', defaultValue: 24) as int;
  }

  /// Ensure cache service is initialized
  static Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
  }

  /// Dispose (close boxes)
  static Future<void> dispose() async {
    await _productsBox?.close();
    await _metadataBox?.close();
    await _settingsBox?.close();
    _isInitialized = false;
    print('✅ Cache Service disposed');
  }
}
