import 'package:ecommerce_int2/app_properties.dart';
import 'package:ecommerce_int2/services/woocommerce_service_cached.dart';
import 'package:ecommerce_int2/services/connectivity_service.dart';
import 'package:ecommerce_int2/widgets/app_pull_to_refresh.dart';
import 'package:flutter/material.dart';

/// Cache Management Page
/// Allows users to view cache stats and clear cache
class CacheManagementPage extends StatefulWidget {
  const CacheManagementPage({super.key});

  @override
  _CacheManagementPageState createState() => _CacheManagementPageState();
}

class _CacheManagementPageState extends State<CacheManagementPage> {
  Map<String, dynamic> cacheStats = {};
  bool isLoading = true;
  bool isOnline = false;

  @override
  void initState() {
    super.initState();
    _loadCacheStats();
    _checkConnectivity();
  }

  Future<void> _checkConnectivity() async {
    final connectivityService = ConnectivityService();
    await connectivityService.initialize();
    final connected = await connectivityService.checkConnectivity();
    setState(() {
      isOnline = connected;
    });
  }

  Future<void> _loadCacheStats() async {
    setState(() {
      isLoading = true;
    });

    try {
      final stats = await WooCommerceServiceCached.getCacheStats();
      setState(() {
        cacheStats = stats;
        isLoading = false;
      });
    } catch (e) {
      print('Error loading cache stats: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _clearProductCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Product Cache?'),
        content: const Text(
          'This will remove all cached product data. You will need an internet connection to reload products.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await WooCommerceServiceCached.clearCache();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Product cache cleared successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _loadCacheStats();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error clearing cache: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _clearImageCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Image Cache?'),
        content: const Text(
          'This will remove all cached images. Images will be downloaded again when needed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        imageCache.clear();
        imageCache.clearLiveImages();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image cache cleared successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _loadCacheStats();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error clearing image cache: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _clearAllCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Cache?'),
        content: const Text(
          'This will remove all cached data including products and images. You will need an internet connection to reload data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await WooCommerceServiceCached.clearCache();
        imageCache.clear();
        imageCache.clearLiveImages();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All cache cleared successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _loadCacheStats();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error clearing cache: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: darkGrey),
        title: const Text(
          'Cache Management',
          style: TextStyle(color: darkGrey),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCacheStats,
            tooltip: 'Refresh Stats',
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : AppPullToRefresh(
              onRefresh: () async {
                await _checkConnectivity();
                await _loadCacheStats();
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  // Connection Status Card
                  Card(
                    child: ListTile(
                      leading: Icon(
                        isOnline ? Icons.cloud_done : Icons.cloud_off,
                        color: isOnline ? Colors.green : Colors.orange,
                        size: 32,
                      ),
                      title: Text(
                        isOnline ? 'Online' : 'Offline',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        isOnline
                            ? 'Connected to internet'
                            : 'Using cached data',
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Cache Statistics
                  const Text(
                    'Cache Statistics',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: darkGrey,
                    ),
                  ),
                  const SizedBox(height: 16),

                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          _buildStatRow(
                            'Total Products',
                            '${cacheStats['total_products'] ?? 0}',
                            Icons.shopping_bag,
                          ),
                          const Divider(),
                          _buildStatRow(
                            'Cache Keys',
                            '${cacheStats['cache_keys'] ?? 0}',
                            Icons.key,
                          ),
                          const Divider(),
                          _buildStatRow(
                            'Estimated Size',
                            '${(cacheStats['size_kb'] ?? 0).toStringAsFixed(1)} KB',
                            Icons.storage,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Cache Actions
                  const Text(
                    'Cache Actions',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: darkGrey,
                    ),
                  ),
                  const SizedBox(height: 16),

                  _buildActionButton(
                    'Clear Product Cache',
                    'Remove all cached product data',
                    Icons.delete_outline,
                    Colors.orange,
                    _clearProductCache,
                  ),

                  const SizedBox(height: 12),

                  _buildActionButton(
                    'Clear Image Cache',
                    'Remove all cached images',
                    Icons.image_not_supported,
                    Colors.orange,
                    _clearImageCache,
                  ),

                  const SizedBox(height: 12),

                  _buildActionButton(
                    'Clear All Cache',
                    'Remove all cached data',
                    Icons.cleaning_services,
                    Colors.red,
                    _clearAllCache,
                  ),

                  const SizedBox(height: 24),

                  // Info Card
                  Card(
                    color: Colors.blue.withOpacity(0.1),
                    child: const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Cache helps load products faster and works offline. It is automatically updated when you have an internet connection.',
                              style: TextStyle(color: darkGrey, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildStatRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: mediumYellow, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 16, color: darkGrey),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: darkGrey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color, size: 32),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onPressed,
      ),
    );
  }
}
