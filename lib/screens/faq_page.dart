import 'package:ecommerce_int2/app_properties.dart';
import 'package:ecommerce_int2/widgets/app_pull_to_refresh.dart';
import 'package:ecommerce_int2/services/page_content_service.dart';
import 'package:ecommerce_int2/models/page_content.dart';
import 'package:ecommerce_int2/utils/logger.dart' as app_logger;
import 'package:ecommerce_int2/utils/cms_html_sanitizer.dart';
import 'package:ecommerce_int2/widgets/cms_html_content_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
        CmsHtmlSanitizer.toPlainText(item.question),
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
          child: CmsHtmlContentWidget(html: item.answer),
        ),
      ],
    );
  }
}
