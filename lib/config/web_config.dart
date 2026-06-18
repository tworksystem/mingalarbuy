import 'package:flutter/foundation.dart';

import '../utils/app_config.dart';

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
   `./scripts/run-web-dev.sh`
   (သို့) `cd backend && npm run proxy` + `flutter run -d chrome --dart-define=WEB_DEV_PROXY=http://127.0.0.1:8787`

3. **Production web (path)** — `https://mingalarbuy.com/app/` (same-domain, CORS မလို)
4. **Production web (subdomain)** — `https://app.mingalarbuy.com/` (`./scripts/build-web-subdomain.sh`, CORS plugin လို)

📱 Mobile app မှာ CORS ပြဿနာ မရှိပါ။
''';

  /// Alternative API endpoints for web (if available)
  static const Map<String, String> alternativeEndpoints = {
    'proxy': 'https://your-proxy-server.com/api/woocommerce',
    'cors_proxy': 'https://cors-anywhere.herokuapp.com/',
  };

  /// Web UI on a different origin than [AppConfig.backendUrl] (needs server CORS).
  static bool get isCrossOriginWebApi =>
      isWeb &&
      !AppConfig.usesLocalDevProxy &&
      (AppConfig.isLocalWebDevPage || AppConfig.isAppWebSubdomainPage);

  /// Localhost dev without [WEB_DEV_PROXY] — browser blocks cross-origin API calls.
  static bool get isLikelyCorsBlock => isCrossOriginWebApi;

  /// Short message for login/snackbar when API is unreachable on local web dev.
  static String get webConnectionErrorMessage {
    if (AppConfig.isLocalWebDevPage && !AppConfig.usesLocalDevProxy) {
      return 'Browser က localhost မှ API ကို တိုက်ရိုက် မခေါ်နိုင်ပါ (CORS)။ '
          'Terminal မှာ ./scripts/run-web-dev.sh ဖြင့် run ပါ။';
    }
    if (AppConfig.isAppWebSubdomainPage) {
      return 'Server ဆီ API မရောက်ပါ (CORS/WAF)။ App rebuild redeploy လုပ်ပါ — '
          'twork-cors plugin မလို (Idempotency-Key header ဖယ်ပြီး)။';
    }
    return 'Request timeout or server unreachable. Please try again.';
  }

  /// Check if we should show CORS warning
  static bool shouldShowCorsWarning(String error) {
    return isWeb &&
        (isLikelyCorsBlock ||
            error.contains('Failed to fetch') ||
            error.contains('XMLHttpRequest') ||
            error.contains('CORS') ||
            error.contains('ClientException'));
  }
}
