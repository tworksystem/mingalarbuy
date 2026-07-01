import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Mouse / trackpad drag scrolling on Flutter Web.
class WebScrollBehavior extends MaterialScrollBehavior {
  const WebScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
      };
}
