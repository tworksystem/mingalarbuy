import 'package:flutter_test/flutter_test.dart';
import '../models/cart_item.dart';
import '../models/product.dart';
import '../models/address.dart';
import '../models/order.dart';
import '../woocommerce_service.dart';
import '../utils/order_debug_helper.dart';

/// Comprehensive order flow test
void main() async {
  print('🧪 Starting Comprehensive Order Flow Test...\n');

  // Test 1: WooCommerce Connection
  await _testWooCommerceConnection();

  // Test 2: Product Search
  await _testProductSearch();

  // Test 3: Order Creation with Debug
  await _testOrderCreationWithDebug();

  print('\n✅ Order Flow Test Completed!');
}

/// Test WooCommerce connection
Future<void> _testWooCommerceConnection() async {
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

/// Test product search
Future<void> _testProductSearch() async {
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

/// Test order creation with comprehensive debugging
Future<void> _testOrderCreationWithDebug() async {
  print('\n🛒 Testing Order Creation with Debug...');

  try {
    // Create test data
    final testProduct = Product(
      'https://example.com/tshirt.jpg',
      'Test T-Shirt',
      'A test t-shirt for order creation',
      25.99,
    );

    final cartItem = CartItem(
      product: testProduct,
      quantity: 2,
    );

    final shippingAddress = Address(
      id: 'test-shipping',
      userId: 'test-user-123',
      firstName: 'John',
      lastName: 'Doe',
      company: '',
      addressLine1: '123 Main Street',
      addressLine2: 'Apt 4B',
      city: 'New York',
      state: 'NY',
      postalCode: '10001',
      country: 'US',
      phone: '555-123-4567',
      email: 'john.doe@example.com',
      type: AddressType.home,
      isDefault: true,
      createdAt: DateTime.now(),
    );

    final billingAddress = Address(
      id: 'test-billing',
      userId: 'test-user-123',
      firstName: 'John',
      lastName: 'Doe',
      company: '',
      addressLine1: '123 Main Street',
      addressLine2: 'Apt 4B',
      city: 'New York',
      state: 'NY',
      postalCode: '10001',
      country: 'US',
      phone: '555-123-4567',
      email: 'john.doe@example.com',
      type: AddressType.home,
      isDefault: true,
      createdAt: DateTime.now(),
    );

    // Run comprehensive debug test
    final success = await OrderDebugHelper.testOrderCreation(
      userId: 'test-user-123',
      cartItems: [cartItem],
      shippingAddress: shippingAddress,
      billingAddress: billingAddress,
      paymentMethod: PaymentMethod.creditCard,
    );

    if (success) {
      print('✅ Order creation debug test passed');
    } else {
      print('❌ Order creation debug test failed');
    }
  } catch (e, stackTrace) {
    print('❌ Order creation debug test error: $e');
    print('Stack trace: $stackTrace');
  }
}
