import 'package:flutter/material.dart';

import 'network_image_widget.dart';
import '../services/network_image_service.dart';

/// Enhanced Product Image Widget with comprehensive error handling and debugging
/// Handles both network and asset images with detailed error reporting
class ProductImageWidget extends StatelessWidget {
  final String imageUrl;
  final double? height;
  final double? width;
  final BoxFit fit;
  final bool debugMode;

  const ProductImageWidget({
    Key? key,
    required this.imageUrl,
    this.height,
    this.width,
    this.fit = BoxFit.contain,
    this.debugMode = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Debug logging
    if (debugMode) {
      print('🖼️ ProductImageWidget: Loading image: $imageUrl');
    }

    // Handle empty or invalid URLs
    if (imageUrl.isEmpty) {
      if (debugMode) print('❌ Empty image URL');
      return _buildPlaceholder('Empty URL');
    }

    // Handle network images
    if (imageUrl.startsWith('http')) {
      return _buildNetworkImage(context);
    } else {
      // Handle asset images
      return _buildAssetImage(context);
    }
  }

  Widget _buildNetworkImage(BuildContext context) {
    final optimizedUrl = NetworkImageService.getOptimizedImageUrl(
      imageUrl,
      width: width?.toInt(),
      height: height?.toInt(),
    );

    if (debugMode) {
      print('🖼️ Original URL: $imageUrl');
      print('🖼️ Optimized URL: $optimizedUrl');
    }

    return NetworkImageWidget(
      imageUrl: optimizedUrl,
      height: height,
      width: width,
      fit: fit,
      expandToFill: height == null && width == null,
      fallbackAsset: 'assets/headphones.png',
    );
  }

  /// Test image URL when error occurs
  void _testImageUrl(String url) async {
    try {
      final result = await NetworkImageService.testImageUrl(url);
      if (debugMode) {
        print('🔍 Image test result: $result');
      }
    } catch (e) {
      if (debugMode) {
        print('❌ Image test error: $e');
      }
    }
  }

  Widget _buildAssetImage(BuildContext context) {
    return Image.asset(
      imageUrl,
      height: height,
      width: width,
      fit: fit,
      errorBuilder: (context, error, stackTrace) {
        if (debugMode) {
          print('❌ Asset image error: $imageUrl');
          print('❌ Error: $error');
        }
        return _buildErrorPlaceholder('Asset Error');
      },
    );
  }

  Widget _buildLoadingPlaceholder() {
    return Container(
      height: height ?? 100,
      width: width ?? 100,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: (height ?? 100) / 4,
              width: (width ?? 100) / 4,
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

  Widget _buildErrorPlaceholder(String errorType) {
    return Container(
      height: height ?? 100,
      width: width ?? 100,
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
              size: (height ?? 100) / 3,
            ),
            const SizedBox(height: 4),
            Text(
              errorType,
              style: TextStyle(fontSize: 8, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            if (debugMode && imageUrl.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(4),
                child: Text(
                  imageUrl.length > 30
                      ? '${imageUrl.substring(0, 30)}...'
                      : imageUrl,
                  style: TextStyle(fontSize: 6, color: Colors.grey[500]),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(String reason) {
    return Container(
      height: height ?? 100,
      width: width ?? 100,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.image_not_supported,
              color: Colors.grey[500],
              size: (height ?? 100) / 3,
            ),
            const SizedBox(height: 4),
            Text(
              reason,
              style: TextStyle(fontSize: 8, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
