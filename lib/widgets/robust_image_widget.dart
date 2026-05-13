import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/network_image_service.dart';
import '../utils/app_config.dart';

/// Robust Image Widget with comprehensive error handling and network optimization
class RobustImageWidget extends StatefulWidget {
  final String imageUrl;
  final double? height;
  final double? width;
  final BoxFit fit;
  final bool enableDebug;
  final Widget? placeholder;
  final Widget? errorWidget;

  const RobustImageWidget({
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
  _RobustImageWidgetState createState() => _RobustImageWidgetState();
}

class _RobustImageWidgetState extends State<RobustImageWidget> {
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  String? _optimizedUrl;

  // OPTIMIZED: Cache connectivity state to avoid repeated checks
  static bool? _cachedConnectivityState;
  static DateTime? _connectivityCheckTime;
  static const Duration _connectivityCacheDuration = Duration(minutes: 1);

  @override
  void initState() {
    super.initState();
    _initializeImage();
  }

  @override
  void didUpdateWidget(RobustImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _initializeImage();
    }
  }

  Future<void> _initializeImage() async {
    if (widget.imageUrl.isEmpty) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Empty image URL';
          _isLoading = false;
        });
      }
      return;
    }

    // OPTIMIZED: Single setState call instead of multiple
    if (mounted) {
      setState(() {
        _isLoading = true;
        _hasError = false;
        _errorMessage = null;
      });
    }

    // Get optimized URL
    _optimizedUrl = NetworkImageService.getOptimizedImageUrl(
      widget.imageUrl,
      width: widget.width?.toInt(),
      height: widget.height?.toInt(),
    );

    if (widget.enableDebug) {
      print('🖼️ RobustImageWidget: ${widget.imageUrl}');
      print('🖼️ Optimized URL: $_optimizedUrl');
    }

    // OPTIMIZED: Skip expensive connectivity checks - let CachedNetworkImage handle errors
    // Only do connectivity check if cache is expired
    if (widget.imageUrl.startsWith('http')) {
      final now = DateTime.now();
      final shouldCheckConnectivity =
          _connectivityCheckTime == null ||
          now.difference(_connectivityCheckTime!) > _connectivityCacheDuration;

      if (shouldCheckConnectivity) {
        try {
          _cachedConnectivityState =
              await NetworkImageService.testConnectivity();
          _connectivityCheckTime = now;
        } catch (e) {
          // If connectivity check fails, assume connected and let image loading handle it
          _cachedConnectivityState = true;
        }
      }

      // Only show error if we know for sure we're offline
      if (_cachedConnectivityState == false) {
        if (mounted) {
          setState(() {
            _hasError = true;
            _errorMessage = 'No internet connection';
            _isLoading = false;
          });
        }
        return;
      }

      // Skip expensive image URL test - let CachedNetworkImage handle it
      // This reduces CPU usage significantly
    }

    // OPTIMIZED: Single setState call at the end
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
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
    if (widget.imageUrl.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: _optimizedUrl ?? widget.imageUrl,
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
        // OLD CODE:
        // httpHeaders: const {
        //   'User-Agent': 'HomeAid-Flutter-App/1.0',
        //   'Accept': 'image/*',
        //   'Accept-Encoding': 'gzip, deflate',
        //   'Connection': 'keep-alive',
        // },
        httpHeaders: const <String, String>{
          'User-Agent': AppConfig.defaultUserAgent,
          'Accept': 'image/*',
          'Accept-Encoding': 'gzip, deflate',
          'Connection': 'keep-alive',
        },
        // OPTIMIZED: Use exact size (1.0x) instead of 1.5x to reduce memory usage
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
        widget.imageUrl,
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
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
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
              Icons.image_not_supported,
              color: Colors.grey[500],
              size: (widget.height ?? 100) / 3,
            ),
            const SizedBox(height: 4),
            Text(
              _errorMessage ?? 'Error',
              style: TextStyle(fontSize: 8, color: Colors.grey[600]),
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
                  style: TextStyle(fontSize: 6, color: Colors.grey[500]),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
