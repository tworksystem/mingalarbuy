import 'package:ecommerce_int2/models/woocommerce_product.dart';
import 'package:ecommerce_int2/screens/search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:ecommerce_int2/widgets/app_pull_to_refresh.dart';

import '../../app_properties.dart';
import 'components/woocommerce_product_options.dart';

class WooCommerceViewProductPage extends StatefulWidget {
  final WooCommerceProduct product;

  const WooCommerceViewProductPage({super.key, required this.product});

  @override
  _WooCommerceViewProductPageState createState() =>
      _WooCommerceViewProductPageState();
}

class _WooCommerceViewProductPageState
    extends State<WooCommerceViewProductPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  int active = 0;

  ///list of product colors
  List<Widget> colors() {
    List<Widget> list = [];
    for (int i = 0; i < 5; i++) {
      list.add(
        InkWell(
          onTap: () {
            setState(() {
              active = i;
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
            child: Transform.scale(
              scale: active == i ? 1.2 : 1,
              child: Card(
                elevation: 3,
                color: Colors.primaries[i],
                child: SizedBox(
                  height: 32,
                  width: 32,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    Widget description = Padding(
      padding: const EdgeInsets.all(24.0),
      child: Text(
        widget.product.shortDescription.isNotEmpty
            ? widget.product.shortDescription.replaceAll(RegExp(r'<[^>]*>'), '')
            : widget.product.description.replaceAll(RegExp(r'<[^>]*>'), ''),
        style: TextStyle(color: Color.fromRGBO(255, 255, 255, 0.6)),
      ),
    );

    return Scaffold(
        key: _scaffoldKey,
        backgroundColor: yellow,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0.0,
          iconTheme: IconThemeData(color: darkGrey),
          actions: <Widget>[
            IconButton(
              icon: SvgPicture.asset(
                'assets/icons/search_icon.svg',
                fit: BoxFit.scaleDown,
              ),
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => SearchPage())),
            )
          ],
          title: Text(
            widget.product.categories.isNotEmpty
                ? widget.product.categories.first.name
                : widget.product.name,
            style: const TextStyle(
                color: darkGrey,
                fontWeight: FontWeight.w500,
                fontFamily: "Montserrat",
                fontSize: 18.0),
          ),
        ),
        body: AppPullToRefresh(
          onRefresh: () async {
            if (!mounted) return;
            setState(() {});
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              width: MediaQuery.of(context).size.width,
              child: Column(
                children: <Widget>[
                  WooCommerceProductOption(
                    _scaffoldKey,
                    product: widget.product,
                  ),
                  description,
                ],
              ),
            ),
          ),
        ));
  }

}
