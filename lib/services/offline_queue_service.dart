import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/logger.dart';
import 'connectivity_service.dart';
import '../models/cart_item.dart';
import '../models/address.dart';
import '../models/order.dart';

/// Offline queue item types
enum OfflineQueueItemType {
  addToCart,
  removeFromCart,
  updateCartQuantity,
  createOrder,
  pointAdjustment,
  updateProfile,
  addAddress,
  updateAddress,
  deleteAddress,
}

/// Offline queue item
class OfflineQueueItem {
  final String id;
  final OfflineQueueItemType type;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  final int retryCount;
  final String? errorMessage;

  OfflineQueueItem({
    required this.id,
    required this.type,
    required this.data,
    required this.createdAt,
    this.retryCount = 0,
    this.errorMessage,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.toString(),
        'data': data,
        'createdAt': createdAt.toIso8601String(),
        'retryCount': retryCount,
        'errorMessage': errorMessage,
      };

  factory OfflineQueueItem.fromJson(Map<String, dynamic> json) {
    return OfflineQueueItem(
      id: json['id'] as String,
      type: OfflineQueueItemType.values.firstWhere(
        (e) => e.toString() == json['type'],
        orElse: () => OfflineQueueItemType.addToCart,
      ),
      data: json['data'] as Map<String, dynamic>,
      createdAt: DateTime.parse(json['createdAt'] as String),
      retryCount: json['retryCount'] as int? ?? 0,
      errorMessage: json['errorMessage'] as String?,
    );
  }

  OfflineQueueItem copyWith({
    String? id,
    OfflineQueueItemType? type,
    Map<String, dynamic>? data,
    DateTime? createdAt,
    int? retryCount,
    String? errorMessage,
  }) {
    return OfflineQueueItem(
      id: id ?? this.id,
      type: type ?? this.type,
      data: data ?? this.data,
      createdAt: createdAt ?? this.createdAt,
      retryCount: retryCount ?? this.retryCount,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// Professional offline queue service
/// Queues actions when offline and syncs when online
class OfflineQueueService extends ChangeNotifier {
  static final OfflineQueueService _instance = OfflineQueueService._internal();
  factory OfflineQueueService() => _instance;
  OfflineQueueService._internal();

  static const String _queueKey = 'offline_queue';
  static const int _maxRetries = 3;
  // OPTIMIZED: Increased from 30s to 60s to reduce CPU usage
  // Queue syncs when connectivity is restored, so less frequent polling is acceptable
  static const Duration _syncInterval = Duration(seconds: 60);

  final List<OfflineQueueItem> _queue = [];
  Timer? _syncTimer;
  bool _isSyncing = false;
  bool _isInitialized = false;
  
  // Callback for order creation (set by OrderProvider)
  Future<dynamic> Function({
    required String userId,
    required List<CartItem> cartItems,
    required Address shippingAddress,
    required Address billingAddress,
    required PaymentMethod paymentMethod,
    double shippingCost,
    double tax,
    double discount,
    String? notes,
    Map<String, dynamic>? metadata,
  })? _orderCreationCallback;

  Future<bool> Function(Map<String, dynamic> payload)? _pointAdjustmentCallback;

  // Getters
  List<OfflineQueueItem> get queue => List.unmodifiable(_queue);
  bool get hasPendingItems => _queue.isNotEmpty;
  int get pendingCount => _queue.length;
  bool get isSyncing => _isSyncing;

  /// Initialize offline queue service
  Future<void> initialize() async {
    if (_isInitialized) {
      Logger.info('OfflineQueueService already initialized', tag: 'OfflineQueue');
      return;
    }

    try {
      // Load queue from storage
      await _loadQueueFromStorage();

      // Start listening to connectivity changes
      ConnectivityService().addListener(_onConnectivityChanged);

      // Start periodic sync timer
      _startSyncTimer();

      _isInitialized = true;
      Logger.info('OfflineQueueService initialized - ${_queue.length} items in queue',
          tag: 'OfflineQueue');
    } catch (e, stackTrace) {
      Logger.error('Failed to initialize OfflineQueueService: $e',
          tag: 'OfflineQueue', error: e, stackTrace: stackTrace);
    }
  }

  /// Add item to offline queue
  Future<String> addToQueue(
    OfflineQueueItemType type,
    Map<String, dynamic> data, {
    String? dedupeKey,
  }) async {
    final generatedId = DateTime.now().millisecondsSinceEpoch.toString();
    final itemId = dedupeKey ?? generatedId;

    if (dedupeKey != null) {
      _queue.removeWhere((item) => item.id == dedupeKey);
    }

    final item = OfflineQueueItem(
      id: itemId,
      type: type,
      data: data,
      createdAt: DateTime.now(),
    );

    _queue.add(item);
    await _saveQueueToStorage();
    notifyListeners();

    Logger.info('Added item to offline queue: ${type.toString()}',
        tag: 'OfflineQueue');

    // Try to sync immediately if online
    if (ConnectivityService().isConnected) {
      _syncQueue();
    }

    return item.id;
  }

  /// Remove item from queue
  Future<void> removeFromQueue(String itemId) async {
    _queue.removeWhere((item) => item.id == itemId);
    await _saveQueueToStorage();
    notifyListeners();

    Logger.info('Removed item from offline queue: $itemId', tag: 'OfflineQueue');
  }

  /// Sync queue when online
  Future<void> _syncQueue() async {
    if (_isSyncing || _queue.isEmpty) return;
    if (!ConnectivityService().isConnected) return;

    _isSyncing = true;
    notifyListeners();

    try {
      Logger.info('Starting queue sync - ${_queue.length} items',
          tag: 'OfflineQueue');

      final itemsToProcess = List<OfflineQueueItem>.from(_queue);
      final List<String> processedIds = [];
      final List<String> failedIds = [];

      for (final item in itemsToProcess) {
        try {
          final success = await _processQueueItem(item);
          if (success) {
            processedIds.add(item.id);
          } else {
            // Increment retry count
            final updatedItem = item.copyWith(retryCount: item.retryCount + 1);
            final index = _queue.indexWhere((i) => i.id == item.id);
            if (index != -1) {
              _queue[index] = updatedItem;
            }

            // Remove if max retries reached
            if (updatedItem.retryCount >= _maxRetries) {
              failedIds.add(item.id);
              Logger.warning(
                  'Item failed after $_maxRetries retries: ${item.id}',
                  tag: 'OfflineQueue');
            }
          }
        } catch (e, stackTrace) {
          Logger.error('Error processing queue item: ${item.id}',
              tag: 'OfflineQueue', error: e, stackTrace: stackTrace);
          failedIds.add(item.id);
        }
      }

      // Remove processed and failed items
      _queue.removeWhere((item) =>
          processedIds.contains(item.id) || failedIds.contains(item.id));
      await _saveQueueToStorage();
      notifyListeners();

      Logger.info(
          'Queue sync completed - Processed: ${processedIds.length}, Failed: ${failedIds.length}, Remaining: ${_queue.length}',
          tag: 'OfflineQueue');
    } catch (e, stackTrace) {
      Logger.error('Error syncing queue: $e',
          tag: 'OfflineQueue', error: e, stackTrace: stackTrace);
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// Process a single queue item
  /// This delegates to appropriate handlers based on item type
  Future<bool> _processQueueItem(OfflineQueueItem item) async {
    try {
      Logger.info('Processing queue item: ${item.type.toString()}',
          tag: 'OfflineQueue');
      
      switch (item.type) {
        case OfflineQueueItemType.addToCart:
          return await _processAddToCart(item);
        case OfflineQueueItemType.removeFromCart:
          return await _processRemoveFromCart(item);
        case OfflineQueueItemType.updateCartQuantity:
          return await _processUpdateCartQuantity(item);
        case OfflineQueueItemType.createOrder:
          return await _processCreateOrder(item);
        case OfflineQueueItemType.pointAdjustment:
          if (_pointAdjustmentCallback == null) {
            Logger.warning('Point adjustment callback not registered',
                tag: 'OfflineQueue');
            return false;
          }
          return await _pointAdjustmentCallback!(item.data);
        case OfflineQueueItemType.updateProfile:
        case OfflineQueueItemType.addAddress:
        case OfflineQueueItemType.updateAddress:
        case OfflineQueueItemType.deleteAddress:
          // These are handled by their respective providers
          Logger.info('Queue item type ${item.type} not yet implemented',
              tag: 'OfflineQueue');
          return true; // Skip for now
      }
    } catch (e, stackTrace) {
      Logger.error('Error processing queue item: ${item.id}',
          tag: 'OfflineQueue', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  /// Process add to cart item
  Future<bool> _processAddToCart(OfflineQueueItem item) async {
    try {
      // Cart operations are local-only, so they're already persisted
      // This is mainly for future server-side cart sync if needed
      Logger.info('Add to cart already processed locally',
          tag: 'OfflineQueue');
      return true;
    } catch (e) {
      Logger.error('Error processing add to cart: $e',
          tag: 'OfflineQueue', error: e);
      return false;
    }
  }

  /// Process remove from cart item
  Future<bool> _processRemoveFromCart(OfflineQueueItem item) async {
    try {
      // Cart operations are local-only, so they're already persisted
      Logger.info('Remove from cart already processed locally',
          tag: 'OfflineQueue');
      return true;
    } catch (e) {
      Logger.error('Error processing remove from cart: $e',
          tag: 'OfflineQueue', error: e);
      return false;
    }
  }

  /// Process update cart quantity item
  Future<bool> _processUpdateCartQuantity(OfflineQueueItem item) async {
    try {
      // Cart operations are local-only, so they're already persisted
      Logger.info('Update cart quantity already processed locally',
          tag: 'OfflineQueue');
      return true;
    } catch (e) {
      Logger.error('Error processing update cart quantity: $e',
          tag: 'OfflineQueue', error: e);
      return false;
    }
  }

  /// Process create order item
  Future<bool> _processCreateOrder(OfflineQueueItem item) async {
    try {
      final data = item.data;
      
      // Extract order data
      final userId = data['userId'] as String;
      final cartItemsJson = data['cartItems'] as List<dynamic>;
      final shippingAddressJson = data['shippingAddress'] as Map<String, dynamic>;
      final billingAddressJson = data['billingAddress'] as Map<String, dynamic>;
      final paymentMethodStr = data['paymentMethod'] as String;
      final shippingCost = (data['shippingCost'] as num?)?.toDouble() ?? 0.0;
      final tax = (data['tax'] as num?)?.toDouble() ?? 0.0;
      final discount = (data['discount'] as num?)?.toDouble() ?? 0.0;
      final notes = data['notes'] as String?;
      final metadata = data['metadata'] as Map<String, dynamic>?;

      // Convert cart items
      final cartItems = cartItemsJson
          .map((item) => CartItem.fromJson(item as Map<String, dynamic>))
          .toList();

      // Convert addresses
      final shippingAddress = Address.fromJson(shippingAddressJson);
      final billingAddress = Address.fromJson(billingAddressJson);

      // Convert payment method
      final paymentMethod = PaymentMethod.values.firstWhere(
        (e) => e.toString().split('.').last == paymentMethodStr,
        orElse: () => PaymentMethod.cashOnDelivery,
      );

      // Use callback to create order
      final orderCreationCallback = _orderCreationCallback;
      if (orderCreationCallback == null) {
        Logger.error('Order creation callback not registered',
            tag: 'OfflineQueue');
        return false;
      }

      // Create order via callback
      final wooOrder = await orderCreationCallback(
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

      if (wooOrder == null) {
        Logger.error('Failed to create order from queue',
            tag: 'OfflineQueue');
        return false;
      }

      Logger.info('Order created successfully from queue',
          tag: 'OfflineQueue');
      return true;
    } catch (e, stackTrace) {
      Logger.error('Error processing create order: $e',
          tag: 'OfflineQueue', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  /// Set order creation callback (called by OrderProvider)
  void setOrderCreationCallback(
    Future<dynamic> Function({
      required String userId,
      required List<CartItem> cartItems,
      required Address shippingAddress,
      required Address billingAddress,
      required PaymentMethod paymentMethod,
      double shippingCost,
      double tax,
      double discount,
      String? notes,
      Map<String, dynamic>? metadata,
    }) callback,
  ) {
    _orderCreationCallback = callback;
    Logger.info('Order creation callback registered', tag: 'OfflineQueue');
  }

  void setPointAdjustmentCallback(
      Future<bool> Function(Map<String, dynamic> payload) callback) {
    _pointAdjustmentCallback = callback;
    Logger.info('Point adjustment callback registered', tag: 'OfflineQueue');
  }

  /// Reset retry state for queued point adjustments after endpoint/auth fixes.
  /// This allows previously failed items to be retried with updated route logic.
  Future<int> resetPointAdjustmentRetriesAndSync() async {
    var updated = 0;
    for (var i = 0; i < _queue.length; i++) {
      final item = _queue[i];
      if (item.type != OfflineQueueItemType.pointAdjustment) continue;
      if (item.retryCount == 0 && item.errorMessage == null) continue;
      _queue[i] = item.copyWith(retryCount: 0, errorMessage: null);
      updated++;
    }
    if (updated > 0) {
      await _saveQueueToStorage();
      notifyListeners();
      Logger.info(
        'Reset retry state for $updated point-adjustment queue items',
        tag: 'OfflineQueue',
      );
    }
    if (ConnectivityService().isConnected && _queue.isNotEmpty) {
      unawaited(_syncQueue());
    }
    return updated;
  }

  /// Handle connectivity changes
  void _onConnectivityChanged() {
    if (ConnectivityService().isConnected && _queue.isNotEmpty) {
      Logger.info('Connection restored, syncing queue', tag: 'OfflineQueue');
      _syncQueue();
    }
  }

  /// Start periodic sync timer
  void _startSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(_syncInterval, (_) {
      if (ConnectivityService().isConnected && _queue.isNotEmpty) {
        _syncQueue();
      }
    });
  }

  /// Load queue from storage
  Future<void> _loadQueueFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queueJson = prefs.getString(_queueKey);

      if (queueJson != null) {
        final List<dynamic> queueData = json.decode(queueJson);
        _queue.clear();
        _queue.addAll(
          queueData
              .map((item) => OfflineQueueItem.fromJson(item as Map<String, dynamic>))
              .toList(),
        );
        Logger.info('Loaded ${_queue.length} items from offline queue',
            tag: 'OfflineQueue');
      }
    } catch (e, stackTrace) {
      Logger.error('Error loading queue from storage: $e',
          tag: 'OfflineQueue', error: e, stackTrace: stackTrace);
    }
  }

  /// Save queue to storage
  Future<void> _saveQueueToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queueJson = json.encode(_queue.map((item) => item.toJson()).toList());
      await prefs.setString(_queueKey, queueJson);
    } catch (e, stackTrace) {
      Logger.error('Error saving queue to storage: $e',
          tag: 'OfflineQueue', error: e, stackTrace: stackTrace);
    }
  }

  /// Clear all queue items
  Future<void> clearQueue() async {
    _queue.clear();
    await _saveQueueToStorage();
    notifyListeners();
    Logger.info('Offline queue cleared', tag: 'OfflineQueue');
  }

  /// Dispose resources
  @override
  void dispose() {
    _syncTimer?.cancel();
    ConnectivityService().removeListener(_onConnectivityChanged);
    super.dispose();
  }
}

