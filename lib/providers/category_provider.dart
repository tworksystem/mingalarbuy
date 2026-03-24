import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/category.dart' as models;
import '../woocommerce_service.dart';
import '../utils/logger.dart';
import '../services/connectivity_service.dart';

/// Category Provider for managing category state
/// Handles fetching categories from WooCommerce API and caching
class CategoryProvider with ChangeNotifier {
  List<models.Category> _categories = [];
  bool _isLoading = false;
  String? _errorMessage;
  static const String _categoriesCacheKey = 'categories_cache';

  // Getters
  List<models.Category> get categories => List.unmodifiable(_categories);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasCategories => _categories.isNotEmpty;

  CategoryProvider() {
    _initialize();
  }

  /// Initialize category provider
  Future<void> _initialize() async {
    _setLoading(true);
    try {
      // Load cached categories first
      await _loadCachedCategories();
      _setLoading(false);
    } catch (e) {
      Logger.error('Error initializing category provider: $e',
          tag: 'CategoryProvider', error: e);
      _setLoading(false);
    }
  }

  /// Load categories from API
  Future<void> loadCategories({bool forceRefresh = false}) async {
    _setLoading(true);
    _clearError();

    try {
      // Check connectivity
      final connectivityService = ConnectivityService();
      final isOnline = connectivityService.isConnected;

      if (!isOnline && !forceRefresh) {
        // Load from cache if offline
        await _loadCachedCategories();
        _setLoading(false);
        return;
      }

      // Fetch categories from WooCommerce
      final wooCategories = await WooCommerceService.getCategories(
        perPage: 100,
        hideEmpty: true, // Only show categories with products
        orderBy: 'name',
        order: 'asc',
      );

      // Convert WooCommerce categories to app categories
      _categories = wooCategories
          .map((wooCategory) => wooCategory.toCategory())
          .toList();

      // Cache categories
      await _cacheCategories(_categories);

      Logger.info('Loaded ${_categories.length} categories from API',
          tag: 'CategoryProvider');

      notifyListeners();
    } catch (e, stackTrace) {
      Logger.error('Error loading categories: $e',
          tag: 'CategoryProvider', error: e, stackTrace: stackTrace);
      _setError('Failed to load categories');
      
      // Try to load from cache on error
      if (_categories.isEmpty) {
        await _loadCachedCategories();
      }
    } finally {
      _setLoading(false);
    }
  }

  /// Search categories by name
  List<models.Category> searchCategories(String query) {
    if (query.isEmpty) return _categories;
    
    final lowerQuery = query.toLowerCase();
    return _categories.where((category) {
      return category.category.toLowerCase().contains(lowerQuery) ||
          (category.description?.toLowerCase().contains(lowerQuery) ?? false);
    }).toList();
  }

  /// Get category by ID
  models.Category? getCategoryById(int id) {
    try {
      return _categories.firstWhere((category) => category.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Get category by slug
  models.Category? getCategoryBySlug(String slug) {
    try {
      return _categories.firstWhere((category) => category.slug == slug);
    } catch (e) {
      return null;
    }
  }

  /// Cache categories to local storage
  Future<void> _cacheCategories(List<models.Category> categories) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final categoriesJson = json.encode(
          categories.map((c) => c.toJson()).toList());
      await prefs.setString(_categoriesCacheKey, categoriesJson);
      Logger.info('Cached ${categories.length} categories',
          tag: 'CategoryProvider');
    } catch (e) {
      Logger.error('Error caching categories: $e',
          tag: 'CategoryProvider', error: e);
    }
  }

  /// Load cached categories from local storage
  Future<void> _loadCachedCategories() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final categoriesJson = prefs.getString(_categoriesCacheKey);

      if (categoriesJson != null) {
        final categoriesData = json.decode(categoriesJson) as List<dynamic>;
        _categories = categoriesData
            .map((item) => models.Category.fromJson(item as Map<String, dynamic>))
            .toList();

        Logger.info('Loaded ${_categories.length} cached categories',
            tag: 'CategoryProvider');
        notifyListeners();
      }
    } catch (e) {
      Logger.error('Error loading cached categories: $e',
          tag: 'CategoryProvider', error: e);
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
  }

  /// Refresh categories
  Future<void> refresh() async {
    await loadCategories(forceRefresh: true);
  }
}

