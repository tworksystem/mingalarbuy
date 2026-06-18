/// URL validation and HTML attribute escaping for web-native image rendering.
class WebImageUrlUtils {
  WebImageUrlUtils._();

  /// Returns true when [raw] is a safe http(s) URL for `<img src>`.
  static bool isSafeNetworkUrl(String? raw) {
    if (raw == null) return false;
    var normalized = raw.trim();
    if (normalized.isEmpty) return false;

    normalized = normalized
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('‘', "'")
        .replaceAll('’', "'")
        .replaceAll(r'\"', '"')
        .replaceAll(r"\'", "'")
        .replaceAll(r'\/', '/');

    while (normalized.length > 1 &&
        (normalized.startsWith('"') || normalized.startsWith("'"))) {
      normalized = normalized.substring(1).trimLeft();
    }
    while (normalized.length > 1 &&
        (normalized.endsWith('"') || normalized.endsWith("'"))) {
      normalized = normalized.substring(0, normalized.length - 1).trimRight();
    }

    final lower = normalized.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return false;
    }
    if (lower.contains('javascript:') || lower.startsWith('data:')) {
      return false;
    }

    final uri = Uri.tryParse(normalized);
    return uri != null && uri.hasAuthority && uri.host.isNotEmpty;
  }

  /// Escapes a value for use inside a double-quoted HTML attribute.
  static String escapeHtmlAttribute(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }
}
