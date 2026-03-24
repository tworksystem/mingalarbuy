import 'package:ecommerce_int2/models/product.dart';
import 'package:ecommerce_int2/widgets/network_image_widget.dart';
import 'package:flutter/material.dart';

class ProductCard extends StatelessWidget {
  final Product product;

  const ProductCard(this.product, {super.key});

  @override
  Widget build(BuildContext context) {
    // OPTIMIZED: Cache MediaQuery to avoid multiple lookups
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = screenWidth / 2 - 29;
    final imageSize = screenWidth / 2 - 64;
    
    return InkWell(
        onTap: null,
        child: Container(
            height: 250,
            width: cardWidth,
            decoration: BoxDecoration(
                borderRadius: BorderRadius.all(Radius.circular(10)),
                color: Color(0xfffbd085).withOpacity(0.46)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    padding: EdgeInsets.all(16.0),
                    width: imageSize,
                    height: imageSize,
                    child: NetworkImageWidget(
                      imageUrl: product.image,
                      fit: BoxFit.contain,
                      fallbackAsset: 'assets/headphones.png',
                    ),
                  ),
                ),
                Flexible(
                  child: Align(
                    alignment: Alignment(1, 0.5),
                    child: Container(
                        margin: const EdgeInsets.only(left: 16.0),
                        padding: const EdgeInsets.all(8.0),
                        decoration: BoxDecoration(
                            color: Color(0xffe0450a).withOpacity(0.51),
                            borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(10),
                                bottomLeft: Radius.circular(10))),
                        child: Text(
                          product.name,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 12.0,
                            color: Colors.white,
                          ),
                        )),
                  ),
                )
              ],
            )));
  }
}
