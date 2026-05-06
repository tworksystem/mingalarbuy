import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// Web: invoke callback when tab/document becomes visible.
StreamSubscription<dynamic>? attachWebVisibilityVisibleListener(
  void Function() onVisible,
) {
  final controller = StreamController<dynamic>();
  late JSFunction listener;

  listener = ((web.Event _) {
    if (web.document.visibilityState == 'visible') {
      onVisible();
    }
    if (!controller.isClosed) {
      controller.add(null);
    }
  }).toJS;

  web.document.addEventListener('visibilitychange', listener);
  controller.onCancel = () {
    web.document.removeEventListener('visibilitychange', listener);
  };
  return controller.stream.listen((_) {});
}
