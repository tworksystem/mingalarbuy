import 'dart:convert';

import 'package:dio/dio.dart';

import '../api_service.dart';
import '../models/page_content.dart';
import '../utils/app_config.dart';
import '../utils/logger.dart' as app_logger;
import '../utils/network_utils.dart';

// Import AboutUsContent model
// Note: AboutUsContent is defined in page_content.dart

/// Get WooCommerce authentication query parameters
/// Same as other services (point_service, engagement_service, etc.)
Map<String, String> _getWooCommerceAuthQueryParams() {
  return {
    'consumer_key': AppConfig.consumerKey,
    'consumer_secret': AppConfig.consumerSecret,
  };
}

/// Page Content Service for fetching dynamic page content from backend
class PageContentService {
  static String? _lastError;
  static String? get lastError => _lastError;

  /// Get page content by slug
  /// 
  /// Supported slugs:
  /// - 'about-us'
  /// - 'terms-of-use' or 'terms'
  /// - 'privacy-policy' or 'privacy'
  /// - 'license'
  /// - 'seller-policy'
  /// - 'return-policy'
  static Future<PageContent?> getPageContent(String pageSlug) async {
    _lastError = null;

    try {
      final uri = Uri.parse(
        '${AppConfig.backendUrl}/wp-json/twork/v1/page-content/$pageSlug',
      ).replace(queryParameters: _getWooCommerceAuthQueryParams());

      app_logger.Logger.info(
          'Fetching page content for slug: $pageSlug',
          tag: 'PageContentService');
      app_logger.Logger.info('Page content URL: $uri', tag: 'PageContentService');

      final Response<dynamic>? response = await ApiService.executeWithRetry(
        () => ApiService.get(
          uri.path,
          queryParameters: uri.queryParameters,
          skipAuth: true,
          headers: const <String, dynamic>{
            'Content-Type': 'application/json',
          },
        ),
        context: 'getPageContent',
      );

      if (NetworkUtils.isValidDioResponse(response)) {
        try {
          final Map<String, dynamic>? data = ApiService.responseAsJsonMap(response);
          if (data == null) {
            _lastError = 'Invalid page content response';
            return null;
          }

          app_logger.Logger.info(
              'Page content response: success=${data['success']}, hasData=${data['data'] != null}',
              tag: 'PageContentService');

          if (data['success'] == true && data['data'] != null) {
            final pageContent = PageContent.fromJson(data['data'] as Map<String, dynamic>);
            app_logger.Logger.info(
                'Successfully loaded page content: ${pageContent.title}',
                tag: 'PageContentService');
            return pageContent;
          } else {
            _lastError = data['message']?.toString() ?? 'Failed to load page content';
            app_logger.Logger.warning(
                'Page content returned success=false. Response: ${jsonEncode(data)}',
                tag: 'PageContentService');
            return null;
          }
        } catch (e, stackTrace) {
          _lastError =
              'Failed to parse response: ${NetworkUtils.getErrorMessage(e)}';
          final String full = ApiService.responseBodyString(response);
          final responsePreview = full.length > 500
              ? '${full.substring(0, 500)}...'
              : full;
          app_logger.Logger.error(
              'Page content JSON parse error: $_lastError',
              tag: 'PageContentService',
              error: e,
              stackTrace: stackTrace);
          app_logger.Logger.error('Response body preview: $responsePreview',
              tag: 'PageContentService');
          return null;
        }
      } else {
        _lastError = 'Invalid response from server. Status: ${response?.statusCode}';
        final String full = ApiService.responseBodyString(response);
        final responsePreview = full.length > 500
            ? '${full.substring(0, 500)}...'
            : (full.isEmpty ? 'No response body' : full);
        app_logger.Logger.error('Page content failed: $_lastError',
            tag: 'PageContentService');
        app_logger.Logger.error('Response body preview: $responsePreview',
            tag: 'PageContentService');
        return null;
      }
    } catch (e, stackTrace) {
      _lastError = NetworkUtils.getErrorMessage(e);
      app_logger.Logger.error('Page content exception: $_lastError',
          tag: 'PageContentService', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  /// Get FAQ items
  static Future<List<FaqItem>> getFaqItems() async {
    _lastError = null;

    try {
      final uri = Uri.parse(
        '${AppConfig.backendUrl}/wp-json/twork/v1/faq',
      ).replace(queryParameters: _getWooCommerceAuthQueryParams());

      app_logger.Logger.info('Fetching FAQ items', tag: 'PageContentService');
      app_logger.Logger.info('FAQ URL: $uri', tag: 'PageContentService');

      final Response<dynamic>? response = await ApiService.executeWithRetry(
        () => ApiService.get(
          uri.path,
          queryParameters: uri.queryParameters,
          skipAuth: true,
          headers: const <String, dynamic>{
            'Content-Type': 'application/json',
          },
        ),
        context: 'getFaqItems',
      );

      if (NetworkUtils.isValidDioResponse(response)) {
        try {
          final Map<String, dynamic>? data = ApiService.responseAsJsonMap(response);
          if (data == null) {
            _lastError = 'Invalid FAQ response';
            return [];
          }

          app_logger.Logger.info(
              'FAQ response: success=${data['success']}, hasData=${data['data'] != null}',
              tag: 'PageContentService');

          if (data['success'] == true && data['data'] != null) {
            final rawItems = data['data'] as List;
            app_logger.Logger.info('Raw FAQ items count: ${rawItems.length}',
                tag: 'PageContentService');

            final List<FaqItem> items = [];
            for (var i = 0; i < rawItems.length; i++) {
              try {
                final item = FaqItem.fromJson(rawItems[i] as Map<String, dynamic>);
                items.add(item);
                app_logger.Logger.info(
                    'Successfully parsed FAQ item ${i + 1}: ${item.question}',
                    tag: 'PageContentService');
              } catch (e) {
                app_logger.Logger.error(
                    'Failed to parse FAQ item ${i + 1}: $e',
                    tag: 'PageContentService',
                    error: e);
                app_logger.Logger.error('Item data: ${jsonEncode(rawItems[i])}',
                    tag: 'PageContentService');
                // Continue parsing other items even if one fails
              }
            }

            // Sort by order
            items.sort((a, b) => a.order.compareTo(b.order));

            app_logger.Logger.info(
                'Loaded ${items.length} FAQ items',
                tag: 'PageContentService');
            return items;
          } else {
            _lastError = data['message']?.toString() ?? 'Failed to load FAQ items';
            app_logger.Logger.warning(
                'FAQ returned success=false or null data. Response: ${jsonEncode(data)}',
                tag: 'PageContentService');
            return [];
          }
        } catch (e, stackTrace) {
          _lastError =
              'Failed to parse response: ${NetworkUtils.getErrorMessage(e)}';
          final String full = ApiService.responseBodyString(response);
          final responsePreview = full.length > 500
              ? '${full.substring(0, 500)}...'
              : full;
          app_logger.Logger.error(
              'FAQ JSON parse error: $_lastError',
              tag: 'PageContentService',
              error: e,
              stackTrace: stackTrace);
          app_logger.Logger.error('Response body preview: $responsePreview',
              tag: 'PageContentService');
          return [];
        }
      } else {
        _lastError = 'Invalid response from server. Status: ${response?.statusCode}';
        final String full = ApiService.responseBodyString(response);
        final responsePreview = full.length > 500
            ? '${full.substring(0, 500)}...'
            : (full.isEmpty ? 'No response body' : full);
        app_logger.Logger.error('FAQ failed: $_lastError',
            tag: 'PageContentService');
        app_logger.Logger.error('Response body preview: $responsePreview',
            tag: 'PageContentService');
        return [];
      }
    } catch (e, stackTrace) {
      _lastError = NetworkUtils.getErrorMessage(e);
      app_logger.Logger.error('FAQ exception: $_lastError',
          tag: 'PageContentService', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  /// Get all pages for dynamic listing
  static Future<List<PageListItem>> getAllPages() async {
    _lastError = null;

    try {
      final uri = Uri.parse(
        '${AppConfig.backendUrl}/wp-json/twork/v1/page-content',
      ).replace(queryParameters: _getWooCommerceAuthQueryParams());

      app_logger.Logger.info('Fetching all pages', tag: 'PageContentService');
      app_logger.Logger.info('Pages URL: $uri', tag: 'PageContentService');

      final Response<dynamic>? response = await ApiService.executeWithRetry(
        () => ApiService.get(
          uri.path,
          queryParameters: uri.queryParameters,
          skipAuth: true,
          headers: const <String, dynamic>{
            'Content-Type': 'application/json',
          },
        ),
        context: 'getAllPages',
      );

      if (NetworkUtils.isValidDioResponse(response)) {
        try {
          final Map<String, dynamic>? data = ApiService.responseAsJsonMap(response);
          if (data == null) {
            _lastError = 'Invalid pages list response';
            return [];
          }

          app_logger.Logger.info(
              'Pages response: success=${data['success']}, hasData=${data['data'] != null}',
              tag: 'PageContentService');

          if (data['success'] == true && data['data'] != null) {
            final rawPages = data['data'] as List;
            app_logger.Logger.info('Raw pages count: ${rawPages.length}',
                tag: 'PageContentService');

            final List<PageListItem> pages = [];
            for (var i = 0; i < rawPages.length; i++) {
              try {
                final page = PageListItem.fromJson(rawPages[i] as Map<String, dynamic>);
                pages.add(page);
                app_logger.Logger.info(
                    'Successfully parsed page ${i + 1}: ${page.title}',
                    tag: 'PageContentService');
              } catch (e) {
                app_logger.Logger.error(
                    'Failed to parse page ${i + 1}: $e',
                    tag: 'PageContentService',
                    error: e);
                app_logger.Logger.error('Page data: ${jsonEncode(rawPages[i])}',
                    tag: 'PageContentService');
                // Continue parsing other pages even if one fails
              }
            }

            // Sort by display_order, then by title
            pages.sort((a, b) {
              final orderCompare = a.displayOrder.compareTo(b.displayOrder);
              if (orderCompare != 0) return orderCompare;
              return a.title.compareTo(b.title);
            });

            app_logger.Logger.info(
                'Loaded ${pages.length} pages',
                tag: 'PageContentService');
            return pages;
          } else {
            _lastError = data['message']?.toString() ?? 'Failed to load pages';
            app_logger.Logger.warning(
                'Pages returned success=false or null data. Response: ${jsonEncode(data)}',
                tag: 'PageContentService');
            return [];
          }
        } catch (e, stackTrace) {
          _lastError =
              'Failed to parse response: ${NetworkUtils.getErrorMessage(e)}';
          final String full = ApiService.responseBodyString(response);
          final responsePreview = full.length > 500
              ? '${full.substring(0, 500)}...'
              : full;
          app_logger.Logger.error(
              'Pages JSON parse error: $_lastError',
              tag: 'PageContentService',
              error: e,
              stackTrace: stackTrace);
          app_logger.Logger.error('Response body preview: $responsePreview',
              tag: 'PageContentService');
          return [];
        }
      } else {
        _lastError = 'Invalid response from server. Status: ${response?.statusCode}';
        final String full = ApiService.responseBodyString(response);
        final responsePreview = full.length > 500
            ? '${full.substring(0, 500)}...'
            : (full.isEmpty ? 'No response body' : full);
        app_logger.Logger.error('Pages failed: $_lastError',
            tag: 'PageContentService');
        app_logger.Logger.error('Response body preview: $responsePreview',
            tag: 'PageContentService');
        return [];
      }
    } catch (e, stackTrace) {
      _lastError = NetworkUtils.getErrorMessage(e);
      app_logger.Logger.error('Pages exception: $_lastError',
          tag: 'PageContentService', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  /// Get About Us content
  static Future<AboutUsContent?> getAboutUsContent() async {
    _lastError = null;

    try {
      final uri = Uri.parse(
        '${AppConfig.backendUrl}/wp-json/twork/v1/about-us',
      ).replace(queryParameters: _getWooCommerceAuthQueryParams());

      app_logger.Logger.info('Fetching About Us content', tag: 'PageContentService');
      app_logger.Logger.info('About Us URL: $uri', tag: 'PageContentService');

      final Response<dynamic>? response = await ApiService.executeWithRetry(
        () => ApiService.get(
          uri.path,
          queryParameters: uri.queryParameters,
          skipAuth: true,
          headers: const <String, dynamic>{
            'Content-Type': 'application/json',
          },
        ),
        context: 'getAboutUsContent',
      );

      if (NetworkUtils.isValidDioResponse(response)) {
        try {
          final Map<String, dynamic>? data = ApiService.responseAsJsonMap(response);
          if (data == null) {
            _lastError = 'Invalid About Us response';
            return null;
          }

          app_logger.Logger.info(
              'About Us response: success=${data['success']}, hasData=${data['data'] != null}',
              tag: 'PageContentService');

          if (data['success'] == true && data['data'] != null) {
            final aboutUsContent = AboutUsContent.fromJson(data['data'] as Map<String, dynamic>);
            app_logger.Logger.info(
                'Successfully loaded About Us content: ${aboutUsContent.companyName}',
                tag: 'PageContentService');
            return aboutUsContent;
          } else {
            _lastError = data['message']?.toString() ?? 'Failed to load About Us content';
            app_logger.Logger.warning(
                'About Us returned success=false. Response: ${jsonEncode(data)}',
                tag: 'PageContentService');
            return null;
          }
        } catch (e, stackTrace) {
          _lastError =
              'Failed to parse response: ${NetworkUtils.getErrorMessage(e)}';
          final String full = ApiService.responseBodyString(response);
          final responsePreview = full.length > 500
              ? '${full.substring(0, 500)}...'
              : full;
          app_logger.Logger.error(
              'About Us JSON parse error: $_lastError',
              tag: 'PageContentService',
              error: e,
              stackTrace: stackTrace);
          app_logger.Logger.error('Response body preview: $responsePreview',
              tag: 'PageContentService');
          return null;
        }
      } else {
        _lastError = 'Invalid response from server. Status: ${response?.statusCode}';
        final String full = ApiService.responseBodyString(response);
        final responsePreview = full.length > 500
            ? '${full.substring(0, 500)}...'
            : (full.isEmpty ? 'No response body' : full);
        app_logger.Logger.error('About Us failed: $_lastError',
            tag: 'PageContentService');
        app_logger.Logger.error('Response body preview: $responsePreview',
            tag: 'PageContentService');
        return null;
      }
    } catch (e, stackTrace) {
      _lastError = NetworkUtils.getErrorMessage(e);
      app_logger.Logger.error('About Us exception: $_lastError',
          tag: 'PageContentService', error: e, stackTrace: stackTrace);
      return null;
    }
  }
}

