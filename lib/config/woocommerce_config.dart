/// WooCommerce API Configuration
///
/// Centralized configuration for WooCommerce REST API integration
/// with mingalarbuy.com
class WooCommerceConfig {
  // API Credentials
  static const String baseUrl = 'https://mingalarbuy.com';
  static const String consumerKey =
      'ck_9838e0a0aa35fee12d90c29026441c096863f0c6';
  static const String consumerSecret =
      'cs_2542de3bf738e35aed466029a0c789579a2034d6';

  // API Endpoints
  static const String apiPath = '/wp-json/wc/v3';
  static const String apiVersion = 'v3';
  static const String productsEndpoint = '/products';
  static const String categoriesEndpoint = '/product_categories';
  static const String ordersEndpoint = '/orders';

  // Configuration
  static const bool isHttps = true;
  static const int perPage = 20;
  static const int timeout = 30; // seconds

  // Cache Settings
  static const Duration cacheExpiration = Duration(hours: 1);
  static const int maxCacheSize = 100; // Maximum cached products

  /// Get full API URL
  static String get apiUrl => '$baseUrl$apiPath';

  /// Get authentication query parameters
  static Map<String, String> get authParams => {
        'consumer_key': consumerKey,
        'consumer_secret': consumerSecret,
      };

  /// Get products URL with pagination
  static String getProductsUrl({int page = 1, int perPage = 20}) {
    return '$apiUrl$productsEndpoint?per_page=$perPage&page=$page';
  }

  /// Get categories URL
  static String getCategoriesUrl({int page = 1}) {
    return '$apiUrl$categoriesEndpoint?per_page=100&page=$page';
  }

  /// Get single product URL
  static String getProductUrl(int productId) {
    return '$apiUrl$productsEndpoint/$productId';
  }

  /// Build authentication URL with query parameters
  static String buildAuthUrl(
    String baseEndpoint, {
    Map<String, String>? queryParameters,
  }) {
    final baseUri = Uri.parse('$apiUrl$baseEndpoint');
    final params = <String, String>{
      ...baseUri.queryParameters,
      ...authParams,
      if (queryParameters != null) ...queryParameters,
    };
    return Uri(
      scheme: baseUri.scheme,
      host: baseUri.host,
      port: baseUri.port,
      path: baseUri.path,
      queryParameters: params,
    ).toString();
  }
}
