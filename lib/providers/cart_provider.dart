import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cart_item.dart';
import '../models/product.dart';
import '../services/offline_queue_service.dart';
import '../services/connectivity_service.dart';

class CartProvider with ChangeNotifier {
  List<CartItem> _items = [];
  bool _isLoading = false;
  static const String _cartKey = 'cart_items';

  /// Bumped on [clearCart] / session invalidation so in-flight [_loadCartFromStorage]
  /// cannot re-apply stale SharedPreferences JSON after a clear or user switch.
  int _cartHydrateEpoch = 0;

  String? _sessionUserId;

  // Getters
  List<CartItem> get items => List.unmodifiable(_items);
  bool get isLoading => _isLoading;
  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;

  // Calculate total items count
  int get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  // Calculate total price
  double get totalPrice =>
      _items.fold(0.0, (sum, item) => sum + item.totalPrice);

  // Get formatted total price
  String get formattedTotalPrice => '${totalPrice.toStringAsFixed(2)} Ks';

  CartProvider() {
    // OLD CODE: constructor called [_loadCartFromStorage] synchronously without
    // invalidation token, so it could race with [clearCart] during auth switch.
    // _loadCartFromStorage();
    Future.microtask(() => _loadCartFromStorage());
  }

  /// Clears in-memory cart and persists; bumps [_cartHydrateEpoch] to cancel
  /// stale storage hydration.
  Future<void> handleAuthStateChange({
    required bool isAuthenticated,
    String? userId,
  }) async {
    if (!isAuthenticated) {
      _sessionUserId = null;
      await clearCart();
      return;
    }
    if (userId == null) return;
    final switched = _sessionUserId != null && _sessionUserId != userId;
    _sessionUserId = userId;
    if (switched) {
      await clearCart();
    }
  }

  /// Load cart from SharedPreferences
  Future<void> _loadCartFromStorage() async {
    final loadToken = _cartHydrateEpoch;
    _setLoading(true);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (loadToken != _cartHydrateEpoch) {
        return;
      }
      final cartJson = prefs.getString(_cartKey);

      if (cartJson != null) {
        final List<dynamic> cartData = json.decode(cartJson);
        if (loadToken != _cartHydrateEpoch) {
          return;
        }
        _items = cartData
            .map((item) => CartItem.fromJson(item as Map<String, dynamic>))
            .toList();
        print('DEBUG: Cart loaded from storage - ${_items.length} items');
      } else if (loadToken == _cartHydrateEpoch) {
        _items = [];
      }
    } catch (e) {
      print('Error loading cart from storage: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Save cart to SharedPreferences
  Future<void> _saveCartToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cartJson = json.encode(
        _items.map((item) => item.toJson()).toList(),
      );
      await prefs.setString(_cartKey, cartJson);
      print('DEBUG: Cart saved to storage - ${_items.length} items');
    } catch (e) {
      print('Error saving cart to storage: $e');
    }
  }

  /// Add product to cart
  Future<void> addToCart(Product product, {int quantity = 1}) async {
    _setLoading(true);

    try {
      // Check if product already exists in cart
      final existingItemIndex = _items.indexWhere(
        (item) =>
            item.product.name == product.name &&
            item.product.price == product.price,
      );

      if (existingItemIndex != -1) {
        // Update quantity of existing item
        _items[existingItemIndex] = _items[existingItemIndex].copyWith(
          quantity: _items[existingItemIndex].quantity + quantity,
        );
        print(
          'DEBUG: Updated existing cart item quantity to ${_items[existingItemIndex].quantity}',
        );
      } else {
        // Add new item to cart
        _items.add(CartItem(product: product, quantity: quantity));
        print('DEBUG: Added new item to cart - ${product.name}');
      }

      await _saveCartToStorage();

      // Queue for offline sync if offline
      if (!ConnectivityService().isConnected) {
        await OfflineQueueService().addToQueue(OfflineQueueItemType.addToCart, {
          'product': {
            'image': product.image,
            'name': product.name,
            'description': product.description,
            'price': product.price,
          },
          'quantity': quantity,
        });
      }

      // Notify listeners BEFORE setting loading to false to ensure UI updates immediately
      notifyListeners();
      print(
        'DEBUG: Cart updated - Total items: $itemCount, Total price: $formattedTotalPrice',
      );
    } catch (e) {
      print('Error adding to cart: $e');
    } finally {
      _setLoading(false);
      // Notify again after loading is complete to ensure all UI updates
      notifyListeners();
    }
  }

  /// Remove product from cart
  Future<void> removeFromCart(Product product) async {
    _setLoading(true);

    try {
      _items.removeWhere(
        (item) =>
            item.product.name == product.name &&
            item.product.price == product.price,
      );

      await _saveCartToStorage();

      // Queue for offline sync if offline (for future server-side cart sync)
      if (!ConnectivityService().isConnected) {
        await OfflineQueueService().addToQueue(
          OfflineQueueItemType.removeFromCart,
          {
            'product': {
              'image': product.image,
              'name': product.name,
              'description': product.description,
              'price': product.price,
            },
          },
        );
      }

      // Notify listeners immediately to update UI
      notifyListeners();
      print('DEBUG: Removed item from cart - Total items: $itemCount');
    } catch (e) {
      print('Error removing from cart: $e');
    } finally {
      _setLoading(false);
      // Notify again after loading is complete
      notifyListeners();
    }
  }

  /// Update quantity of cart item
  Future<void> updateQuantity(CartItem cartItem, int newQuantity) async {
    if (newQuantity <= 0) {
      await removeFromCart(cartItem.product);
      return;
    }

    _setLoading(true);

    try {
      final itemIndex = _items.indexWhere(
        (item) =>
            item.product.name == cartItem.product.name &&
            item.product.price == cartItem.product.price,
      );

      if (itemIndex != -1) {
        _items[itemIndex] = _items[itemIndex].copyWith(quantity: newQuantity);
        await _saveCartToStorage();

        // Queue for offline sync if offline
        if (!ConnectivityService().isConnected) {
          await OfflineQueueService().addToQueue(
            OfflineQueueItemType.updateCartQuantity,
            {
              'product': {
                'image': cartItem.product.image,
                'name': cartItem.product.name,
                'description': cartItem.product.description,
                'price': cartItem.product.price,
              },
              'quantity': newQuantity,
            },
          );
        }

        // Notify listeners immediately to update UI
        notifyListeners();
        print(
          'DEBUG: Updated cart item quantity to $newQuantity - Total items: $itemCount',
        );
      }
    } catch (e) {
      print('Error updating quantity: $e');
    } finally {
      _setLoading(false);
      // Notify again after loading is complete
      notifyListeners();
    }
  }

  /// Clear entire cart
  Future<void> clearCart() async {
    // OLD CODE: no [_cartHydrateEpoch] bump, so a concurrent [_loadCartFromStorage]
    // could repopulate [_items] after prefs were cleared.
    // _setLoading(true);
    // try {
    //   _items.clear();
    _cartHydrateEpoch++;
    final loadToken = _cartHydrateEpoch;
    _setLoading(true);

    try {
      _items.clear();
      await _saveCartToStorage();
      print('DEBUG: Cart cleared');
    } catch (e) {
      print('Error clearing cart: $e');
    } finally {
      if (loadToken == _cartHydrateEpoch) {
        _setLoading(false);
      }
      notifyListeners();
    }
  }

  /// Check if product is in cart
  bool isInCart(Product product) {
    return _items.any(
      (item) =>
          item.product.name == product.name &&
          item.product.price == product.price,
    );
  }

  /// Get quantity of product in cart
  int getQuantity(Product product) {
    final item = _items.firstWhere(
      (item) =>
          item.product.name == product.name &&
          item.product.price == product.price,
      orElse: () => CartItem(product: product, quantity: 0),
    );
    return item.quantity;
  }

  /// Get cart item for product
  CartItem? getCartItem(Product product) {
    try {
      return _items.firstWhere(
        (item) =>
            item.product.name == product.name &&
            item.product.price == product.price,
      );
    } catch (e) {
      return null;
    }
  }

  /// Set loading state
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  /// Force refresh cart from storage
  Future<void> refreshCart() async {
    await _loadCartFromStorage();
  }
}
