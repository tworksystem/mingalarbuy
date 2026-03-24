import 'package:ecommerce_int2/app_properties.dart';
import 'package:ecommerce_int2/models/product.dart';
import 'package:ecommerce_int2/screens/product/components/product_card.dart';
import 'package:ecommerce_int2/screens/product/view_product_page.dart';
import 'package:ecommerce_int2/screens/product/all_products_page.dart';
import 'package:ecommerce_int2/woocommerce_service.dart';
import 'package:ecommerce_int2/utils/logger.dart';
import 'package:flutter/material.dart';

/// More Products Widget with Actual WooCommerce Data
/// 
/// Features:
/// - Loads actual products from WooCommerce
/// - Excludes current product from the list
/// - Professional loading and error states
/// - "View Products" button to navigate to All Products Page
/// - Material Design 3 styling
class MoreProducts extends StatefulWidget {
  /// Optional: Current product to exclude from the list
  final Product? currentProduct;
  
  /// Maximum number of products to display
  final int maxProducts;

  const MoreProducts({
    super.key,
    this.currentProduct,
    this.maxProducts = 10,
  });

  @override
  State<MoreProducts> createState() => _MoreProductsState();
}

class _MoreProductsState extends State<MoreProducts> {
  List<Product> _products = [];
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  /// Load actual products from WooCommerce
  Future<void> _loadProducts() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = null;
    });

    try {
      // Load products from WooCommerce
      final wooProducts = await WooCommerceService.getProducts(
        perPage: widget.maxProducts + 5, // Load extra to account for exclusions
      );

      // Convert to Product model
      var products = wooProducts.map((woo) => woo.toProduct()).toList();

      // Exclude current product if provided
      if (widget.currentProduct != null) {
        products = products
            .where((p) => p.id != widget.currentProduct!.id)
            .toList();
      }

      // Limit to maxProducts
      if (products.length > widget.maxProducts) {
        products = products.take(widget.maxProducts).toList();
      }

      if (mounted) {
        setState(() {
          _products = products;
          _isLoading = false;
        });
      }

      Logger.info(
          'Loaded ${products.length} products for MoreProducts',
          tag: 'MoreProducts');
    } catch (e, stackTrace) {
      Logger.error('Error loading more products: $e',
          tag: 'MoreProducts', error: e, stackTrace: stackTrace);
      
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = 'Failed to load products. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Header with "View Products" button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'More products',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  shadows: shadow,
                ),
              ),
              // View Products Button
              TextButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AllProductsPage(),
                    ),
                  );
                },
                icon: const Icon(
                  Icons.arrow_forward,
                  size: 16,
                ),
                label: const Text(
                  'View Products',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Products List or Loading/Error State
        Container(
          margin: const EdgeInsets.only(bottom: 20.0),
          height: 250,
          child: _buildContent(),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return _buildLoadingState();
    }

    if (_hasError) {
      return _buildErrorState();
    }

    if (_products.isEmpty) {
      return _buildEmptyState();
    }

    return _buildProductsList();
  }

  Widget _buildLoadingState() {
    return Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(Colors.white.withValues(alpha: 0.8)),
        strokeWidth: 2,
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            color: Colors.white.withValues(alpha: 0.7),
            size: 32,
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage ?? 'Failed to load',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _loadProducts,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.shopping_bag_outlined,
            color: Colors.white.withValues(alpha: 0.7),
            size: 32,
          ),
          const SizedBox(height: 8),
          Text(
            'No more products',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductsList() {
    return ListView.builder(
      itemCount: _products.length,
      scrollDirection: Axis.horizontal,
      // OPTIMIZED: Add cacheExtent for better performance
      cacheExtent: 500,
      // OPTIMIZED: Add key for better widget recycling
      itemBuilder: (context, index) {
        final product = _products[index];
        return KeyedSubtree(
          key: ValueKey('more_product_${product.id}_$index'),
          child: Padding(
          // Calculates the left and right margins to be even with the screen margin
          padding: index == 0
              ? const EdgeInsets.only(left: 24.0, right: 8.0)
              : index == _products.length - 1
                  ? const EdgeInsets.only(right: 24.0, left: 8.0)
                  : const EdgeInsets.symmetric(horizontal: 8.0),
          child: GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ViewProductPage(product: product),
                ),
              );
            },
            child: ProductCard(product),
            ),
          ),
        );
      },
    );
  }
}
