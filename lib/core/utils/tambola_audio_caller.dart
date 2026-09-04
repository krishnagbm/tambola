import 'package:flutter_tts/flutter_tts.dart';

class TambolaAudioCaller {
  static final TambolaAudioCaller _instance = TambolaAudioCaller._internal();
  factory TambolaAudioCaller() => _instance;
  TambolaAudioCaller._internal();

  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;
  bool isMuted = false;

  static const Map<int, String> _nicknames = {
    1: 'Number 1. Single digit 1',
    2: 'Number 2. Single digit 2',
    3: 'Number 3. Good luck 3',
    4: 'Number 4. Single number 4',
    5: 'Number 5. Single number 5',
    6: 'Number 6. Single number 6',
    7: 'Number 7. Lucky seven 7',
    8: 'Number 8. Big fat lady 8',
    9: 'Number 9. Single number 9',
    10: 'Number 10. A big fat hen 10',
    11: 'Number 11. Two legs eleven',
    13: 'Number 13. Lucky thirteen',
    20: 'Number 20. Blind twenty',
    22: 'Number 22. Two little ducks 22',
    25: 'Number 25. Two and five, twenty five',
    40: 'Number 40. Life begins at forty',
    50: 'Number 50. Half century 50',
    55: 'Number 55. All the fives 55',
    66: 'Number 66. Clickety click 66',
    75: 'Number 75. Diamond Jubilee 75',
    77: 'Number 77. Two hockey sticks 77',
    88: 'Number 88. Two fat ladies 88',
    90: 'Number 90. Top of the house, ninety!',
  };

  Future<void> _initTts() async {
    if (_isInitialized) return;
    try {
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setSpeechRate(0.48);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      _isInitialized = true;
    } catch (_) {}
  }

  /// Announces the called number aloud
  Future<void> announceNumber(int number, {bool useNicknames = true}) async {
    if (isMuted) return;
    await _initTts();

    String speechText;
    if (useNicknames && _nicknames.containsKey(number)) {
      speechText = _nicknames[number]!;
    } else if (number < 10) {
      speechText = 'Single number $number';
    } else {
      final tens = number ~/ 10;
      final ones = number % 10;
      if (ones == 0) {
        speechText = 'Number $number';
      } else {
        speechText = '$tens and $ones, $number';
      }
    }

    try {
      await _flutterTts.stop();
      await _flutterTts.speak(speechText);
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _flutterTts.stop();
    } catch (_) {}
  }
}
