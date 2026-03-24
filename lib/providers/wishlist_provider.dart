import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/wishlist_item.dart';
import '../models/product.dart';

class WishlistProvider with ChangeNotifier {
  List<WishlistItem> _items = [];
  bool _isLoading = false;
  String? _errorMessage;
  static const String _wishlistKey = 'user_wishlist';

  // Getters
  List<WishlistItem> get items => List.unmodifiable(_items);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;
  int get itemCount => _items.length;

  WishlistProvider() {
    _loadWishlistFromStorage();
  }

  /// Load wishlist from SharedPreferences
  Future<void> _loadWishlistFromStorage() async {
    _setLoading(true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final wishlistJson = prefs.getString(_wishlistKey);

      if (wishlistJson != null) {
        final List<dynamic> wishlistData = json.decode(wishlistJson);
        _items = wishlistData
            .map((item) => WishlistItem.fromJson(item as Map<String, dynamic>))
            .toList();
        print('DEBUG: Wishlist loaded from storage - ${_items.length} items');
      }
    } catch (e) {
      print('Error loading wishlist from storage: $e');
      _setError('Failed to load wishlist');
    } finally {
      _setLoading(false);
    }
  }

  /// Save wishlist to SharedPreferences
  Future<void> _saveWishlistToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final wishlistJson =
          json.encode(_items.map((item) => item.toJson()).toList());
      await prefs.setString(_wishlistKey, wishlistJson);
      print('DEBUG: Wishlist saved to storage - ${_items.length} items');
    } catch (e) {
      print('Error saving wishlist to storage: $e');
    }
  }

  /// Add product to wishlist
  Future<WishlistItem?> addToWishlist({
    required String userId,
    required Product product,
    String? notes,
    Map<String, dynamic>? metadata,
  }) async {
    _setLoading(true);
    _clearError();

    try {
      // Check if product already exists in wishlist
      final existingItem = _items.firstWhere(
        (item) =>
            item.userId == userId &&
            item.product.name == product.name &&
            item.product.price == product.price,
        orElse: () => WishlistItem(
          id: '',
          userId: '',
          product: Product('', '', '', 0),
          addedAt: DateTime.now(),
        ),
      );

      if (existingItem.id.isNotEmpty) {
        _setError('Product is already in your wishlist');
        return null;
      }

      // Generate wishlist item ID
      final itemId = 'WISH-${DateTime.now().millisecondsSinceEpoch}';

      // Create wishlist item
      final wishlistItem = WishlistItem(
        id: itemId,
        userId: userId,
        product: product,
        addedAt: DateTime.now(),
        notes: notes,
        metadata: metadata,
      );

      // Add to wishlist
      _items.insert(0, wishlistItem); // Add to beginning for newest first
      await _saveWishlistToStorage();
      notifyListeners();

      print('DEBUG: Product added to wishlist - $itemId');
      return wishlistItem;
    } catch (e) {
      print('Error adding to wishlist: $e');
      _setError('Failed to add to wishlist: $e');
      return null;
    } finally {
      _setLoading(false);
    }
  }

  /// Remove product from wishlist
  Future<bool> removeFromWishlist(String itemId) async {
    _setLoading(true);
    _clearError();

    try {
      final itemIndex = _items.indexWhere((item) => item.id == itemId);
      if (itemIndex == -1) {
        _setError('Wishlist item not found');
        return false;
      }

      _items.removeAt(itemIndex);
      await _saveWishlistToStorage();
      notifyListeners();

      print('DEBUG: Product removed from wishlist - $itemId');
      return true;
    } catch (e) {
      print('Error removing from wishlist: $e');
      _setError('Failed to remove from wishlist');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Remove product by product details
  Future<bool> removeProductFromWishlist(String userId, Product product) async {
    _setLoading(true);
    _clearError();

    try {
      final itemIndex = _items.indexWhere(
        (item) =>
            item.userId == userId &&
            item.product.name == product.name &&
            item.product.price == product.price,
      );

      if (itemIndex == -1) {
        _setError('Product not found in wishlist');
        return false;
      }

      _items.removeAt(itemIndex);
      await _saveWishlistToStorage();
      notifyListeners();

      print('DEBUG: Product removed from wishlist');
      return true;
    } catch (e) {
      print('Error removing product from wishlist: $e');
      _setError('Failed to remove product from wishlist');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Clear entire wishlist
  Future<bool> clearWishlist() async {
    _setLoading(true);
    _clearError();

    try {
      _items.clear();
      await _saveWishlistToStorage();
      notifyListeners();

      print('DEBUG: Wishlist cleared');
      return true;
    } catch (e) {
      print('Error clearing wishlist: $e');
      _setError('Failed to clear wishlist');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Check if product is in wishlist
  bool isInWishlist(String userId, Product product) {
    return _items.any(
      (item) =>
          item.userId == userId &&
          item.product.name == product.name &&
          item.product.price == product.price,
    );
  }

  /// Get wishlist item by product
  WishlistItem? getWishlistItem(String userId, Product product) {
    try {
      return _items.firstWhere(
        (item) =>
            item.userId == userId &&
            item.product.name == product.name &&
            item.product.price == product.price,
      );
    } catch (e) {
      return null;
    }
  }

  /// Get wishlist items by user
  List<WishlistItem> getWishlistByUser(String userId) {
    return _items.where((item) => item.userId == userId).toList();
  }

  /// Update wishlist item notes
  Future<bool> updateWishlistItemNotes(String itemId, String notes) async {
    _setLoading(true);
    _clearError();

    try {
      final itemIndex = _items.indexWhere((item) => item.id == itemId);
      if (itemIndex == -1) {
        _setError('Wishlist item not found');
        return false;
      }

      final item = _items[itemIndex];
      final updatedItem = item.copyWith(notes: notes);
      _items[itemIndex] = updatedItem;

      await _saveWishlistToStorage();
      notifyListeners();

      print('DEBUG: Wishlist item notes updated - $itemId');
      return true;
    } catch (e) {
      print('Error updating wishlist item notes: $e');
      _setError('Failed to update wishlist item notes');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Search wishlist items
  List<WishlistItem> searchWishlist(String query) {
    if (query.isEmpty) return _items;

    final lowercaseQuery = query.toLowerCase();
    return _items.where((item) {
      return item.product.name.toLowerCase().contains(lowercaseQuery) ||
          item.product.description.toLowerCase().contains(lowercaseQuery) ||
          (item.notes?.toLowerCase().contains(lowercaseQuery) ?? false);
    }).toList();
  }

  /// Get recently added items
  List<WishlistItem> getRecentlyAdded({int limit = 5}) {
    final sortedItems = List<WishlistItem>.from(_items);
    sortedItems.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return sortedItems.take(limit).toList();
  }

  /// Get wishlist item by ID
  WishlistItem? getWishlistItemById(String itemId) {
    try {
      return _items.firstWhere((item) => item.id == itemId);
    } catch (e) {
      return null;
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

  /// Force refresh wishlist from storage
  Future<void> refreshWishlist() async {
    await _loadWishlistFromStorage();
  }
}
