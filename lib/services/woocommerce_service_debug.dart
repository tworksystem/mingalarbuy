import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/woocommerce_config.dart';
import '../models/product.dart';
import 'woocommerce_service.dart';

/// Debug version of WooCommerce Service to test API responses
class WooCommerceServiceDebug {
  /// Test API connection and get raw response
  static Future<void> testAPIConnection() async {
    print('🔍 Testing WooCommerce API Connection...\n');

    try {
      final url = WooCommerceConfig.buildAuthUrl(
        WooCommerceConfig.productsEndpoint,
        queryParameters: {
          'per_page': '3',
          'page': '1',
        },
      );

      print('📡 API URL: $url\n');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'HomeAid-Flutter-App/1.0',
        },
      ).timeout(
        const Duration(seconds: 30),
      );

      print('📊 Response Status: ${response.statusCode}');
      print('📊 Response Headers: ${response.headers}');
      print('📊 Response Body Length: ${response.body.length}');

      if (response.statusCode == 200) {
        print('✅ API Response Success\n');

        final data = json.decode(response.body);
        print('📦 Response Type: ${data.runtimeType}');
        print('📦 Items Count: ${data is List ? data.length : 'Not a list'}');

        if (data is List && data.isNotEmpty) {
          print('\n🔍 Analyzing first product:');
          final firstProduct = data.first;

          print('   - ID: ${firstProduct['id']}');
          print('   - Name: ${firstProduct['name']}');
          print('   - Price: ${firstProduct['price']}');
          print('   - Status: ${firstProduct['status']}');

          // Check images
          final images = firstProduct['images'];
          print('   - Images Type: ${images.runtimeType}');
          print(
              '   - Images Count: ${images is List ? images.length : 'Not a list'}');

          if (images is List && images.isNotEmpty) {
            print('   - First Image:');
            final firstImage = images.first;
            print('     * ID: ${firstImage['id']}');
            print('     * SRC: ${firstImage['src']}');
            print('     * Name: ${firstImage['name']}');
            print('     * Alt: ${firstImage['alt']}');

            // Test image URL
            final imageUrl = firstImage['src'];
            if (imageUrl != null && imageUrl.isNotEmpty) {
              print('\n🖼️ Testing image URL: $imageUrl');
              await _testImageUrl(imageUrl);
            } else {
              print('❌ No image URL found');
            }
          } else {
            print('❌ No images found in product');
          }
        } else {
          print('❌ No products in response');
        }
      } else {
        print('❌ API Response Error');
        print('Response Body: ${response.body}');
      }
    } catch (e) {
      print('❌ API Test Error: $e');
    }
  }

  /// Test specific image URL
  static Future<void> _testImageUrl(String imageUrl) async {
    try {
      print('   🔗 Testing image URL...');

      final uri = Uri.parse(imageUrl);
      print('   ✅ URL parsed successfully');
      print('   📋 Scheme: ${uri.scheme}');
      print('   📋 Host: ${uri.host}');
      print('   📋 Path: ${uri.path}');

      // Test if URL is accessible
      final response = await http.head(Uri.parse(imageUrl)).timeout(
            const Duration(seconds: 10),
          );

      print('   📊 Image Response Status: ${response.statusCode}');
      print('   📊 Content Type: ${response.headers['content-type']}');
      print('   📊 Content Length: ${response.headers['content-length']}');

      if (response.statusCode == 200) {
        print('   ✅ Image URL is accessible');
      } else {
        print('   ❌ Image URL not accessible');
      }
    } catch (e) {
      print('   ❌ Image URL test error: $e');
    }
  }

  /// Test WooCommerce configuration
  static void testConfiguration() {
    print('🔧 Testing WooCommerce Configuration...\n');

    print('Base URL: ${WooCommerceConfig.baseUrl}');
    print('API Version: ${WooCommerceConfig.apiVersion}');
    print('Consumer Key: ${WooCommerceConfig.consumerKey.substring(0, 10)}...');
    print(
        'Consumer Secret: ${WooCommerceConfig.consumerSecret.substring(0, 10)}...');

    final productsUrl = WooCommerceConfig.productsEndpoint;
    print('Products Endpoint: $productsUrl');

    final authUrl =
        WooCommerceConfig.buildAuthUrl(productsUrl, queryParameters: {
      'per_page': '1',
    });
    print('Full Auth URL: $authUrl\n');
  }

  /// Test product conversion
  static Future<void> testProductConversion() async {
    print('🔄 Testing Product Conversion...\n');

    try {
      final service = WooCommerceService();
      final products = await service.getProducts(perPage: 2);

      if (products.isNotEmpty) {
        final wooProduct = products.first;
        print('WooCommerce Product:');
        print('  - ID: ${wooProduct.id}');
        print('  - Name: ${wooProduct.name}');
        print('  - Images: ${wooProduct.images.length}');

        if (wooProduct.images.isNotEmpty) {
          print('  - First Image URL: ${wooProduct.images.first.src}');
        }

        // Convert to legacy Product
        final legacyProduct = Product.fromWooCommerce(wooProduct);
        print('\nLegacy Product:');
        print('  - Name: ${legacyProduct.name}');
        print('  - Image: "${legacyProduct.image}"');
        print('  - Image Length: ${legacyProduct.image.length}');
        print('  - Image Empty: ${legacyProduct.image.isEmpty}');
        print(
            '  - Starts with http: ${legacyProduct.image.startsWith('http')}');
      }
    } catch (e) {
      print('❌ Product conversion test error: $e');
    }
  }

  /// Run all debug tests
  static Future<void> runAllTests() async {
    print('🚀 Starting WooCommerce Debug Tests...\n');

    testConfiguration();
    await testAPIConnection();
    await testProductConversion();

    print('\n✅ Debug Tests Complete');
  }
}
