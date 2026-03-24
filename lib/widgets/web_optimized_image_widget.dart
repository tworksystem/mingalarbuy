import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/web_network_service_stub.dart'
    if (dart.library.html) '../services/web_network_service.dart';

/// Web-optimized image widget with CORS and connectivity handling
class WebOptimizedImageWidget extends StatefulWidget {
  final String imageUrl;
  final double? height;
  final double? width;
  final BoxFit fit;
  final bool enableDebug;
  final Widget? placeholder;
  final Widget? errorWidget;

  const WebOptimizedImageWidget({
    Key? key,
    required this.imageUrl,
    this.height,
    this.width,
    this.fit = BoxFit.contain,
    this.enableDebug = false,
    this.placeholder,
    this.errorWidget,
  }) : super(key: key);

  @override
  _WebOptimizedImageWidgetState createState() =>
      _WebOptimizedImageWidgetState();
}

class _WebOptimizedImageWidgetState extends State<WebOptimizedImageWidget> {
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  String? _workingImageUrl;

  @override
  void initState() {
    super.initState();
    _initializeImage();
  }

  @override
  void didUpdateWidget(WebOptimizedImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _initializeImage();
    }
  }

  Future<void> _initializeImage() async {
    if (widget.imageUrl.isEmpty) {
      setState(() {
        _hasError = true;
        _errorMessage = 'Empty image URL';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = null;
    });

    if (widget.enableDebug) {
      print('🌐 WebOptimizedImageWidget: ${widget.imageUrl}');
    }

    // Handle network images
    if (widget.imageUrl.startsWith('http')) {
      try {
        // Test browser connectivity
        final isConnected = await WebNetworkService.testBrowserConnectivity();
        if (!isConnected) {
          setState(() {
            _hasError = true;
            _errorMessage = 'No internet connection';
            _isLoading = false;
          });
          return;
        }

        // Test WooCommerce server access
        final isServerAccessible =
            await WebNetworkService.testWooCommerceWebAccess();
        if (!isServerAccessible) {
          setState(() {
            _hasError = true;
            _errorMessage = 'Server connection failed';
            _isLoading = false;
          });
          return;
        }

        // Find working image URL
        _workingImageUrl =
            await WebNetworkService.getWorkingImageUrl(widget.imageUrl);

        if (widget.enableDebug) {
          print('✅ Working image URL: $_workingImageUrl');
        }
      } catch (e) {
        if (widget.enableDebug) {
          print('❌ Image initialization error: $e');
        }
        setState(() {
          _hasError = true;
          _errorMessage = 'Network test failed: $e';
          _isLoading = false;
        });
        return;
      }
    } else {
      // Asset image
      _workingImageUrl = widget.imageUrl;
    }

    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return widget.placeholder ?? _buildDefaultPlaceholder();
    }

    if (_hasError) {
      return widget.errorWidget ?? _buildErrorWidget();
    }

    return _buildImage();
  }

  Widget _buildImage() {
    if (_workingImageUrl!.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: _workingImageUrl!,
        height: widget.height,
        width: widget.width,
        fit: widget.fit,
        placeholder: (context, url) =>
            widget.placeholder ?? _buildDefaultPlaceholder(),
        errorWidget: (context, url, error) {
          if (widget.enableDebug) {
            print('❌ CachedNetworkImage error: $error');
          }
          return widget.errorWidget ?? _buildErrorWidget();
        },
        httpHeaders: {
          'Accept': 'image/*',
          'User-Agent': WebNetworkService.userAgent,
          'Accept-Encoding': 'gzip, deflate',
          'Connection': 'keep-alive',
          'Cache-Control': 'no-cache',
          'Origin': WebNetworkService.currentOrigin,
        },
        // OPTIMIZED: Use exact size (1.0x) instead of 1.5x to reduce memory usage
        // This significantly reduces memory footprint for cached images
        memCacheHeight: widget.height?.toInt(),
        memCacheWidth: widget.width?.toInt(),
        // OPTIMIZED: Reduced disk cache limits to save storage
        maxHeightDiskCache: 600,
        maxWidthDiskCache: 600,
        fadeInDuration: const Duration(milliseconds: 300),
        fadeOutDuration: const Duration(milliseconds: 300),
      );
    } else {
      return Image.asset(
        _workingImageUrl!,
        height: widget.height,
        width: widget.width,
        fit: widget.fit,
        errorBuilder: (context, error, stackTrace) {
          if (widget.enableDebug) {
            print('❌ Asset image error: $error');
          }
          return widget.errorWidget ?? _buildErrorWidget();
        },
      );
    }
  }

  Widget _buildDefaultPlaceholder() {
    return Container(
      height: widget.height ?? 100,
      width: widget.width ?? 100,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: (widget.height ?? 100) / 4,
              width: (widget.width ?? 100) / 4,
              child: const CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Loading...',
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      height: widget.height ?? 100,
      width: widget.width ?? 100,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[400]!, width: 1),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.wifi_off,
              color: Colors.grey[500],
              size: (widget.height ?? 100) / 3,
            ),
            const SizedBox(height: 4),
            Text(
              _errorMessage ?? 'Error',
              style: TextStyle(
                fontSize: 8,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (widget.enableDebug && widget.imageUrl.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(4),
                child: Text(
                  widget.imageUrl.length > 20
                      ? '${widget.imageUrl.substring(0, 20)}...'
                      : widget.imageUrl,
                  style: TextStyle(
                    fontSize: 6,
                    color: Colors.grey[500],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
