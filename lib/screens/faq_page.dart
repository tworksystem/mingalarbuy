import 'package:ecommerce_int2/app_properties.dart';
import 'package:ecommerce_int2/widgets/app_pull_to_refresh.dart';
import 'package:ecommerce_int2/services/page_content_service.dart';
import 'package:ecommerce_int2/models/page_content.dart';
import 'package:ecommerce_int2/utils/logger.dart' as app_logger;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';

class FaqPage extends StatefulWidget {
  const FaqPage({super.key});

  @override
  _FaqPageState createState() => _FaqPageState();
}

class _FaqPageState extends State<FaqPage> {
  List<FaqItem> _faqItems = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFaq();
  }

  Future<void> _loadFaq() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final items = await PageContentService.getFaqItems();
      
      if (mounted) {
        setState(() {
          _faqItems = items;
          _isLoading = false;
          if (items.isEmpty && PageContentService.lastError != null) {
            _error = PageContentService.lastError;
          }
        });
      }
    } catch (e) {
      app_logger.Logger.error('Error loading FAQ: $e',
          tag: 'FaqPage', error: e);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load FAQ: ${e.toString()}';
        });
      }
    }
  }

  /// Strip HTML tags to get plain text (for question title)
  String _stripHtmlTags(String html) {
    if (html.isEmpty) return '';
    return html
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
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
        elevation: 0, 
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      body: SafeArea(
        bottom: true,
        child: AppPullToRefresh(
          onRefresh: _loadFaq,
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.grey[600]!),
              ),
              const SizedBox(height: 16),
              Text(
                'Loading FAQ...',
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

    if (_error != null && _faqItems.isEmpty) {
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
                'Failed to load FAQ',
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
                onPressed: _loadFaq,
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

    if (_faqItems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.help_outline,
                size: 48,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'No FAQ Available',
                style: TextStyle(
                  color: Colors.grey[700],
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'FAQ items are being prepared. Please check back later.',
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

    // ORIGINAL DESIGN: Simple list with ExpansionTile (keeping original design)
    return Padding(
      padding: const EdgeInsets.only(top: 24.0),
      child: ListView(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 24.0, right: 24.0, bottom: 16.0),
            child: Text(
              'FAQ',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 18.0,
              ),
            ),
          ),
          ..._faqItems.map((item) => _buildFaqItem(item)).toList(),
        ],
      ),
    );
  }

  Widget _buildFaqItem(FaqItem item) {
    return ExpansionTile(
      title: Text(
        _stripHtmlTags(item.question),
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.grey[600],
        ),
      ),
      children: [
        Container(
          padding: const EdgeInsets.all(16.0),
          color: const Color(0xffFAF1E2),
          width: double.infinity,
          child: _buildHtmlContent(item.answer),
        ),
      ],
    );
  }

  /// Build HTML content using flutter_html package for professional rendering
  Widget _buildHtmlContent(String htmlContent) {
    if (htmlContent.isEmpty) {
      return const SizedBox.shrink();
    }

    return Html(
      data: htmlContent,
      style: {
        'body': Style(
          margin: Margins.zero,
          padding: HtmlPaddings.zero,
          fontSize: FontSize(12.0),
          color: Colors.grey[700],
          lineHeight: LineHeight(1.6),
        ),
        'p': Style(
          margin: Margins.only(bottom: 8),
          fontSize: FontSize(12.0),
          color: Colors.grey[700],
          lineHeight: LineHeight(1.6),
        ),
        'h1': Style(
          fontSize: FontSize(18.0),
          fontWeight: FontWeight.bold,
          color: Colors.black87,
          margin: Margins.only(bottom: 12, top: 8),
        ),
        'h2': Style(
          fontSize: FontSize(16.0),
          fontWeight: FontWeight.bold,
          color: Colors.black87,
          margin: Margins.only(bottom: 10, top: 8),
        ),
        'h3': Style(
          fontSize: FontSize(14.0),
          fontWeight: FontWeight.bold,
          color: Colors.black87,
          margin: Margins.only(bottom: 8, top: 6),
        ),
        'strong': Style(
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
        'b': Style(
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
        'em': Style(
          fontStyle: FontStyle.italic,
        ),
        'i': Style(
          fontStyle: FontStyle.italic,
        ),
        'ul': Style(
          margin: Margins.only(bottom: 8, left: 16),
          padding: HtmlPaddings.zero,
        ),
        'ol': Style(
          margin: Margins.only(bottom: 8, left: 16),
          padding: HtmlPaddings.zero,
        ),
        'li': Style(
          margin: Margins.only(bottom: 4),
          fontSize: FontSize(12.0),
          color: Colors.grey[700],
          lineHeight: LineHeight(1.6),
        ),
        'a': Style(
          color: Colors.blue[700],
          textDecoration: TextDecoration.underline,
        ),
        'code': Style(
          backgroundColor: Colors.grey[200],
          padding: HtmlPaddings.all(4),
          fontFamily: 'monospace',
          fontSize: FontSize(11.0),
        ),
        'pre': Style(
          backgroundColor: Colors.grey[200],
          padding: HtmlPaddings.all(8),
          margin: Margins.only(bottom: 8),
        ),
        'blockquote': Style(
          border: Border(
            left: BorderSide(
              color: Colors.grey[400]!,
              width: 4,
            ),
          ),
          padding: HtmlPaddings.only(left: 12),
          margin: Margins.only(left: 8, bottom: 8),
          fontStyle: FontStyle.italic,
          color: Colors.grey[600],
        ),
        'table': Style(
          border: Border.all(color: Colors.grey[400]!),
          margin: Margins.only(bottom: 8),
        ),
        'th': Style(
          backgroundColor: Colors.grey[200],
          padding: HtmlPaddings.all(8),
          fontWeight: FontWeight.bold,
        ),
        'td': Style(
          padding: HtmlPaddings.all(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
      },
      extensions: [
        // Add any custom extensions if needed
      ],
    );
  }
}
