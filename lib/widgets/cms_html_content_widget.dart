import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

import '../app_properties.dart';
import '../theme/app_theme.dart';
import '../utils/cms_html_sanitizer.dart';
import '../utils/html_link_launcher.dart';

/// Light (CMS pages) or dark-on-overlay (engagement quick view) HTML rendering.
enum CmsHtmlColorScheme { light, darkOnOverlay }

/// Shared CMS / engagement HTML renderer using [flutter_html] (browser-native img tags).
class CmsHtmlContentWidget extends StatelessWidget {
  final String html;
  final CmsHtmlColorScheme colorScheme;

  const CmsHtmlContentWidget({
    super.key,
    required this.html,
    this.colorScheme = CmsHtmlColorScheme.light,
  });

  @override
  Widget build(BuildContext context) {
    if (html.isEmpty) return const SizedBox.shrink();

    final sanitized = CmsHtmlSanitizer.sanitize(html);
    if (sanitized.isEmpty) return const SizedBox.shrink();

    final isDark = colorScheme == CmsHtmlColorScheme.darkOnOverlay;
    final textColor = isDark ? Colors.white : darkGrey;
    final linkColor = isDark ? Colors.lightBlueAccent : AppTheme.deepBlue;
    final codeBg = isDark ? Colors.white12 : Colors.grey[200]!;
    final blockquoteBg = isDark ? Colors.white10 : Colors.grey[50];
    final blockquoteText = isDark ? Colors.white70 : Colors.grey[700]!;
    final tableBorder = isDark ? Colors.white24 : Colors.grey[400]!;
    final thBg = isDark ? Colors.white12 : Colors.grey[200]!;

    return Html(
      data: sanitized,
      onLinkTap: (url, _, __) => HtmlLinkLauncher.launch(context, url),
      style: {
        'body': Style(
          margin: Margins.zero,
          padding: HtmlPaddings.zero,
          fontSize: FontSize(isDark ? 16.0 : 15.0),
          color: textColor,
          lineHeight: LineHeight(1.6),
        ),
        'p': Style(
          margin: Margins.only(bottom: isDark ? 10 : 12),
          fontSize: FontSize(isDark ? 16.0 : 15.0),
          color: textColor,
          lineHeight: LineHeight(1.6),
        ),
        'h1': Style(
          fontSize: FontSize(isDark ? 22.0 : 24.0),
          fontWeight: FontWeight.bold,
          color: textColor,
          margin: Margins.only(bottom: 14, top: 8),
        ),
        'h2': Style(
          fontSize: FontSize(isDark ? 20.0 : 20.0),
          fontWeight: FontWeight.bold,
          color: textColor,
          margin: Margins.only(bottom: 12, top: 8),
        ),
        'h3': Style(
          fontSize: FontSize(isDark ? 18.0 : 18.0),
          fontWeight: FontWeight.bold,
          color: textColor,
          margin: Margins.only(bottom: 10, top: 6),
        ),
        'strong': Style(fontWeight: FontWeight.bold, color: textColor),
        'b': Style(fontWeight: FontWeight.bold, color: textColor),
        'em': Style(fontStyle: FontStyle.italic, color: textColor),
        'i': Style(fontStyle: FontStyle.italic, color: textColor),
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
          fontSize: FontSize(isDark ? 16.0 : 15.0),
          color: textColor,
          lineHeight: LineHeight(1.6),
        ),
        'a': Style(
          color: linkColor,
          textDecoration: TextDecoration.underline,
        ),
        'code': Style(
          backgroundColor: codeBg,
          padding: HtmlPaddings.all(4),
          fontFamily: 'monospace',
          fontSize: FontSize(13.0),
          color: textColor,
        ),
        'blockquote': Style(
          border: Border(
            left: BorderSide(color: linkColor, width: 4),
          ),
          padding: HtmlPaddings.only(left: 16, top: 8, bottom: 8, right: 8),
          margin: Margins.only(left: 8, bottom: 12),
          fontStyle: FontStyle.italic,
          color: blockquoteText,
          backgroundColor: blockquoteBg,
        ),
        'table': Style(
          border: Border.all(color: tableBorder),
          margin: Margins.only(bottom: 12),
          width: Width(100, Unit.percent),
        ),
        'th': Style(
          backgroundColor: thBg,
          padding: HtmlPaddings.all(10),
          fontWeight: FontWeight.bold,
          border: Border.all(color: tableBorder),
        ),
        'td': Style(
          padding: HtmlPaddings.all(10),
          border: Border.all(color: isDark ? Colors.white12 : Colors.grey[300]!),
        ),
        'img': Style(
          width: Width(100, Unit.percent),
          margin: Margins.only(bottom: 12),
        ),
      },
    );
  }
}
