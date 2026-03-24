import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ecommerce_int2/providers/cart_provider.dart';
import 'package:ecommerce_int2/models/product.dart';
import 'package:ecommerce_int2/screens/shop/check_out_page.dart';
import 'package:ecommerce_int2/theme/app_theme.dart';

class CartButton extends StatelessWidget {
  final Product product;
  final bool showQuantity;
  final bool showCartIcon;
  final VoidCallback? onPressed;

  const CartButton({
    super.key,
    required this.product,
    this.showQuantity = true,
    this.showCartIcon = true,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<CartProvider>(
      builder: (context, cartProvider, child) {
        final isInCart = cartProvider.isInCart(product);
        final cartQuantity = cartProvider.getQuantity(product);

        if (showCartIcon) {
          return IconButton(
            onPressed: onPressed ??
                () async {
                  if (isInCart) {
                    Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => CheckOutPage()));
                  } else {
                    await cartProvider.addToCart(product);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${product.name} added to cart'),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
            icon: Stack(
              children: [
                Icon(
                  isInCart ? Icons.shopping_cart : Icons.add_shopping_cart,
                  color: isInCart ? Colors.green : Colors.grey[600],
                ),
                if (isInCart && showQuantity && cartQuantity > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      constraints: BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        '$cartQuantity',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          );
        }

        return ElevatedButton.icon(
          onPressed: onPressed ??
              () async {
                if (isInCart) {
                  Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => CheckOutPage()));
                } else {
                  await cartProvider.addToCart(product);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${product.name} added to cart'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
          icon: Icon(
            isInCart ? Icons.shopping_cart : Icons.add_shopping_cart,
            size: 18,
          ),
          label: Text(
            isInCart ? 'In Cart ($cartQuantity)' : 'Add to Cart',
            style: const TextStyle(fontSize: 14),
          ),
          style: ElevatedButton.styleFrom(
            // PlanetMM colors: deep blue for primary, bright purple when in cart
            backgroundColor:
                isInCart ? AppTheme.brightPurple : AppTheme.deepBlue,
            foregroundColor: AppTheme.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      },
    );
  }
}
