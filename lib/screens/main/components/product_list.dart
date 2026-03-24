import 'dart:math' as math;

import 'package:card_swiper/card_swiper.dart';
import 'package:ecommerce_int2/app_properties.dart';
import 'package:ecommerce_int2/models/product.dart';
import 'package:ecommerce_int2/screens/product/product_page.dart';
import 'package:ecommerce_int2/widgets/network_image_widget.dart';
import 'package:flutter/material.dart';

class ProductList extends StatelessWidget {
  final List<Product> products;

  final SwiperController swiperController = SwiperController();

  ProductList({super.key, required this.products});

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final rawHeight = screenSize.height * 0.3;
    final rawWidth = screenSize.width * 0.68;
    final cardHeight = math.max(200.0, math.min(rawHeight, 260.0));
    final cardWidth = math.max(220.0, math.min(rawWidth, 320.0));

    return SizedBox(
      height: cardHeight,
      child: Swiper(
        itemCount: products.length,
        itemBuilder: (_, index) {
          return ProductCard(
              height: cardHeight, width: cardWidth, product: products[index]);
        },
        scale: 0.8,
        controller: swiperController,
        viewportFraction: 0.75,
        loop: false,
        fade: 0.5,
        pagination: SwiperPagination(
          alignment: Alignment.centerLeft,
          builder: VerticalDotSwiperPaginationBuilder(
            activeColor: Colors.white,
            color: Colors.white.withValues(alpha: 0.4),
            size: 6,
            activeSize: 10,
            space: 6,
            backgroundColor: Colors.black.withValues(alpha: 0.12),
            borderColor: Colors.white.withValues(alpha: 0.18),
            alignment: Alignment.centerLeft,
            margin: const EdgeInsets.only(left: 16.0, top: 12.0, bottom: 12.0),
          ),
        ),
      ),
    );
  }
}

class ProductCard extends StatefulWidget {
  final Product product;
  final double height;
  final double width;

  const ProductCard({
    super.key,
    required this.product,
    required this.height,
    required this.width,
  });

  @override
  _ProductCardState createState() => _ProductCardState();
}

class VerticalDotSwiperPaginationBuilder extends SwiperPlugin {
  const VerticalDotSwiperPaginationBuilder({
    this.size = 6.0,
    this.activeSize = 10.0,
    this.space = 4.0,
    required this.color,
    required this.activeColor,
    this.backgroundColor,
    this.borderColor,
    this.alignment = Alignment.centerLeft,
    this.margin = const EdgeInsets.only(left: 16.0, top: 12.0, bottom: 12.0),
    this.padding = const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
  });

  final double size;
  final double activeSize;
  final double space;
  final Color color;
  final Color activeColor;
  final Color? backgroundColor;
  final Color? borderColor;
  final Alignment alignment;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context, SwiperPluginConfig config) {
    if (config.itemCount <= 1) {
      return const SizedBox.shrink();
    }

    final dots = List<Widget>.generate(config.itemCount, (index) {
      final bool isActive = index == config.activeIndex;
      final double indicatorSize = isActive ? activeSize : size;

      return AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        width: indicatorSize,
        height: indicatorSize,
        margin: EdgeInsets.symmetric(vertical: space / 2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive ? activeColor : color,
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: activeColor.withValues(alpha: 0.35),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
      );
    });

    return Align(
      alignment: alignment,
      child: Container(
        margin: margin,
        padding: padding,
        decoration: BoxDecoration(
          color: backgroundColor ?? Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: borderColor ?? Colors.white.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: dots,
        ),
      ),
    );
  }
}

class _ProductCardState extends State<ProductCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _elevationAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    _elevationAnimation = Tween<double>(
      begin: 0.0,
      end: 8.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _animationController.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    _animationController.reverse();
  }

  void _handleTapCancel() {
    _animationController.reverse();
  }

  void _handleProductTap() {
    // Add haptic feedback
    // HapticFeedback.lightImpact();

    // Navigate with custom transition
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            ProductPage(product: widget.product),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeInOut;

          var tween = Tween(begin: begin, end: end).chain(
            CurveTween(curve: curve),
          );

          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: GestureDetector(
            onTapDown: _handleTapDown,
            onTapUp: _handleTapUp,
            onTapCancel: _handleTapCancel,
            onTap: _handleProductTap,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              height: widget.height,
              width: widget.width,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.all(Radius.circular(24)),
                color: mediumYellow,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: _elevationAnimation.value,
                    offset: Offset(0, _elevationAnimation.value / 2),
                  ),
                ],
              ),
              child: Stack(
                children: <Widget>[
                  // Product content
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        // Product name with better typography
                        Padding(
                          padding:
                              const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 4.0),
                          child: Text(
                            widget.product.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16.0,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),

                        // Price with enhanced styling
                        Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                            margin: const EdgeInsets.only(
                                right: 16.0, bottom: 16.0),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12.0,
                              vertical: 6.0,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(12),
                                bottomLeft: Radius.circular(12),
                              ),
                              color: Color.fromRGBO(224, 69, 10, 1),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              widget.product.formattedPrice,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Product image with Hero animation
                  Positioned.fill(
                    top: 18,
                    bottom: widget.height * 0.35,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Hero(
                        tag:
                            'product_${widget.product.name}_${widget.product.image}',
                        child: NetworkImageWidget(
                          imageUrl: widget.product.image,
                          height: widget.height * 0.55,
                          width: widget.width * 0.7,
                          fit: BoxFit.contain,
                          fallbackAsset: 'assets/headphones.png',
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
    );
  }
}
