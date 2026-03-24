import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class NetworkImageWidget extends StatelessWidget {
  final String imageUrl;
  final double? height;
  final double? width;
  final BoxFit fit;
  final String fallbackAsset;

  const NetworkImageWidget({
    super.key,
    required this.imageUrl,
    this.height,
    this.width,
    this.fit = BoxFit.contain,
    this.fallbackAsset = 'assets/headphones.png',
  });

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = _normalizeUrl(imageUrl);

    if (resolvedUrl == null || resolvedUrl.isEmpty) {
      return _buildFallbackImage();
    }

    // If it's a local asset, use Image.asset
    if (!_isNetworkUrl(resolvedUrl)) {
      return Image.asset(
        resolvedUrl,
        height: height,
        width: width,
        fit: fit,
        errorBuilder: (context, error, stackTrace) {
          return _buildFallbackImage();
        },
      );
    }

    // On web, prefer Image.network to avoid service worker/cache conflicts
    if (kIsWeb) {
      return Image.network(
        resolvedUrl,
        height: height,
        width: width,
        fit: fit,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _buildLoadingIndicator();
        },
        errorBuilder: (context, error, stackTrace) {
          return _buildFallbackImage();
        },
      );
    }

    // For mobile/desktop, use CachedNetworkImage (falls back to Image.network on error)
    try {
      return CachedNetworkImage(
        imageUrl: resolvedUrl,
        height: height,
        width: width,
        fit: fit,
        placeholder: (context, url) => _buildLoadingIndicator(),
        errorWidget: (context, url, error) => _buildFallbackImage(),
        fadeInDuration: const Duration(milliseconds: 300),
        fadeOutDuration: const Duration(milliseconds: 100),
      );
    } catch (e) {
      return Image.network(
        resolvedUrl,
        height: height,
        width: width,
        fit: fit,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _buildLoadingIndicator();
        },
        errorBuilder: (context, error, stackTrace) {
          return _buildFallbackImage();
        },
      );
    }
  }

  String? _normalizeUrl(String? raw) {
    if (raw == null) return null;
    var normalized = raw.trim();
    if (normalized.isEmpty) return null;

    // Replace common smart quotes with standard quotes
    normalized = normalized
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('‘', "'")
        .replaceAll('’', "'");

    // Unescape common escaped quotes and slashes
    normalized = normalized
        .replaceAll(r'\"', '"')
        .replaceAll(r"\'", "'")
        .replaceAll(r'\/', '/');

    // Strip leading/trailing quotes repeatedly
    while (normalized.length > 1 &&
        (normalized.startsWith('"') || normalized.startsWith("'"))) {
      normalized = normalized.substring(1).trimLeft();
    }
    while (normalized.length > 1 &&
        (normalized.endsWith('"') || normalized.endsWith("'"))) {
      normalized = normalized.substring(0, normalized.length - 1).trimRight();
    }

    // Remove leading/trailing backslashes occasionally introduced with escapes
    normalized = normalized.replaceAll(RegExp(r'^\\+'), '');
    normalized = normalized.replaceAll(RegExp(r'\\+$'), '');

    normalized = normalized.trim();
    return normalized.isEmpty ? null : normalized;
  }

  bool _isNetworkUrl(String url) {
    final lower = url.trim().toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return true;
    }
    if (lower.contains('://')) {
      return true;
    }
    if (lower.startsWith('www.')) {
      return true;
    }

    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  Widget _buildLoadingIndicator() {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackImage() {
    return Image.asset(
      fallbackAsset,
      height: height,
      width: width,
      fit: fit,
      errorBuilder: (context, error, stackTrace) {
        // Ultimate fallback - colored container
        return Container(
          height: height,
          width: width,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.image_not_supported,
            color: Colors.grey,
            size: 40,
          ),
        );
      },
    );
  }
}
