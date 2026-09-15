import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/palette.dart';
import '../services/theme_controller.dart';
import '../services/animation_level_controller.dart';

/// Dokunma zerreleri için ortak hafıza. Tek örnek; her katman aynı
/// zerrecikleri (ekran-oranlı konum + doğum anı) okur.
class AmbientPoke {
  final Offset frac; // 0..1 ekran oranı
  final int bornMs;
  const AmbientPoke(this.frac, this.bornMs);
}

class AmbientFx {
  AmbientFx._();
  static final AmbientFx instance = AmbientFx._();

  static const _maxPokes = 12;
  final List<AmbientPoke> pokes = [];
  final ValueNotifier<int> tick = ValueNotifier(0);

  void poke(Offset frac) {
    if (pokes.length >= _maxPokes) pokes.removeAt(0);
    pokes.add(AmbientPoke(frac, DateTime.now().millisecondsSinceEpoch));
    tick.value++;
  }
}

/// Atmosfer katmanı: içeriğin ARKASINA çizilen, temaya özel sessiz
/// hareketli arka plan + dokunuş zerreleri.
///
/// Kullanım: `AmbientLayer(palette: p, child: ...)` — child aynen kalır,
/// katman altına çizer, dokunuşları yutmadan dinler.
///
/// Pil kuralları: 30 fps tavan; Hareket=Kapalı iken zaman donuk (statik
/// desen hiç yeniden çizilmez); uygulama arka plandayken ticker durur.
class AmbientLayer extends StatefulWidget {
  final CobblestonePalette palette;
  final Widget child;

  const AmbientLayer({super.key, required this.palette, required this.child});

  @override
  State<AmbientLayer> createState() => _AmbientLayerState();
}

class _AmbientLayerState extends State<AmbientLayer>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;
  final ValueNotifier<int> _repaint = ValueNotifier(0);
  Duration _last = Duration.zero;

  /// v5.1.3: PAYLAŞILAN zaman — tüm AmbientLayer'lar aynı fazda çizer.
  /// Ekran üstüne ekran gelip dönerken tema "sıçraması" bitti.
  static double _time = 0;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AmbientFx.instance.tick.addListener(_bump);
    _ticker = createTicker(_onTick);
    // v5.1.3: ticker başlangıçta ÇALIŞIR — eskiden yalnızca uygulama
    // arka plana gidip dönünce başlıyordu; soğuk açılışta tema donuk
    // kalıyordu ("bazen animasyon donuyor" bundandı).
    _ticker.start();
  }

  void _bump() => _repaint.value++;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final nowPaused = state != AppLifecycleState.resumed;
    if (nowPaused == _paused) return;
    _paused = nowPaused;
    if (_paused) {
      _ticker.stop();
    } else {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    final level = AnimationLevelController.instance.levelNotifier.value;
    if (level == AnimLevel.off) return; // zaman donuk: statik desen
    // Kare hızını ~30fps'e sınırla: 120Hz ekranlarda her v-sync'te tüm
    // ekranı yeniden rasterize etmek arayüzü kilitliyordu.
    if (_last != Duration.zero && (elapsed - _last).inMicroseconds < 30000) {
      return;
    }
    final dt = (_last == Duration.zero)
        ? 0.033
        : ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.066).toDouble();
    _last = elapsed;
    _time += dt * level.speedFactor;
    _repaint.value++;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AmbientFx.instance.tick.removeListener(_bump);
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Atmosfer>(
      valueListenable: ThemeController.instance.atmosferNotifier,
      builder: (context, _, _) {
        return ValueListenableBuilder<AnimLevel>(
          valueListenable: AnimationLevelController.instance.levelNotifier,
          builder: (context, level, _) {
            final style = ThemeController.instance.resolved;
            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _AmbientPainter(
                      style: style,
                      palette: widget.palette,
                      level: level,
                      time: () => _time,
                      repaint: _repaint,
                    ),
                  ),
                ),
                Material(color: Colors.transparent, child: widget.child),
              ],
            );
          },
        );
      },
    );
  }
}

class _AmbientPainter extends CustomPainter {
  _AmbientPainter({
    required this.style,
    required this.palette,
    required this.level,
    required this.time,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final Atmosfer style;
  final CobblestonePalette palette;
  final AnimLevel level;
  final double Function() time;

  // Küçük deterministik RNG (yerel, çakışmasız).
  double _hash(int i, int salt) {
    var h = (i * 374761393 + salt * 668265263) & 0x7FFFFFFF;
    h = (h * 1103515245 + 12345) & 0x7FFFFFFF;
    return h / 0x7FFFFFFF;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = time();
    final w = size.width, h = size.height;
    switch (style) {
      case Atmosfer.gece:
        _aurora(canvas, w, h, t);
        break;
      case Atmosfer.gunduz:
        _water(canvas, w, h, t);
        break;
      case Atmosfer.orman:
        _forest(canvas, w, h, t);
        break;
      case Atmosfer.neon:
        _neon(canvas, w, h, t);
        break;
      case Atmosfer.auto:
        break; // auto hiçbir zaman çözülmeden kalmaz
    }
    _pokes(canvas, w, h);
  }

  // 🌌 Gece: süzülen aurora şeritleri + seyrek yıldız.
  void _aurora(Canvas canvas, double w, double h, double t) {
    for (var k = 0; k < 2; k++) {
      final base = h * (0.18 + 0.22 * k);
      final sp = 0.10 + 0.05 * k;
      final ph = k * 2.1;
      final path = Path()..moveTo(-40, base);
      for (var i = 0; i <= 24; i++) {
        final x = -40 + (w + 80) * (i / 24);
        final y =
            base +
            math.sin((i / 24) * math.pi * 2 * 1.2 + t * sp * 2 * math.pi + ph) *
                h *
                0.045;
        path.lineTo(x, y);
      }
      final col = k == 0
          ? palette.accent2
          : Color.lerp(palette.accent2, palette.orange, 0.4)!;
      // Ağır MaskFilter blur yerine katmanlı yumuşak çizgi (aynı yumuşak
      // görünüm, çok düşük raster maliyeti).
      for (final l in <List<double>>[
        [h * 0.16, 0.012],
        [h * 0.10, 0.024],
        [h * 0.05, 0.045],
      ]) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = l[0]
            ..strokeCap = StrokeCap.round
            ..color = col.withValues(alpha: l[1]),
        );
      }
    }
    for (var i = 0; i < 20; i++) {
      final fx = _hash(i, 7), fy = _hash(i, 13);
      final tw =
          0.5 + 0.5 * math.sin(t * (0.4 + _hash(i, 3)) * 2 * math.pi + i);
      canvas.drawCircle(
        Offset(fx * w, fy * h),
        0.9 + _hash(i, 5) * 1.1,
        Paint()
          ..color = (i.isEven ? palette.orangeLight : Colors.white).withValues(alpha: (0.05 + 0.10 * tw) * 0.55,),
      );
    }
  }

  // ☀️ Gündüz: kayan ışık huzmesi + ince su dalgaları.
  void _water(Canvas canvas, double w, double h, double t) {
    final sweep = ((t * 0.06) % 1.4) - 0.2; // -0.2 .. 1.2
    final cx = sweep * w;
    canvas.save();
    canvas.translate(cx, h * 0.5);
    canvas.rotate(-0.30);
    canvas.drawRect(
      Rect.fromCenter(center: Offset.zero, width: w * 0.22, height: h * 2.2),
      Paint()
        ..shader =
            LinearGradient(
              colors: [
                palette.accent3.withValues(alpha: 0.0),
                palette.accent3.withValues(alpha: 0.05),
                palette.accent3.withValues(alpha: 0.0),
              ],
            ).createShader(
              Rect.fromCenter(
                center: Offset.zero,
                width: w * 0.22,
                height: h * 2.2,
              ),
            ),
    );
    canvas.restore();

    for (var k = 0; k < 3; k++) {
      final y0 = h * (0.42 + 0.18 * k);
      final sp = 0.08 + 0.04 * k;
      final path = Path()..moveTo(-20, y0);
      for (var i = 0; i <= 28; i++) {
        final x = -20 + (w + 40) * (i / 28);
        final y =
            y0 +
            math.sin(
                  (i / 28) * math.pi * 2 * 1.6 + t * sp * 2 * math.pi + k * 1.7,
                ) *
                7;
        path.lineTo(x, y);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..color = palette.accent2.withValues(alpha: 0.08),
      );
    }
  }

  // 🍃 Orman: süzülen yaprak salkımları + çiy parıltısı.
  void _forest(Canvas canvas, double w, double h, double t) {
    for (var k = 0; k < 3; k++) {
      final y0 = h * (0.22 + 0.26 * k);
      final sp = 0.06 + 0.03 * k;
      final drift = (t * sp) % 1.0;
      final path = Path();
      for (var i = 0; i <= 30; i++) {
        final x = -w * 0.2 + (w * 1.4) * ((i / 30 + drift) % 1.0);
        final y =
            y0 +
            math.sin(
                  (i / 30) * math.pi * 2 * 2.2 + t * sp * 2 * math.pi + k * 2.3,
                ) *
                h *
                0.035;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      final col = k == 1 ? palette.accent3 : palette.accent2;
      for (final l in <List<double>>[
        [18, 0.014],
        [9, 0.028],
        [4.5, 0.050],
      ]) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = l[0]
            ..strokeCap = StrokeCap.round
            ..color = col.withValues(alpha: l[1]),
        );
      }
    }
    for (var i = 0; i < 12; i++) {
      final fx = _hash(i, 21), fy = _hash(i, 27);
      final tw =
          0.5 + 0.5 * math.sin(t * (0.3 + _hash(i, 31)) * 2 * math.pi + i * 2);
      canvas.drawCircle(
        Offset(fx * w, fy * h),
        1.0 + _hash(i, 33) * 0.9,
        Paint()
          ..color = palette.orangeLight.withValues(alpha: (0.04 + 0.09 * tw) * 0.6),
      );
    }
  }

  // ⚡ Neon: kenarlarda mor/mavi buğu.
  void _neon(Canvas canvas, double w, double h, double t) {
    final pulse = level == AnimLevel.lively
        ? (0.85 + 0.15 * math.sin(t * 2 * math.pi * 0.7))
        : 1.0;
    canvas.drawCircle(
      Offset(w * 0.12, h * 0.10),
      w * 0.65,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                palette.orange.withValues(alpha: (0.05 * pulse).clamp(0.0, 1.0)),
                palette.orange.withValues(alpha: 0.0),
              ],
            ).createShader(
              Rect.fromCircle(
                center: Offset(w * 0.12, h * 0.10),
                radius: w * 0.65,
              ),
            ),
    );
    canvas.drawCircle(
      Offset(w * 0.92, h * 0.94),
      w * 0.7,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                palette.orangeLight.withValues(alpha: (0.045 * pulse).clamp(0.0, 1.0),),
                palette.orangeLight.withValues(alpha: 0.0),
              ],
            ).createShader(
              Rect.fromCircle(
                center: Offset(w * 0.92, h * 0.94),
                radius: w * 0.7,
              ),
            ),
    );
  }

  // Dokunuş zerreleri — temaya göre şekil değiştirir.
  void _pokes(Canvas canvas, double w, double h) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final list = List<AmbientPoke>.from(AmbientFx.instance.pokes);
    for (final p in list) {
      final age = (now - p.bornMs) / 1000.0;
      final origin = Offset(p.frac.dx * w, p.frac.dy * h);
      switch (style) {
        case Atmosfer.gece:
          // yıldız tozu: dışa saçılan zerreler
          if (age > 0.8) break;
          for (var i = 0; i < 6; i++) {
            final a = (i / 6) * math.pi * 2 + _hash(i, p.bornMs & 0xFFFF);
            final d = 12 + 46 * Curves.easeOut.transform(age / 0.8);
            final pos = origin + Offset(math.cos(a), math.sin(a)) * d;
            final al = (1 - age / 0.8) * 0.65;
            canvas.drawCircle(
              pos,
              1.8,
              Paint()..color = palette.orangeLight.withValues(alpha: al),
            );
          }
          break;
        case Atmosfer.gunduz:
          // su halkaları
          if (age > 0.9) break;
          for (var k = 0; k < 2; k++) {
            final pr = ((age - k * 0.12).clamp(0.0, 0.9)) / 0.9;
            if (pr <= 0) continue;
            canvas.drawCircle(
              origin,
              8 + 66 * Curves.easeOut.transform(pr),
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.8
                ..color = palette.accent2.withValues(alpha: (1 - pr) * 0.30),
            );
          }
          break;
        case Atmosfer.orman:
          // süzülen yaprak zerrecikleri
          if (age > 0.9) break;
          for (var i = 0; i < 5; i++) {
            final ph = _hash(i, p.bornMs & 0xFFFF) * math.pi * 2;
            final sway = math.sin(age * 6 + ph) * 10;
            final pos = origin + Offset(-18 + i * 9 + sway, 6 + age * 52);
            final al = (1 - age / 0.9) * 0.55;
            canvas.drawCircle(
              pos,
              2.0,
              Paint()
                ..color = (i.isEven ? palette.orangeLight : palette.accent3)
                    .withValues(alpha: al),
            );
          }
          break;
        case Atmosfer.neon:
          // kısa kıvılcım
          if (age > 0.45) break;
          final pr = age / 0.45;
          canvas.drawCircle(
            origin,
            6 + 40 * Curves.easeOut.transform(pr),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.0
              ..color = palette.accent3.withValues(alpha: (1 - pr) * 0.5),
          );
          for (var i = 0; i < 8; i++) {
            final a = (i / 8) * math.pi * 2;
            final pos =
                origin + Offset(math.cos(a), math.sin(a)) * (6 + 30 * pr);
            canvas.drawCircle(
              pos,
              1.4,
              Paint()..color = palette.orangeLight.withValues(alpha: (1 - pr) * 0.7),
            );
          }
          break;
        case Atmosfer.auto:
          break;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AmbientPainter oldDelegate) => true;
}

