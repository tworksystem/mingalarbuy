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

  static final RegExp _htmlTags = RegExp(r'<[^>]*>');

  /// Returns sanitized HTML safe for in-app CMS display.
  static String sanitize(String raw) {
    if (raw.isEmpty) return raw;

    var out = raw.replaceAll(_blockedTags, '');
    out = out.replaceAll(_eventHandlers, '');
    out = out.replaceAll(_javascriptHref, r'$1="#"');
    out = out.replaceAll(_dataUriScript, 'src=""');
    return injectImgReferrerPolicy(out.trim());
  }

  /// Plain text for search, previews, and accordion titles.
  static String toPlainText(String html) {
    if (html.isEmpty) return '';

    return html
        .replaceAll(_htmlTags, ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Adds hotlink-safe referrer policy to CMS `<img>` tags (web browser native load).
  static String injectImgReferrerPolicy(String html) {
    if (html.isEmpty) return html;
    return html.replaceAllMapped(
      RegExp(
        r'<\s*img((?![^>]*\breferrerpolicy\b)[^>]*)>',
        caseSensitive: false,
      ),
      (match) => '<img referrerpolicy="no-referrer"${match.group(1)!}>',
    );
  }
}
