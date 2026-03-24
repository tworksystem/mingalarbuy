import 'package:flutter/foundation.dart';

/// Web-specific configuration for handling CORS and browser limitations
class WebConfig {
  /// Check if running on web platform
  static bool get isWeb => kIsWeb;

  /// CORS error message for users
  static const String corsErrorMessage = '''
🚫 CORS Error - Cross-Origin Request Blocked

The WooCommerce API server (tworksystem.com) does not allow requests from web browsers due to CORS (Cross-Origin Resource Sharing) restrictions.

🔧 Solutions:

1. **Use Mobile App** (Recommended)
   - Run the app on Android or iOS
   - Mobile apps don't have CORS restrictions
   - Full functionality available

2. **Server Configuration** (For developers)
   - Contact the website administrator
   - Request CORS headers to be added:
     - Access-Control-Allow-Origin: *
     - Access-Control-Allow-Methods: GET, POST, OPTIONS
     - Access-Control-Allow-Headers: Content-Type, Authorization

3. **Proxy Server** (Advanced)
   - Set up a proxy server that adds CORS headers
   - Route API calls through the proxy

4. **Browser Extension** (Development only)
   - Use CORS browser extension for testing
   - Not recommended for production

📱 For the best experience, please use the mobile version of this app.
''';

  /// Alternative API endpoints for web (if available)
  static const Map<String, String> alternativeEndpoints = {
    'proxy': 'https://your-proxy-server.com/api/woocommerce',
    'cors_proxy': 'https://cors-anywhere.herokuapp.com/',
  };

  /// Check if we should show CORS warning
  static bool shouldShowCorsWarning(String error) {
    return isWeb &&
        (error.contains('Failed to fetch') ||
            error.contains('CORS') ||
            error.contains('ClientException'));
  }
}
