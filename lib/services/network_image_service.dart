import 'dart:io';
import 'package:http/http.dart' as http;

/// Professional Network Image Service with retry mechanism and error handling
class NetworkImageService {
  static const int _maxRetries = 3;
  static const Duration _timeout = Duration(seconds: 30);
  static const Duration _retryDelay = Duration(seconds: 2);

  /// Test network connectivity
  static Future<bool> testConnectivity() async {
    try {
      // Test with a reliable endpoint
      final response = await http.get(
        Uri.parse('https://www.google.com'),
        headers: {
          'User-Agent': 'HomeAid-Flutter-App/1.0',
        },
      ).timeout(_timeout);

      return response.statusCode == 200;
    } catch (e) {
      print('❌ Network connectivity test failed: $e');
      return false;
    }
  }

  /// Test WooCommerce server connectivity
  static Future<bool> testWooCommerceConnectivity() async {
    try {
      final response = await http.get(
        Uri.parse('https://www.homeaid.com.mm'),
        headers: {
          'User-Agent': 'HomeAid-Flutter-App/1.0',
        },
      ).timeout(_timeout);

      final isConnected = response.statusCode == 200;
      print(
          '🔗 WooCommerce server connectivity: ${isConnected ? "✅ Connected" : "❌ Failed"}');
      return isConnected;
    } catch (e) {
      print('❌ WooCommerce connectivity test failed: $e');
      return false;
    }
  }

  /// Test specific image URL with retry mechanism
  static Future<ImageTestResult> testImageUrl(String imageUrl,
      {int maxRetries = _maxRetries}) async {
    print('🖼️ Testing image URL: $imageUrl');

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        print('   Attempt $attempt/$maxRetries');

        final response = await http.head(
          Uri.parse(imageUrl),
          headers: {
            'User-Agent': 'HomeAid-Flutter-App/1.0',
            'Accept': 'image/*',
            'Accept-Encoding': 'gzip, deflate',
            'Connection': 'keep-alive',
          },
        ).timeout(_timeout);

        print('   📊 Status: ${response.statusCode}');
        print('   📊 Content-Type: ${response.headers['content-type']}');
        print('   📊 Content-Length: ${response.headers['content-length']}');

        if (response.statusCode == 200) {
          final contentType = response.headers['content-type'] ?? '';
          if (contentType.startsWith('image/')) {
            print('   ✅ Image URL is valid and accessible');
            return ImageTestResult.success(imageUrl, response.statusCode);
          } else {
            print('   ❌ URL returns non-image content: $contentType');
            return ImageTestResult.error(
                imageUrl, 'Non-image content type: $contentType');
          }
        } else if (response.statusCode == 404) {
          print('   ❌ Image not found (404)');
          return ImageTestResult.error(imageUrl, 'Image not found (404)');
        } else if (response.statusCode == 403) {
          print('   ❌ Access forbidden (403)');
          return ImageTestResult.error(imageUrl, 'Access forbidden (403)');
        } else {
          print('   ❌ HTTP error: ${response.statusCode}');
          if (attempt < maxRetries) {
            print('   ⏳ Retrying in ${_retryDelay.inSeconds} seconds...');
            await Future.delayed(_retryDelay);
            continue;
          }
          return ImageTestResult.error(
              imageUrl, 'HTTP error: ${response.statusCode}');
        }
      } catch (e) {
        print('   ❌ Attempt $attempt failed: $e');

        if (e is SocketException) {
          print('   🔌 Socket exception - network connectivity issue');
        } else if (e is HttpException) {
          print('   🌐 HTTP exception - server communication issue');
        } else if (e.toString().contains('statusCode: 0')) {
          print('   📡 StatusCode 0 - network request failed');
        }

        if (attempt < maxRetries) {
          print('   ⏳ Retrying in ${_retryDelay.inSeconds} seconds...');
          await Future.delayed(_retryDelay);
        } else {
          return ImageTestResult.error(imageUrl, e.toString());
        }
      }
    }

    return ImageTestResult.error(imageUrl, 'All retry attempts failed');
  }

  /// Get optimized image URL for better loading
  static String getOptimizedImageUrl(String originalUrl,
      {int? width, int? height}) {
    if (originalUrl.isEmpty) return originalUrl;

    try {
      final uri = Uri.parse(originalUrl);

      // For WordPress/WooCommerce images, we can add size parameters
      if (uri.host.contains('homeaid.com.mm') &&
          uri.path.contains('wp-content/uploads')) {
        // WordPress image optimization
        final queryParams = <String, String>{};
        if (width != null) queryParams['w'] = width.toString();
        if (height != null) queryParams['h'] = height.toString();

        if (queryParams.isNotEmpty) {
          return uri.replace(queryParameters: queryParams).toString();
        }
      }

      return originalUrl;
    } catch (e) {
      print('❌ Error optimizing image URL: $e');
      return originalUrl;
    }
  }

  /// Get fallback image URL
  static String getFallbackImageUrl({int? width, int? height}) {
    final w = width ?? 300;
    final h = height ?? 300;
    return 'https://via.placeholder.com/${w}x$h/cccccc/666666?text=No+Image';
  }
}

/// Result of image URL testing
class ImageTestResult {
  final bool isSuccess;
  final String url;
  final String? error;
  final int? statusCode;

  ImageTestResult._(this.isSuccess, this.url, this.error, this.statusCode);

  factory ImageTestResult.success(String url, int statusCode) {
    return ImageTestResult._(true, url, null, statusCode);
  }

  factory ImageTestResult.error(String url, String error) {
    return ImageTestResult._(false, url, error, null);
  }

  @override
  String toString() {
    if (isSuccess) {
      return 'ImageTestResult.success($url, statusCode: $statusCode)';
    } else {
      return 'ImageTestResult.error($url, error: $error)';
    }
  }
}
