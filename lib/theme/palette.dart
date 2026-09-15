import 'package:flutter/material.dart';

/// Cobblestone renk paleti.
///
/// bg/bg2/card/cardBorder/mute/orange/orangeLight/neonGlow: uygulamanın
/// her yerinde kullanılan klasik alanlar (isimler korunur, arayüz dokunmaz).
/// accent2/accent3: atmosfer temalarının "ikinci sesi" — aurora laciverdi,
/// su mavisi, yaprak sarisi, elektrik mavisi gibi. Ambient katman ve
/// CairnID'in temalı stilleri bunlardan beslenir.
class CobblestonePalette {
  final Color bg;
  final Color bg2;
  final Color card;
  final Color cardBorder;
  final Color mute;
  final Color orange;
  final Color orangeLight;
  final bool neonGlow;
  final Color accent2;
  final Color accent3;

  const CobblestonePalette({
    required this.bg,
    required this.bg2,
    required this.card,
    required this.cardBorder,
    required this.mute,
    required this.orange,
    required this.orangeLight,
    required this.neonGlow,
    required this.accent2,
    required this.accent3,
  });

  /// Temalar arası yumuşak geçiş için renk interpolasyonu.
  /// neonGlow eşiği yarıda değişir.
  static CobblestonePalette lerp(
    CobblestonePalette a,
    CobblestonePalette b,
    double t,
  ) {
    return CobblestonePalette(
      bg: Color.lerp(a.bg, b.bg, t)!,
      bg2: Color.lerp(a.bg2, b.bg2, t)!,
      card: Color.lerp(a.card, b.card, t)!,
      cardBorder: Color.lerp(a.cardBorder, b.cardBorder, t)!,
      mute: Color.lerp(a.mute, b.mute, t)!,
      orange: Color.lerp(a.orange, b.orange, t)!,
      orangeLight: Color.lerp(a.orangeLight, b.orangeLight, t)!,
      neonGlow: t < 0.5 ? a.neonGlow : b.neonGlow,
      accent2: Color.lerp(a.accent2, b.accent2, t)!,
      accent3: Color.lerp(a.accent3, b.accent3, t)!,
    );
  }
}

/// 🌌 Gece (Aurora) — derin lacivert-siyah, kutup ışığı tohumları.
const gecePalette = CobblestonePalette(
  bg: Color(0xFF050505),
  bg2: Color(0xFF0A0A0A),
  card: Color(0xFF121212),
  cardBorder: Color(0xFF2A2A2A),
  mute: Color(0xFF9A9A9A),
  orange: Color(0xFFFF6B00),
  orangeLight: Color(0xFFFF9E42),
  neonGlow: true,
  accent2: Color(0xFF31508E), // aurora laciverdi
  accent3: Color(0xFF2A9D8F), // aurora camgöbeği ipucu
);

/// ☀️ Gündüz (Duru Su) — ferah, aydınlatılmış, sıcak kontrast.
/// Not: Uygulamanın metinleri beyaz tabanlı olduğundan gövde aydınlık ama
/// okunabilir koyulukta tutulur; su parıltısı açık renkle gelir.
const gunduzPalette = CobblestonePalette(
  bg: Color(0xFF2B251C),
  bg2: Color(0xFF372E22),
  card: Color(0xFF413729),
  cardBorder: Color(0xFF5A4B39),
  mute: Color(0xFFC9BCA7),
  orange: Color(0xFFFF8524),
  orangeLight: Color(0xFFFFC069),
  neonGlow: false,
  accent2: Color(0xFF63B7C9), // duru su
  accent3: Color(0xFFFFF0D0), // güneş beyazı
);

/// 🍃 Orman (Bio Flow) — koyu toprak omurga, yaprak yeşili aksan.
const ormanPalette = CobblestonePalette(
  bg: Color(0xFF10160E),
  bg2: Color(0xFF16200F),
  card: Color(0xFF1A2318),
  cardBorder: Color(0xFF2E3D28),
  mute: Color(0xFF93A288),
  orange: Color(0xFF8CC265), // yaprak
  orangeLight: Color(0xFFC9E27A), // açık yaprak / genç filiz
  neonGlow: true,
  accent2: Color(0xFF4E7A3A), // derin yaprak
  accent3: Color(0xFFE5C56B), // toprak sarisi ışık
);

/// ⚡ Neon — kapkara zemin, fosfor patlamaları.
const neonPalette = CobblestonePalette(
  bg: Color(0xFF060507),
  bg2: Color(0xFF0B0A11),
  card: Color(0xFF14111F),
  cardBorder: Color(0xFF2B2545),
  mute: Color(0xFF8E8AA8),
  orange: Color(0xFFB44DFF), // fosforlu mor
  orangeLight: Color(0xFF5AC8FF), // elektrik mavisi
  neonGlow: true,
  accent2: Color(0xFF7A3ED0),
  accent3: Color(0xFFFF6B00), // turuncu patlama noktası
);

/// Geriye dönük uyumluluk: eski adlar yeni temalara bağlanır.
/// (Eski "gündüz/ gece" kavramının yerini atmosferler aldı.)
const dayPalette = gunduzPalette;
const nightPalette = gecePalette;

List<BoxShadow> buildGlow(
  CobblestonePalette p,
  Color color, {
  double blur = 18,
  double spread = 0.5,
}) {
  if (!p.neonGlow) return const [];
  return [
    BoxShadow(
      color: color.withValues(alpha: 0.55),
      blurRadius: blur,
      spreadRadius: spread,
    ),
  ];
}

