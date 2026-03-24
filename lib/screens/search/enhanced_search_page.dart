import 'package:ecommerce_int2/app_properties.dart';
import 'package:ecommerce_int2/models/product.dart';
import 'package:ecommerce_int2/providers/product_filter_provider.dart';
import 'package:ecommerce_int2/services/search_service.dart';
import 'package:ecommerce_int2/screens/product/view_product_page.dart';
import 'package:ecommerce_int2/utils/logger.dart';
import 'package:ecommerce_int2/widgets/network_status_banner.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Professional enhanced search page with autocomplete, recent searches, and filters
class EnhancedSearchPage extends StatefulWidget {
  const EnhancedSearchPage({super.key});

  @override
  _EnhancedSearchPageState createState() => _EnhancedSearchPageState();
}

class _EnhancedSearchPageState extends State<EnhancedSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  
  List<String> _recentSearches = [];
  List<String> _suggestions = [];
  List<Product> _searchResults = [];
  bool _isLoading = false;
  bool _showSuggestions = false;
  String _currentQuery = '';

  @override
  void initState() {
    super.initState();
    _loadRecentSearches();
    _searchController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// Load recent searches
  Future<void> _loadRecentSearches() async {
    final searches = await SearchService.getRecentSearches();
    setState(() {
      _recentSearches = searches;
    });
  }

  /// Handle search text changes
  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query != _currentQuery) {
      _currentQuery = query;
      if (query.isEmpty) {
        setState(() {
          _suggestions = [];
          _searchResults = [];
          _showSuggestions = true;
        });
        _loadRecentSearches();
      } else {
        _loadSuggestions(query);
      }
    }
  }

  /// Handle focus changes
  void _onFocusChanged() {
    if (_searchFocusNode.hasFocus && _searchController.text.isEmpty) {
      setState(() {
        _showSuggestions = true;
      });
    }
  }

  /// Load search suggestions (autocomplete)
  Future<void> _loadSuggestions(String query) async {
    if (query.isEmpty) return;

    try {
      final suggestions = await SearchService.getSearchSuggestions(query);
      setState(() {
        _suggestions = suggestions;
        _showSuggestions = true;
      });
    } catch (e) {
      Logger.error('Error loading suggestions: $e', tag: 'EnhancedSearchPage', error: e);
    }
  }

  /// Perform search
  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _showSuggestions = true;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _showSuggestions = false;
    });

    try {
      // Save to recent searches
      await SearchService.saveSearchQuery(query);

      // Get filter provider
      final filterProvider = Provider.of<ProductFilterProvider>(context, listen: false);
      
      // Update search query in filter provider
      await filterProvider.updateSearchQuery(query);

      // Get filtered results
      final results = filterProvider.filteredProducts;

      setState(() {
        _searchResults = results;
        _isLoading = false;
      });

      // Reload recent searches
      await _loadRecentSearches();
    } catch (e, stackTrace) {
      Logger.error('Error performing search: $e',
          tag: 'EnhancedSearchPage', error: e, stackTrace: stackTrace);
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Clear search
  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchResults = [];
      _suggestions = [];
      _showSuggestions = true;
      _currentQuery = '';
    });
    _loadRecentSearches();
  }

  /// Select suggestion
  void _selectSuggestion(String suggestion) {
    _searchController.text = suggestion;
    _searchFocusNode.unfocus();
    _performSearch(suggestion);
  }

  /// Clear recent searches
  Future<void> _clearRecentSearches() async {
    await SearchService.clearRecentSearches();
    setState(() {
      _recentSearches = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return NetworkStatusBanner(
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: darkGrey),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: _buildSearchBar(),
          actions: [
            if (_searchController.text.isNotEmpty)
              IconButton(
                icon: Icon(Icons.clear, color: darkGrey),
                onPressed: _clearSearch,
              ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  /// Build search bar
  Widget _buildSearchBar() {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(20),
      ),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'Search products...',
          hintStyle: TextStyle(color: Colors.grey[600]),
          prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
        onSubmitted: _performSearch,
      ),
    );
  }

  /// Build body content
  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(mediumYellow),
        ),
      );
    }

    if (_showSuggestions) {
      return _buildSuggestionsView();
    }

    if (_searchResults.isEmpty && _currentQuery.isNotEmpty) {
      return _buildEmptyResultsView();
    }

    return _buildResultsView();
  }

  /// Build suggestions view (recent searches + autocomplete)
  Widget _buildSuggestionsView() {
    return RefreshIndicator(
      onRefresh: _loadRecentSearches,
      color: mediumYellow,
      child: ListView(
        padding: EdgeInsets.all(16),
        children: [
          // Recent searches section
          if (_recentSearches.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Searches',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: darkGrey,
                  ),
                ),
                TextButton(
                  onPressed: _clearRecentSearches,
                  child: Text(
                    'Clear',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _recentSearches.map((search) {
                return ActionChip(
                  label: Text(search),
                  avatar: Icon(Icons.history, size: 18),
                  onPressed: () => _selectSuggestion(search),
                  backgroundColor: Colors.grey[100],
                );
              }).toList(),
            ),
            SizedBox(height: 24),
          ],

          // Suggestions section
          if (_suggestions.isNotEmpty) ...[
            Text(
              'Suggestions',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: darkGrey,
              ),
            ),
            SizedBox(height: 12),
            ..._suggestions.map((suggestion) {
              return ListTile(
                leading: Icon(Icons.search, color: mediumYellow),
                title: Text(suggestion),
                onTap: () => _selectSuggestion(suggestion),
              );
            }),
          ],

          // Empty state
          if (_recentSearches.isEmpty && _suggestions.isEmpty)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search,
                    size: 64,
                    color: Colors.grey[300],
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Start searching for products',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Build results view
  Widget _buildResultsView() {
    return RefreshIndicator(
      onRefresh: () => _performSearch(_currentQuery),
      color: mediumYellow,
      child: ListView.builder(
        padding: EdgeInsets.all(16),
        itemCount: _searchResults.length,
        itemBuilder: (context, index) {
          final product = _searchResults[index];
          return Card(
            margin: EdgeInsets.only(bottom: 12),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              contentPadding: EdgeInsets.all(12),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  product.image,
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 60,
                      height: 60,
                      color: Colors.grey[200],
                      child: Icon(Icons.image, color: Colors.grey),
                    );
                  },
                ),
              ),
              title: Text(
                product.name,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              subtitle: Text(
                product.formattedPrice,
                style: TextStyle(
                  color: mediumYellow,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              trailing: Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ViewProductPage(product: product),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  /// Build empty results view
  Widget _buildEmptyResultsView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 64,
            color: Colors.grey[300],
          ),
          SizedBox(height: 16),
          Text(
            'No products found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Try different keywords or filters',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }
}

