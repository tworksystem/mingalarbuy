import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

import 'web_html_image_impl_stub.dart';

/// Web: real DOM `<img>` — no XHR/CORS (unlike [flutter_html] which uses [Image.network]).
Widget buildWebNativeImage(WebNativeImageParams params) {
  return _WebDomImage(params: params);
}

class _WebDomImage extends StatefulWidget {
  final WebNativeImageParams params;

  const _WebDomImage({required this.params});

  @override
  State<_WebDomImage> createState() => _WebDomImageState();
}

class _WebDomImageState extends State<_WebDomImage> {
  static int _viewIdSeq = 0;

  late final String _viewType;
  late final html.ImageElement _img;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _viewType = 'twork-dom-img-${_viewIdSeq++}';
    _img = _createImageElement(widget.params);
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int _) => _wrapImage(_img),
    );
    _img.onError.listen((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  html.ImageElement _createImageElement(WebNativeImageParams params) {
    final img = html.ImageElement()
      ..src = params.imageUrl
      ..referrerPolicy = 'no-referrer'
      ..alt = params.alt ?? ''
      ..style.border = '0'
      ..style.margin = '0'
      ..style.padding = '0'
      ..style.display = 'block'
      ..style.objectFit = objectFitCss(params.fit);
    _applySizing(img, params);
    return img;
  }

  void _applySizing(html.ImageElement img, WebNativeImageParams params) {
    if (params.expandToFill) {
      img.style.width = '100%';
      img.style.height = '100%';
      img.style.maxWidth = '100%';
      return;
    }
    if (params.width != null) {
      img.style.width = '${params.width!.toStringAsFixed(1)}px';
    } else {
      img.style.width = 'auto';
      img.style.maxWidth = '100%';
    }
    if (params.height != null) {
      img.style.height = '${params.height!.toStringAsFixed(1)}px';
    } else {
      img.style.height = 'auto';
    }
  }

  html.Element _wrapImage(html.ImageElement img) {
    final wrapper = html.DivElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.overflow = 'hidden'
      ..style.margin = '0'
      ..style.padding = '0'
      ..style.lineHeight = '0';
    wrapper.append(img);
    return wrapper;
  }

  @override
  void didUpdateWidget(covariant _WebDomImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final p = widget.params;
    if (oldWidget.params.imageUrl != p.imageUrl) {
      _failed = false;
      _img.src = p.imageUrl;
    }
    _applySizing(_img, p);
  }

  Widget _error() =>
      widget.params.errorWidget ??
      Container(
        height: widget.params.height,
        width: widget.params.width,
        color: Colors.grey[300],
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image, color: Colors.grey, size: 40),
      );

  Widget _platformView() => HtmlElementView(viewType: _viewType);

  @override
  Widget build(BuildContext context) {
    if (_failed) return _error();

    final p = widget.params;
    Widget child;

    if (p.expandToFill) {
      if (p.height != null || p.width != null) {
        child = SizedBox(
          height: p.height,
          width: p.width,
          child: _platformView(),
        );
      } else {
        child = SizedBox.expand(child: _platformView());
      }
    } else if (p.height != null || p.width != null) {
      child = SizedBox(
        height: p.height,
        width: p.width,
        child: _platformView(),
      );
    } else {
      child = LayoutBuilder(
        builder: (context, constraints) {
          final h = constraints.maxHeight;
          final w = constraints.maxWidth;
          final hasBounds =
              h.isFinite && w.isFinite && h > 0 && w > 0;
          if (hasBounds) {
            return SizedBox(
              height: h,
              width: w,
              child: _platformView(),
            );
          }
          return _platformView();
        },
      );
    }

    if (p.borderRadius != null) {
      child = ClipRRect(borderRadius: p.borderRadius!, child: child);
    }
    return child;
  }
}
