import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

import '../utils/web_image_url_utils.dart';

class WebNativeImageParams {
  final String imageUrl;
  final double? height;
  final double? width;
  final BoxFit fit;
  final String? alt;
  final bool expandToFill;
  final BorderRadius? borderRadius;
  final Widget? errorWidget;

  const WebNativeImageParams({
    required this.imageUrl,
    this.height,
    this.width,
    this.fit = BoxFit.contain,
    this.alt,
    this.expandToFill = false,
    this.borderRadius,
    this.errorWidget,
  });
}

/// Non-web fallback (should not be called when [kIsWeb] guards are correct).
Widget buildWebNativeImage(WebNativeImageParams params) {
  return const SizedBox.shrink();
}

String objectFitCss(BoxFit fit) {
  switch (fit) {
    case BoxFit.cover:
      return 'cover';
    case BoxFit.fill:
      return 'fill';
    case BoxFit.fitWidth:
    case BoxFit.fitHeight:
    case BoxFit.scaleDown:
      return 'scale-down';
    case BoxFit.none:
      return 'none';
    case BoxFit.contain:
      return 'contain';
  }
}

String _buildImgHtml(
  WebNativeImageParams params, {
  required bool fillParent,
}) {
  final safeUrl = WebImageUrlUtils.escapeHtmlAttribute(params.imageUrl.trim());
  final altText = params.alt != null && params.alt!.isNotEmpty
      ? WebImageUrlUtils.escapeHtmlAttribute(params.alt!)
      : '';
  final objectFit = objectFitCss(params.fit);

  if (fillParent) {
    return '<body style="margin:0;padding:0;width:100%;height:100%;overflow:hidden">'
        '<img src="$safeUrl" alt="$altText" referrerpolicy="no-referrer" '
        'loading="lazy" decoding="async" '
        'style="width:100%;height:100%;object-fit:$objectFit;display:block" />'
        '</body>';
  }

  return '<img src="$safeUrl" alt="$altText" referrerpolicy="no-referrer" '
      'loading="lazy" decoding="async" '
      'style="object-fit:$objectFit;display:block;max-width:100%;'
      '${params.height != null ? 'height:${params.height!.toStringAsFixed(1)}px;' : ''}'
      '${params.width != null ? 'width:${params.width!.toStringAsFixed(1)}px;' : ''}" />';
}

Widget _wrapHtmlImage(
  WebNativeImageParams params, {
  required bool fillParent,
  double? boxHeight,
  double? boxWidth,
}) {
  Widget child = Html(
    data: _buildImgHtml(params, fillParent: fillParent),
    style: {
      'body': Style(
        margin: Margins.zero,
        padding: HtmlPaddings.zero,
        width: fillParent ? Width(100, Unit.percent) : null,
        height: fillParent ? Height(100, Unit.percent) : null,
      ),
      'img': Style(
        display: Display.block,
        margin: Margins.zero,
        padding: HtmlPaddings.zero,
      ),
    },
  );

  if (fillParent) {
    if (boxHeight != null || boxWidth != null) {
      child = SizedBox(height: boxHeight, width: boxWidth, child: child);
    } else {
      child = SizedBox.expand(child: child);
    }
  } else if (boxHeight != null || boxWidth != null) {
    child = SizedBox(height: boxHeight, width: boxWidth, child: child);
  }

  if (params.borderRadius != null) {
    child = ClipRRect(borderRadius: params.borderRadius!, child: child);
  }

  return child;
}

/// Non-web / tests only. On web, [web_html_image_impl_web.dart] uses DOM `<img>`.
/// Do not use [flutter_html] here — its img builtin calls [Image.network] (CORS on cross-origin).
Widget buildFlutterHtmlImage(WebNativeImageParams params) {
  if (params.expandToFill) {
    return _wrapHtmlImage(params, fillParent: true);
  }

  if (params.height != null || params.width != null) {
    return _wrapHtmlImage(
      params,
      fillParent: false,
      boxHeight: params.height,
      boxWidth: params.width,
    );
  }

  // No explicit size: inherit parent constraints (fixes 0×0 invisible images).
  return LayoutBuilder(
    builder: (context, constraints) {
      final h = constraints.maxHeight;
      final w = constraints.maxWidth;
      final hasBounds =
          h.isFinite && w.isFinite && h > 0 && w > 0;

      if (hasBounds) {
        return _wrapHtmlImage(
          params,
          fillParent: true,
          boxHeight: h,
          boxWidth: w,
        );
      }

      return _wrapHtmlImage(params, fillParent: false);
    },
  );
}
