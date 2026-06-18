import 'package:flutter/material.dart';

import '../utils/web_image_url_utils.dart';
import 'web_html_image_impl_stub.dart';
import 'web_html_image_impl_stub.dart'
    if (dart.library.html) 'web_html_image_impl_web.dart' as web_impl;
///
/// Intended for `kIsWeb` only; mobile callers should use [CachedNetworkImage].
class WebHtmlImageWidget extends StatelessWidget {
  final String imageUrl;
  final double? height;
  final double? width;
  final BoxFit fit;
  final String? alt;
  final bool expandToFill;
  final BorderRadius? borderRadius;
  final Widget? placeholder;
  final Widget? errorWidget;

  const WebHtmlImageWidget({
    super.key,
    required this.imageUrl,
    this.height,
    this.width,
    this.fit = BoxFit.contain,
    this.alt,
    this.expandToFill = false,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
  });

  Widget _defaultError() {
    return Container(
      height: height,
      width: width,
      color: Colors.grey[300],
      alignment: Alignment.center,
      child: const Icon(
        Icons.broken_image,
        color: Colors.grey,
        size: 40,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!WebImageUrlUtils.isSafeNetworkUrl(imageUrl)) {
      return errorWidget ?? _defaultError();
    }

    return web_impl.buildWebNativeImage(
      WebNativeImageParams(
        imageUrl: imageUrl,
        height: height,
        width: width,
        fit: fit,
        alt: alt,
        expandToFill: expandToFill,
        borderRadius: borderRadius,
        errorWidget: errorWidget,
      ),
    );
  }
}
