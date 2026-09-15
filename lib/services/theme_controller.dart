import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/palette.dart';

/// Atmosfer teması. `auto` seçiliyken saat dilimine göre gündüzleri
/// "Gündüz", geceleri "Gece" atmosferi çözülür (eski otomatik davranış).
enum Atmosfer { auto, gece, gunduz, orman, neon }

extension AtmosferInfo on Atmosfer {
  String get label {
    switch (this) {
      case Atmosfer.auto:
        return 'Otomatik (Saate Göre)';
      case Atmosfer.gece:
        return 'Gece — Aurora';
      case Atmosfer.gunduz:
        return 'Gündüz — Duru Su';
      case Atmosfer.orman:
        return 'Orman — Bio Flow';
      case Atmosfer.neon:
        return 'Neon';
    }
  }

  String get subtitle {
    switch (this) {
      case Atmosfer.auto:
        return '21:00 - 07:00 arası Gece, gündüzleri Gündüz atmosferi';
      case Atmosfer.gece:
        return 'Derin lacivert, kutup ışıkları, yıldız tozu';
      case Atmosfer.gunduz:
        return 'Ferah aydınlık, duru su parıltısı, yumuşak dalgalar';
      case Atmosfer.orman:
        return 'Koyu toprak, yaprak salkımları, çiy parıltısı';
      case Atmosfer.neon:
        return 'Fosforlu mor, elektrik mavisi, turuncu patlamalar';
    }
  }
}

/// Geriye dönük uyumluluk: eski 3'lü mod. (Eski kod hâlâ bunu okuyabilir;
/// controller iki yönde senkron tutar.)
enum ThemeMode3 { auto, day, night }

/// Tema sağlayıcısı: atmosfer seçimi, otomatik çözümleme ve paletin
/// YUMUŞAK (morph) geçişle hedefe kayması burada yönetilir.
class ThemeController {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  final ValueNotifier<Atmosfer> atmosferNotifier = ValueNotifier(Atmosfer.auto);

  /// Her karede okunabilen CANLI palet: tema değişince ~600 ms boyunca eski
  /// paletten yeniye lerp'lenir ("PAT" diye atlama yok).
  final ValueNotifier<CobblestonePalette> paletteNotifier = ValueNotifier(
    gecePalette,
  );

  /// Legacy okuyucular için eşlenmiş görünüm.
  final ValueNotifier<ThemeMode3> modeNotifier = ValueNotifier(ThemeMode3.auto);

  static const _prefsKey = 'atmosfer_v1';
  static const _legacyPrefsKey = 'theme_mode_v1';

  Atmosfer _lastResolved = Atmosfer.gece;
  Timer? _morphTimer;
  Timer? _autoTimer;

  /// Seçime göre ETKİN atmosfer (auto saat dilimine çözülür).
  Atmosfer get resolved {
    final sel = atmosferNotifier.value;
    if (sel != Atmosfer.auto) return sel;
    final h = DateTime.now().hour;
    return (h >= 21 || h < 7) ? Atmosfer.gece : Atmosfer.gunduz;
  }

  CobblestonePalette paletteFor(Atmosfer a) {
    switch (a) {
      case Atmosfer.gece:
        return gecePalette;
      case Atmosfer.gunduz:
        return gunduzPalette;
      case Atmosfer.orman:
        return ormanPalette;
      case Atmosfer.neon:
        return neonPalette;
      case Atmosfer.auto:
        return paletteFor(resolved);
    }
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    Atmosfer a;
    if (saved != null) {
      a = Atmosfer.values.firstWhere(
        (v) => v.name == saved,
        orElse: () => Atmosfer.auto,
      );
    } else {
      // Eski tercihten göç: day→gündüz, night→gece, yoksa auto.
      final legacy = prefs.getString(_legacyPrefsKey);
      a = switch (legacy) {
        'day' => Atmosfer.gunduz,
        'night' => Atmosfer.gece,
        _ => Atmosfer.auto,
      };
    }
    // Neon ve Orman seçenekleri kaldırıldı; eski kayıtlar Gece'ye taşınır.
    if (a == Atmosfer.neon || a == Atmosfer.orman) {
      a = Atmosfer.gece;
      await prefs.setString(_prefsKey, a.name);
    }
    atmosferNotifier.value = a;

    _lastResolved = resolved;
    paletteNotifier.value = paletteFor(_lastResolved);
    _syncLegacy();
    // Otomatik modda saat dilimi devrilince temayı kendiliğinden morph'la.
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(const Duration(minutes: 1), checkAutoRollover);
  }

  /// main.dart'ın dakikalık zamanlayıcısı da burayı çağırabilir.
  void checkAutoRollover([Timer? _]) {
    final r = resolved;
    if (r != _lastResolved) {
      _lastResolved = r;
      _morphTo(paletteFor(r));
      _syncLegacy();
    }
  }

  Future<void> setAtmosfer(Atmosfer a) async {
    if (a == atmosferNotifier.value) return;
    atmosferNotifier.value = a;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, a.name);
    _lastResolved = resolved;
    _morphTo(paletteFor(_lastResolved));
    _syncLegacy();
  }

  /// 600 ms'lik yumuşak palet geçişi.
  void _morphTo(CobblestonePalette target) {
    _morphTimer?.cancel();
    final from = paletteNotifier.value;
    const steps = 10;
    var i = 0;
    _morphTimer = Timer.periodic(const Duration(milliseconds: 40), (t) {
      i++;
      final v = (i / steps).clamp(0.0, 1.0).toDouble();
      paletteNotifier.value = CobblestonePalette.lerp(
        from,
        target,
        Curves.easeInOut.transform(v),
      );
      if (i >= steps) {
        paletteNotifier.value = target;
        t.cancel();
      }
    });
  }

  /// Eski API — yeni kullanımlar setAtmosfer'i çağırmalı.
  Future<void> setMode(ThemeMode3 m) => setAtmosfer(switch (m) {
    ThemeMode3.day => Atmosfer.gunduz,
    ThemeMode3.night => Atmosfer.gece,
    ThemeMode3.auto => Atmosfer.auto,
  });

  /// Durum çubuğu simgeleri hep koyu zemin üstünde: hepsi açık simge ister.
  bool computeIsNight() => true;

  void _syncLegacy() {
    modeNotifier.value = switch (resolved) {
      Atmosfer.gunduz => ThemeMode3.day,
      _ => ThemeMode3.night,
    };
  }
}

