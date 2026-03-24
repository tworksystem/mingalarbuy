import 'dart:math' as math;
import 'dart:ui';

import 'package:ecommerce_int2/app_properties.dart';
import 'package:ecommerce_int2/models/product.dart';
import 'package:ecommerce_int2/screens/product/product_page.dart';
import 'package:ecommerce_int2/widgets/network_image_widget.dart';
import 'package:flutter/material.dart';

class WeeklyFeaturedShowcase extends StatefulWidget {
  const WeeklyFeaturedShowcase({
    super.key,
    required this.products,
    this.onViewAll,
  });

  final List<Product> products;
  final VoidCallback? onViewAll;

  @override
  State<WeeklyFeaturedShowcase> createState() => _WeeklyFeaturedShowcaseState();
}

class _WeeklyFeaturedShowcaseState extends State<WeeklyFeaturedShowcase> {
  late final PageController _pageController;
  double _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      viewportFraction: 0.82,
    );
    _pageController.addListener(_handlePageChanged);
  }

  @override
  void dispose() {
    _pageController.removeListener(_handlePageChanged);
    _pageController.dispose();
    super.dispose();
  }

  void _handlePageChanged() {
    final page = _pageController.page;
    if (page != null && mounted) {
      setState(() {
        _currentPage = page;
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    if (widget.products.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header texts ("Weekly", "View All") have been removed per design
        // request. We keep a subtle divider only, so the focus is on the
        // product slider itself.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: const _WeeklyHeader(),
        ),
        const SizedBox(height: 8),
        // OPTIMIZED: Removed expensive TweenAnimationBuilder, use RepaintBoundary for better performance
        RepaintBoundary(
          child: SizedBox(
            height: _carouselHeightFor(context),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return ClipRect(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: widget.products.length,
                    physics: const BouncingScrollPhysics(),
                    // OPTIMIZED: Add key for better widget recycling
                    itemBuilder: (context, index) {
                      final product = widget.products[index];
                      return KeyedSubtree(
                        key: ValueKey('weekly_product_${product.id}_$index'),
                        child: _WeeklyFeaturedCard(
                        product: product,
                        index: index,
                        pageValue: _currentPage,
                        onOpenProduct: () => _openProduct(product),
                        cardHeight: constraints.maxHeight,
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        _PageIndicators(
          controller: _pageController,
          currentPage: _currentPage,
          itemCount: widget.products.length,
        ),
      ],
    );
  }

  void _openProduct(Product product) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            ProductPage(product: product),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 0.1);
          const end = Offset.zero;
          final tween = Tween(begin: begin, end: end).chain(
            CurveTween(curve: Curves.easeOutCubic),
          );
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: animation.drive(tween),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 320),
      ),
    );
  }

  double _carouselHeightFor(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final calculated = size.height * 0.36;
    return calculated.clamp(240.0, 340.0);
  }
}

class _WeeklyHeader extends StatelessWidget {
  const _WeeklyHeader();

  @override
  Widget build(BuildContext context) {
    // Design: we only keep a subtle divider and remove all header texts
    // ("Weekly", "View All") so that the carousel feels more minimal.
    return _WeeklyDivider();
  }
}

class _WeeklyDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 2,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            mediumYellow.withValues(alpha: 0.4),
            Colors.transparent,
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}


class _GhostPill extends StatelessWidget {
  const _GhostPill({
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Open product',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Colors.white,
                Color(0xFFE2F1FF),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Icon(
            icon,
            size: 18,
            color: darkGrey,
          ),
        ),
      ),
    );
  }
}

class _WeeklyFeaturedCard extends StatelessWidget {
  const _WeeklyFeaturedCard({
    required this.product,
    required this.index,
    required this.pageValue,
    required this.onOpenProduct,
    required this.cardHeight,
  });

  final Product product;
  final int index;
  final double pageValue;
  final VoidCallback onOpenProduct;
  final double cardHeight;

  @override
  Widget build(BuildContext context) {
    final delta = (index - pageValue).clamp(-1.0, 1.0);
    final scale = 1 - (delta.abs() * 0.06);
    final translateY = 20 * delta.abs();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      transform: Matrix4.identity()
        ..translate(0.0, translateY)
        ..scale(scale),
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: GestureDetector(
          onTap: onOpenProduct,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _GradientCardBackground(product: product),
              _CardTextureOverlay(delta: delta),
              _CardContent(
                product: product,
                cardHeight: cardHeight,
                onOpenProduct: onOpenProduct,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GradientCardBackground extends StatelessWidget {
  const _GradientCardBackground({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final colors = _resolveGradient(product);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.last.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 16),
            spreadRadius: -6,
          ),
        ],
      ),
    );
  }

  List<Color> _resolveGradient(Product product) {
    final palette = product.extra?['palette'];
    if (palette is List && palette.length >= 2) {
      final resolvedColors = palette
          .whereType<String>()
          .map((hex) => _hexToColor(hex))
          .whereType<Color>()
          .toList(growable: false);
      if (resolvedColors.length >= 2) {
        return resolvedColors.take(2).toList();
      }
    }
    return [
      mediumYellow,
      const Color(0xFFFF8B5C),
    ];
  }

  Color? _hexToColor(String value) {
    final buffer = StringBuffer();
    if (value.length == 6 || value.length == 7) {
      buffer.write('ff');
    }
    buffer.write(value.replaceFirst('#', ''));
    final hex = int.tryParse(buffer.toString(), radix: 16);
    if (hex == null) {
      return null;
    }
    return Color(hex);
  }
}

class _CardTextureOverlay extends StatelessWidget {
  const _CardTextureOverlay({required this.delta});

  final double delta;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 350),
          opacity: 0.45 - (delta.abs() * 0.1),
          child: Container(
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.all(Radius.circular(28)),
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  Colors.white24,
                  Colors.transparent,
                  Colors.black12,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CardContent extends StatelessWidget {
  const _CardContent({
    required this.product,
    required this.cardHeight,
    required this.onOpenProduct,
  });

  final Product product;
  final double cardHeight;
  final VoidCallback onOpenProduct;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rating = _resolveRating(product);
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topRight,
            child: Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.bolt_rounded,
                color: Colors.amber,
                size: 24,
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final totalHeight = constraints.maxHeight;
              final headerGap = math.min(10.0, totalHeight * 0.04);
              final sectionGap = math.min(12.0, totalHeight * 0.05);
              final bodyPadding =
                  EdgeInsets.only(top: math.min(6.0, totalHeight * 0.03));

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: headerGap),
                  Expanded(
                    flex: 18,
                    child: LayoutBuilder(
                      builder: (context, innerConstraints) {
                        final squareSize = math.min(
                          innerConstraints.maxHeight,
                          innerConstraints.maxWidth * 1.05,
                        );
                        final haloSize = squareSize * 1.1;

                        return Center(
                          child: TweenAnimationBuilder<double>(
                            duration: const Duration(milliseconds: 320),
                            curve: Curves.easeOutBack,
                            tween: Tween(begin: 0.92, end: 1.0),
                            builder: (context, scale, child) =>
                                Transform.scale(scale: scale, child: child),
                            child: SizedBox(
                              width: squareSize,
                              height: squareSize,
                              child: Stack(
                                clipBehavior: Clip.none,
                                alignment: Alignment.center,
                                children: [
                                  Container(
                                    width: haloSize,
                                    height: haloSize,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: RadialGradient(
                                        colors: [
                                          Colors.white.withValues(alpha: 0.35),
                                          Colors.white.withValues(alpha: 0.0),
                                        ],
                                      ),
                                    ),
                                  ),
                                  AspectRatio(
                                    aspectRatio: 1,
                                    child: Hero(
                                      tag:
                                          'weekly_featured_${product.id ?? product.name}_${product.image}',
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(32),
                                        child: Padding(
                                          padding: const EdgeInsets.all(6.0),
                                          child: FittedBox(
                                            fit: BoxFit.contain,
                                            child: SizedBox(
                                              width: squareSize,
                                              height: squareSize,
                                              child: NetworkImageWidget(
                                                imageUrl: product.image,
                                                fit: BoxFit.contain,
                                                fallbackAsset:
                                                    'assets/headphones.png',
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  SizedBox(height: sectionGap),
                  Expanded(
                    flex: 6,
                    child: Padding(
                      padding: bodyPadding,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      product.name,
                                      style:
                                          theme.textTheme.titleMedium?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        height: 1.2,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    SizedBox(
                                      height:
                                          math.min(6.0, totalHeight * 0.025),
                                    ),
                                    if (rating != null)
                                      _MetaChip(
                                        icon: Icons.star_rounded,
                                        label: rating.toStringAsFixed(1),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              _GhostPill(
                                icon: Icons.arrow_outward_rounded,
                                onPressed: onOpenProduct,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  double? _resolveRating(Product product) {
    final ratings = product.extra?['average_rating'];
    if (ratings is num) {
      return ratings.toDouble();
    }
    if (ratings is String) {
      return double.tryParse(ratings);
    }
    return null;
  }
}

class _PageIndicators extends StatefulWidget {
  const _PageIndicators({
    required this.controller,
    required this.currentPage,
    required this.itemCount,
  });

  final PageController controller;
  final double currentPage;
  final int itemCount;

  @override
  State<_PageIndicators> createState() => _PageIndicatorsState();
}

class _PageIndicatorsState extends State<_PageIndicators> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_rebuildOnChange);
  }

  @override
  void didUpdateWidget(covariant _PageIndicators oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_rebuildOnChange);
      widget.controller.addListener(_rebuildOnChange);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuildOnChange);
    super.dispose();
  }

  void _rebuildOnChange() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.itemCount <= 1) {
      return const SizedBox(height: 12);
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(widget.itemCount, (index) {
        final progress = (widget.currentPage - index).abs().clamp(0.0, 1.0);
        final size = lerpDouble(12, 6, progress)!;
        final opacity = lerpDouble(1, 0.3, progress)!;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          height: 6,
          width: size,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: opacity * 0.35),
            borderRadius: BorderRadius.circular(12),
          ),
        );
      }),
    );
  }
}
