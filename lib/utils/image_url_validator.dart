import 'package:http/http.dart' as http;

/// Image URL Validator
/// Validates and fixes image URLs for WooCommerce products
class ImageUrlValidator {
  /// Validate and fix image URL
  static String? validateAndFixUrl(String url) {
    if (url.isEmpty) return null;

    try {
      final uri = Uri.parse(url);

      // Check if URL is valid
      if (uri.scheme.isEmpty || uri.host.isEmpty) {
        print('❌ Invalid URL structure: $url');
        return null;
      }

      // Ensure HTTPS for security
      if (uri.scheme == 'http') {
        final httpsUrl = url.replaceFirst('http://', 'https://');
        print('🔄 Converting HTTP to HTTPS: $httpsUrl');
        return httpsUrl;
      }

      // Check if it's a valid image URL
      if (!_isValidImageUrl(url)) {
        print('❌ Not a valid image URL: $url');
        return null;
      }

      return url;
    } catch (e) {
      print('❌ URL parse error: $e');
      return null;
    }
  }

  /// Check if URL looks like an image
  static bool _isValidImageUrl(String url) {
    final imageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'];
    final lowerUrl = url.toLowerCase();

    // Check for image extensions
    for (final ext in imageExtensions) {
      if (lowerUrl.contains(ext)) {
        return true;
      }
    }

    // Check for common image paths
    final imagePaths = [
      '/wp-content/uploads/',
      '/images/',
      '/media/',
      '/uploads/'
    ];
    for (final path in imagePaths) {
      if (lowerUrl.contains(path)) {
        return true;
      }
    }

    return false;
  }

  /// Test if image URL is accessible
  static Future<bool> testImageAccess(String url) async {
    try {
      final response = await http.head(Uri.parse(url)).timeout(
            const Duration(seconds: 10),
          );

      return response.statusCode == 200;
    } catch (e) {
      print('❌ Image access test failed: $e');
      return false;
    }
  }

  /// Get fallback image URL
  static String getFallbackImageUrl() {
    return 'https://via.placeholder.com/300x300/cccccc/666666?text=No+Image';
  }

  /// Process WooCommerce product images
  static List<String> processProductImages(List<dynamic> imageData) {
    final List<String> validUrls = [];

    for (final image in imageData) {
      if (image is Map<String, dynamic>) {
        final src = image['src']?.toString();
        if (src != null && src.isNotEmpty) {
          final validatedUrl = validateAndFixUrl(src);
          if (validatedUrl != null) {
            validUrls.add(validatedUrl);
          }
        }
      }
    }

    return validUrls;
  }
}
