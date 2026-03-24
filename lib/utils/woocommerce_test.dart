import 'package:ecommerce_int2/woocommerce_service.dart';
import 'package:ecommerce_int2/models/product.dart';
import 'package:ecommerce_int2/models/address.dart';
import 'package:ecommerce_int2/models/cart_item.dart';
import 'package:ecommerce_int2/models/order.dart';
import 'package:ecommerce_int2/utils/logger.dart';

/// Test class for WooCommerce integration
class WooCommerceTest {
  /// Test WooCommerce order creation
  static Future<void> testOrderCreation() async {
    Logger.info('Starting WooCommerce order creation test',
        tag: 'WooCommerceTest');

    try {
      // Create test product
      final product = Product(
        'assets/headphones.png',
        'Test Product',
        'Test Description',
        29.99,
      );

      // Create test cart item
      final cartItem = CartItem(
        product: product,
        quantity: 2,
      );

      // Create test address
      final address = Address(
        id: 'test-address-1',
        userId: 'test-user-1',
        firstName: 'John',
        lastName: 'Doe',
        addressLine1: '123 Test Street',
        addressLine2: 'Apt 1',
        city: 'Test City',
        state: 'Test State',
        postalCode: '12345',
        country: 'US',
        phone: '123-456-7890',
        email: 'john.doe@test.com',
        type: AddressType.home,
        isDefault: true,
        createdAt: DateTime.now(),
      );

      // Test WooCommerce order creation
      final wooOrder = await WooCommerceService.createOrder(
        customerId: 'test-user-1',
        cartItems: [cartItem],
        shippingAddress: address,
        billingAddress: address,
        paymentMethod: PaymentMethod.creditCard,
        shippingCost: 5.99,
        tax: 2.50,
        discount: 0.0,
        notes: 'Test order from Flutter app',
        metadata: {
          'test': true,
          'source': 'flutter_app',
        },
      );

      if (wooOrder != null) {
        Logger.info(
          '✅ WooCommerce order created successfully!',
          tag: 'WooCommerceTest',
        );
        Logger.info(
          'Order ID: ${wooOrder.id}',
          tag: 'WooCommerceTest',
        );
        Logger.info(
          'Order Status: ${wooOrder.status}',
          tag: 'WooCommerceTest',
        );
        Logger.info(
          'Order Total: \$${wooOrder.total}',
          tag: 'WooCommerceTest',
        );
        Logger.info(
          'Line Items: ${wooOrder.lineItems.length}',
          tag: 'WooCommerceTest',
        );
      } else {
        Logger.error(
          '❌ Failed to create WooCommerce order',
          tag: 'WooCommerceTest',
        );
      }
    } catch (e, stackTrace) {
      Logger.error(
        '❌ WooCommerce test failed: $e',
        tag: 'WooCommerceTest',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Test WooCommerce customer orders retrieval
  static Future<void> testGetCustomerOrders() async {
    Logger.info('Testing WooCommerce customer orders retrieval',
        tag: 'WooCommerceTest');

    try {
      final orders = await WooCommerceService.getCustomerOrders('test-user-1');

      Logger.info(
        '✅ Retrieved ${orders.length} orders for customer',
        tag: 'WooCommerceTest',
      );

      for (final order in orders) {
        Logger.info(
          'Order ${order.id}: ${order.status} - \$${order.total}',
          tag: 'WooCommerceTest',
        );
      }
    } catch (e, stackTrace) {
      Logger.error(
        '❌ Failed to retrieve customer orders: $e',
        tag: 'WooCommerceTest',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Test order status update
  static Future<void> testUpdateOrderStatus() async {
    Logger.info('Testing WooCommerce order status update',
        tag: 'WooCommerceTest');

    try {
      // This would need a real order ID from a previous test
      final success =
          await WooCommerceService.updateOrderStatus(1, 'processing');

      if (success) {
        Logger.info('✅ Order status updated successfully',
            tag: 'WooCommerceTest');
      } else {
        Logger.warning('⚠️ Order status update failed', tag: 'WooCommerceTest');
      }
    } catch (e, stackTrace) {
      Logger.error(
        '❌ Failed to update order status: $e',
        tag: 'WooCommerceTest',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Run all tests
  static Future<void> runAllTests() async {
    Logger.info('🚀 Starting WooCommerce integration tests',
        tag: 'WooCommerceTest');

    await testOrderCreation();
    await Future.delayed(Duration(seconds: 2));

    await testGetCustomerOrders();
    await Future.delayed(Duration(seconds: 2));

    await testUpdateOrderStatus();

    Logger.info('✅ All WooCommerce tests completed', tag: 'WooCommerceTest');
  }
}
