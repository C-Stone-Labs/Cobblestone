import 'package:flutter/material.dart';

/// v5.1.3: uygulama genelinde hareket ve şekil dizgesi (design tokens).
/// Amaç: her animasyon ve köşe "tek elden" çıksın — 15 farklı süre ve
/// 11 farklı yarıçap yerine küçük, tutarlı bir ölçek.
///
/// Süreler: fast (mikro), normal (standart geçiş), slow (vurgulu).
/// (Zamanlayıcılar — marquee tick, toast bekleme — bu dizgeye girmez.)
abstract final class CobbleMotion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 400);
}

/// Köşeler: small (rozet/mini görsel), card (kart/kutu/düğme),
/// sheet (alt sayfa/diyalog).
abstract final class CobbleRadii {
  static const double small = 8;
  static const double card = 16;
  static const double sheet = 20;
}
