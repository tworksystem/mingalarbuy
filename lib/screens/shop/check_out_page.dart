import 'package:ecommerce_int2/app_properties.dart';
import 'package:ecommerce_int2/models/product.dart';
import 'package:ecommerce_int2/providers/cart_provider.dart';
import 'package:ecommerce_int2/screens/payment/unpaid_page.dart';
import 'package:ecommerce_int2/screens/orders/checkout_flow_page.dart';
import 'package:ecommerce_int2/widgets/app_pull_to_refresh.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'components/shop_item_list.dart';

class CheckOutPage extends StatefulWidget {
  const CheckOutPage({super.key});

  @override
  _CheckOutPageState createState() => _CheckOutPageState();
}

class _CheckOutPageState extends State<CheckOutPage> {
  @override
  Widget build(BuildContext context) {
    return Consumer<CartProvider>(
      builder: (context, cartProvider, child) {
        // Only use actual cart data - no dummy data
        if (cartProvider.isEmpty) {
          return Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0.0,
              iconTheme: IconThemeData(color: darkGrey),
              title: Text(
                'Checkout',
                style: TextStyle(
                    color: darkGrey, fontWeight: FontWeight.w500, fontSize: 18.0),
              ),
            ),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.shopping_cart_outlined,
                    size: 100,
                    color: Colors.grey[300],
                  ),
                  SizedBox(height: 20),
                  Text(
                    'Your cart is empty',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600],
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Add some items to your cart first',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Use actual cart items only - get products from cart items
        final List<Product> products = cartProvider.items.map((item) => item.product).toList();

        Widget checkOutButton = InkWell(
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => CheckoutFlowPage())),
          child: Container(
            height: 80,
            width: MediaQuery.of(context).size.width / 1.5,
            decoration: BoxDecoration(
                gradient: mainButton,
                boxShadow: [
                  BoxShadow(
                    color: Color.fromRGBO(0, 0, 0, 0.16),
                    offset: Offset(0, 5),
                    blurRadius: 10.0,
                  )
                ],
                borderRadius: BorderRadius.circular(9.0)),
            child: Center(
              child: Text("Check Out",
                  style: const TextStyle(
                      color: Color(0xfffefefe),
                      fontWeight: FontWeight.w600,
                      fontStyle: FontStyle.normal,
                      fontSize: 20.0)),
            ),
          ),
        );

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0.0,
            iconTheme: IconThemeData(color: darkGrey),
            actions: <Widget>[
              IconButton(
                icon: Image.asset('assets/icons/denied_wallet.png'),
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => UnpaidPage())),
              )
            ],
            title: Text(
              'Checkout',
              style: TextStyle(
                  color: darkGrey, fontWeight: FontWeight.w500, fontSize: 18.0),
            ),
          ),
          body: LayoutBuilder(
            builder: (_, constraints) => AppPullToRefresh(
              onRefresh: () async {
                if (!mounted) return;
                setState(() {});
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: ClampingScrollPhysics(),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 32.0),
                      height: 48.0,
                      color: yellow,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Text(
                            'Subtotal',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16),
                          ),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: <Widget>[
                              Text(
                                cartProvider.formattedTotalPrice,
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18),
                              ),
                              Text(
                                '${cartProvider.itemCount} items',
                                style: TextStyle(
                                    color: Colors.white.withOpacity(0.9),
                                    fontWeight: FontWeight.w500,
                                    fontSize: 12),
                              ),
                            ],
                          )
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 300,
                      child: Scrollbar(
                        child: ListView.builder(
                          itemBuilder: (_, index) {
                            final product = products[index];
                            final cartItem = cartProvider.getCartItem(product);

                            return ShopItemList(
                              product,
                              quantity: cartItem?.quantity ?? 1,
                              onRemove: () async {
                                if (cartProvider.isInCart(product)) {
                                  await cartProvider.removeFromCart(product);
                                } else {
                                  setState(() {
                                    products.removeAt(index);
                                  });
                                }
                              },
                              onQuantityChange: cartProvider.isInCart(product)
                                  ? (newQuantity) async {
                                      await cartProvider.updateQuantity(
                                          cartItem!, newQuantity);
                                    }
                                  : null,
                            );
                          },
                          itemCount: products.length,
                        ),
                      ),
                    ),
                    SizedBox(height: 24),
                    Center(
                        child: Padding(
                      padding: EdgeInsets.only(
                          bottom: MediaQuery.of(context).padding.bottom == 0
                              ? 20
                              : MediaQuery.of(context).padding.bottom),
                      child: checkOutButton,
                    ))
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
