import 'package:flutter/foundation.dart';
import 'dart:html' as html;

/// Web Debug Helper for troubleshooting Flutter web issues
class WebDebugHelper {
  /// Initialize web debugging
  static void initialize() {
    if (kIsWeb) {
      print('🌐 WebDebugHelper: Initializing...');

      // Check browser console
      _checkBrowserConsole();

      // Check network status
      _checkNetworkStatus();

      // Check Flutter web initialization
      _checkFlutterWebInit();

      // Add debug listeners
      _addDebugListeners();
    }
  }

  /// Check browser console
  static void _checkBrowserConsole() {
    try {
      print('🌐 Browser: ${html.window.navigator.userAgent}');
      print('🌐 URL: ${html.window.location.href}');
      print('🌐 Protocol: ${html.window.location.protocol}');
      print('🌐 Host: ${html.window.location.host}');
    } catch (e) {
      print('❌ Browser console check failed: $e');
    }
  }

  /// Check network status
  static void _checkNetworkStatus() {
    try {
      final isOnline = html.window.navigator.onLine ?? false;
      print('🌐 Network status: ${isOnline ? "Online" : "Offline"}');

      // Listen for online/offline events
      html.window.addEventListener('online', (event) {
        print('🌐 Network: Online');
      });

      html.window.addEventListener('offline', (event) {
        print('🌐 Network: Offline');
      });
    } catch (e) {
      print('❌ Network status check failed: $e');
    }
  }

  /// Check Flutter web initialization
  static void _checkFlutterWebInit() {
    try {
      // Check if Flutter is loaded
      try {
        final flutterLoaded =
            html.window.navigator.userAgent.contains('Flutter');
        print('🌐 Flutter loaded: $flutterLoaded');
      } catch (e) {
        print('🌐 Flutter loaded: false');
      }

      // Check if app is initialized
      final appInitialized = html.document.querySelector('#loading') == null;
      print('🌐 App initialized: $appInitialized');
    } catch (e) {
      print('❌ Flutter web init check failed: $e');
    }
  }

  /// Add debug listeners
  static void _addDebugListeners() {
    try {
      // Listen for errors
      html.window.addEventListener('error', (event) {
        print('❌ Window error: $event');
      });

      // Listen for unhandled promise rejections
      html.window.addEventListener('unhandledrejection', (event) {
        print('❌ Unhandled promise rejection: $event');
      });

      // Listen for beforeunload
      html.window.addEventListener('beforeunload', (event) {
        print('🌐 App is being unloaded');
      });
    } catch (e) {
      print('❌ Debug listeners setup failed: $e');
    }
  }

  /// Test basic functionality
  static void testBasicFunctionality() {
    if (kIsWeb) {
      print('🧪 Testing basic functionality...');

      try {
        // Test DOM access
        final body = html.document.body;
        print('✅ DOM access: ${body != null}');

        // Test window access
        final window = html.window;
        print('✅ Window access: ${window != null}');

        // Test navigator access
        final navigator = html.window.navigator;
        print('✅ Navigator access: ${navigator != null}');

        // Test localStorage
        final storage = html.window.localStorage;
        print('✅ LocalStorage access: ${storage != null}');

        print('🧪 Basic functionality test completed');
      } catch (e) {
        print('❌ Basic functionality test failed: $e');
      }
    }
  }

  /// Log current app state
  static void logAppState() {
    if (kIsWeb) {
      print('📊 Current App State:');
      print('  - URL: ${html.window.location.href}');
      print('  - Online: ${html.window.navigator.onLine}');
      print('  - User Agent: ${html.window.navigator.userAgent}');
      print('  - Language: ${html.window.navigator.language}');
      print('  - Platform: ${html.window.navigator.platform}');
    }
  }

  /// Force reload the page
  static void forceReload() {
    if (kIsWeb) {
      print('🔄 Force reloading page...');
      html.window.location.reload();
    }
  }

  /// Check for common issues
  static void checkCommonIssues() {
    if (kIsWeb) {
      print('🔍 Checking for common issues...');

      try {
        // Check if running in HTTPS
        final isHttps = html.window.location.protocol == 'https:';
        print('🔒 HTTPS: $isHttps');

        // Check if running on localhost
        final isLocalhost = html.window.location.hostname == 'localhost' ||
            html.window.location.hostname == '127.0.0.1';
        print('🏠 Localhost: $isLocalhost');

        // Check for service worker
        try {
          final serviceWorker = html.window.navigator.serviceWorker;
          print(
              '⚙️ Service Worker: ${serviceWorker != null ? "Available" : "Not available"}');
        } catch (e) {
          print('⚙️ Service Worker: Not available');
        }

        // Check for WebGL
        final canvas = html.CanvasElement();
        final gl = canvas.getContext3d();
        print('🎮 WebGL: ${gl != null}');

        // Check memory usage
        final memory = html.window.performance.getEntriesByType('memory');
        if (memory.isNotEmpty) {
          print('💾 Memory tracking: Available');
        }
            } catch (e) {
        print('❌ Common issues check failed: $e');
      }
    }
  }

  /// Performance monitoring
  static void startPerformanceMonitoring() {
    if (kIsWeb) {
      print('📈 Starting performance monitoring...');

      try {
        final performance = html.window.performance;
        // Monitor page load time
        performance.addEventListener('load', (event) {
          final loadTime = performance.now();
          print('📈 Page load time: ${loadTime}ms');
        });

        // Monitor navigation timing
        final navTiming = performance.getEntriesByType('navigation');
        if (navTiming.isNotEmpty) {
          print('📈 Navigation timing available');
        }

        // Monitor resource timing
        final resourceTiming = performance.getEntriesByType('resource');
        print('📈 Resources loaded: ${resourceTiming.length}');
            } catch (e) {
        print('❌ Performance monitoring setup failed: $e');
      }
    }
  }
}
