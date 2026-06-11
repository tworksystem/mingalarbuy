import 'package:flutter/foundation.dart';

/// Web-specific configuration for handling CORS and browser limitations
class WebConfig {
  /// Check if running on web platform
  static bool get isWeb => kIsWeb;

  /// CORS error message for users (Burmese-friendly).
  static const String corsErrorMessage = '''
🚫 CORS — Browser က API ကို တိုက်ရိုက် ခေါ်လို့ မရပါ

localhost မှာ web run လုပ်ရင် mingalarbuy.com API ကို browser security က ပိတ်ထားနိုင်ပါတယ်။

✅ ဖြေရှင်းနည်း (တစ်ခု ရွေးပါ):

1. **Admin — Nginx CORS (အကြံပြု, plugin မလို)**:
   `backend/nginx/twork-web-cors.conf` ကို server မှာ include လုပ်ပြီး nginx reload

2. **Developer — Local proxy** (Admin မပြင်သေးရင်):
   `cd backend && npm run proxy`
   `flutter run -d chrome --dart-define=WEB_DEV_PROXY=http://127.0.0.1:8787`

3. **Production web** — `https://mingalarbuy.com/app/` အောက်မှာ host (same-domain, CORS မလို)

📱 Mobile app မှာ CORS ပြဿနာ မရှိပါ။
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
