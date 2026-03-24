import 'package:flutter/foundation.dart';
import '../woocommerce_service.dart';

/// Simple order debugging utility
class SimpleOrderDebug {
  /// Test the complete order creation flow
  static Future<void> testOrderFlow() async {
    print('🧪 Starting Simple Order Debug Test...\n');

    // Test 1: WooCommerce Connection
    print('🔌 Testing WooCommerce Connection...');
    try {
      final isConnected = await WooCommerceService.testConnection();
      if (isConnected) {
        print('✅ WooCommerce connection successful');
      } else {
        print('❌ WooCommerce connection failed');
      }
    } catch (e) {
      print('❌ WooCommerce connection error: $e');
    }

    // Test 2: Product Search
    print('\n🔍 Testing Product Search...');
    try {
      final products =
          await WooCommerceService.getProducts(search: 'T-Shirt', perPage: 5);
      print('Found ${products.length} products');

      for (final product in products) {
        print(
            '  - ${product.name} (ID: ${product.id}, Price: ${product.formattedPrice})');
      }

      if (products.isNotEmpty) {
        print('✅ Product search successful');
      } else {
        print('⚠️ No products found');
      }
    } catch (e) {
      print('❌ Product search error: $e');
    }

    // Test 3: Manual API Test
    print('\n🌐 Testing Manual API Call...');
    try {
      final response = await WooCommerceService.testConnection();
      if (response) {
        print('✅ Manual API test successful');
      } else {
        print('❌ Manual API test failed');
      }
    } catch (e) {
      print('❌ Manual API test error: $e');
    }

    print('\n✅ Simple Order Debug Test Completed!');
  }

  /// Get detailed system information
  static Map<String, dynamic> getSystemInfo() {
    return {
      'timestamp': DateTime.now().toIso8601String(),
      'platform': defaultTargetPlatform.name,
      'debug_mode': kDebugMode,
      'flutter_version': '3.x',
    };
  }

  /// Log system information
  static void logSystemInfo() {
    final info = getSystemInfo();
    print('📊 System Information:');
    for (final entry in info.entries) {
      print('  ${entry.key}: ${entry.value}');
    }
  }
}

/// Run the simple order debug test
void main() async {
  SimpleOrderDebug.logSystemInfo();
  await SimpleOrderDebug.testOrderFlow();
}
