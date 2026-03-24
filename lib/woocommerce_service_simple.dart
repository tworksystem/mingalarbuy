import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models/woocommerce_product.dart';
import 'models/woocommerce_order.dart';
import 'utils/logger.dart';
import 'utils/app_config.dart';

/// Simplified WooCommerce service without model conflicts
class WooCommerceServiceSimple {
  static const String baseUrl = AppConfig.baseUrl;
  static const String consumerKey = AppConfig.consumerKey;
  static const String consumerSecret = AppConfig.consumerSecret;

  /// Test WooCommerce connection
  static Future<bool> testConnection() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/products?per_page=1'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization':
              'Basic ${base64Encode(utf8.encode('$consumerKey:$consumerSecret'))}',
        },
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        Logger.info('WooCommerce connection test successful',
            tag: 'WooCommerceServiceSimple');
        return true;
      } else {
        Logger.error(
            'WooCommerce connection test failed: ${response.statusCode}',
            tag: 'WooCommerceServiceSimple');
        return false;
      }
    } catch (e) {
      Logger.error('WooCommerce connection test error: $e',
          tag: 'WooCommerceServiceSimple');
      return false;
    }
  }

  /// Get products with search functionality
  static Future<List<WooCommerceProduct>> getProducts({
    int perPage = 20,
    int page = 1,
    String? category,
    String? search,
    bool? featured,
  }) async {
    try {
      String url = '$baseUrl/products?per_page=$perPage&page=$page';

      if (category != null) {
        url += '&category=$category';
      }
      if (search != null && search.isNotEmpty) {
        url += '&search=${Uri.encodeComponent(search)}';
      }
      if (featured != null) {
        url += '&featured=$featured';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization':
              'Basic ${base64Encode(utf8.encode('$consumerKey:$consumerSecret'))}',
        },
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final List<dynamic> productsData = json.decode(response.body);
        return productsData
            .map((product) => WooCommerceProduct.fromJson(product))
            .toList();
      } else {
        throw Exception(
            'Failed to fetch products: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      Logger.error('Error fetching products: $e',
          tag: 'WooCommerceServiceSimple');
      return [];
    }
  }

  /// Create a simple test order
  static Future<WooCommerceOrder?> createTestOrder() async {
    try {
      final orderData = {
        'status': 'pending',
        'currency': 'USD',
        'date_created': DateTime.now().toIso8601String(),
        'date_modified': DateTime.now().toIso8601String(),
        'total': '25.99',
        'subtotal': '25.99',
        'total_tax': '0.00',
        'shipping_total': '0.00',
        'discount_total': '0.00',
        'line_items': [
          {
            'name': 'Test Product',
            'product_id': 737,
            'quantity': 1,
            'subtotal': '25.99',
            'subtotal_tax': '0.00',
            'total': '25.99',
            'total_tax': '0.00',
            'price': '25.99',
            'sku': 'TEST-001'
          }
        ],
        'billing': {
          'first_name': 'Test',
          'last_name': 'User',
          'address_1': '123 Test St',
          'city': 'Test City',
          'state': 'TS',
          'postcode': '12345',
          'country': 'US',
          'email': 'test@example.com',
          'phone': '555-000-0000'
        },
        'shipping': {
          'first_name': 'Test',
          'last_name': 'User',
          'address_1': '123 Test St',
          'city': 'Test City',
          'state': 'TS',
          'postcode': '12345',
          'country': 'US'
        },
        'payment_method': 'bacs',
        'payment_method_title': 'Direct Bank Transfer',
        'paid': false
      };

      final response = await http.post(
        Uri.parse('$baseUrl/orders'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization':
              'Basic ${base64Encode(utf8.encode('$consumerKey:$consumerSecret'))}',
        },
        body: json.encode(orderData),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final responseData = json.decode(response.body);
        Logger.info('Raw API response: ${response.body}',
            tag: 'WooCommerceServiceSimple');

        if (responseData is Map<String, dynamic>) {
          final createdOrder = WooCommerceOrder.fromJson(responseData);
          Logger.info('Test order created successfully: ${createdOrder.id}',
              tag: 'WooCommerceServiceSimple');
          return createdOrder;
        } else {
          Logger.error(
              'Unexpected response format: ${responseData.runtimeType}',
              tag: 'WooCommerceServiceSimple');
          return null;
        }
      } else {
        Logger.error(
            'Failed to create test order: ${response.statusCode} - ${response.body}',
            tag: 'WooCommerceServiceSimple');
        return null;
      }
    } catch (e) {
      Logger.error('Error creating test order: $e',
          tag: 'WooCommerceServiceSimple');
      return null;
    }
  }
}
