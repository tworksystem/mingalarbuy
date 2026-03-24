import 'package:ecommerce_int2/app_properties.dart';
import 'package:ecommerce_int2/models/product.dart';
import 'package:ecommerce_int2/woocommerce_service.dart';
import 'package:ecommerce_int2/screens/product/product_page.dart';
import 'package:ecommerce_int2/widgets/network_image_widget.dart';
import 'package:ecommerce_int2/utils/logger.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter/material.dart';

class RecommendedList extends StatefulWidget {
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  const RecommendedList({
    super.key,
    this.shrinkWrap = false,
    this.physics,
  });

  @override
  _RecommendedListState createState() => _RecommendedListState();
}

class _RecommendedListState extends State<RecommendedList> {
  List<Product> products = [];
  bool isLoading = true;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  Future<void> _loadProducts() async {
    if (_isDisposed) return;

    Logger.info('Loading recommended products', tag: 'RecommendedList');

    try {
      final stopwatch = Stopwatch()..start();
      final wooProducts = await WooCommerceService.getProducts(perPage: 9);
      stopwatch.stop();

      Logger.logPerformance('Load Recommended Products', stopwatch.elapsed);

      if (_isDisposed) return;

      final convertedProducts =
          wooProducts.map((wooProduct) => wooProduct.toProduct()).toList();

      if (mounted) {
        setState(() {
          products = convertedProducts;
          isLoading = false;
        });
      }

      Logger.info(
          'Successfully loaded ${convertedProducts.length} recommended products',
          tag: 'RecommendedList');
    } catch (e, stackTrace) {
      Logger.error('Load Recommended Products: $e',
          tag: 'RecommendedList', error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return SizedBox(
        height: 200,
        child: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(mediumYellow),
          ),
        ),
      );
    }

    final header = Row(
      children: <Widget>[
        Container(
          margin: const EdgeInsets.only(left: 16.0, right: 8.0),
          width: 4,
          height: 20,
          color: mediumYellow,
        ),
        Text(
          'Recommended',
          style: TextStyle(
            color: darkGrey,
            fontSize: 16.0,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );

    final grid = MasonryGridView.count(
      shrinkWrap: widget.shrinkWrap,
      physics: widget.shrinkWrap
          ? (widget.physics ?? const NeverScrollableScrollPhysics())
          : widget.physics,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
      crossAxisCount: 4,
      itemCount: products.length,
      itemBuilder: (BuildContext context, int index) => ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(5.0)),
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ProductPage(product: products[index]))),
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  Colors.grey.withOpacity(0.3),
                  Colors.grey.withOpacity(0.7),
                ],
                center: const Alignment(0, 0),
                radius: 0.6,
                focal: const Alignment(0, 0),
                focalRadius: 0.1,
              ),
            ),
            child: Hero(
              tag:
                  'recommended_${products[index].name}_${products[index].image}',
              child: NetworkImageWidget(
                imageUrl: products[index].image,
                fit: BoxFit.cover,
                fallbackAsset: 'assets/headphones.png',
              ),
            ),
          ),
        ),
      ),
      mainAxisSpacing: 4.0,
      crossAxisSpacing: 4.0,
    );

    if (widget.shrinkWrap) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          header,
          grid,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        header,
        Expanded(child: grid),
      ],
    );
  }
}
