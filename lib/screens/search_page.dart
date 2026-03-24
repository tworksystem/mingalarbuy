import 'package:ecommerce_int2/app_properties.dart';
import 'package:ecommerce_int2/models/product.dart';
import 'package:ecommerce_int2/woocommerce_service.dart';
import 'package:ecommerce_int2/screens/product/view_product_page.dart';
import 'package:ecommerce_int2/utils/logger.dart';
import 'package:ecommerce_int2/widgets/app_pull_to_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:rubber/rubber.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  _SearchPageState createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage>
    with SingleTickerProviderStateMixin {
  String selectedPeriod = "";
  String selectedCategory = "";
  String selectedPrice = "";
  List<Product> products = [];
  bool isLoading = false;
  final TextEditingController searchController = TextEditingController();

  List<String> timeFilter = [
    'Brand',
    'New',
    'Latest',
    'Trending',
    'Discount',
  ];

  List<String> categoryFilter = [
    'Skull Candy',
    'Boat',
    'JBL',
    'Micromax',
    'Seg',
  ];

  List<String> priceFilter = [
    '50-200 Ks',
    '200-400 Ks',
    '400-800 Ks',
    '800-1000 Ks',
  ];

  List<Product> searchResults = [];

  @override
  void initState() {
    super.initState();
    loadAllProducts();
    _controller = RubberAnimationController(
        vsync: this,
        halfBoundValue: AnimationControllerValue(percentage: 0.4),
        upperBoundValue: AnimationControllerValue(percentage: 0.4),
        lowerBoundValue: AnimationControllerValue(pixel: 50),
        duration: Duration(milliseconds: 200));
  }

  Future<void> loadAllProducts() async {
    setState(() {
      isLoading = true;
    });

    try {
      final wooProducts = await WooCommerceService.getProducts(perPage: 50);
      final convertedProducts =
          wooProducts.map((wooProduct) => wooProduct.toProduct()).toList();

      setState(() {
        products = convertedProducts;
        searchResults = convertedProducts;
        isLoading = false;
      });
    } catch (e, stackTrace) {
      Logger.error('Error loading products: $e',
          tag: 'SearchPage', error: e, stackTrace: stackTrace);
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> searchProducts(String query) async {
    if (query.isEmpty) {
      setState(() {
        searchResults = products;
      });
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final wooProducts =
          await WooCommerceService.searchProducts(query, perPage: 20);
      final convertedProducts =
          wooProducts.map((wooProduct) => wooProduct.toProduct()).toList();

      setState(() {
        searchResults = convertedProducts;
        isLoading = false;
      });
    } catch (e, stackTrace) {
      Logger.error('Error searching products: $e',
          tag: 'SearchPage', error: e, stackTrace: stackTrace);
      setState(() {
        isLoading = false;
      });
    }
  }

  late RubberAnimationController _controller;


  Widget _getLowerLayer() {
    return Container(
      margin: const EdgeInsets.only(top: kToolbarHeight),
      child: Column(
        children: <Widget>[
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  'Search',
                  style: TextStyle(
                    color: darkGrey,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                CloseButton()
              ],
            ),
          ),
          Container(
            margin: EdgeInsets.symmetric(horizontal: 16.0),
            decoration: BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: Colors.orange, width: 1))),
            child: TextField(
              controller: searchController,
              onChanged: (value) {
                searchProducts(value);
              },
              cursorColor: darkGrey,
              decoration: InputDecoration(
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                prefixIcon: SvgPicture.asset(
                  'assets/icons/search_icon.svg',
                  fit: BoxFit.scaleDown,
                ),
                suffix: TextButton(
                  onPressed: () {
                    searchController.clear();
                    searchResults.clear();
                  },
                  child: Text(
                    'Clear',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ),
            ),
          ),
          Flexible(
            child: Container(
              color: Colors.orange[50],
              child: ListView.builder(
                  itemCount: searchResults.length,
                  itemBuilder: (_, index) => Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.0),
                      child: ListTile(
                        onTap: () =>
                            Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => ViewProductPage(
                                      product: searchResults[index],
                                    ))),
                        title: Text(searchResults[index].name),
                      ))),
            ),
          )
        ],
      ),
    );
  }

  Widget _getUpperLayer() {
    return Container(
      decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
                color: Color.fromRGBO(0, 0, 0, 0.05),
                offset: Offset(0, -3),
                blurRadius: 10)
          ],
          borderRadius: BorderRadius.only(
              topRight: Radius.circular(24), topLeft: Radius.circular(24)),
          color: Colors.white),
      child: ListView(
        physics: NeverScrollableScrollPhysics(),
//          controller: _scrollController,
        children: <Widget>[
          Align(
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                'Filters',
                style: TextStyle(color: Colors.grey[300]),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding:
                  const EdgeInsets.only(left: 32.0, top: 16.0, bottom: 16.0),
              child: Text(
                'Sort By',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          SizedBox(
            height: 50,
            child: ListView.builder(
              itemBuilder: (_, index) => Center(
                  child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 8.0,
                ),
                child: InkWell(
                    onTap: () {
                      setState(() {
                        selectedPeriod = timeFilter[index];
                      });
                    },
                    child: Container(
                        padding: EdgeInsets.symmetric(
                            vertical: 4.0, horizontal: 20.0),
                        decoration: selectedPeriod == timeFilter[index]
                            ? BoxDecoration(
                                color: Color(0xffFDB846),
                                borderRadius:
                                    BorderRadius.all(Radius.circular(45)))
                            : BoxDecoration(),
                        child: Text(
                          timeFilter[index],
                          style: TextStyle(fontSize: 16.0),
                        ))),
              )),
              itemCount: timeFilter.length,
              scrollDirection: Axis.horizontal,
            ),
          ),
          SizedBox(
            height: 50,
            child: ListView.builder(
              itemBuilder: (_, index) => Center(
                  child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 8.0,
                ),
                child: InkWell(
                    onTap: () {
                      setState(() {
                        selectedCategory = categoryFilter[index];
                      });
                    },
                    child: Container(
                        padding: EdgeInsets.symmetric(
                            vertical: 4.0, horizontal: 20.0),
                        decoration: selectedCategory == categoryFilter[index]
                            ? BoxDecoration(
                                color: Color(0xffFDB846),
                                borderRadius:
                                    BorderRadius.all(Radius.circular(45)))
                            : BoxDecoration(),
                        child: Text(
                          categoryFilter[index],
                          style: TextStyle(fontSize: 16.0),
                        ))),
              )),
              itemCount: categoryFilter.length,
              scrollDirection: Axis.horizontal,
            ),
          ),
          SizedBox(
            height: 50,
            child: ListView.builder(
              itemBuilder: (_, index) => Center(
                  child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 8.0,
                ),
                child: InkWell(
                    onTap: () {
                      setState(() {
                        selectedPrice = priceFilter[index];
                      });
                    },
                    child: Container(
                        padding: EdgeInsets.symmetric(
                            vertical: 4.0, horizontal: 20.0),
                        decoration: selectedPrice == priceFilter[index]
                            ? BoxDecoration(
                                color: Color(0xffFDB846),
                                borderRadius:
                                    BorderRadius.all(Radius.circular(45)))
                            : BoxDecoration(),
                        child: Text(
                          priceFilter[index],
                          style: TextStyle(fontSize: 16.0),
                        ))),
              )),
              itemCount: priceFilter.length,
              scrollDirection: Axis.horizontal,
            ),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: SafeArea(
        top: true,
        bottom: false,
        child: Scaffold(
//          bottomSheet: ClipRRect(
//            borderRadius: BorderRadius.only(
//                topRight: Radius.circular(25), topLeft: Radius.circular(25)),
//            child: BottomSheet(
//                onClosing: () {},
//                builder: (_) => Container(
//                      padding: EdgeInsets.all(16.0),
//                      child: Row(
//                          mainAxisAlignment: MainAxisAlignment.center,
//                          children: <Widget>[Text('Filters')]),
//                      color: Colors.white,
//                      width: MediaQuery.of(context).size.height,
//                    )),
//          ),
            body: RubberBottomSheet(
          lowerLayer: AppPullToRefresh(
            onRefresh: () async {
              await loadAllProducts();
            },
            child: _getLowerLayer(),
          ), // The underlying page (Widget)
          upperLayer: _getUpperLayer(), // The bottomsheet content (Widget)
          animationController: _controller, // The one we created earlier
        )),
      ),
    );
  }
}
