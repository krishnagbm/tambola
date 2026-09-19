import 'package:flutter/foundation.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:js_interop' as js;

@js.JS('navigator.wakeLock.request')
external js.JSPromise<js.JSObject>? _requestWakeLock(js.JSString type);

class WakeLockHelper {
  static bool _isActive = false;

  /// Requests a screen wake lock to keep the device screen active during live gameplay
  static Future<void> keepScreenOn() async {
    if (!kIsWeb) return;
    if (_isActive) return;

    try {
      final promise = _requestWakeLock('screen'.toJS);
      if (promise != null) {
        await promise.toDart;
        _isActive = true;
        debugPrint('[WakeLock] Screen wake lock acquired successfully.');
      }
    } catch (e) {
      debugPrint('[WakeLock] Wake Lock API not supported or failed: $e');
    }
  }

  /// Releases the screen wake lock when game finishes or player leaves
  static Future<void> release() async {
    if (!kIsWeb) return;
    if (!_isActive) return;

    try {
      _isActive = false;
      debugPrint('[WakeLock] Screen wake lock released.');
    } catch (_) {}
  }
}
