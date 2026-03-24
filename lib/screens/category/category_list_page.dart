import 'package:ecommerce_int2/app_properties.dart';
import 'package:ecommerce_int2/models/category.dart';
import 'package:ecommerce_int2/providers/category_provider.dart';
import 'package:ecommerce_int2/widgets/modern_loading_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import 'components/staggered_category_card.dart';

class CategoryListPage extends StatefulWidget {
  const CategoryListPage({super.key});

  @override
  _CategoryListPageState createState() => _CategoryListPageState();
}

class _CategoryListPageState extends State<CategoryListPage> {
  List<Category> searchResults = [];
  TextEditingController searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Load categories when page opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCategories();
    });
  }

  Future<void> _loadCategories() async {
    final categoryProvider = Provider.of<CategoryProvider>(context, listen: false);
    
    // Load categories if not already loaded
    if (!categoryProvider.hasCategories) {
      await categoryProvider.loadCategories();
    }
    
    // Initialize search results with all categories
    _updateSearchResults(categoryProvider.categories);
  }

  void _updateSearchResults(List<Category> categories) {
    setState(() {
      searchResults = List<Category>.from(categories);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Color(0xffF9F9F9),
      child: Container(
        margin: const EdgeInsets.only(top: kToolbarHeight),
        padding: EdgeInsets.symmetric(horizontal: 16.0),
        child: Consumer<CategoryProvider>(
          builder: (context, categoryProvider, child) {
            // Update search results when categories change
            if (searchResults.isEmpty && categoryProvider.categories.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _updateSearchResults(categoryProvider.categories);
              });
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Align(
                  alignment: Alignment(-1, 0),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.0),
                    child: Text(
                      'Category List',
                      style: TextStyle(
                        color: darkGrey,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                Container(
                  padding: EdgeInsets.only(left: 16.0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.all(Radius.circular(5)),
                    color: Colors.white,
                  ),
                  child: TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Search categories',
                      prefixIcon: SvgPicture.asset(
                        'assets/icons/search_icon.svg',
                        fit: BoxFit.scaleDown,
                      ),
                    ),
                    onChanged: (value) {
                      if (value.isNotEmpty) {
                        final results = categoryProvider.searchCategories(value);
                        setState(() {
                          searchResults = List<Category>.from(results);
                        });
                      } else {
                        setState(() {
                          searchResults = List<Category>.from(categoryProvider.categories);
                        });
                      }
                    },
                  ),
                ),
                Flexible(
                  child: categoryProvider.isLoading && searchResults.isEmpty
                      ? Center(
                          child: ModernLoadingIndicator(
                            size: 50,
                            color: mediumYellow,
                          ),
                        )
                      : categoryProvider.errorMessage != null &&
                              searchResults.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    size: 64,
                                    color: Colors.grey[400],
                                  ),
                                  SizedBox(height: 16),
                                  Text(
                                    categoryProvider.errorMessage ?? 'Error loading categories',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey[600],
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: () {
                                      categoryProvider.loadCategories(forceRefresh: true);
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: mediumYellow,
                                    ),
                                    child: Text('Retry'),
                                  ),
                                ],
                              ),
                            )
                          : searchResults.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.category_outlined,
                                        size: 64,
                                        color: Colors.grey[400],
                                      ),
                                      SizedBox(height: 16),
                                      Text(
                                        'No categories found',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : RefreshIndicator(
                                  onRefresh: () async {
                                    await categoryProvider.refresh();
                                    setState(() {
                                      searchResults = List<Category>.from(categoryProvider.categories);
                                    });
                                  },
                                  color: mediumYellow,
                                  child: ListView.builder(
                                    itemCount: searchResults.length,
                                    itemBuilder: (_, index) => Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 16.0,
                                      ),
                                      child: StaggeredCardCard(
                                        begin: searchResults[index].begin,
                                        end: searchResults[index].end,
                                        categoryName:
                                            searchResults[index].category,
                                        assetPath: searchResults[index].image,
                                        category: searchResults[index],
                                      ),
                                    ),
                                  ),
                                ),
                )
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }
}
