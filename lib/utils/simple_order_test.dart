import 'package:ecommerce_int2/utils/price_formatter.dart';
import '../woocommerce_service.dart';
import '../models/cart_item.dart';
import '../models/product.dart';
import '../models/address.dart';
import '../models/order.dart';

/// Simple order creation test
void main() async {
  print('🧪 Starting Simple Order Creation Test...\n');

  // Test 1: WooCommerce Connection Test
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

  // Test 2: Product Search Test
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

  // Test 3: Simple Order Creation Test
  print('\n🛒 Testing Order Creation...');
  try {
    // Create test product using correct constructor
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

    // Create test addresses with required userId
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

  print('\n✅ Simple Order Creation Test Completed!');
}
