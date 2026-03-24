import '../models/cart_item.dart';
import '../models/product.dart';
import '../models/address.dart';
import '../models/order.dart';
import '../woocommerce_service.dart';
import '../utils/logger.dart';

/// Comprehensive order debugging helper
class OrderDebugHelper {
  /// Debug the complete order creation process
  static Future<Map<String, dynamic>> debugOrderCreation({
    required String userId,
    required List<CartItem> cartItems,
    required Address shippingAddress,
    required Address billingAddress,
    required PaymentMethod paymentMethod,
    double shippingCost = 0.0,
    double tax = 0.0,
    double discount = 0.0,
  }) async {
    final debugInfo = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'userId': userId,
      'cartItemsCount': cartItems.length,
      'paymentMethod': paymentMethod.name,
      'shippingCost': shippingCost,
      'tax': tax,
      'discount': discount,
      'steps': <Map<String, dynamic>>[],
      'errors': <String>[],
      'success': false,
    };

    try {
      // Step 1: Validate input data
      await _debugStep(debugInfo, 'Input Validation', () async {
        if (userId.isEmpty) throw Exception('User ID is empty');
        if (cartItems.isEmpty) throw Exception('Cart is empty');
        if (shippingAddress.firstName.isEmpty) {
          throw Exception('Shipping address first name is empty');
        }
        if (billingAddress.firstName.isEmpty) {
          throw Exception('Billing address first name is empty');
        }

        Logger.info('Input validation passed', tag: 'OrderDebugHelper');
        return 'All input data is valid';
      });

      // Step 2: Test WooCommerce connection
      await _debugStep(debugInfo, 'WooCommerce Connection Test', () async {
        final isConnected = await WooCommerceService.testConnection();
        if (!isConnected) {
          throw Exception('WooCommerce API connection failed');
        }
        Logger.info('WooCommerce connection test passed',
            tag: 'OrderDebugHelper');
        return 'WooCommerce API is accessible';
      });

      // Step 3: Validate cart items
      await _debugStep(debugInfo, 'Cart Items Validation', () async {
        for (int i = 0; i < cartItems.length; i++) {
          final item = cartItems[i];
          if (item.product.name.isEmpty) {
            throw Exception('Cart item $i has empty product name');
          }
          if (item.quantity <= 0) {
            throw Exception(
                'Cart item $i has invalid quantity: ${item.quantity}');
          }
          if (item.product.price <= 0) {
            throw Exception(
                'Cart item $i has invalid price: ${item.product.price}');
          }
        }
        Logger.info('Cart items validation passed', tag: 'OrderDebugHelper');
        return 'All cart items are valid';
      });

      // Step 4: Test product search
      await _debugStep(debugInfo, 'Product Search Test', () async {
        final products =
            await WooCommerceService.getProducts(search: 'T-Shirt', perPage: 5);
        if (products.isEmpty) {
          throw Exception('No products found in WooCommerce');
        }
        Logger.info(
            'Product search test passed - found ${products.length} products',
            tag: 'OrderDebugHelper');
        return 'Found ${products.length} products in WooCommerce';
      });

      // Step 5: Test order creation with minimal data
      await _debugStep(debugInfo, 'Minimal Order Creation Test', () async {
        // Create a test product
        final testProduct = Product(
          'https://example.com/test.jpg',
          'Test Product',
          'Test Description',
          10.0,
        );

        final testCartItem = CartItem(
          product: testProduct,
          quantity: 1,
        );

        final testOrder = await WooCommerceService.createOrder(
          customerId: userId,
          cartItems: [testCartItem],
          shippingAddress: shippingAddress,
          billingAddress: billingAddress,
          paymentMethod: paymentMethod,
          shippingCost: 0.0,
          tax: 0.0,
          discount: 0.0,
          notes: 'Debug test order',
          metadata: {'debug': true},
        );

        if (testOrder == null) {
          throw Exception('Test order creation returned null');
        }

        Logger.info(
            'Minimal order creation test passed - Order ID: ${testOrder.id}',
            tag: 'OrderDebugHelper');
        return 'Test order created successfully with ID: ${testOrder.id}';
      });

      // Step 6: Test with actual cart items
      await _debugStep(debugInfo, 'Actual Cart Items Order Test', () async {
        final actualOrder = await WooCommerceService.createOrder(
          customerId: userId,
          cartItems: cartItems,
          shippingAddress: shippingAddress,
          billingAddress: billingAddress,
          paymentMethod: paymentMethod,
          shippingCost: shippingCost,
          tax: tax,
          discount: discount,
          notes: 'Debug actual order',
          metadata: {'debug': true, 'cart_items_count': cartItems.length},
        );

        if (actualOrder == null) {
          throw Exception('Actual order creation returned null');
        }

        Logger.info(
            'Actual order creation test passed - Order ID: ${actualOrder.id}',
            tag: 'OrderDebugHelper');
        return 'Actual order created successfully with ID: ${actualOrder.id}';
      });

      debugInfo['success'] = true;
      Logger.info('All order creation tests passed successfully',
          tag: 'OrderDebugHelper');
    } catch (e, stackTrace) {
      debugInfo['errors'].add('$e');
      debugInfo['stackTrace'] = stackTrace.toString();
      Logger.error('Order creation debug failed: $e',
          tag: 'OrderDebugHelper', error: e, stackTrace: stackTrace);
    }

    return debugInfo;
  }

  /// Debug a single step
  static Future<void> _debugStep(
    Map<String, dynamic> debugInfo,
    String stepName,
    Future<String> Function() stepFunction,
  ) async {
    final stepInfo = <String, dynamic>{
      'name': stepName,
      'startTime': DateTime.now().toIso8601String(),
      'success': false,
      'result': '',
      'error': '',
    };

    try {
      final result = await stepFunction();
      stepInfo['success'] = true;
      stepInfo['result'] = result;
      stepInfo['endTime'] = DateTime.now().toIso8601String();

      Logger.info('Debug step passed: $stepName', tag: 'OrderDebugHelper');
    } catch (e, stackTrace) {
      stepInfo['success'] = false;
      stepInfo['error'] = e.toString();
      stepInfo['endTime'] = DateTime.now().toIso8601String();

      debugInfo['errors'].add('$stepName: $e');
      Logger.error('Debug step failed: $stepName - $e',
          tag: 'OrderDebugHelper', error: e, stackTrace: stackTrace);
    }

    (debugInfo['steps'] as List<Map<String, dynamic>>).add(stepInfo);
  }

  /// Get detailed debug report
  static String getDebugReport(Map<String, dynamic> debugInfo) {
    final buffer = StringBuffer();

    buffer.writeln('=== ORDER CREATION DEBUG REPORT ===');
    buffer.writeln('Timestamp: ${debugInfo['timestamp']}');
    buffer.writeln('User ID: ${debugInfo['userId']}');
    buffer.writeln('Cart Items: ${debugInfo['cartItemsCount']}');
    buffer.writeln('Payment Method: ${debugInfo['paymentMethod']}');
    buffer.writeln('Success: ${debugInfo['success']}');
    buffer.writeln();

    if (debugInfo['errors'].isNotEmpty) {
      buffer.writeln('=== ERRORS ===');
      for (final error in debugInfo['errors']) {
        buffer.writeln('❌ $error');
      }
      buffer.writeln();
    }

    buffer.writeln('=== DEBUG STEPS ===');
    final steps = debugInfo['steps'] as List<Map<String, dynamic>>;
    for (final step in steps) {
      final status = step['success'] ? '✅' : '❌';
      buffer.writeln('$status ${step['name']}');
      if (step['result'].isNotEmpty) {
        buffer.writeln('   Result: ${step['result']}');
      }
      if (step['error'].isNotEmpty) {
        buffer.writeln('   Error: ${step['error']}');
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// Test order creation with comprehensive logging
  static Future<bool> testOrderCreation({
    required String userId,
    required List<CartItem> cartItems,
    required Address shippingAddress,
    required Address billingAddress,
    required PaymentMethod paymentMethod,
  }) async {
    try {
      Logger.info('Starting comprehensive order creation test',
          tag: 'OrderDebugHelper');

      final debugInfo = await debugOrderCreation(
        userId: userId,
        cartItems: cartItems,
        shippingAddress: shippingAddress,
        billingAddress: billingAddress,
        paymentMethod: paymentMethod,
      );

      final report = getDebugReport(debugInfo);
      Logger.info('Debug Report:\n$report', tag: 'OrderDebugHelper');

      return debugInfo['success'] as bool;
    } catch (e, stackTrace) {
      Logger.error('Order creation test failed: $e',
          tag: 'OrderDebugHelper', error: e, stackTrace: stackTrace);
      return false;
    }
  }
}
