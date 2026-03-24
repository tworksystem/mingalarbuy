import 'package:card_swiper/card_swiper.dart';
import 'package:ecommerce_int2/app_properties.dart';
import 'package:ecommerce_int2/models/woocommerce_product.dart';
import 'package:ecommerce_int2/services/product_repository.dart';
import 'package:ecommerce_int2/screens/product/woocommerce_product_page.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// WooCommerce Product List with Original UI Design
///
/// Displays WooCommerce products using the beautiful swiper design
class WooCommerceProductList extends StatefulWidget {
  const WooCommerceProductList({super.key});

  @override
  _WooCommerceProductListState createState() => _WooCommerceProductListState();
}

class _WooCommerceProductListState extends State<WooCommerceProductList> {
  final ProductRepository _repository = ProductRepository();
  final SwiperController swiperController = SwiperController();
  List<WooCommerceProduct> _products = [];
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final products = await _repository.getProducts(perPage: 10);
      if (mounted) {
        setState(() {
          _products = products;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading products: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    double cardHeight = MediaQuery.of(context).size.height / 2.7;
    double cardWidth = MediaQuery.of(context).size.width / 1.8;

    if (_isLoading) {
      return SizedBox(
        height: cardHeight,
        child: Center(
          child: CircularProgressIndicator(color: mediumYellow),
        ),
      );
    }

    if (_hasError || _products.isEmpty) {
      return SizedBox(
        height: cardHeight,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                _hasError ? 'Failed to load products' : 'No products found',
                style: TextStyle(color: Colors.grey),
              ),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadProducts,
                child: Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: cardHeight,
      child: Swiper(
        itemCount: _products.length,
        itemBuilder: (_, index) {
          final product = _products[index];
          return InkWell(
            onTap: () => Navigator.of(context).push(
              PageRouteBuilder(
                pageBuilder: (_, __, ___) =>
                    WooCommerceProductPage(product: product),
                transitionsBuilder: (_, animation, __, child) {
                  final curved = CurvedAnimation(
                      parent: animation, curve: Curves.easeOutCubic);
                  return SlideTransition(
                    position: Tween<Offset>(
                            begin: const Offset(0.0, 1.0), end: Offset.zero)
                        .animate(curved),
                    child: child,
                  );
                },
                transitionDuration: const Duration(milliseconds: 350),
              ),
            ),
            child: WooCommerceProductCard(
              height: cardHeight,
              width: cardWidth,
              product: product,
            ),
          );
        },
        scale: 0.8,
        controller: swiperController,
        viewportFraction: 0.6,
        loop: false,
        fade: 0.5,
        pagination: SwiperCustomPagination(
          builder: (context, config) {
            Color activeColor = mediumYellow;
            Color color = Colors.grey.withOpacity(.3);
            double size = 10.0;
            double space = 5.0;

            List<Widget> dots = [];
            int itemCount = config.itemCount;
            int activeIndex = config.activeIndex;

            for (int i = 0; i < itemCount; ++i) {
              bool active = i == activeIndex;
              dots.add(Container(
                key: Key("pagination_$i"),
                margin: EdgeInsets.all(space),
                child: ClipOval(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active ? activeColor : color,
                    ),
                    width: size,
                    height: size,
                  ),
                ),
              ));
            }

            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: dots,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// WooCommerce Product Card with Original Design
class WooCommerceProductCard extends StatelessWidget {
  final WooCommerceProduct product;
  final double height;
  final double width;

  const WooCommerceProductCard({
    super.key,
    required this.product,
    required this.height,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: width,
      child: Stack(
        children: [
          // Product Image with Hero transition
          Container(
            margin: EdgeInsets.only(left: 30),
            height: height,
            width: width,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.all(Radius.circular(24)),
              color: mediumYellow,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(24)),
              child: Hero(
                tag: product.imageUrl,
                child: CachedNetworkImage(
                  imageUrl: product.imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: Colors.grey[200],
                    child: Center(
                      child: CircularProgressIndicator(color: mediumYellow),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.grey[200],
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shopping_bag, size: 64, color: Colors.grey),
                        SizedBox(height: 8),
                        Text(
                          product.name,
                          style: TextStyle(fontSize: 14),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Product Info
          Positioned(
            bottom: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Product Name
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SizedBox(
                    width: width - 100,
                    child: Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            offset: Offset(0, 2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 8),

                // Price Container
                Container(
                  width: width,
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: Color.fromRGBO(224, 224, 224, 1),
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(24),
                      bottomRight: Radius.circular(24),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Price
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (product.onSale && product.salePrice != null) ...[
                            Text(
                              product.formattedRegularPrice,
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                            SizedBox(height: 4),
                          ],
                          Text(
                            product.formattedPrice,
                            style: TextStyle(
                              color: darkGrey,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),

                      // Rating or Badge
                      if (product.onSale && product.discountPercentage != null)
                        Container(
                          padding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '-${product.discountPercentage}%',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        )
                      else if (product.featured)
                        Container(
                          padding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: mediumYellow,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Featured',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        )
                      else if (product.ratingCount > 0)
                        Row(
                          children: [
                            Icon(Icons.star, color: Colors.amber, size: 16),
                            SizedBox(width: 4),
                            Text(
                              product.ratingValue.toStringAsFixed(1),
                              style: TextStyle(
                                color: darkGrey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Sale Badge (top right)
          if (product.onSale && product.discountPercentage != null)
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      offset: Offset(0, 2),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Text(
                  'SALE',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),

          // Stock Badge (top left)
          if (!product.inStock)
            Positioned(
              top: 16,
              left: 46,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      offset: Offset(0, 2),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Text(
                  'Out of Stock',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
