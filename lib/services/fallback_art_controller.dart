import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Albüm kapağı yokken: taş resmi (bildirimdeki) veya nota logosu.
enum FallbackArt { stone, note }

class FallbackArtController {
  FallbackArtController._();
  static final FallbackArtController instance = FallbackArtController._();

  static const _prefsKey = 'fallback_art_v1';
  static const _native = MethodChannel('cobble/native');

  final ValueNotifier<FallbackArt> modeNotifier = ValueNotifier(FallbackArt.stone);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved == 'note') modeNotifier.value = FallbackArt.note;
    } catch (_) {}
    try {
      await _native.invokeMethod('setFallbackArt', {
        'mode': modeNotifier.value == FallbackArt.note ? 'note' : 'stone',
      });
    } catch (_) {}
  }

  Future<void> setMode(FallbackArt mode) async {
    modeNotifier.value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, mode == FallbackArt.note ? 'note' : 'stone');
    } catch (_) {}
    try {
      await _native.invokeMethod('setFallbackArt', {
        'mode': mode == FallbackArt.note ? 'note' : 'stone',
      });
    } catch (_) {}
  }
}
