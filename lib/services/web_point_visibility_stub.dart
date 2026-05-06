import 'dart:async';

/// Non-web platforms: no browser visibility change API.
StreamSubscription<dynamic>? attachWebVisibilityVisibleListener(
  void Function() onVisible,
) {
  return null;
}
