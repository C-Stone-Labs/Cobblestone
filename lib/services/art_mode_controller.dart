import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Şimdi Çalınıyor ekranındaki büyük alanın modu:
/// • cover  → albüm kapağı (kapak yoksa klasik nota simgesi)
/// • cairn  → CairnID (etkileşimli ekolayzer halkası)
/// Kullanıcının son seçimi kalıcı olarak hatırlanır.
enum ArtMode { cover, cairn }

class ArtModeController {
  ArtModeController._();
  static final ArtModeController instance = ArtModeController._();

  final ValueNotifier<ArtMode> modeNotifier = ValueNotifier(ArtMode.cover);
  static const _prefsKey = 'art_mode_v1';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved == 'cairn') modeNotifier.value = ArtMode.cairn;
  }

  Future<void> setMode(ArtMode mode) async {
    modeNotifier.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode == ArtMode.cairn ? 'cairn' : 'cover');
  }

  Future<void> toggle() => setMode(
    modeNotifier.value == ArtMode.cover ? ArtMode.cairn : ArtMode.cover,
  );
}

