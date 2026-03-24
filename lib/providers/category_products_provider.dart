import 'package:flutter/foundation.dart';

import '../models/category.dart' as models;
import '../models/product.dart';
import '../utils/logger.dart';
import '../woocommerce_service.dart';

/// Provider responsible for loading and paginating products for a given category.
class CategoryProductsProvider with ChangeNotifier {
  CategoryProductsProvider({
    required this.category,
    int perPage = 12,
  })  : assert(perPage > 0, 'perPage must be greater than zero'),
        _perPage = perPage;

  final models.Category category;
  final int _perPage;

  final List<Product> _products = [];
  int _currentPage = 1;
  bool _isInitialLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _errorMessage;
  bool _isDisposed = false;

  List<Product> get products => List.unmodifiable(_products);
  bool get isInitialLoading => _isInitialLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _hasMore;
  bool get isEmpty => _products.isEmpty;
  String? get errorMessage => _errorMessage;

  /// Load the first page of products.
  Future<void> loadInitial({bool forceRefresh = false}) async {
    if (_isInitialLoading) return;
    if (!forceRefresh && _products.isNotEmpty) return;

    _clearError();
    _setInitialLoading(true);

    if (forceRefresh) {
      _products.clear();
      _currentPage = 1;
      _hasMore = true;
    }

    try {
      final products = await _fetchProducts(page: 1);
      _products
        ..clear()
        ..addAll(products);

      _currentPage = 1;
      _hasMore = products.length == _perPage;

      Logger.info(
        'Loaded ${products.length} products for category "${category.category}"',
        tag: 'CategoryProductsProvider',
        metadata: {
          'categoryId': category.id,
          'categorySlug': category.slug,
        },
      );
    } catch (error, stackTrace) {
      Logger.error(
        'Failed to load initial category products',
        tag: 'CategoryProductsProvider',
        error: error,
        stackTrace: stackTrace,
        metadata: {
          'categoryId': category.id,
          'categorySlug': category.slug,
        },
      );
      _setError('Failed to load products for this category.');
    } finally {
      _setInitialLoading(false);
      _safeNotifyListeners();
    }
  }

  /// Load the next page of products.
  Future<void> loadMore() async {
    if (_isInitialLoading || _isLoadingMore || !_hasMore) return;

    _setLoadingMore(true);
    _clearError();

    final nextPage = _currentPage + 1;

    try {
      final products = await _fetchProducts(page: nextPage);

      if (products.isEmpty) {
        _hasMore = false;
      } else {
        _products.addAll(products);
        _currentPage = nextPage;
        _hasMore = products.length == _perPage;

        Logger.debug(
          'Appended ${products.length} more products for category "${category.category}"',
          tag: 'CategoryProductsProvider',
          metadata: {
            'categoryId': category.id,
            'categorySlug': category.slug,
            'page': nextPage,
          },
        );
      }
    } catch (error, stackTrace) {
      Logger.error(
        'Failed to load additional category products',
        tag: 'CategoryProductsProvider',
        error: error,
        stackTrace: stackTrace,
        metadata: {
          'categoryId': category.id,
          'categorySlug': category.slug,
          'page': nextPage,
        },
      );
      _setError('Could not load more products. Pull to refresh and try again.');
    } finally {
      _setLoadingMore(false);
      _safeNotifyListeners();
    }
  }

  /// Refresh products.
  Future<void> refresh() => loadInitial(forceRefresh: true);

  Future<List<Product>> _fetchProducts({required int page}) async {
    if (page < 1) {
      throw ArgumentError.value(page, 'page', 'Page index must be >= 1');
    }

    if (category.id != null && category.id! > 0) {
      final wooProducts = await WooCommerceService.getProducts(
        perPage: _perPage,
        page: page,
        category: category.id!.toString(),
        orderBy: 'date',
        order: 'desc',
      );
      return wooProducts.map((woo) => woo.toProduct()).toList(growable: false);
    }

    // Fallback to slug/name search when category id is missing.
    final lookupTerm = (category.slug?.isNotEmpty ?? false)
        ? category.slug!
        : category.category;

    Logger.warning(
      'Category "${category.category}" is missing an ID. Falling back to search query lookup.',
      tag: 'CategoryProductsProvider',
      metadata: {
        'categoryId': category.id,
        'categorySlug': category.slug,
        'page': page,
      },
    );

    final wooProducts = await WooCommerceService.getProducts(
      perPage: _perPage,
      page: page,
      search: lookupTerm,
      orderBy: 'date',
      order: 'desc',
    );

    final normalizedLookup = lookupTerm.toLowerCase();
    return wooProducts
        .map((woo) => woo.toProduct())
        .where(
          (product) =>
              product.name.toLowerCase().contains(normalizedLookup) ||
              product.categoryIds.isNotEmpty,
        )
        .toList(growable: false);
  }

  void _setInitialLoading(bool value) {
    if (_isInitialLoading == value) return;
    _isInitialLoading = value;
    _safeNotifyListeners();
  }

  void _setLoadingMore(bool value) {
    if (_isLoadingMore == value) return;
    _isLoadingMore = value;
    _safeNotifyListeners();
  }

  void _setError(String? message) {
    if (_errorMessage == message) return;
    _errorMessage = message;
    _safeNotifyListeners();
  }

  void _clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    _safeNotifyListeners();
  }

  void _safeNotifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}

