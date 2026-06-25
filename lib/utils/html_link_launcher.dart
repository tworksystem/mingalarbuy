import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_config.dart';
import 'logger.dart';

/// Opens links from CMS / product HTML (`<a href>`) with safe fallbacks.
class HtmlLinkLauncher {
  HtmlLinkLauncher._();

  static DateTime? _lastTapAt;
  static const _debounce = Duration(milliseconds: 500);

  static Future<void> launch(BuildContext context, String? rawUrl) async {
    if (rawUrl == null) return;

    final url = rawUrl.trim();
    if (url.isEmpty || url == '#') return;

    final now = DateTime.now();
    if (_lastTapAt != null && now.difference(_lastTapAt!) < _debounce) {
      return;
    }
    _lastTapAt = now;

    final resolved = _resolveUrl(url);
    final uri = Uri.tryParse(resolved);
    if (uri == null) {
      _showMessage(context, 'Link မမှန်ကန်ပါ', Colors.orange);
      return;
    }

    if (uri.scheme.toLowerCase() == 'javascript') {
      return;
    }

    if (!_isAllowedScheme(uri)) {
      if (context.mounted) {
        _showMessage(context, 'ဤ link ကို ဖွင့်၍ မရပါ', Colors.orange);
      }
      return;
    }

    try {
      // Web: inAppWebView is unsupported — use new tab / platform default first.
      if (kIsWeb) {
        if (await _tryLaunch(uri, LaunchMode.platformDefault)) return;
        if (await _tryLaunch(uri, LaunchMode.externalApplication)) return;
      } else {
        if (await _tryLaunch(uri, LaunchMode.inAppWebView)) return;
        if (await _tryLaunch(uri, LaunchMode.externalApplication)) return;
        if (await _tryLaunch(uri, LaunchMode.platformDefault)) return;
      }

      if (context.mounted) {
        _showMessage(
          context,
          'Link ဖွင့်၍ မရပါ။ အင်တာနက် စစ်ဆေးပြီး ထပ်စမ်းကြည့်ပါ။',
          Colors.orange,
        );
      }
    } catch (e, stackTrace) {
      Logger.warning(
        'HtmlLinkLauncher failed for $resolved: $e',
        tag: 'HtmlLinkLauncher',
        error: e,
        stackTrace: stackTrace,
      );
      if (context.mounted) {
        _showMessage(context, 'Link ဖွင့်၍ မရပါ', Colors.red);
      }
    }
  }

  static const Set<String> _allowedSchemes = {
    'http',
    'https',
    'mailto',
    'tel',
  };

  static bool _isAllowedScheme(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme.isEmpty) return false;
    return _allowedSchemes.contains(scheme);
  }

  static String _resolveUrl(String url) {
    if (url.startsWith('//')) {
      return 'https:$url';
    }
    if (url.startsWith('/')) {
      final base = AppConfig.effectiveBackendUrl;
      final normalizedBase = base.endsWith('/')
          ? base.substring(0, base.length - 1)
          : base;
      return '$normalizedBase$url';
    }
    return url;
  }

  static Future<bool> _tryLaunch(Uri uri, LaunchMode mode) async {
    if (!await canLaunchUrl(uri)) return false;
    return launchUrl(uri, mode: mode);
  }

  static void _showMessage(
    BuildContext context,
    String message,
    Color background,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: background,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
