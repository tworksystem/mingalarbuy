import 'package:ecommerce_int2/utils/price_formatter.dart';

import '../woocommerce_service_simple.dart';

/// Simple working test without model conflicts
void main() async {
  print('🧪 Starting Simple Working Test...\n');

  // Test 1: WooCommerce Connection
  print('🔌 Testing WooCommerce Connection...');
  try {
    final isConnected = await WooCommerceServiceSimple.testConnection();
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
    final products = await WooCommerceServiceSimple.getProducts(
        search: 'T-Shirt', perPage: 5);
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

  // Test 3: Create Test Order
  print('\n🛒 Testing Order Creation...');
  try {
    final order = await WooCommerceServiceSimple.createTestOrder();
    if (order != null) {
      print('✅ Test order created successfully!');
      print('  Order ID: ${order.id}');
      print('  Status: ${order.status}');
      print('  Total: ${PriceFormatter.format(order.total)}');
      print('  Currency: ${order.currency}');
    } else {
      print('❌ Test order creation failed');
    }
  } catch (e) {
    print('❌ Test order creation error: $e');
  }

  print('\n✅ Simple Working Test Completed!');
}
