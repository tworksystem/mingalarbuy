import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/page_content.dart';
import '../services/page_content_service.dart';
import '../app_properties.dart';
import '../theme/app_theme.dart';
import '../utils/logger.dart' as app_logger;
import 'app_pull_to_refresh.dart';
import 'cms_html_content_widget.dart';

/// Professional Dynamic Content Page Widget
/// Displays HTML content from backend with modern, creative design
class DynamicContentPage extends StatefulWidget {
  final String pageSlug;
  final String pageTitle;
  final IconData? icon;
  final Color? headerColor;

  const DynamicContentPage({
    super.key,
    required this.pageSlug,
    required this.pageTitle,
    this.icon,
    this.headerColor,
  });

  @override
  State<DynamicContentPage> createState() => _DynamicContentPageState();
}

class _DynamicContentPageState extends State<DynamicContentPage> {
  PageContent? _content;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final content = await PageContentService.getPageContent(widget.pageSlug);

      if (mounted) {
        setState(() {
          _content = content;
          _isLoading = false;
          if (content == null) {
            _error = PageContentService.lastError ?? 'Failed to load content';
          }
        });
      }
    } catch (e) {
      app_logger.Logger.error('Error loading page content: $e',
          tag: 'DynamicContentPage', error: e);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load content: ${e.toString()}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headerColor = widget.headerColor ?? AppTheme.deepBlue;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: darkGrey),
        title: Text(
          widget.pageTitle,
          style: TextStyle(
            color: darkGrey,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      body: AppPullToRefresh(
        onRefresh: _loadContent,
        child: _buildBody(theme, headerColor),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, Color headerColor) {
    if (_isLoading) {
      return _buildLoadingState();
    }

    if (_error != null && _content == null) {
      return _buildErrorState();
    }

    if (_content == null) {
      return _buildEmptyState();
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Creative Header Card
          _buildHeaderCard(theme, headerColor),

          const SizedBox(height: 24),

          // Content Card
          _buildContentCard(theme),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(ThemeData theme, Color headerColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            headerColor,
            headerColor.withOpacity(0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: headerColor.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          if (widget.icon != null) ...[
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.2),
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: Icon(
                widget.icon,
                color: Colors.white,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            _content!.title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildContentCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: CmsHtmlContentWidget(html: _content!.content),
    );
  }

  Widget _buildLoadingState() {
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
              'Loading content...',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load content',
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Unknown error',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadContent,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.deepBlue,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.description_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'Content Coming Soon',
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This page is being prepared. Please check back later.',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
