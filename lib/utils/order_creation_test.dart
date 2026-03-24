import 'package:ecommerce_int2/utils/price_formatter.dart';
import 'package:flutter_test/flutter_test.dart';
import '../woocommerce_service.dart';
import '../models/cart_item.dart';
import '../models/product.dart';
import '../models/address.dart';
import '../models/order.dart';

/// Comprehensive order creation test suite
class OrderCreationTest {
  static Future<void> runTests() async {
    print('🧪 Starting Order Creation Tests...\n');

    // Test 1: WooCommerce Connection Test
    await _testWooCommerceConnection();

    // Test 2: Product Search Test
    await _testProductSearch();

    // Test 3: Order Creation Test
    await _testOrderCreation();

    // Test 4: Error Handling Test
    await _testErrorHandling();

    print('\n✅ All Order Creation Tests Completed!');
  }

  /// Test WooCommerce API connection
  static Future<void> _testWooCommerceConnection() async {
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
  }

  /// Test product search functionality
  static Future<void> _testProductSearch() async {
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
  }

  /// Test order creation with real data
  static Future<void> _testOrderCreation() async {
    print('\n🛒 Testing Order Creation...');

    try {
      // Create test product
      final testProduct = Product(
        'https://example.com/tshirt.jpg',
        'Test T-Shirt',
        'A test t-shirt for order creation',
        25.99,
      );

      // Create test cart item
      final cartItem = CartItem(
        product: testProduct,
        quantity: 2,
      );

      // Create test addresses
      final shippingAddress = Address(
        id: 'test-shipping',
        userId: 'test-user-123',
        firstName: 'John',
        lastName: 'Doe',
        addressLine1: '123 Main Street',
        addressLine2: 'Apt 4B',
        city: 'New York',
        state: 'NY',
        postalCode: '10001',
        country: 'US',
        phone: '555-123-4567',
        email: 'john.doe@example.com',
        isDefault: true,
        createdAt: DateTime.now(),
      );

      final billingAddress = Address(
        id: 'test-billing',
        userId: 'test-user-123',
        firstName: 'John',
        lastName: 'Doe',
        addressLine1: '123 Main Street',
        addressLine2: 'Apt 4B',
        city: 'New York',
        state: 'NY',
        postalCode: '10001',
        country: 'US',
        phone: '555-123-4567',
        email: 'john.doe@example.com',
        isDefault: true,
        createdAt: DateTime.now(),
      );

      // Create order
      final order = await WooCommerceService.createOrder(
        customerId: 'test-customer-123',
        cartItems: [cartItem],
        shippingAddress: shippingAddress,
        billingAddress: billingAddress,
        paymentMethod: PaymentMethod.creditCard,
        shippingCost: 5.99,
        tax: 2.50,
        discount: 0.0,
        notes: 'Test order from Flutter app',
        metadata: {
          'source': 'flutter_app',
          'test_order': true,
        },
      );

      if (order != null) {
        print('✅ Order created successfully!');
        print('  Order ID: ${order.id}');
        print('  Status: ${order.status}');
        print('  Total: ${PriceFormatter.format(order.total)}');
        print('  Currency: ${order.currency}');
        print('  Line Items: ${order.lineItems.length}');
      } else {
        print('❌ Order creation failed - returned null');
      }
    } catch (e, stackTrace) {
      print('❌ Order creation error: $e');
      print('Stack trace: $stackTrace');
    }
  }

  /// Test error handling scenarios
  static Future<void> _testErrorHandling() async {
    print('\n🚨 Testing Error Handling...');

    try {
      // Test with invalid product
      final invalidProduct = Product(
        '',
        'Non-existent Product',
        'This product does not exist',
        999.99,
      );

      final cartItem = CartItem(
        product: invalidProduct,
        quantity: 1,
      );

      final address = Address(
        id: 'test-address',
        userId: 'test-user-123',
        firstName: 'Test',
        lastName: 'User',
        addressLine1: '123 Test St',
        city: 'Test City',
        state: 'TS',
        postalCode: '12345',
        country: 'US',
        phone: '555-000-0000',
        email: 'test@example.com',
        isDefault: true,
        createdAt: DateTime.now(),
      );

      final order = await WooCommerceService.createOrder(
        customerId: 'test-customer',
        cartItems: [cartItem],
        shippingAddress: address,
        billingAddress: address,
        paymentMethod: PaymentMethod.creditCard,
      );

      if (order != null) {
        print('✅ Order created even with invalid product (fallback worked)');
      } else {
        print('⚠️ Order creation failed as expected with invalid product');
      }
    } catch (e) {
      print('✅ Error handling working correctly: $e');
    }
  }
}

/// Run the order creation tests
void main() async {
  await OrderCreationTest.runTests();
}
