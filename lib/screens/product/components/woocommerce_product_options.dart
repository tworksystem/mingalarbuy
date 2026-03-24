import 'package:ecommerce_int2/app_properties.dart';
import 'package:ecommerce_int2/models/woocommerce_product.dart';
import 'package:ecommerce_int2/providers/cart_provider.dart';
import 'package:ecommerce_int2/screens/shop/check_out_page.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

class WooCommerceProductOption extends StatelessWidget {
  final GlobalKey<ScaffoldState> scaffoldKey;
  final WooCommerceProduct product;
  const WooCommerceProductOption(
    this.scaffoldKey, {
    super.key,
    required this.product,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: Stack(
        children: <Widget>[
          Positioned(
            left: 16.0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: product.imageUrl,
                height: 200,
                width: 200,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  height: 200,
                  width: 200,
                  color: Colors.grey[200],
                  child: Center(
                    child: CircularProgressIndicator(color: mediumYellow),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  height: 200,
                  width: 200,
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
          Positioned(
            right: 0.0,
            child: SizedBox(
              height: 180,
              width: 300,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Text(
                      product.name,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: shadow,
                      ),
                    ),
                  ),
                  // Single "Buy Now" button: clears cart, adds this WooCommerce product, then goes to checkout
                  Consumer<CartProvider>(
                    builder: (context, cartProvider, child) {
                      return InkWell(
                        onTap: () async {
                          final cartProduct = product.toProduct();
                          await cartProvider.clearCart();
                          await cartProvider.addToCart(cartProduct);
                          // ignore: use_build_context_synchronously
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => CheckOutPage()),
                          );
                        },
                        child: Container(
                          width: MediaQuery.of(context).size.width / 2.5,
                          decoration: BoxDecoration(
                            gradient: mainButton,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(10.0),
                              bottomLeft: Radius.circular(10.0),
                            ),
                          ),
                          padding:
                              const EdgeInsets.symmetric(vertical: 16.0),
                          child: const Center(
                            child: Text(
                              'Buy Now',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}
