import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:ecommerce_int2/config/woocommerce_config.dart';
import 'package:ecommerce_int2/models/woocommerce_product.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// WooCommerce API Service
///
/// Handles all API calls to WooCommerce REST API with proper
/// authentication, error handling, and response parsing.
class WooCommerceService {
  final http.Client _client;

  WooCommerceService({http.Client? client}) : _client = client ?? http.Client();

  /// Fetch products from WooCommerce API
  ///
  /// [page] - Page number for pagination (default: 1)
  /// [perPage] - Number of products per page (default: 20)
  /// [featured] - Filter for featured products only
  /// [category] - Filter by category ID
  /// [search] - Search query string
  Future<List<WooCommerceProduct>> fetchProducts({
    int page = 1,
    int perPage = 20,
    bool? featured,
    int? category,
    String? search,
  }) async {
    try {
      debugPrint('🛒 Fetching products from WooCommerce API...');
      debugPrint('📍 URL: ${WooCommerceConfig.baseUrl}');

      // Build query parameters
      final queryParams = <String, String>{
        ...WooCommerceConfig.authParams,
        'per_page': perPage.toString(),
        'page': page.toString(),
      };

      if (featured != null) {
        queryParams['featured'] = featured.toString();
      }

      if (category != null) {
        queryParams['category'] = category.toString();
      }

      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
      }

      // Build URI
      final uri = Uri.parse(WooCommerceConfig.getProductsUrl(
        page: page,
        perPage: perPage,
      ));
      
      // Add query parameters manually
      final finalUri = Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.port,
        path: uri.path,
        queryParameters: queryParams,
      );

      debugPrint('🔗 Request URL: $finalUri');

      // Make HTTP request
      final response = await _client.get(
        finalUri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ).timeout(
        Duration(seconds: WooCommerceConfig.timeout),
        onTimeout: () {
          throw TimeoutException(
              'Connection timeout after ${WooCommerceConfig.timeout} seconds');
        },
      );

      debugPrint('📡 Response status: ${response.statusCode}');

      // Handle response
      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(response.body);
        debugPrint('✅ Fetched ${jsonList.length} products successfully');

        final products =
            jsonList.map((json) => WooCommerceProduct.fromJson(json)).toList();

        return products;
      } else if (response.statusCode == 401) {
        throw WooCommerceException(
          'Authentication failed. Please check your API credentials.',
          statusCode: 401,
        );
      } else if (response.statusCode == 404) {
        throw WooCommerceException(
          'API endpoint not found. Please check your WooCommerce installation.',
          statusCode: 404,
        );
      } else {
        final errorBody = json.decode(response.body);
        throw WooCommerceException(
          errorBody['message'] ?? 'Failed to fetch products',
          statusCode: response.statusCode,
        );
      }
    } on SocketException catch (e) {
      debugPrint('❌ Network error: $e');
      throw WooCommerceException(
        'No internet connection. Please check your network.',
        originalError: e,
      );
    } on TimeoutException catch (e) {
      debugPrint('❌ Timeout error: $e');
      throw WooCommerceException(
        'Request timeout. Please try again.',
        originalError: e,
      );
    } on FormatException catch (e) {
      debugPrint('❌ JSON parsing error: $e');
      throw WooCommerceException(
        'Invalid response format from server.',
        originalError: e,
      );
    } catch (e) {
      debugPrint('❌ Unexpected error: $e');
      if (e is WooCommerceException) rethrow;

      // Handle web-specific CORS errors
      if (kIsWeb && e.toString().contains('Failed to fetch')) {
        throw WooCommerceException(
          'CORS Error: The server does not allow cross-origin requests from web browsers. '
          'This is a server-side configuration issue. Please contact the website administrator '
          'to enable CORS for your domain, or use the mobile app instead.',
          originalError: e,
        );
      }

      // Handle other web-specific errors
      if (kIsWeb && e.toString().contains('ClientException')) {
        throw WooCommerceException(
          'Web Browser Error: Unable to make the request from the web browser. '
          'This might be due to CORS restrictions or network policies. '
          'Try using the mobile app or contact support.',
          originalError: e,
        );
      }

      throw WooCommerceException(
        'An unexpected error occurred: ${e.toString()}',
        originalError: e,
      );
    }
  }

  /// Fetch a single product by ID
  Future<WooCommerceProduct?> fetchProductById(int productId) async {
    try {
      debugPrint('🛒 Fetching product ID: $productId');

      final uri = Uri.parse(WooCommerceConfig.getProductUrl(productId))
          ;
      
      final authUri = Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.port,
        path: uri.path,
        queryParameters: WooCommerceConfig.authParams,
      );

      final response = await _client.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ).timeout(Duration(seconds: WooCommerceConfig.timeout));

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        debugPrint('✅ Fetched product successfully');
        return WooCommerceProduct.fromJson(jsonData);
      } else if (response.statusCode == 404) {
        debugPrint('⚠️ Product not found');
        return null;
      } else {
        throw WooCommerceException(
          'Failed to fetch product',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      debugPrint('❌ Error fetching product: $e');
      if (e is WooCommerceException) rethrow;

      // Handle web-specific CORS errors
      if (kIsWeb && e.toString().contains('Failed to fetch')) {
        throw WooCommerceException(
          'CORS Error: The server does not allow cross-origin requests from web browsers. '
          'This is a server-side configuration issue. Please contact the website administrator '
          'to enable CORS for your domain, or use the mobile app instead.',
          originalError: e,
        );
      }

      throw WooCommerceException(
        'Failed to fetch product: ${e.toString()}',
        originalError: e,
      );
    }
  }

  /// Alias for fetchProducts - for backward compatibility
  Future<List<WooCommerceProduct>> getProducts({
    int page = 1,
    int perPage = 20,
    bool? featured,
    int? category,
    String? search,
  }) async {
    return fetchProducts(
      page: page,
      perPage: perPage,
      featured: featured,
      category: category,
      search: search,
    );
  }

  /// Get featured products
  Future<List<WooCommerceProduct>> getFeaturedProducts({
    int page = 1,
    int perPage = 20,
  }) async {
    return fetchProducts(
      page: page,
      perPage: perPage,
      featured: true,
    );
  }

  /// Get on-sale products
  Future<List<WooCommerceProduct>> getOnSaleProducts({
    int page = 1,
    int perPage = 20,
  }) async {
    // WooCommerce doesn't have a direct on-sale filter,
    // so we fetch all and filter client-side
    final products = await fetchProducts(page: page, perPage: perPage);
    return products.where((p) => p.onSale).toList();
  }

  /// Get categories
  Future<List<dynamic>> getCategories({int page = 1, int? perPage}) async {
    try {
      final uri = Uri.parse(WooCommerceConfig.getCategoriesUrl(page: page))
          ;
      
      final authUri = Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.port,
        path: uri.path,
        queryParameters: WooCommerceConfig.authParams,
      );

      final response = await _client.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ).timeout(Duration(seconds: WooCommerceConfig.timeout));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw WooCommerceException(
          'Failed to fetch categories',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      if (e is WooCommerceException) rethrow;
      throw WooCommerceException('Failed to fetch categories: ${e.toString()}');
    }
  }

  /// Check connection - alias for testConnection
  Future<bool> checkConnection() async {
    return testConnection();
  }

  /// Test API connection
  Future<bool> testConnection() async {
    try {
      debugPrint('🔍 Testing WooCommerce API connection...');

      final uri = Uri.parse(WooCommerceConfig.getProductsUrl(perPage: 1))
          ;
      
      final authUri = Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.port,
        path: uri.path,
        queryParameters: WooCommerceConfig.authParams,
      );

      final response = await _client.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        debugPrint('✅ API connection successful');
        return true;
      } else {
        debugPrint('❌ API connection failed: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ API connection test failed: $e');
      return false;
    }
  }

  /// Dispose resources
  void dispose() {
    _client.close();
  }
}

/// Custom exception for WooCommerce API errors
class WooCommerceException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic originalError;

  WooCommerceException(
    this.message, {
    this.statusCode,
    this.originalError,
  });

  @override
  String toString() {
    if (statusCode != null) {
      return 'WooCommerceException [$statusCode]: $message';
    }
    return 'WooCommerceException: $message';
  }
}
