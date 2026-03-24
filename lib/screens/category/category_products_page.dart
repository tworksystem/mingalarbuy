import 'package:ecommerce_int2/app_properties.dart';
import 'package:ecommerce_int2/models/category.dart';
import 'package:ecommerce_int2/models/product.dart';
import 'package:ecommerce_int2/providers/category_products_provider.dart';
import 'package:ecommerce_int2/screens/product/view_product_page.dart';
import 'package:ecommerce_int2/widgets/network_image_widget.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// A dedicated page that displays products belonging to a specific category.
class CategoryProductsPage extends StatefulWidget {
  const CategoryProductsPage({
    super.key,
    required this.category,
  });

  final Category category;

  @override
  State<CategoryProductsPage> createState() => _CategoryProductsPageState();
}

class _CategoryProductsPageState extends State<CategoryProductsPage> {
  late final ScrollController _scrollController;
  CategoryProductsProvider? _provider;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    _provider = null;
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;

    final threshold = 320.0;
    final extentAfter = _scrollController.position.extentAfter;
    if (extentAfter < threshold) {
      _provider?.loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<CategoryProductsProvider>(
      create: (_) =>
          CategoryProductsProvider(category: widget.category)..loadInitial(),
      child: Consumer<CategoryProductsProvider>(
        builder: (context, provider, _) {
          _provider = provider;
          return Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              iconTheme: const IconThemeData(color: darkGrey),
              title: Text(
                widget.category.category,
                style: const TextStyle(
                  color: darkGrey,
                  fontWeight: FontWeight.w600,
                ),
              ),
              actions: [
                if (provider.products.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: Text(
                          '${provider.products.length} items',
                          key: ValueKey(provider.products.length),
                          style: const TextStyle(
                            color: darkGrey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            body: RefreshIndicator(
              onRefresh: provider.refresh,
              color: mediumYellow,
              child: _buildBody(context, provider),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    CategoryProductsProvider provider,
  ) {
    if (provider.isInitialLoading && provider.products.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(mediumYellow),
        ),
      );
    }

    if (provider.errorMessage != null && provider.products.isEmpty) {
      return _ErrorState(
        message: provider.errorMessage!,
        onRetry: () => provider.loadInitial(forceRefresh: true),
      );
    }

    if (provider.products.isEmpty) {
      return _EmptyState(
        categoryName: widget.category.category,
        onBrowseAll: () => provider.loadInitial(forceRefresh: true),
      );
    }

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        if (provider.errorMessage != null)
          SliverToBoxAdapter(
            child: _InlineErrorBanner(
              message: provider.errorMessage!,
              onRetry: () => provider.loadMore(),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final product = provider.products[index];
                return _ProductTile(product: product);
              },
              childCount: provider.products.length,
            ),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.68,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: _buildLoadMoreIndicator(provider),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom + 24,
          ),
        ),
      ],
    );
  }

  Widget _buildLoadMoreIndicator(CategoryProductsProvider provider) {
    if (provider.isLoadingMore) {
      return const Center(
        child: SizedBox(
          height: 28,
          width: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.8,
            valueColor: AlwaysStoppedAnimation<Color>(mediumYellow),
          ),
        ),
      );
    }

    if (!provider.hasMore) {
      return const Center(
        child: Text(
          'You\'ve reached the end',
          style: TextStyle(
            color: Colors.grey,
            fontSize: 12,
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final extra = product.extra ?? const <String, dynamic>{};
    final averageRatingRaw = (extra['averageRating'] ??
            extra['average_rating'] ??
            extra['rating'])
        ?.toString();
    final averageRating = double.tryParse(averageRatingRaw ?? '');
    final int ratingCount = () {
      final dynamic countValue =
          extra['ratingCount'] ?? extra['rating_count'] ?? extra['reviews'];
      if (countValue is num) {
        return countValue.toInt();
      }
      if (countValue is String) {
        return int.tryParse(countValue) ?? 0;
      }
      return 0;
    }();
    final bool isOnSale = extra['onSale'] == true;
    final double ratingValue = averageRating ?? 0;
    final bool hasRating = ratingValue > 0;
    final bool isTopRated =
        hasRating && ratingValue >= 4.5 && ratingCount >= 5;
    final String? badgeLabel = isOnSale
        ? 'On sale'
        : isTopRated
            ? 'Top rated'
            : null;
    final Color badgeColor =
        isOnSale ? const Color(0xFFE53935) : const Color(0xFF1E88E5);

    return LayoutBuilder(
      builder: (context, constraints) {
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ViewProductPage(product: product),
                ),
              );
            },
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white,
                    mediumYellow.withValues(alpha: 0.08),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: mediumYellow.withValues(alpha: 0.2),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        Align(
                          alignment: Alignment.center,
                          child: Container(
                            width: double.infinity,
                            margin: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: LinearGradient(
                                colors: [
                                  mediumYellow.withValues(alpha: 0.16),
                                  mediumYellow.withValues(alpha: 0.04),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.center,
                          child: Hero(
                            tag: 'product_${product.name}_${product.image}',
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: NetworkImageWidget(
                                imageUrl: product.image,
                                fit: BoxFit.cover,
                                fallbackAsset: 'assets/placeholder.png',
                              ),
                            ),
                          ),
                        ),
                        if (badgeLabel != null)
                          Positioned(
                            top: 0,
                            left: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: badgeColor.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: badgeColor.withValues(alpha: 0.35),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Text(
                                badgeLabel,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ),
                        if (hasRating)
                          Positioned(
                            top: 0,
                            right: 0,
                            child: _RatingBadge(
                              rating: ratingValue,
                              ratingCount: ratingCount,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    fit: FlexFit.loose,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: darkGrey,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _ProductMetaRow(
                          formattedPrice: product.formattedPrice,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProductMetaRow extends StatelessWidget {
  const _ProductMetaRow({
    required this.formattedPrice,
  });

  final String formattedPrice;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: mediumYellow,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: mediumYellow.withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Text(
          formattedPrice,
          style: const TextStyle(
            color: darkGrey,
            fontWeight: FontWeight.w700,
            fontSize: 14,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

class _RatingBadge extends StatelessWidget {
  const _RatingBadge({
    required this.rating,
    required this.ratingCount,
  });

  final double rating;
  final int ratingCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.star_rounded,
            color: Colors.amber,
            size: 16,
          ),
          const SizedBox(width: 4),
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '($ratingCount)',
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red[300],
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                color: darkGrey,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: mediumYellow,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.categoryName,
    required this.onBrowseAll,
  });

  final String categoryName;
  final VoidCallback onBrowseAll;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No products found in $categoryName yet.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                color: darkGrey,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: onBrowseAll,
              style: OutlinedButton.styleFrom(
                foregroundColor: mediumYellow,
                side: const BorderSide(color: mediumYellow),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Reload'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineErrorBanner extends StatelessWidget {
  const _InlineErrorBanner({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red[100]!),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 13,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
