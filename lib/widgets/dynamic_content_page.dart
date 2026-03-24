import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/page_content.dart';
import '../services/page_content_service.dart';
import '../app_properties.dart';
import '../theme/app_theme.dart';
import '../utils/logger.dart' as app_logger;
import 'app_pull_to_refresh.dart';
import 'package:flutter_html/flutter_html.dart';

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
      child: _buildHtmlContent(_content!.content),
    );
  }

  /// Build HTML content using flutter_html package for professional rendering
  Widget _buildHtmlContent(String html) {
    if (html.isEmpty) {
      return const SizedBox.shrink();
    }

    return Html(
      data: html,
      style: {
        'body': Style(
          margin: Margins.zero,
          padding: HtmlPaddings.zero,
          fontSize: FontSize(15.0),
          color: darkGrey,
          lineHeight: LineHeight(1.6),
        ),
        'p': Style(
          margin: Margins.only(bottom: 12),
          fontSize: FontSize(15.0),
          color: darkGrey,
          lineHeight: LineHeight(1.6),
        ),
        'h1': Style(
          fontSize: FontSize(24.0),
          fontWeight: FontWeight.bold,
          color: darkGrey,
          margin: Margins.only(bottom: 16, top: 8),
        ),
        'h2': Style(
          fontSize: FontSize(20.0),
          fontWeight: FontWeight.bold,
          color: darkGrey,
          margin: Margins.only(bottom: 14, top: 8),
        ),
        'h3': Style(
          fontSize: FontSize(18.0),
          fontWeight: FontWeight.bold,
          color: darkGrey,
          margin: Margins.only(bottom: 12, top: 8),
        ),
        'h4': Style(
          fontSize: FontSize(16.0),
          fontWeight: FontWeight.bold,
          color: darkGrey,
          margin: Margins.only(bottom: 10, top: 6),
        ),
        'h5': Style(
          fontSize: FontSize(14.0),
          fontWeight: FontWeight.bold,
          color: darkGrey,
          margin: Margins.only(bottom: 8, top: 6),
        ),
        'h6': Style(
          fontSize: FontSize(13.0),
          fontWeight: FontWeight.bold,
          color: darkGrey,
          margin: Margins.only(bottom: 8, top: 6),
        ),
        'strong': Style(
          fontWeight: FontWeight.bold,
          color: darkGrey,
        ),
        'b': Style(
          fontWeight: FontWeight.bold,
          color: darkGrey,
        ),
        'em': Style(
          fontStyle: FontStyle.italic,
          color: darkGrey,
        ),
        'i': Style(
          fontStyle: FontStyle.italic,
          color: darkGrey,
        ),
        'ul': Style(
          margin: Margins.only(bottom: 12, left: 16),
          padding: HtmlPaddings.zero,
        ),
        'ol': Style(
          margin: Margins.only(bottom: 12, left: 16),
          padding: HtmlPaddings.zero,
        ),
        'li': Style(
          margin: Margins.only(bottom: 6),
          fontSize: FontSize(15.0),
          color: darkGrey,
          lineHeight: LineHeight(1.6),
        ),
        'a': Style(
          color: AppTheme.deepBlue,
          textDecoration: TextDecoration.underline,
        ),
        'code': Style(
          backgroundColor: Colors.grey[200],
          padding: HtmlPaddings.all(4),
          fontFamily: 'monospace',
          fontSize: FontSize(13.0),
          color: darkGrey,
        ),
        'pre': Style(
          backgroundColor: Colors.grey[200],
          padding: HtmlPaddings.all(12),
          margin: Margins.only(bottom: 12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        'blockquote': Style(
          border: Border(
            left: BorderSide(
              color: AppTheme.deepBlue,
              width: 4,
            ),
          ),
          padding: HtmlPaddings.only(left: 16, top: 8, bottom: 8, right: 8),
          margin: Margins.only(left: 8, bottom: 12),
          fontStyle: FontStyle.italic,
          color: Colors.grey[700],
          backgroundColor: Colors.grey[50],
        ),
        'table': Style(
          border: Border.all(color: Colors.grey[400]!),
          margin: Margins.only(bottom: 12),
          width: Width(100, Unit.percent),
        ),
        'th': Style(
          backgroundColor: Colors.grey[200],
          padding: HtmlPaddings.all(12),
          fontWeight: FontWeight.bold,
          border: Border.all(color: Colors.grey[400]!),
          textAlign: TextAlign.center,
        ),
        'td': Style(
          padding: HtmlPaddings.all(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        'img': Style(
          width: Width(100, Unit.percent),
          margin: Margins.only(bottom: 12),
        ),
        'hr': Style(
          border: Border(
            top: BorderSide(color: Colors.grey[300]!, width: 1),
          ),
          margin: Margins.symmetric(vertical: 16),
        ),
      },
      extensions: [
        // Add any custom extensions if needed
      ],
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
