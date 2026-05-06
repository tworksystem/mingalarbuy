import 'package:flutter/foundation.dart';

/// Professional app configuration management
class AppConfig {
  static const String appName = 'PlanetMM';
  static const String appVersion = '1.0.0';
  static const String buildNumber = '1';

  // API Configuration (WooCommerce - mingalarbuy.com)
  static const String baseUrl = 'https://mingalarbuy.com/wp-json/wc/v3';
  static const String wpBaseUrl = 'https://mingalarbuy.com/wp-json/wp/v2';
  static const String consumerKey =
      'ck_9838e0a0aa35fee12d90c29026441c096863f0c6';
  static const String consumerSecret =
      'cs_2542de3bf738e35aed466029a0c789579a2034d6';

  // Backend Server Configuration (for FCM notifications)
  //
  // ⚠️ CRITICAL: This MUST be YOUR webhook server URL, NOT Firebase console URL!
  //
  // 🔴 WRONG: https://console.firebase.google.com (Firebase Console URL)
  // ✅ CORRECT: https://your-webhook-server.com (Your deployed server)
  //
  // Setup Steps:
  // 1. Deploy backend/webhook_server.js to Heroku/AWS/DigitalOcean
  // 2. Get your server URL from deployment platform
  // 3. Update backendUrl below with YOUR server URL
  //
  // Examples:
  // - Local testing: 'http://localhost:3000'
  // - Heroku: 'https://twork-webhook.herokuapp.com'
  // - AWS/DigitalOcean: 'https://webhook.yourdomain.com'
  //
  // For NOW: Using WooCommerce host as backend base (adjust if you deploy a separate webhook server)
  static const String backendUrl = 'https://mingalarbuy.com';
  static const String backendRegisterTokenEndpoint =
      '/wp-json/twork/v1/register-token';
  static const String tworkApiBasePath = '/wp-json/twork/v1';
  static const String tworkPointsEarnEndpoint = '$tworkApiBasePath/points/earn';
  static const String tworkPointsRedeemEndpoint =
      '$tworkApiBasePath/points/redeem';
  static const String tworkPointsBalancePath = '$tworkApiBasePath/points/balance';
  static const String tworkPointsTransactionsPath =
      '$tworkApiBasePath/points/transactions';
  static const String tworkEngagementFeedPath =
      '$tworkApiBasePath/engagement/feed';
  static const String tworkPollStatePath = '$tworkApiBasePath/poll/state';

  // Performance Settings
  static const int maxCacheSize = 100;
  static const Duration cacheExpiry = Duration(minutes: 5);
  static const Duration networkTimeout = Duration(seconds: 30);
  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(seconds: 2);

  // UI Settings
  static const double defaultPadding = 16.0;
  static const double defaultMargin = 8.0;
  static const double defaultBorderRadius = 12.0;
  static const Duration defaultAnimationDuration = Duration(milliseconds: 300);

  // Feature Flags
  static const bool enableAnalytics = true;
  static const bool enableCrashReporting = true;
  static const bool enablePerformanceMonitoring = kDebugMode;
  static const bool enableNetworkLogging = kDebugMode;

  // Pagination
  static const int defaultPageSize = 20;
  static const int maxPageSize = 100;

  // Image Settings
  static const int maxImageCacheSize = 50;
  static const Duration imageCacheExpiry = Duration(hours: 1);

  // Security
  static const bool enableSSL = true;
  static const bool enableCertificatePinning = false;

  // Development
  static const bool isDevelopment = kDebugMode;
  static const bool isProduction = kReleaseMode;

  /// Get configuration value with fallback
  static T getValue<T>(String key, T defaultValue) {
    // This would integrate with your configuration system
    return defaultValue;
  }

  /// Check if feature is enabled
  static bool isFeatureEnabled(String feature) {
    switch (feature) {
      case 'analytics':
        return enableAnalytics;
      case 'crash_reporting':
        return enableCrashReporting;
      case 'performance_monitoring':
        return enablePerformanceMonitoring;
      case 'network_logging':
        return enableNetworkLogging;
      default:
        return false;
    }
  }

  /// Get API endpoint
  static String getApiEndpoint(String endpoint) {
    return '$baseUrl/$endpoint';
  }

  /// Build a full backend URL from a twork endpoint path.
  static String tworkEndpoint(String endpointPath) {
    return '$backendUrl$endpointPath';
  }

  /// Get headers for API requests
  static Map<String, String> getApiHeaders() {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Basic ${_getAuthToken()}',
      'User-Agent': '$appName/$appVersion',
    };
  }

  static String _getAuthToken() {
    // This would properly encode the credentials
    return 'Basic $consumerKey:$consumerSecret';
  }
}

/// Environment-specific configuration
class EnvironmentConfig {
  static const String development = 'development';
  static const String staging = 'staging';
  static const String production = 'production';

  static String get current {
    if (kDebugMode) return development;
    if (kProfileMode) return staging;
    return production;
  }

  static bool get isDevelopment => current == development;
  static bool get isStaging => current == staging;
  static bool get isProduction => current == production;
}

/// Feature flags management
class FeatureFlags {
  static const String orderManagement = 'order_management';
  static const String analytics = 'analytics';
  static const String pushNotifications = 'push_notifications';
  static const String offlineMode = 'offline_mode';
  static const String darkMode = 'dark_mode';

  static bool isEnabled(String feature) {
    return AppConfig.isFeatureEnabled(feature);
  }

  static void enable(String feature) {
    // Implementation for enabling features
  }

  static void disable(String feature) {
    // Implementation for disabling features
  }
}

/// Performance thresholds
class PerformanceThresholds {
  static const Duration maxLoadTime = Duration(seconds: 5);
  static const Duration maxNetworkTimeout = Duration(seconds: 30);
  static const int maxMemoryUsage = 100; // MB
  static const int maxCacheSize = 100;
  static const Duration maxCacheAge = Duration(hours: 1);
}

/// Security configuration
class SecurityConfig {
  static const bool enableBiometricAuth = false;
  static const bool enablePinAuth = false;
  static const bool enableSessionTimeout = true;
  static const Duration sessionTimeout = Duration(hours: 24);
  static const int maxLoginAttempts = 5;
  static const Duration lockoutDuration = Duration(minutes: 15);
}
