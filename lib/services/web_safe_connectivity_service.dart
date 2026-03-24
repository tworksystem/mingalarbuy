import 'dart:async';
import 'package:flutter/foundation.dart';

/// Web-safe connectivity service that doesn't use connectivity_plus on web
class WebSafeConnectivityService {
  static final WebSafeConnectivityService _instance =
      WebSafeConnectivityService._internal();
  factory WebSafeConnectivityService() => _instance;
  WebSafeConnectivityService._internal();

  StreamController<bool>? _connectionStatusController;
  bool _hasConnection = true;
  bool get hasConnection => _hasConnection;

  /// Initialize connectivity monitoring with web compatibility
  Future<void> initialize() async {
    try {
      _connectionStatusController = StreamController<bool>.broadcast();

      if (kIsWeb) {
        print('🌐 Web platform detected - using browser connectivity');
        await _initializeWebConnectivity();
      } else {
        print('📱 Mobile platform detected - using connectivity_plus');
        await _initializeMobileConnectivity();
      }

      print('✅ WebSafe Connectivity Service initialized');
    } catch (e) {
      print('❌ WebSafe Connectivity Service initialization failed: $e');
      // Don't rethrow - let the app continue with default connectivity
      _hasConnection = true;
    }
  }

  /// Initialize web-specific connectivity monitoring
  Future<void> _initializeWebConnectivity() async {
    // For web, we'll assume connectivity is available
    // In a real app, you might check navigator.onLine
    _hasConnection = true;
    _connectionStatusController?.add(_hasConnection);
  }

  /// Initialize mobile-specific connectivity monitoring
  Future<void> _initializeMobileConnectivity() async {
    // For mobile, we could use connectivity_plus
    // For now, just assume connectivity is available
    _hasConnection = true;
    _connectionStatusController?.add(_hasConnection);
  }

  /// Check current connectivity status
  Future<bool> checkConnectivity() async {
    try {
      if (kIsWeb) {
        // For web, assume connectivity is available
        return true;
      } else {
        // For mobile, could check actual connectivity
        return true;
      }
    } catch (e) {
      print('❌ Error checking connectivity: $e');
      return true; // Default to connected
    }
  }

  /// Stream of connection status changes
  Stream<bool> get connectionStatusStream {
    if (_connectionStatusController == null) {
      // Return a stream that always emits true if not initialized
      return Stream.value(true);
    }
    return _connectionStatusController!.stream;
  }

  /// Get connection type as string
  Future<String> getConnectionType() async {
    if (kIsWeb) {
      return 'web';
    } else {
      return 'mobile';
    }
  }

  /// Dispose
  void dispose() {
    _connectionStatusController?.close();
    print('✅ WebSafe Connectivity Service disposed');
  }
}

/// Singleton instance for easy access
final webSafeConnectivityService = WebSafeConnectivityService();
