import 'package:ecommerce_int2/widgets/woocommerce_product_list.dart';
import 'package:flutter/material.dart';
import 'package:ecommerce_int2/widgets/app_pull_to_refresh.dart';

/// WooCommerce Products Page
///
/// Displays products from Home Aid Myanmar (homeaid.com.mm)
/// using WooCommerce REST API integration.
class WooCommercePage extends StatefulWidget {
  const WooCommercePage({super.key});

  @override
  _WooCommercePageState createState() => _WooCommercePageState();
}

class _WooCommercePageState extends State<WooCommercePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Home Aid Myanmar',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'www.homeaid.com.mm',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'All Products'),
            Tab(text: 'Featured'),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: () {
              // Force refresh
              setState(() {});
            },
            tooltip: 'Refresh Products',
          ),
          IconButton(
            icon: Icon(Icons.info_outline),
            onPressed: () {
              _showInfoDialog();
            },
            tooltip: 'About Integration',
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // All Products Tab
          AppPullToRefresh(
            onRefresh: () async {
              if (!mounted) return;
              setState(() {});
            },
            child: WooCommerceProductList(featured: false),
          ),
          // Featured Products Tab
          AppPullToRefresh(
            onRefresh: () async {
              if (!mounted) return;
              setState(() {});
            },
            child: WooCommerceProductList(featured: true),
          ),
        ],
      ),
    );
  }

  void _showInfoDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.shopping_cart, color: Colors.blue),
            SizedBox(width: 8),
            Text('WooCommerce Integration'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'This app is connected to:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('🏪 Home Aid Myanmar'),
              Text('🌐 www.homeaid.com.mm'),
              SizedBox(height: 16),
              Text(
                'Features:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              _buildFeatureItem('Real-time product synchronization'),
              _buildFeatureItem('Offline caching support'),
              _buildFeatureItem('Featured products showcase'),
              _buildFeatureItem('Product search & filtering'),
              _buildFeatureItem('Stock status tracking'),
              _buildFeatureItem('Automatic price updates'),
              SizedBox(height: 16),
              Text(
                'Pull down to refresh products anytime!',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Got it!'),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: 4, left: 8),
      child: Row(
        children: [
          Icon(Icons.check_circle, size: 16, color: Colors.green),
          SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}
