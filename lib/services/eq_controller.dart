import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_controller.dart';

/// Gerçek ekolayzer (SES MERKEZİ) — Android tarafındaki EqEngine'i sürer.
///
/// Servis henüz bağlanmadıysa otomatik olarak bağlanmayı bekler; motor
/// cihazda yoksa `supportedNotifier` false kalır ve arayüz bölümü gizlenir.
class EqController {
  EqController._();
  static final EqController instance = EqController._();

  static const MethodChannel _ch = MethodChannel('cobble/eq');
  static const _prefsKey = 'eq_v1';

  final supportedNotifier = ValueNotifier<bool>(false);
  final enabledNotifier = ValueNotifier<bool>(false);
  final levelsNotifier = ValueNotifier<List<int>>(const []);
  final bassNotifier = ValueNotifier<int>(0); // 0..1000 (binde)
  final virtNotifier = ValueNotifier<int>(0); // 0..1000

  int bandCount = 0;
  int minLevel = -1500; // millibel
  int maxLevel = 1500;
  List<int> freqs = const [];
  bool bassSupported = false;
  bool virtSupported = false;

  bool _initialized = false;

  /// Uygulama açılışında bir kez çağrılır; servis hazır olana kadar sabırla
  /// bekler, sonra kalıcı tercihleri motora uygular.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    unawaited(_initWhenReady());
  }

  Future<void> _initWhenReady() async {
    if (!audioServiceReady.value) {
      void Function()? listener;
      final ready = Completer<void>();
      listener = () {
        if (audioServiceReady.value && !ready.isCompleted) {
          ready.complete();
          audioServiceReady.removeListener(listener!);
        }
      };
      audioServiceReady.addListener(listener);
      try {
        await ready.future.timeout(const Duration(seconds: 20));
      } catch (_) {}
    }
    // Motora ulaşımı nazik aralıklarla dene (ses kanalı ilk çalmada düşebilir).
    for (var attempt = 0; attempt < 40; attempt++) {
      if (await probe()) return;
      await Future.delayed(const Duration(milliseconds: 1500));
    }
    supportedNotifier.value = false;
  }

  /// Tek denemelik EQ yoklaması. Ayarlar'daki "Tekrar Dene" de bunu çağırır.
  Future<bool> probe() async {
    if (supportedNotifier.value) return true;
    try {
      final d = await _ch.invokeMapMethod<String, dynamic>('describe');
      if (d?['supported'] == true) {
        _applyDescription(d!);
        await _restore();
        supportedNotifier.value = true;
        return true;
      }
    } catch (_) {}
    return false;
  }

  void _applyDescription(Map<String, dynamic> d) {
    bandCount = (d['bandCount'] as num?)?.toInt() ?? 0;
    minLevel = (d['minLevel'] as num?)?.toInt() ?? -1500;
    maxLevel = (d['maxLevel'] as num?)?.toInt() ?? 1500;
    freqs = [
      for (final f in (d['freqs'] as List?) ?? const []) (f as num).toInt(),
    ];
    bassSupported = d['bassSupported'] == true;
    virtSupported = d['virtualizerSupported'] == true;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    var enabled = false;
    List<int> levels = List<int>.filled(bandCount, 0);
    var bass = 0;
    var virt = 0;
    if (raw != null) {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        enabled = j['enabled'] == true;
        final saved = [
          for (final l in (j['levels'] as List?) ?? const [])
            (l as num).toInt(),
        ];
        for (var i = 0; i < levels.length && i < saved.length; i++) {
          levels[i] = saved[i];
        }
        bass = (j['bass'] as num?)?.toInt() ?? 0;
        virt = (j['virtualizer'] as num?)?.toInt() ?? 0;
      } catch (_) {}
    }
    enabledNotifier.value = enabled;
    levelsNotifier.value = levels;
    bassNotifier.value = bass;
    virtNotifier.value = virt;
    await _applyAll();
  }

  Future<void> _applyAll() async {
    try {
      await _ch.invokeMethod('apply', {
        'enabled': enabledNotifier.value,
        'levels': levelsNotifier.value,
        'bass': bassNotifier.value,
        'virtualizer': virtNotifier.value,
      });
    } catch (_) {}
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode({
        'enabled': enabledNotifier.value,
        'levels': levelsNotifier.value,
        'bass': bassNotifier.value,
        'virtualizer': virtNotifier.value,
      }),
    );
  }

  Future<void> setEnabled(bool v) async {
    enabledNotifier.value = v;
    await _applyAll();
    await _persist();
  }

  Future<void> setBand(int band, int level) async {
    final l = List<int>.from(levelsNotifier.value);
    if (band < 0 || band >= l.length) return;
    l[band] = level.clamp(minLevel, maxLevel);
    levelsNotifier.value = l;
    await _applyAll();
    await _persist();
  }

  Future<void> setBass(int strength) async {
    bassNotifier.value = strength.clamp(0, 1000);
    await _applyAll();
    await _persist();
  }

  Future<void> setVirtualizer(int strength) async {
    virtNotifier.value = strength.clamp(0, 1000);
    await _applyAll();
    await _persist();
  }

  /// Hazır profiller (-1..1 oranları, cihazın dB aralığına ölçeklenir).
  static const presets = <String, List<double>>{
    'Normal': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    'Bas Ağırlıklı': [0.85, 0.75, 0.45, 0.2, 0, -0.1, -0.05, 0.05, 0.1, 0.05],
    'Vokal': [-0.25, -0.15, 0.1, 0.35, 0.65, 0.55, 0.35, 0.15, 0.05, 0],
    'Rock': [0.5, 0.4, 0.2, -0.1, -0.15, 0.2, 0.4, 0.55, 0.65, 0.45],
    'Gece': [0.3, 0.2, 0.05, 0, -0.1, -0.15, -0.2, -0.15, -0.2, -0.25],
    'Elektronik': [0.7, 0.55, 0.2, 0, 0.15, 0.35, 0.2, 0.4, 0.55, 0.5],
  };

  double _lerpRatio(List<double> curve, int band) {
    if (bandCount <= 1) return curve[2];
    final t = band / (bandCount - 1) * (curve.length - 1);
    final i = t.floor().clamp(0, curve.length - 2);
    final f = t - i;
    return curve[i] + (curve[i + 1] - curve[i]) * f;
  }

  Future<void> applyPreset(String name) async {
    final curve = presets[name];
    if (curve == null || bandCount == 0) return;
    final span = minLevel.abs() < maxLevel ? minLevel.abs() : maxLevel;
    final scale = (span * 0.7).round(); // profiller aralığın ~%70'ini kullanır
    final levels = <int>[
      for (var b = 0; b < bandCount; b++)
        (_lerpRatio(curve, b) * scale).round().clamp(minLevel, maxLevel),
    ];
    levelsNotifier.value = levels;
    await _applyAll();
    await _persist();
  }
}

