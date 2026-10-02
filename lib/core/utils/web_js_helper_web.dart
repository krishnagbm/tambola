import 'dart:js_interop';

@JS('openDabbyModal')
external void _openDabbyModalJs();

@JS('closeDabbyModal')
external void _closeDabbyModalJs();

/// Web implementation calling window.openDabbyModal() registered in web/index.html
class WebJsHelper {
  static bool openDabbyModal() {
    try {
      _openDabbyModalJs();
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool closeDabbyModal() {
    try {
      _closeDabbyModalJs();
      return true;
    } catch (_) {
      return false;
    }
  }
}
