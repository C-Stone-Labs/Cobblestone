import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/cairn_id.dart';

/// CairnID Nabız modu köprüsü (Paket-11 içinde geliyor).
///
/// Açıkken yerli taraftan akan enerji özetleri (seviyes/bas) CairnID'nin
/// nefes alma şiddetini sürer; kapalıyken CairnID bugünkü klasik davranışına
/// birebir döner (dokunuş + rastgele canlılık).
class RhythmController {
  RhythmController._();
  static final RhythmController instance = RhythmController._();

  static const EventChannel _ch = EventChannel('cobble/rhythm');
  static const _prefsKey = 'cairn_rhythm_v1';

  final enabledNotifier = ValueNotifier<bool>(false);

  StreamSubscription<dynamic>? _sub;
  bool _initialized = false;

  /// Uygulama açılışında bir kez: kalıcı tercihi okur, açıksa yayına bağlanır.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_prefsKey) ?? false;
    enabledNotifier.value = enabled;
    cairnRhythmOn = enabled;
    if (enabled) _subscribe();
  }

  void _subscribe() {
    _sub?.cancel();
    _sub = _ch.receiveBroadcastStream().listen(_onFeel, onError: (_) {});
  }

  void _onFeel(dynamic ev) {
    if (ev is! Map) return;
    final playing = ev['playing'] == true;
    if (!playing) {
      cairnRhythmLevel = 0;
      cairnRhythmBass = 0;
      return;
    }
    final l = (ev['level'] as num?)?.toDouble() ?? 0;
    final b = (ev['bass'] as num?)?.toDouble() ?? 0;
    // Yumuşatma: ani sıçramalar yerine nefes hissi.
    cairnRhythmLevel += (l - cairnRhythmLevel) * 0.35;
    cairnRhythmBass += (b - cairnRhythmBass) * 0.3;
  }

  Future<void> setEnabled(bool v) async {
    enabledNotifier.value = v;
    cairnRhythmOn = v;
    if (!v) {
      cairnRhythmLevel = 0;
      cairnRhythmBass = 0;
      await _sub?.cancel();
      _sub = null;
    } else {
      _subscribe();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, v);
  }
}

