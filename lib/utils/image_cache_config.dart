import 'package:flutter/painting.dart';

import 'app_config.dart';

/// Applies global Flutter image cache limits (RAM) for long browsing sessions.
class AppImageCacheConfig {
  AppImageCacheConfig._();

  static void apply() {
    final cache = PaintingBinding.instance.imageCache;
    cache.maximumSize = AppConfig.maxImageCacheSize;
    cache.maximumSizeBytes = AppConfig.maxImageCacheSizeBytes;
  }

  /// Called under memory pressure — keeps app alive; images reload on demand.
  static void trimUnderPressure() {
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();
  }
}
