/// Test file for WooCommerce API connection
/// Run this to verify your WooCommerce integration is working
///
/// Usage: Import this file in main.dart and call testWooCommerceConnection()
/// Or create a test button in your UI that calls this function

import 'package:ecommerce_int2/config/woocommerce_config.dart';
import 'package:ecommerce_int2/services/woocommerce_service.dart';

Future<void> testWooCommerceConnection() async {
  print('=== WooCommerce Connection Test ===\n');

  // Test 1: Configuration
  print('1. Testing Configuration...');
  print('   Base URL: ${WooCommerceConfig.baseUrl}');
  print('   API Version: ${WooCommerceConfig.apiVersion}');
  print('   Products Endpoint: ${WooCommerceConfig.productsEndpoint}');
  print('   ✓ Configuration loaded\n');

  // Test 2: Connection Check
  print('2. Testing API Connection...');
  try {
    final service = WooCommerceService();
    final isConnected = await service.checkConnection();
    if (isConnected) {
      print('   ✓ API connection successful\n');
    } else {
      print('   ✗ API connection failed\n');
      return;
    }
  } catch (e) {
    print('   ✗ Connection error: $e\n');
    return;
  }

  // Test 3: Fetch Products
  print('3. Testing Product Fetching...');
  try {
    final service = WooCommerceService();
    final products = await service.getProducts(perPage: 5);
    print('   ✓ Fetched ${products.length} products');

    if (products.isNotEmpty) {
      print('   Sample product:');
      final product = products.first;
      print('     - ID: ${product.id}');
      print('     - Name: ${product.name}');
      print('     - Price: \$${product.price}');
      print('     - Images: ${product.images.length}');
      if (product.images.isNotEmpty) {
        print('     - Image URL: ${product.images.first.src}');
      }
      print(
          '     - Categories: ${product.categories.map((c) => c.name).join(", ")}');
      print('     - In Stock: ${product.stockStatus}');
    }
    print('');
  } catch (e) {
    print('   ✗ Product fetching error: $e\n');
    return;
  }

  // Test 4: Featured Products
  print('4. Testing Featured Products...');
  try {
    final service = WooCommerceService();
    final featured = await service.getFeaturedProducts(perPage: 3);
    print('   ✓ Fetched ${featured.length} featured products');
    for (var product in featured) {
      print('     - ${product.name} (\$${product.price})');
    }
    print('');
  } catch (e) {
    print('   ✗ Featured products error: $e\n');
  }

  // Test 5: On Sale Products
  print('5. Testing On Sale Products...');
  try {
    final service = WooCommerceService();
    final onSale = await service.getOnSaleProducts(perPage: 3);
    print('   ✓ Fetched ${onSale.length} on sale products');
    for (var product in onSale) {
      print(
          '     - ${product.name} (\$${product.price}, was \$${product.regularPrice})');
    }
    print('');
  } catch (e) {
    print('   ✗ On sale products error: $e\n');
  }

  // Test 6: Categories
  print('6. Testing Categories...');
  try {
    final service = WooCommerceService();
    final categories = await service.getCategories(page: 1);
    print('   ✓ Fetched ${categories.length} categories');
    for (var category in categories) {
      print('     - ${category['name']} (ID: ${category['id']})');
    }
    print('');
  } catch (e) {
    print('   ✗ Categories error: $e\n');
  }

  print('=== Test Complete ===');
}

/// Quick test that returns true if connection works
Future<bool> quickConnectionTest() async {
  try {
    final service = WooCommerceService();
    await service.getProducts(perPage: 1);
    return true;
  } catch (e) {
    print('Connection test failed: $e');
    return false;
  }
}
