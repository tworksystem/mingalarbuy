import 'dart:convert';

import 'package:dio/dio.dart';

/// Detects Imunify360 / WAF bot-protection payloads (often HTTP 200 + JSON message).
class WafResponseUtils {
  WafResponseUtils._();

  static bool looksLikeWafBlockMessage(String lowerMessage) {
    return lowerMessage.contains('imunify') ||
        lowerMessage.contains('bot-protection') ||
        lowerMessage.contains('bot protection') ||
        (lowerMessage.contains('access denied') &&
            lowerMessage.contains('whitelist'));
  }

  static Map<String, dynamic>? _bodyAsMap(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    if (data is String && data.trim().isNotEmpty) {
      try {
        final decoded = json.decode(data);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }
    return null;
  }

  static bool isWafBlockedBody(dynamic data) {
    final map = _bodyAsMap(data);
    if (map == null) {
      return false;
    }
    final message = (map['message'] as String?)?.trim().toLowerCase() ?? '';
    if (message.isNotEmpty && looksLikeWafBlockMessage(message)) {
      return true;
    }
    final code = (map['code'] as String?)?.trim().toLowerCase() ?? '';
    return code.contains('bot') && message.contains('denied');
  }

  static bool isWafBlockedResponse(Response<dynamic>? response) {
    if (response == null) {
      return false;
    }
    if (response.extra['wafBlocked'] == true) {
      return true;
    }
    return isWafBlockedBody(response.data);
  }

  static const String userFacingMessage =
      'Server temporarily blocked this request. Please try again in a moment.';
}
