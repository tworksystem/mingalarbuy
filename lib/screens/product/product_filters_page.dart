import 'package:ecommerce_int2/app_properties.dart';
import 'package:ecommerce_int2/models/product_filters.dart';
import 'package:ecommerce_int2/providers/product_filter_provider.dart';
import 'package:ecommerce_int2/widgets/app_pull_to_refresh.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Professional product filters page
class ProductFiltersPage extends StatefulWidget {
  final ProductFilters initialFilters;

  ProductFiltersPage({
    super.key,
    ProductFilters? initialFilters,
  }) : initialFilters = initialFilters ?? ProductFilters();

  @override
  _ProductFiltersPageState createState() => _ProductFiltersPageState();
}

class _ProductFiltersPageState extends State<ProductFiltersPage> {
  late ProductFilters _filters;
  PriceRange? _priceRange;
  SortOption? _selectedSort;

  @override
  void initState() {
    super.initState();
    _filters = widget.initialFilters;
    _priceRange = _filters.priceRange;
    _selectedSort = _filters.sortBy;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: darkGrey),
        title: Text(
          'Filters',
          style: TextStyle(
            color: darkGrey,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          if (_filters.hasFilters)
            TextButton(
              onPressed: _clearFilters,
              child: Text(
                'Clear All',
                style: TextStyle(color: Colors.red),
              ),
            ),
        ],
      ),
      body: AppPullToRefresh(
        onRefresh: () async {
          if (!mounted) return;
          setState(() {});
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // Sort options
            _buildSortSection(),
            SizedBox(height: 24),

            // Price range
            _buildPriceRangeSection(),
            SizedBox(height: 24),

            // Stock filter
            _buildStockFilterSection(),
            SizedBox(height: 24),

            // Featured filter
            _buildFeaturedFilterSection(),
            SizedBox(height: 24),

            // Apply button
            _buildApplyButton(),
            ],
          ),
        ),
      ),
    );
  }

  /// Build sort section
  Widget _buildSortSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sort By',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: darkGrey,
          ),
        ),
        SizedBox(height: 12),
        ...SortOption.allOptions.map((option) {
          final isSelected = _selectedSort == option;
          return RadioListTile<SortOption>(
            title: Text(option.displayName),
            value: option,
            groupValue: _selectedSort,
            onChanged: (value) {
              setState(() {
                _selectedSort = value;
              });
            },
            activeColor: mediumYellow,
            selected: isSelected,
          );
        }),
      ],
    );
  }

  /// Build price range section
  Widget _buildPriceRangeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Price Range',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: darkGrey,
          ),
        ),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  labelText: 'Min Price',
                  prefixText: 'Ks ',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  final min = double.tryParse(value);
                  setState(() {
                    _priceRange = PriceRange(
                      min: min,
                      max: _priceRange?.max,
                    );
                  });
                },
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  labelText: 'Max Price',
                  prefixText: 'Ks ',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  final max = double.tryParse(value);
                  setState(() {
                    _priceRange = PriceRange(
                      min: _priceRange?.min,
                      max: max,
                    );
                  });
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Build stock filter section
  Widget _buildStockFilterSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Availability',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: darkGrey,
          ),
        ),
        SizedBox(height: 12),
        CheckboxListTile(
          title: Text('In Stock Only'),
          value: _filters.inStock ?? false,
          onChanged: (value) {
            setState(() {
              _filters = _filters.copyWith(inStock: value);
            });
          },
          activeColor: mediumYellow,
        ),
      ],
    );
  }

  /// Build featured filter section
  Widget _buildFeaturedFilterSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Product Type',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: darkGrey,
          ),
        ),
        SizedBox(height: 12),
        CheckboxListTile(
          title: Text('Featured Products Only'),
          value: _filters.featured ?? false,
          onChanged: (value) {
            setState(() {
              _filters = _filters.copyWith(featured: value);
            });
          },
          activeColor: mediumYellow,
        ),
      ],
    );
  }

  /// Build apply button
  Widget _buildApplyButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _applyFilters,
        style: ElevatedButton.styleFrom(
          backgroundColor: mediumYellow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          'Apply Filters',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  /// Apply filters
  void _applyFilters() {
    final updatedFilters = _filters.copyWith(
      priceRange: _priceRange,
      sortBy: _selectedSort,
    );

    final filterProvider = Provider.of<ProductFilterProvider>(context, listen: false);
    filterProvider.applyFilters(updatedFilters);

    Navigator.of(context).pop(updatedFilters);
  }

  /// Clear all filters
  void _clearFilters() {
    setState(() {
      _filters = ProductFilters();
      _priceRange = null;
      _selectedSort = null;
    });
  }
}

