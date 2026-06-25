import 'package:dio/dio.dart';

import '../api_service.dart';
import '../models/forgot_password_settings.dart';
import '../models/register_request.dart';
import '../utils/app_config.dart';
import '../utils/logger.dart';
import '../utils/network_utils.dart';

/// Fetches forgot-password screen copy and customer-service button config from backend.
class ForgotPasswordSettingsService {
  static ForgotPasswordSettings? _cachedSettings;
  static DateTime? _cacheTimestamp;
  static const Duration _cacheDuration = Duration(minutes: 5);

  static const String _defaultHintText =
      'သင့် အသုံးပြုသူအမည် + @${RegisterRequest.autoEmailDomain} ပုံစံဖြင့် ထည့်ပါ။';

  static const String _defaultCsLabel = 'Customer Service ဆက်သွယ်ရန်';

  static ForgotPasswordSettings get _fallbackSettings => ForgotPasswordSettings(
        emailDomain: RegisterRequest.autoEmailDomain,
        hintText: '$_defaultHintText ဥပမာ — myname@${RegisterRequest.autoEmailDomain}',
        customerService: const CustomerServiceConfig(
          enabled: false,
          label: _defaultCsLabel,
          link: '',
        ),
      );

  static void clearCache() {
    _cachedSettings = null;
    _cacheTimestamp = null;
  }

  static Future<ForgotPasswordSettings> getSettings({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _cachedSettings != null &&
        _cacheTimestamp != null &&
        DateTime.now().difference(_cacheTimestamp!) < _cacheDuration) {
      return _cachedSettings!;
    }

    try {
      final uri = Uri.parse(
        '${AppConfig.backendUrl}/wp-json/twork/v1/app/forgot-password-settings',
      );

      final Response<dynamic>? response = await ApiService.executeWithRetry(
        () => ApiService.get(
          uri.path,
          queryParameters: uri.queryParameters,
          skipAuth: true,
          headers: const <String, dynamic>{
            'Content-Type': 'application/json',
          },
        ),
        context: 'getForgotPasswordSettings',
      );

      if (NetworkUtils.isValidDioResponse(response)) {
        final Map<String, dynamic>? data =
            ApiService.responseAsJsonMap(response);
        if (data != null &&
            data['success'] == true &&
            data['data'] is Map<String, dynamic>) {
          final settings = _normalize(
            ForgotPasswordSettings.fromJson(
              data['data'] as Map<String, dynamic>,
            ),
          );
          _cachedSettings = settings;
          _cacheTimestamp = DateTime.now();
          Logger.info(
            'Forgot password settings loaded (cs=${settings.customerService.isVisible})',
            tag: 'ForgotPasswordSettingsService',
          );
          return settings;
        }
      }
    } catch (e, stackTrace) {
      Logger.warning(
        'Forgot password settings fetch failed, using fallback: $e',
        tag: 'ForgotPasswordSettingsService',
        error: e,
        stackTrace: stackTrace,
      );
    }

    final fallback = _fallbackSettings;
    _cachedSettings = fallback;
    _cacheTimestamp = DateTime.now();
    return fallback;
  }

  static ForgotPasswordSettings _normalize(ForgotPasswordSettings raw) {
    final domain = raw.emailDomain.isNotEmpty
        ? raw.emailDomain
        : RegisterRequest.autoEmailDomain;

    var hint = raw.hintText;
    if (hint.isEmpty) {
      hint = '$_defaultHintText ဥပမာ — myname@$domain';
    }

    final cs = raw.customerService;
    final label = cs.label.isNotEmpty ? cs.label : _defaultCsLabel;

    return ForgotPasswordSettings(
      emailDomain: domain,
      hintText: hint,
      customerService: CustomerServiceConfig(
        enabled: cs.enabled,
        label: label,
        link: cs.link,
      ),
    );
  }
}
