import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/order.dart';
import '../models/address.dart';
import '../models/cart_item.dart';
import '../models/product.dart';
import '../woocommerce_service.dart';
import '../models/woocommerce_order.dart';
import '../utils/logger.dart';
import '../utils/monitoring.dart';
import '../utils/data_validator.dart';
import '../services/offline_queue_service.dart';
import '../services/connectivity_service.dart';
import '../services/point_service.dart';
import '../models/point_transaction.dart';

class OrderProvider with ChangeNotifier {
  List<Order> _orders = [];
  bool _isLoading = false;
  bool _isInitialized = false;
  String? _errorMessage;
  String? _currentUserId; // Track current user ID
  static const String _ordersKey = 'user_orders';

  // Getters
  List<Order> get orders => List.unmodifiable(_orders);
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  String? get errorMessage => _errorMessage;
  bool get hasOrders => _orders.isNotEmpty;
  bool get isEmpty => _orders.isEmpty;

  // Get orders by status
  List<Order> getOrdersByStatus(OrderStatus status) {
    return _orders.where((order) => order.status == status).toList();
  }

  // Get active orders (not completed or cancelled)
  List<Order> get activeOrders =>
      _orders.where((order) => order.isActive).toList();

  // Get completed orders
  List<Order> get completedOrders =>
      _orders.where((order) => order.isCompleted).toList();

  // Get pending orders
  List<Order> get pendingOrders => getOrdersByStatus(OrderStatus.pending);

  // Get processing orders
  List<Order> get processingOrders => getOrdersByStatus(OrderStatus.processing);

  // Get shipped orders
  List<Order> get shippedOrders => getOrdersByStatus(OrderStatus.shipped);

  // Get delivered orders
  List<Order> get deliveredOrders => getOrdersByStatus(OrderStatus.delivered);

  // Get cancelled orders
  List<Order> get cancelledOrders => getOrdersByStatus(OrderStatus.cancelled);

  // Get orders by payment status
  List<Order> getOrdersByPaymentStatus(PaymentStatus status) {
    return _orders.where((order) => order.paymentStatus == status).toList();
  }

  // Get total spent
  double get totalSpent => _orders
      .where((order) => order.isCompleted)
      .fold(0.0, (sum, order) => sum + order.total);

  // Get formatted total spent
  String get formattedTotalSpent => '${totalSpent.toStringAsFixed(2)} Ks';

  OrderProvider() {
    _loadOrdersFromStorage();
    _registerOfflineQueueCallback();
  }

  /// Register order creation callback with offline queue service
  void _registerOfflineQueueCallback() {
    OfflineQueueService().setOrderCreationCallback(
      ({
        required String userId,
        required List<CartItem> cartItems,
        required Address shippingAddress,
        required Address billingAddress,
        required PaymentMethod paymentMethod,
        double shippingCost = 0.0,
        double tax = 0.0,
        double discount = 0.0,
        String? notes,
        Map<String, dynamic>? metadata,
      }) async {
        return await createOrder(
          userId: userId,
          cartItems: cartItems,
          shippingAddress: shippingAddress,
          billingAddress: billingAddress,
          paymentMethod: paymentMethod,
          shippingCost: shippingCost,
          tax: tax,
          discount: discount,
          notes: notes,
          metadata: metadata,
        );
      },
    );
  }

  /// Load orders from SharedPreferences
  Future<void> _loadOrdersFromStorage() async {
    _setLoading(true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final ordersJson = prefs.getString(_ordersKey);

      if (ordersJson != null) {
        final List<dynamic> ordersData = json.decode(ordersJson);
        _orders = ordersData
            .map((order) => Order.fromJson(order as Map<String, dynamic>))
            .toList();
        Logger.debug('Orders loaded from storage - ${_orders.length} orders',
            tag: 'OrderProvider');
      }
      _isInitialized = true;
    } catch (e, stackTrace) {
      Logger.error('Error loading orders from storage: $e',
          tag: 'OrderProvider', error: e, stackTrace: stackTrace);
      _setError('Failed to load orders');
      _isInitialized = true; // Mark as initialized even on error
    } finally {
      _setLoading(false);
    }
  }

  /// Save orders to SharedPreferences
  Future<void> _saveOrdersToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ordersJson =
          json.encode(_orders.map((order) => order.toJson()).toList());
      await prefs.setString(_ordersKey, ordersJson);
      Logger.debug('Orders saved to storage - ${_orders.length} orders',
          tag: 'OrderProvider');
    } catch (e, stackTrace) {
      Logger.error('Error saving orders to storage: $e',
          tag: 'OrderProvider', error: e, stackTrace: stackTrace);
    }
  }

  /// Create a new order from cart items
  Future<Order?> createOrder({
    required String userId,
    required List<CartItem> cartItems,
    required Address shippingAddress,
    required Address billingAddress,
    required PaymentMethod paymentMethod,
    double shippingCost = 0.0,
    double tax = 0.0,
    double discount = 0.0,
    String? notes,
    Map<String, dynamic>? metadata,
  }) async {
    _setLoading(true);
    _clearError();

    try {
      Logger.info('Creating order for user: $userId', tag: 'OrderProvider');

      // Track order creation start
      final startTime = DateTime.now();
      MonitoringService.trackBusinessEvent('order_creation_started',
          userId: userId);

      // Enterprise-grade validation
      final validationResult = DataValidator.validateOrderData(
        userId: userId,
        cartItems: cartItems,
        shippingAddress: shippingAddress,
        billingAddress: billingAddress,
        paymentMethod: paymentMethod,
        shippingCost: shippingCost,
        tax: tax,
        discount: discount,
      );

      if (!validationResult.isValid) {
        MonitoringService.trackErrorEvent(
          'order_validation_failed',
          validationResult.errorMessage,
          userId: userId,
          severity: 'warning',
        );
        _setError('Order validation failed: ${validationResult.errorMessage}');
        return null;
      }

      // Check connectivity first
      final connectivityService = ConnectivityService();
      final isOnline = connectivityService.isConnected;

      // If offline OR WooCommerce connection test fails, queue order for later sync.
      // This prevents checkout from hard-failing due to transient network/timeout issues.
      bool shouldQueueOffline = !isOnline;
      if (isOnline) {
        final isConnected = await WooCommerceService.testConnection();
        if (!isConnected) {
          shouldQueueOffline = true;
          MonitoringService.trackErrorEvent(
            'woocommerce_connection_failed',
            'WooCommerce API connection test failed (will queue order for sync)',
            userId: userId,
            severity: 'warning',
          );
        }
      }

      if (shouldQueueOffline) {
        Logger.info(
          'Queuing order for sync (offline or backend unreachable)',
          tag: 'OrderProvider',
        );

        try {
          // Queue order for offline sync
          await OfflineQueueService().addToQueue(
            OfflineQueueItemType.createOrder,
            {
              'userId': userId,
              'cartItems': cartItems.map((item) => item.toJson()).toList(),
              'shippingAddress': shippingAddress.toJson(),
              'billingAddress': billingAddress.toJson(),
              'paymentMethod': paymentMethod.toString().split('.').last,
              'shippingCost': shippingCost,
              'tax': tax,
              'discount': discount,
              'notes': notes,
              'metadata': metadata,
            },
          );

          // Create local order (pending sync)
          final subtotal =
              cartItems.fold(0.0, (sum, item) => sum + item.totalPrice);
          final total = subtotal + shippingCost + tax - discount;

          final orderItems = cartItems
              .map((cartItem) => OrderItem(
                    product: cartItem.product,
                    quantity: cartItem.quantity,
                    unitPrice: cartItem.product.price,
                  ))
              .toList();

          final orderId = 'OFFLINE-${DateTime.now().millisecondsSinceEpoch}';

          final order = Order(
            id: orderId,
            userId: userId,
            items: orderItems,
            shippingAddress: shippingAddress,
            billingAddress: billingAddress,
            subtotal: subtotal,
            shippingCost: shippingCost,
            tax: tax,
            discount: discount,
            total: total,
            status: OrderStatus.pending,
            paymentStatus: PaymentStatus.pending,
            paymentMethod: paymentMethod,
            createdAt: DateTime.now(),
            notes: notes,
            metadata: {
              ...?metadata,
              'offline': true,
              'queued': true,
              'queued_at': DateTime.now().toIso8601String(),
            },
          );

          _orders.insert(0, order);
          await _saveOrdersToStorage();
          notifyListeners();

          Logger.info('Order queued for offline sync: $orderId',
              tag: 'OrderProvider');

          // Create pending transaction for offline order (non-blocking)
          _createPendingTransactionForOrder(userId, total, orderId)
              .catchError((e) {
            Logger.error(
                'Error creating pending transaction for offline order: $e',
                tag: 'OrderProvider',
                error: e);
          });

          return order;
        } catch (e, stackTrace) {
          Logger.error('Error queueing order for offline sync: $e',
              tag: 'OrderProvider', error: e, stackTrace: stackTrace);
          _setError('Failed to queue order for offline sync: $e');
          return null;
        }
      }

      // First, create order in WooCommerce backend
      WooCommerceOrder? wooOrder;
      try {
        Logger.info('Creating WooCommerce order for user: $userId',
            tag: 'OrderProvider');

        wooOrder = await WooCommerceService.createOrder(
          customerId: userId,
          cartItems: cartItems,
          shippingAddress: shippingAddress,
          billingAddress: billingAddress,
          paymentMethod: paymentMethod,
          shippingCost: shippingCost,
          tax: tax,
          discount: discount,
          notes: notes,
          metadata: metadata,
        );

        if (wooOrder == null) {
          throw Exception('Failed to create order in WooCommerce backend');
        }

        Logger.info(
          'WooCommerce order created successfully: ${wooOrder.id}',
          tag: 'OrderProvider',
        );

        // Track successful WooCommerce order creation
        MonitoringService.trackBusinessEvent('woocommerce_order_created',
            data: {'woocommerce_id': wooOrder.id.toString()}, userId: userId);
      } catch (e, stackTrace) {
        Logger.error(
          'Failed to create WooCommerce order: $e',
          tag: 'OrderProvider',
          error: e,
          stackTrace: stackTrace,
        );

        // Track WooCommerce order creation failure
        MonitoringService.trackErrorEvent(
          'woocommerce_order_creation_failed',
          e,
          userId: userId,
          severity: 'error',
        );

        _setError('Failed to create order in backend: $e');
        return null;
      }

      // Calculate totals
      final subtotal =
          cartItems.fold(0.0, (sum, item) => sum + item.totalPrice);
      final total = subtotal + shippingCost + tax - discount;

      // Create order items
      final orderItems = cartItems
          .map((cartItem) => OrderItem(
                product: cartItem.product,
                quantity: cartItem.quantity,
                unitPrice: cartItem.product.price,
              ))
          .toList();

      // Use WooCommerce order ID if available, otherwise generate local ID
      final orderId = wooOrder.id != null
          ? 'WC-${wooOrder.id}'
          : 'ORD-${DateTime.now().millisecondsSinceEpoch}';

      // Create local order with WooCommerce sync info
      final order = Order(
        id: orderId,
        userId: userId,
        items: orderItems,
        shippingAddress: shippingAddress,
        billingAddress: billingAddress,
        subtotal: subtotal,
        shippingCost: shippingCost,
        tax: tax,
        discount: discount,
        total: total,
        status: _mapWooCommerceStatus(wooOrder.status),
        paymentStatus: PaymentStatus.pending,
        paymentMethod: paymentMethod,
        createdAt: DateTime.now(),
        notes: notes,
        metadata: {
          ...?metadata,
          'woocommerce_id': wooOrder.id,
          'woocommerce_status': wooOrder.status,
          'sync_timestamp': DateTime.now().toIso8601String(),
        },
      );

      // Add to orders list
      _orders.insert(0, order); // Add to beginning for newest first
      await _saveOrdersToStorage();
      notifyListeners();

      Logger.info('Order created successfully: $orderId', tag: 'OrderProvider');

      // Track successful order creation
      final duration = DateTime.now().difference(startTime);
      MonitoringService.trackPerformanceEvent('order_creation', duration,
          userId: userId);
      MonitoringService.trackOrderCreation(
        orderId,
        total: total,
        itemCount: cartItems.length,
        paymentMethod: paymentMethod.name,
        userId: userId,
      );

      // Create pending transaction for order (non-blocking)
      _createPendingTransactionForOrder(userId, total, orderId).catchError((e) {
        Logger.error('Error creating pending transaction for order: $e',
            tag: 'OrderProvider', error: e);
      });

      return order;
    } catch (e) {
      Logger.error('Error creating order: $e', tag: 'OrderProvider', error: e);
      _setError('Failed to create order: $e');
      return null;
    } finally {
      _setLoading(false);
    }
  }

  /// Update order status
  Future<bool> updateOrderStatus(String orderId, OrderStatus newStatus) async {
    _setLoading(true);
    _clearError();

    try {
      final orderIndex = _orders.indexWhere((order) => order.id == orderId);
      if (orderIndex == -1) {
        _setError('Order not found');
        return false;
      }

      final order = _orders[orderIndex];
      final updatedOrder = order.copyWith(
        status: newStatus,
        updatedAt: DateTime.now(),
        shippedAt:
            newStatus == OrderStatus.shipped ? DateTime.now() : order.shippedAt,
        deliveredAt: newStatus == OrderStatus.delivered
            ? DateTime.now()
            : order.deliveredAt,
      );

      _orders[orderIndex] = updatedOrder;
      await _saveOrdersToStorage();
      notifyListeners();

      Logger.debug('Order status updated - $orderId to $newStatus',
          tag: 'OrderProvider');
      return true;
    } catch (e, stackTrace) {
      Logger.error('Error updating order status: $e',
          tag: 'OrderProvider', error: e, stackTrace: stackTrace);
      _setError('Failed to update order status');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Update payment status
  Future<bool> updatePaymentStatus(String orderId, PaymentStatus newStatus,
      {String? paymentId}) async {
    _setLoading(true);
    _clearError();

    try {
      final orderIndex = _orders.indexWhere((order) => order.id == orderId);
      if (orderIndex == -1) {
        _setError('Order not found');
        return false;
      }

      final order = _orders[orderIndex];
      final updatedOrder = order.copyWith(
        paymentStatus: newStatus,
        paymentId: paymentId ?? order.paymentId,
        updatedAt: DateTime.now(),
      );

      _orders[orderIndex] = updatedOrder;
      await _saveOrdersToStorage();
      notifyListeners();

      Logger.debug('Payment status updated - $orderId to $newStatus',
          tag: 'OrderProvider');
      return true;
    } catch (e, stackTrace) {
      Logger.error('Error updating payment status: $e',
          tag: 'OrderProvider', error: e, stackTrace: stackTrace);
      _setError('Failed to update payment status');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Add tracking number to order
  Future<bool> addTrackingNumber(String orderId, String trackingNumber) async {
    _setLoading(true);
    _clearError();

    try {
      final orderIndex = _orders.indexWhere((order) => order.id == orderId);
      if (orderIndex == -1) {
        _setError('Order not found');
        return false;
      }

      final order = _orders[orderIndex];
      final updatedOrder = order.copyWith(
        trackingNumber: trackingNumber,
        updatedAt: DateTime.now(),
      );

      _orders[orderIndex] = updatedOrder;
      await _saveOrdersToStorage();
      notifyListeners();

      Logger.debug('Tracking number added - $orderId', tag: 'OrderProvider');
      return true;
    } catch (e, stackTrace) {
      Logger.error('Error adding tracking number: $e',
          tag: 'OrderProvider', error: e, stackTrace: stackTrace);
      _setError('Failed to add tracking number');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Cancel order
  Future<bool> cancelOrder(String orderId) async {
    return await updateOrderStatus(orderId, OrderStatus.cancelled);
  }

  /// Get order by ID
  Order? getOrderById(String orderId) {
    try {
      return _orders.firstWhere((order) => order.id == orderId);
    } catch (e) {
      return null;
    }
  }

  /// Get orders by date range
  List<Order> getOrdersByDateRange(DateTime startDate, DateTime endDate) {
    return _orders.where((order) {
      return order.createdAt.isAfter(startDate) &&
          order.createdAt.isBefore(endDate);
    }).toList();
  }

  /// Get orders by product
  List<Order> getOrdersByProduct(String productId) {
    return _orders.where((order) {
      return order.items.any((item) => item.product.name == productId);
    }).toList();
  }

  /// Search orders
  List<Order> searchOrders(String query) {
    if (query.isEmpty) return _orders;

    final lowercaseQuery = query.toLowerCase();
    return _orders.where((order) {
      return order.id.toLowerCase().contains(lowercaseQuery) ||
          order.items.any((item) =>
              item.product.name.toLowerCase().contains(lowercaseQuery)) ||
          order.shippingAddress.city.toLowerCase().contains(lowercaseQuery) ||
          order.shippingAddress.state.toLowerCase().contains(lowercaseQuery);
    }).toList();
  }

  /// Clear all orders (for testing)
  Future<void> clearAllOrders() async {
    _setLoading(true);
    try {
      _orders.clear();
      _currentUserId = null;
      await _saveOrdersToStorage();
      notifyListeners();
      print('DEBUG: All orders cleared');
    } catch (e) {
      print('Error clearing orders: $e');
      _setError('Failed to clear orders');
    } finally {
      _setLoading(false);
    }
  }

  /// Handle authentication state changes
  /// Clears orders when user logs out or switches accounts
  Future<void> handleAuthStateChange({
    required bool isAuthenticated,
    String? userId,
  }) async {
    if (!isAuthenticated) {
      // User logged out - clear all orders
      Logger.info('User logged out, clearing orders', tag: 'OrderProvider');
      _orders.clear();
      _currentUserId = null;
      await _saveOrdersToStorage();
      notifyListeners();
    } else if (userId != null && _currentUserId != null && _currentUserId != userId) {
      // User switched accounts - clear old user's orders
      Logger.info('User switched accounts, clearing previous user orders. Old: $_currentUserId, New: $userId', tag: 'OrderProvider');
      _orders.clear();
      _currentUserId = userId;
      await _saveOrdersToStorage();
      notifyListeners();
    } else if (userId != null) {
      // Same user or first login - just update current user ID
      _currentUserId = userId;
    }
  }

  /// Set loading state
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  /// Set error message
  void _setError(String error) {
    _errorMessage = error;
    notifyListeners();
  }

  /// Clear error message
  void _clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Force refresh orders from storage
  Future<void> refreshOrders() async {
    await _loadOrdersFromStorage();
  }

  /// Sync orders with WooCommerce backend
  Future<void> syncOrdersWithWooCommerce(String userId,
      {bool skipNotifications = false}) async {
    // If user ID changed, clear old orders first
    if (_currentUserId != null && _currentUserId != userId) {
      Logger.info('User ID changed during sync, clearing old orders. Old: $_currentUserId, New: $userId', tag: 'OrderProvider');
      _orders.clear();
      await _saveOrdersToStorage();
    }
    
    _currentUserId = userId;
    _setLoading(true);
    _clearError();

    try {
      Logger.info('Syncing orders with WooCommerce for user: $userId',
          tag: 'OrderProvider');

      // Fetch orders from WooCommerce
      final wooOrders = await WooCommerceService.getCustomerOrders(userId);

      Logger.info('Retrieved ${wooOrders.length} orders from WooCommerce',
          tag: 'OrderProvider');

      // Track new orders added
      int newOrdersAdded = 0;
      int ordersUpdated = 0;

      // Process each WooCommerce order
      for (final wooOrder in wooOrders) {
        // Try multiple ways to match orders (by WC ID or order ID format)
        int localOrderIndex = _orders.indexWhere(
          (order) =>
              order.metadata?['woocommerce_id'] == wooOrder.id ||
              (wooOrder.id != null && order.id == 'WC-${wooOrder.id}'),
        );

        if (localOrderIndex != -1) {
          // Update existing order - ALWAYS update status from WooCommerce
          final localOrder = _orders[localOrderIndex];
          final mappedStatus = _mapWooCommerceStatus(wooOrder.status);

          // Check if status actually changed - check both mapped status and raw WooCommerce status
          final statusChanged = localOrder.status != mappedStatus;
          final previousWooStatus =
              localOrder.metadata?['woocommerce_status'] as String?;
          final wooStatusChanged = previousWooStatus != wooOrder.status;

          // Log comparison for debugging
          Logger.info(
              'Order ${localOrder.id} status check: local=${localOrder.status}, mapped=$mappedStatus, previousWoo=$previousWooStatus, newWoo=${wooOrder.status}',
              tag: 'OrderProvider');

          // Always update with latest WooCommerce data
          final updatedOrder = localOrder.copyWith(
            status: mappedStatus, // Update status from WooCommerce
            updatedAt: DateTime.now(),
            // Update payment status based on WooCommerce paid status
            paymentStatus: wooOrder.paymentDetails.paid
                ? PaymentStatus.paid
                : localOrder.paymentStatus,
            metadata: {
              ...?localOrder.metadata,
              'woocommerce_id': wooOrder.id,
              'woocommerce_status': wooOrder.status,
              'woocommerce_status_raw': wooOrder.status, // Store raw status
              'woocommerce_payment_method':
                  wooOrder.paymentDetails.paymentMethod,
              'woocommerce_payment_method_title':
                  wooOrder.paymentDetails.paymentMethodTitle,
              'woocommerce_payment_status':
                  wooOrder.paymentDetails.paid ? 'paid' : 'pending',
              'sync_timestamp': DateTime.now().toIso8601String(),
              'last_synced': DateTime.now().toIso8601String(),
            },
          );

          _orders[localOrderIndex] = updatedOrder;

          if (statusChanged || wooStatusChanged) {
            Logger.info(
                'Order ${localOrder.id} status updated: ${localOrder.status} -> $mappedStatus (WooCommerce: ${wooOrder.status})',
                tag: 'OrderProvider');
            ordersUpdated++;

            // Only create notification if not skipped (e.g., when triggered by push notification)
            // Push notifications already create in-app notifications, so we skip to avoid duplicates
            if (!skipNotifications) {
              // Notification disabled by user request
              // try {
              //   await NotificationService().showOrderStatusUpdate(
              //     orderId: localOrder.id,
              //     oldStatus: localOrder.status.toString(),
              //     newStatus: wooOrder.status,
              //     orderTitle: 'Order Status Updated',
              //   );
              //   Logger.info(
              //       'Notification sent for order ${localOrder.id} status update',
              //       tag: 'OrderProvider');
              // } catch (e) {
              //   Logger.error(
              //       'Failed to show notification for order status update: $e',
              //       tag: 'OrderProvider',
              //       error: e);
              //   // Don't fail the sync if notification fails
              // }
            } else {
              Logger.info(
                  'Skipping notification creation (already handled by push notification)',
                  tag: 'OrderProvider');
            }
          } else {
            Logger.info(
                'Order ${localOrder.id} status unchanged: ${wooOrder.status}',
                tag: 'OrderProvider');
          }
        } else {
          // Create new local order from WooCommerce order if not exists locally
          // This handles cases where orders were created on another device
          try {
            final newOrder =
                _convertWooCommerceOrderToLocalOrder(wooOrder, userId);
            if (newOrder != null) {
              _orders.add(newOrder);
              newOrdersAdded++;
              Logger.info('Added new order from WooCommerce: ${newOrder.id}',
                  tag: 'OrderProvider');

              // Show notification for new order
              // Notification disabled by user request
              // try {
              //   await NotificationService().showNewOrderNotification(
              //     orderId: newOrder.id,
              //     total: newOrder.formattedTotal,
              //     orderTitle: 'New Order Received',
              //   );
              //   Logger.info('Notification sent for new order ${newOrder.id}',
              //       tag: 'OrderProvider');
              // } catch (e) {
              //   Logger.error('Failed to show notification for new order: $e',
              //       tag: 'OrderProvider', error: e);
              //   // Don't fail the sync if notification fails
              // }
            }
          } catch (e) {
            Logger.error(
                'Failed to convert WooCommerce order ${wooOrder.id} to local order: $e',
                tag: 'OrderProvider',
                error: e);
            // Continue with other orders
          }
        }
      }

      // Sort orders by date (newest first)
      _orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      await _saveOrdersToStorage();
      notifyListeners();

      Logger.info(
        'Orders synced successfully. ${wooOrders.length} orders from WooCommerce. '
        '$newOrdersAdded new orders added, $ordersUpdated orders updated.',
        tag: 'OrderProvider',
      );
    } catch (e) {
      Logger.error(
        'Failed to sync orders with WooCommerce: $e',
        tag: 'OrderProvider',
        error: e,
      );
      _setError('Failed to sync orders: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Convert WooCommerce order to local Order model
  Order? _convertWooCommerceOrderToLocalOrder(
      WooCommerceOrder wooOrder, String userId) {
    try {
      // Extract addresses from WooCommerce order
      final shippingAddress = Address(
        id: 'ADDR-${DateTime.now().millisecondsSinceEpoch}',
        userId: userId,
        firstName: wooOrder.shipping.firstName,
        lastName: wooOrder.shipping.lastName,
        addressLine1: wooOrder.shipping.address1,
        addressLine2: wooOrder.shipping.address2,
        city: wooOrder.shipping.city,
        state: wooOrder.shipping.state,
        postalCode: wooOrder.shipping.postcode,
        country: wooOrder.shipping.country,
        phone: '', // WooCommerce shipping doesn't have phone
        email: '', // WooCommerce shipping doesn't have email
        createdAt: DateTime.now(),
      );

      final billingAddress = Address(
        id: 'ADDR-${DateTime.now().millisecondsSinceEpoch + 1}',
        userId: userId,
        firstName: wooOrder.billing.firstName,
        lastName: wooOrder.billing.lastName,
        addressLine1: wooOrder.billing.address1,
        addressLine2: wooOrder.billing.address2,
        city: wooOrder.billing.city,
        state: wooOrder.billing.state,
        postalCode: wooOrder.billing.postcode,
        country: wooOrder.billing.country,
        phone: wooOrder.billing.phone,
        email: wooOrder.billing.email,
        createdAt: DateTime.now(),
      );

      // Convert line items to OrderItems
      final orderItems = wooOrder.lineItems.map((lineItem) {
        // Create a basic product from line item
        final product = Product(
          'assets/placeholder.png', // Default image
          lineItem.name,
          '', // No description from WooCommerce
          lineItem.price,
        );

        return OrderItem(
          product: product,
          quantity: lineItem.quantity,
          unitPrice: lineItem.price,
        );
      }).toList();

      // Parse payment method
      PaymentMethod paymentMethod = PaymentMethod.cashOnDelivery;
      final paymentMethodStr =
          wooOrder.paymentDetails.paymentMethod.toLowerCase();
      if (paymentMethodStr.contains('stripe') ||
          paymentMethodStr.contains('card')) {
        paymentMethod = PaymentMethod.creditCard;
      } else if (paymentMethodStr.contains('paypal') ||
          paymentMethodStr.contains('mobile')) {
        paymentMethod = PaymentMethod.mobilePayment;
      } else if (paymentMethodStr.contains('bacs') ||
          paymentMethodStr.contains('bank')) {
        paymentMethod = PaymentMethod.bankTransfer;
      } else if (paymentMethodStr.contains('cod')) {
        paymentMethod = PaymentMethod.cashOnDelivery;
      }

      // Parse dates
      final createdAt =
          DateTime.tryParse(wooOrder.dateCreated) ?? DateTime.now();
      final updatedAt =
          DateTime.tryParse(wooOrder.dateModified) ?? DateTime.now();

      // Create order ID from WooCommerce ID
      final orderId = 'WC-${wooOrder.id}';

      final order = Order(
        id: orderId,
        userId: userId,
        items: orderItems,
        shippingAddress: shippingAddress,
        billingAddress: billingAddress,
        subtotal: wooOrder.subtotal,
        shippingCost: wooOrder.shippingTotal,
        tax: wooOrder.totalTax,
        discount: wooOrder.discountTotal,
        total: wooOrder.total,
        status: _mapWooCommerceStatus(wooOrder.status),
        paymentStatus: wooOrder.paymentDetails.paid
            ? PaymentStatus.paid
            : PaymentStatus.pending,
        paymentMethod: paymentMethod,
        createdAt: createdAt,
        updatedAt: updatedAt,
        notes: wooOrder.customerNote,
        metadata: {
          'woocommerce_id': wooOrder.id,
          'woocommerce_status': wooOrder.status,
          'woocommerce_status_raw': wooOrder.status,
          'woocommerce_payment_method': wooOrder.paymentDetails.paymentMethod,
          'woocommerce_payment_method_title':
              wooOrder.paymentDetails.paymentMethodTitle,
          'woocommerce_payment_status':
              wooOrder.paymentDetails.paid ? 'paid' : 'pending',
          'sync_timestamp': DateTime.now().toIso8601String(),
          'last_synced': DateTime.now().toIso8601String(),
        },
      );

      return order;
    } catch (e, stackTrace) {
      Logger.error('Error converting WooCommerce order to local order: $e',
          tag: 'OrderProvider', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  /// Update order status in WooCommerce backend
  Future<bool> updateOrderStatusInWooCommerce(
      String orderId, OrderStatus newStatus) async {
    try {
      final order = getOrderById(orderId);
      if (order == null) {
        Logger.error('Order not found: $orderId', tag: 'OrderProvider');
        return false;
      }

      final wooCommerceId = order.metadata?['woocommerce_id'];
      if (wooCommerceId == null) {
        Logger.warning('No WooCommerce ID found for order: $orderId',
            tag: 'OrderProvider');
        return false;
      }

      final wooCommerceStatus = _mapToWooCommerceStatus(newStatus);
      final success = await WooCommerceService.updateOrderStatus(
        int.parse(wooCommerceId.toString()),
        wooCommerceStatus,
      );

      if (success) {
        Logger.info(
          'Order status updated in WooCommerce: $orderId to $wooCommerceStatus',
          tag: 'OrderProvider',
        );
      }

      return success;
    } catch (e) {
      Logger.error(
        'Failed to update order status in WooCommerce: $e',
        tag: 'OrderProvider',
        error: e,
      );
      return false;
    }
  }

  /// Map WooCommerce status to local OrderStatus
  /// Handles all WooCommerce order statuses
  OrderStatus _mapWooCommerceStatus(String wooStatus) {
    final status = wooStatus.toLowerCase().trim();

    switch (status) {
      case 'pending':
      case 'on-hold':
        return OrderStatus.pending;
      case 'processing':
      case 'in-progress':
        return OrderStatus.processing;
      case 'confirmed':
        return OrderStatus.confirmed;
      case 'shipped':
      case 'shipping':
      case 'out-for-delivery':
        return OrderStatus.shipped;
      case 'completed':
      case 'delivered':
      case 'done':
        return OrderStatus.delivered;
      case 'cancelled':
      case 'canceled':
      case 'failed':
        return OrderStatus.cancelled;
      case 'refunded':
      case 'refund':
        return OrderStatus.refunded;
      default:
        Logger.warning(
            'Unknown WooCommerce status: $wooStatus, mapping to pending',
            tag: 'OrderProvider');
        return OrderStatus.pending;
    }
  }

  /// Get WooCommerce status text for display
  String getWooCommerceStatusText(Order? order) {
    if (order?.metadata == null) return '';
    final wooStatus = order!.metadata!['woocommerce_status'] ??
        order.metadata!['woocommerce_status_raw'] ??
        '';
    if (wooStatus.isEmpty) return '';

    // Format WooCommerce status for display (capitalize and replace hyphens)
    return wooStatus
        .split('-')
        .map((word) =>
            word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  /// Map local OrderStatus to WooCommerce status
  String _mapToWooCommerceStatus(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return 'pending';
      case OrderStatus.confirmed:
        return 'processing';
      case OrderStatus.processing:
        return 'processing';
      case OrderStatus.shipped:
        return 'shipped';
      case OrderStatus.delivered:
        return 'completed';
      case OrderStatus.cancelled:
        return 'cancelled';
      case OrderStatus.refunded:
        return 'refunded';
    }
  }

  /// Create pending transaction for order
  /// This creates a pending transaction that will be approved when order status changes to completed/processing
  /// For pending transactions, we sync immediately to backend so admins can see them
  Future<void> _createPendingTransactionForOrder(
      String userId, double orderTotal, String orderId) async {
    try {
      // Calculate points that will be earned (1 point per $1 spent)
      final pointsEarned = PointService.calculatePointsFromOrder(orderTotal);

      if (pointsEarned > 0) {
        // Create pending transaction - will be approved when order is completed
        // For pending transactions, we need to sync immediately to backend
        final transaction = PointTransaction(
          id: '${DateTime.now().millisecondsSinceEpoch}',
          userId: userId,
          type: PointTransactionType.earn,
          points: pointsEarned,
          description: 'Points from order #$orderId (pending)',
          orderId: orderId,
          createdAt: DateTime.now(),
          expiresAt: DateTime.now().add(Duration(days: 365)),
          status: PointTransactionStatus.pending,
        );

        // Save transaction locally first
        await PointService.saveTransactionLocally(transaction);

        // Sync immediately to backend (blocking) so it appears in Point System
        try {
          final syncSuccess = await PointService.syncTransactionToBackendSync(
            userId: userId,
            transaction: transaction,
          );

          if (syncSuccess) {
            Logger.info(
                'Pending transaction created and synced to backend for order: $orderId - $pointsEarned points',
                tag: 'OrderProvider');
          } else {
            Logger.warning(
                'Pending transaction created locally but failed to sync to backend for order: $orderId',
                tag: 'OrderProvider');
            // Queue for later sync
            await PointService.enqueueTransactionForSync(userId, transaction);
          }
        } catch (e) {
          Logger.error('Error syncing pending transaction to backend: $e',
              tag: 'OrderProvider', error: e);
          // Queue for later sync
          await PointService.enqueueTransactionForSync(userId, transaction);
        }
      }
    } catch (e) {
      Logger.error('Error creating pending transaction for order: $e',
          tag: 'OrderProvider', error: e);
      // Don't throw - transaction creation should not block order creation
    }
  }
}
