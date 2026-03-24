import 'package:ecommerce_int2/models/product.dart';
import 'package:ecommerce_int2/screens/search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:ecommerce_int2/widgets/app_pull_to_refresh.dart';

import '../../app_properties.dart';
import 'components/product_options.dart';

class ViewProductPage extends StatefulWidget {
  final Product product;

  const ViewProductPage({super.key, required this.product});

  @override
  _ViewProductPageState createState() => _ViewProductPageState();
}

class _ViewProductPageState extends State<ViewProductPage> {
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
        widget.product.description,
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
            _getCategoryName(),
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
                  ProductOption(
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

  /// Get category name from product extra data or fallback to product name
  String _getCategoryName() {
    final extra = widget.product.extra;
    if (extra != null && extra['categoryNames'] != null) {
      final categoryNames = extra['categoryNames'];
      if (categoryNames is List && categoryNames.isNotEmpty) {
        return categoryNames.first.toString();
      }
    }
    // Fallback to product name if no category found
    return widget.product.name;
  }
}
