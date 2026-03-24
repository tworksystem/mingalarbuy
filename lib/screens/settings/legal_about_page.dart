import 'package:ecommerce_int2/app_properties.dart';
import 'package:ecommerce_int2/widgets/app_pull_to_refresh.dart';
import 'package:ecommerce_int2/services/page_content_service.dart';
import 'package:ecommerce_int2/models/page_content.dart';
import 'package:ecommerce_int2/widgets/dynamic_content_page.dart';
import 'package:ecommerce_int2/theme/app_theme.dart';
import 'package:ecommerce_int2/utils/logger.dart' as app_logger;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LegalAboutPage extends StatefulWidget {
  const LegalAboutPage({super.key});

  @override
  _LegalAboutPageState createState() => _LegalAboutPageState();
}

class _LegalAboutPageState extends State<LegalAboutPage> {
  List<PageListItem> _pages = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPages();
  }

  Future<void> _loadPages() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final pages = await PageContentService.getAllPages();
      
      if (mounted) {
        setState(() {
          _pages = pages;
          _isLoading = false;
          if (pages.isEmpty && PageContentService.lastError != null) {
            _error = PageContentService.lastError;
          }
        });
      }
    } catch (e) {
      app_logger.Logger.error('Error loading pages: $e',
          tag: 'LegalAboutPage', error: e);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load pages: ${e.toString()}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        iconTheme: IconThemeData(
            color: Colors.black,
          ),
        backgroundColor: Colors.transparent,
        title: Text(
          'Settings',
          style: TextStyle(color: darkGrey),
        ),
        elevation: 0, systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      body: SafeArea(
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.only(top:24.0,left: 24.0, right: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text(
                  'Legal & About',
                  style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 18.0),
                ),
              ),
              Flexible(
                child: AppPullToRefresh(
                  onRefresh: _loadPages,
                  child: _buildPagesList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPagesList() {
    if (_isLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.deepBlue),
              ),
              const SizedBox(height: 16),
              Text(
                'Loading pages...',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null && _pages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'Failed to load pages',
                style: TextStyle(
                  color: Colors.grey[700],
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error ?? 'Unknown error',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadPages,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[800],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_pages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.description_outlined,
                size: 48,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'No Pages Available',
                style: TextStyle(
                  color: Colors.grey[700],
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Pages are being prepared. Please check back later.',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: _pages.map((page) => _buildPolicyTile(
        context,
        page: page,
      )).toList(),
    );
  }

  Widget _buildPolicyTile(
    BuildContext context, {
    required PageListItem page,
  }) {
    // Get icon and color from meta data or use defaults based on slug
    final iconData = _getIconForPage(page);
    final color = _getColorForPage(page);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            iconData,
            color: color,
            size: 24,
          ),
        ),
        title: Text(
          page.title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: darkGrey,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: Colors.grey[400],
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DynamicContentPage(
              pageSlug: page.slug,
              pageTitle: page.title,
              icon: iconData,
              headerColor: color,
            ),
          ),
        ),
      ),
    );
  }

  /// Get icon for page based on meta data or slug
  IconData _getIconForPage(PageListItem page) {
    // Check if icon is specified in meta data
    if (page.meta != null && page.meta!['icon'] != null) {
      final iconName = page.meta!['icon'].toString();
      // Map common icon names to IconData
      switch (iconName) {
        case 'description_outlined':
          return Icons.description_outlined;
        case 'privacy_tip_outlined':
          return Icons.privacy_tip_outlined;
        case 'copyright_outlined':
          return Icons.copyright_outlined;
        case 'store_outlined':
          return Icons.store_outlined;
        case 'assignment_return_outlined':
          return Icons.assignment_return_outlined;
        case 'info_outline':
          return Icons.info_outline;
        default:
          break;
      }
    }

    // Default icon mapping based on slug
    final slug = page.slug.toLowerCase();
    if (slug.contains('terms')) {
      return Icons.description_outlined;
    } else if (slug.contains('privacy')) {
      return Icons.privacy_tip_outlined;
    } else if (slug.contains('license')) {
      return Icons.copyright_outlined;
    } else if (slug.contains('seller')) {
      return Icons.store_outlined;
    } else if (slug.contains('return')) {
      return Icons.assignment_return_outlined;
    } else if (slug.contains('about')) {
      return Icons.info_outline;
    }
    return Icons.description_outlined; // Default icon
  }

  /// Get color for page based on meta data or slug
  Color _getColorForPage(PageListItem page) {
    // Check if color is specified in meta data (hex format)
    if (page.meta != null && page.meta!['color'] != null) {
      final colorString = page.meta!['color'].toString();
      if (colorString.startsWith('#')) {
        try {
          return Color(int.parse(colorString.substring(1), radix: 16) + 0xFF000000);
        } catch (e) {
          app_logger.Logger.warning('Invalid color format: $colorString', tag: 'LegalAboutPage');
        }
      }
    }

    // Default color mapping based on slug
    final slug = page.slug.toLowerCase();
    if (slug.contains('terms')) {
      return AppTheme.deepBlue;
    } else if (slug.contains('privacy')) {
      return AppTheme.brightPurple;
    } else if (slug.contains('license')) {
      return Colors.orange;
    } else if (slug.contains('seller')) {
      return Colors.green;
    } else if (slug.contains('return')) {
      return Colors.teal;
    } else if (slug.contains('about')) {
      return AppTheme.deepBlue;
    }
    return AppTheme.deepBlue; // Default color
  }
}
