import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// CairnID animasyonunun ve dokunma tepkisinin şiddeti. Sabit, sınırlı 4
/// seviye — kullanıcı serbest bir sayı giremez, sadece bunlardan birini seçer.
enum AnimLevel { off, calm, normal, lively }

extension AnimLevelTuning on AnimLevel {
  /// Boşta akan hareketin hız çarpanı (0 = donmuş; şarkıya özel sabit desen).
  double get speedFactor {
    switch (this) {
      case AnimLevel.off:
        return 0.0;
      case AnimLevel.calm:
        return 0.5;
      case AnimLevel.normal:
        return 1.0;
      case AnimLevel.lively:
        return 1.75;
    }
  }

  /// Çubukların salınım genişliği (çarpan).
  double get amplitude {
    switch (this) {
      case AnimLevel.off:
        return 0.85;
      case AnimLevel.calm:
        return 0.70;
      case AnimLevel.normal:
        return 0.95;
      case AnimLevel.lively:
        return 1.15;
    }
  }

  /// Parmağın çubukları en fazla kaç piksel dışa iteceği
  /// (240px kutu için ayarlı; farklı boyutlarda oranlanır).
  double get scatter {
    switch (this) {
      case AnimLevel.off:
        return 0.0;
      case AnimLevel.calm:
        return 10.0;
      case AnimLevel.normal:
        return 22.0;
      case AnimLevel.lively:
        return 38.0;
    }
  }

  /// Yay sönümü: düşük değer = bıraktıktan sonra daha uzun, "jölemsi" titreme.
  double get damping {
    switch (this) {
      case AnimLevel.off:
        return 14.0;
      case AnimLevel.calm:
        return 12.0;
      case AnimLevel.normal:
        return 9.0;
      case AnimLevel.lively:
        return 6.5;
    }
  }

  String get label {
    switch (this) {
      case AnimLevel.off:
        return 'Kapalı';
      case AnimLevel.calm:
        return 'Sakin';
      case AnimLevel.normal:
        return 'Normal';
      case AnimLevel.lively:
        return 'Canlı';
    }
  }
}

class AnimationLevelController {
  AnimationLevelController._();
  static final AnimationLevelController instance = AnimationLevelController._();

  final ValueNotifier<AnimLevel> levelNotifier = ValueNotifier(
    AnimLevel.normal,
  );
  static const _prefsKey = 'anim_level_v1';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt(_prefsKey);
    if (saved != null && saved >= 0 && saved < AnimLevel.values.length) {
      levelNotifier.value = AnimLevel.values[saved];
    }
  }

  Future<void> setLevel(AnimLevel level) async {
    levelNotifier.value = level;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKey, level.index);
  }
}

