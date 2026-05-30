/// Sanitizes CMS HTML before [flutter_html] render (whitelist-style stripping).
/// Does not reduce content to plain text — preserves allowed tags for legal/about pages.
class CmsHtmlSanitizer {
  CmsHtmlSanitizer._();

  static final RegExp _blockedTags = RegExp(
    r'<\s*/?\s*(script|iframe|object|embed|form|input|button|link|meta|base|style)\b[^>]*>',
    caseSensitive: false,
  );

  static final RegExp _eventHandlers = RegExp(
    r'\s+on[a-z]+\s*=\s*("[^"]*"|\S+)',
    caseSensitive: false,
  );

  static final RegExp _javascriptHref = RegExp(
    r'(href|src|xlink:href)\s*=\s*"?javascript:',
    caseSensitive: false,
  );

  static final RegExp _dataUriScript = RegExp(
    r'src\s*=\s*"?data:text/html',
    caseSensitive: false,
  );

  /// Returns sanitized HTML safe for in-app CMS display.
  static String sanitize(String raw) {
    if (raw.isEmpty) return raw;

    var out = raw.replaceAll(_blockedTags, '');
    out = out.replaceAll(_eventHandlers, '');
    out = out.replaceAll(_javascriptHref, r'$1="#"');
    out = out.replaceAll(_dataUriScript, 'src=""');
    return out.trim();
  }
}
