import 'dart:js_interop';

@JS('openDabbyModal')
external void _openDabbyModalJs();

@JS('closeDabbyModal')
external void _closeDabbyModalJs();

@JS('speakBallWeb')
external void _speakBallWebJs(JSString text);

@JS('playBallChime')
external void _playBallChimeJs();

@JS('unlockAudioEngine')
external void _unlockAudioEngineJs();

/// Web implementation calling window functions registered in web/index.html
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

  static bool speakBallWeb(String text) {
    try {
      _speakBallWebJs(text.toJS);
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool playBallChime() {
    try {
      _playBallChimeJs();
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool unlockAudioEngine() {
    try {
      _unlockAudioEngineJs();
      return true;
    } catch (_) {
      return false;
    }
  }
}
