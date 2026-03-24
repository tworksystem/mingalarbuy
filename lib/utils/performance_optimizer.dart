import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Professional performance optimization utilities
class PerformanceOptimizer {
  static const int _maxCacheSize = 100;
  static final Map<String, dynamic> _cache = {};
  static final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheExpiry = Duration(minutes: 5);

  /// Cache with automatic expiry
  static T? getCached<T>(String key) {
    if (!_cache.containsKey(key)) return null;

    final timestamp = _cacheTimestamps[key];
    if (timestamp == null ||
        DateTime.now().difference(timestamp) > _cacheExpiry) {
      _cache.remove(key);
      _cacheTimestamps.remove(key);
      return null;
    }

    return _cache[key] as T?;
  }

  static void setCached<T>(String key, T value) {
    _cache[key] = value;
    _cacheTimestamps[key] = DateTime.now();

    // Clean up old cache entries
    if (_cache.length > _maxCacheSize) {
      _cleanupCache();
    }
  }

  static void _cleanupCache() {
    final now = DateTime.now();
    final keysToRemove = <String>[];

    _cacheTimestamps.forEach((key, timestamp) {
      if (now.difference(timestamp) > _cacheExpiry) {
        keysToRemove.add(key);
      }
    });

    for (final key in keysToRemove) {
      _cache.remove(key);
      _cacheTimestamps.remove(key);
    }
  }

  static void clearCache() {
    _cache.clear();
    _cacheTimestamps.clear();
  }
}

/// Optimized image loading widget
class OptimizedImage extends StatelessWidget {
  final String imageUrl;
  final String? fallbackAsset;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? placeholder;
  final Widget? errorWidget;

  const OptimizedImage({
    super.key,
    required this.imageUrl,
    this.fallbackAsset,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Image.network(
        imageUrl,
        fit: fit,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return placeholder ??
              Container(
                color: Colors.grey[200],
                child: Center(
                  child: CircularProgressIndicator(
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                        : null,
                  ),
                ),
              );
        },
        errorBuilder: (context, error, stackTrace) {
          return errorWidget ??
              Container(
                color: Colors.grey[200],
                child: fallbackAsset != null
                    ? Image.asset(fallbackAsset!, fit: fit)
                    : Icon(Icons.image, color: Colors.grey),
              );
        },
      ),
    );
  }
}

/// Debounced function execution
class Debouncer {
  final Duration delay;
  Timer? _timer;

  Debouncer({this.delay = const Duration(milliseconds: 500)});

  void call(VoidCallback callback) {
    _timer?.cancel();
    _timer = Timer(delay, callback);
  }

  void dispose() {
    _timer?.cancel();
  }
}

/// Throttled function execution
class Throttler {
  final Duration delay;
  DateTime? _lastExecution;

  Throttler({this.delay = const Duration(milliseconds: 300)});

  void call(VoidCallback callback) {
    final now = DateTime.now();
    if (_lastExecution == null || now.difference(_lastExecution!) >= delay) {
      _lastExecution = now;
      callback();
    }
  }
}

/// Memory-efficient list builder
class OptimizedListView extends StatelessWidget {
  final List<dynamic> items;
  final Widget Function(BuildContext, int) itemBuilder;
  final ScrollController? controller;
  final EdgeInsetsGeometry? padding;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  const OptimizedListView({
    super.key,
    required this.items,
    required this.itemBuilder,
    this.controller,
    this.padding,
    this.shrinkWrap = false,
    this.physics,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      padding: padding,
      shrinkWrap: shrinkWrap,
      physics: physics,
      itemCount: items.length,
      itemBuilder: (context, index) {
        // Add key for better performance
        return KeyedSubtree(
          key: ValueKey('item_$index'),
          child: itemBuilder(context, index),
        );
      },
    );
  }
}

/// Lazy loading widget
class LazyLoader extends StatefulWidget {
  final Widget child;
  final VoidCallback? onVisible;
  final Duration delay;

  const LazyLoader({
    super.key,
    required this.child,
    this.onVisible,
    this.delay = const Duration(milliseconds: 100),
  });

  @override
  _LazyLoaderState createState() => _LazyLoaderState();
}

class _LazyLoaderState extends State<LazyLoader> {
  bool _isVisible = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) {
        setState(() {
          _isVisible = true;
        });
        widget.onVisible?.call();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return _isVisible ? widget.child : SizedBox.shrink();
  }
}

/// Performance monitoring widget
class PerformanceMonitor extends StatefulWidget {
  final Widget child;
  final String name;
  final bool enabled;

  const PerformanceMonitor({
    super.key,
    required this.child,
    required this.name,
    this.enabled = kDebugMode,
  });

  @override
  _PerformanceMonitorState createState() => _PerformanceMonitorState();
}

class _PerformanceMonitorState extends State<PerformanceMonitor> {
  late DateTime _startTime;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      _startTime = DateTime.now();
    }
  }

  @override
  void dispose() {
    if (widget.enabled) {
      final duration = DateTime.now().difference(_startTime);
      print('⏱️ ${widget.name} rendered in ${duration.inMilliseconds}ms');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// Memory usage tracker
class MemoryTracker {
  static void logMemoryUsage(String context) {
    if (kDebugMode) {
      // This would integrate with actual memory monitoring
      print('🧠 Memory usage for $context: [Placeholder]');
    }
  }
}

/// Widget tree optimization
class WidgetTreeOptimizer {
  static Widget optimizeTree(Widget child) {
    return RepaintBoundary(
      child: child,
    );
  }

  static Widget addRepaintBoundary(Widget child) {
    return RepaintBoundary(child: child);
  }

  static Widget addAutomaticKeepAlive(Widget child) {
    return AutomaticKeepAlive(child: child);
  }
}
