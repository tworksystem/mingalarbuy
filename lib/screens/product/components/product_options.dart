import 'package:ecommerce_int2/app_properties.dart';
import 'package:ecommerce_int2/models/product.dart';
import 'package:ecommerce_int2/providers/cart_provider.dart';
import 'package:ecommerce_int2/screens/orders/checkout_flow_page.dart';
import 'package:ecommerce_int2/widgets/network_image_widget.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ProductOption extends StatelessWidget {
  final GlobalKey<ScaffoldState> scaffoldKey;
  final Product product;
  const ProductOption(
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
            child: SizedBox(
              height: 200,
              width: 200,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: NetworkImageWidget(
                  imageUrl: product.image,
                  fit: BoxFit.contain,
                  fallbackAsset: 'assets/headphones.png',
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
                  // Single "Buy Now" button: clears cart, adds this product, then goes to payment flow directly
                  Consumer<CartProvider>(
                    builder: (context, cartProvider, child) {
                      return InkWell(
                        onTap: () async {
                          // Ensure this product is the one being checked out
                          await cartProvider.clearCart();
                          await cartProvider.addToCart(product);
                          // Navigate straight into checkout flow (bypass intermediate cart page)
                          // ignore: use_build_context_synchronously
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => CheckoutFlowPage(),
                            ),
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
                          padding: const EdgeInsets.symmetric(vertical: 16.0),
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
