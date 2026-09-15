import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../theme/palette.dart';
import '../services/animation_level_controller.dart';
import '../services/theme_controller.dart';

/// SDK sürümünden bağımsız, aynı girdi için her zaman aynı çıktıyı üreten
/// basit metin özeti (djb2 varyantı).
int stableSeedHash(String s) {
  int hash = 5381;
  for (final unit in s.codeUnits) {
    hash = ((hash * 33) + unit) & 0x7FFFFFFF;
  }
  return hash;
}

/// Deterministik sözde-rastgele üreteç (LCG).
class _Rng {
  _Rng(int seed) : _s = seed & 0x7FFFFFFF;
  int _s;
  int next() {
    _s = (_s * 1103515245 + 12345) & 0x7FFFFFFF;
    return _s;
  }

  double nextDouble() => next() / 0x7FFFFFFF;
}

/// Nabız köprüsü (Paket-11): RhythmController bu değerleri besler.
/// `cairnRhythmOn` kapalıyken CairnID bugünkü klasik davranışını BİREBİR
/// sürdürür (dokunuş + rastgele canlılık); açıkken müziğin enerjisi nefes
/// alma şiddetini ve parlaklığı sürer.
bool cairnRhythmOn = false;
double cairnRhythmLevel = 0; // 0..1 toplam yoğunluk (yumuşatılmış)
double cairnRhythmBass = 0; // 0..1 bas ağırlığı (yumuşatılmış)

/// Şarkının CairnID kimliği. Aynı şarkı her zaman aynı görünümü üretir.
class _CairnSpec {
  _CairnSpec({
    required this.colors,
    required this.barCount,
    required this.tempo,
    required this.spin,
    required this.phaseA,
    required this.freqA,
    required this.phaseB,
    required this.freqB,
    required this.bright,
  });

  final List<Color> colors; // temadan beslenen tonlar
  final int barCount;
  final double tempo;
  final double spin;
  final List<double> phaseA, freqA, phaseB, freqB, bright;
}

_CairnSpec _deriveSpec(String seed, CobblestonePalette p) {
  final rng = _Rng(stableSeedHash(seed));
  final tones = <Color>[
    p.orange,
    p.orangeLight,
    p.accent2,
    Color.lerp(p.orange, p.orangeLight, 0.5)!,
    Color.lerp(p.accent2, p.orangeLight, 0.4)!,
  ];
  Color pick() => tones[rng.next() % tones.length];

  final n = 56 + rng.next() % 21; // 56..76 temel örnek
  List<double> fill(double Function() f) =>
      List<double>.generate(n, (_) => f());

  return _CairnSpec(
    colors: [pick(), pick(), pick()],
    barCount: n,
    tempo: 0.7 + rng.nextDouble() * 0.5,
    spin: (0.05 + rng.nextDouble() * 0.12) * (rng.next().isEven ? 1.0 : -1.0),
    phaseA: fill(() => rng.nextDouble() * math.pi * 2),
    freqA: fill(() => 0.9 + rng.nextDouble() * 1.6),
    phaseB: fill(() => rng.nextDouble() * math.pi * 2),
    freqB: fill(() => 2.2 + rng.nextDouble() * 2.4),
    bright: fill(() => 0.75 + rng.nextDouble() * 0.35),
  );
}

/// Canlı simülasyon durumu (tüm stiller ortak kullanır).
class _CairnSim {
  _CairnSim(this.spec)
    : disp = List<double>.filled(spec.barCount, 0),
      vel = List<double>.filled(spec.barCount, 0);

  final _CairnSpec spec;
  final List<double> disp;
  final List<double> vel;
  double time = 0;
  double touchAngle = 0;
  double touchPower = 0;
}

double _angDist(double a, double b) {
  var d = (a - b) % (math.pi * 2);
  if (d > math.pi) d -= math.pi * 2;
  if (d < -math.pi) d += math.pi * 2;
  return d.abs();
}

/// CairnID — albüm kapağı alanındaki etkileşimli görsel kimlik.
///
/// Stil, atmosfer temasından otomatik gelir:
/// • Gece    → plazma şeritleri (aurora)
/// • Gündüz  → eşmerkezli su halkaları
/// • Orman   → süzülen yaprak salkımları
/// • Neon    → klasik ekolayzer halkası + kuyrukluyıldızlar
/// Dokunma fiziği (yay, dürtü, sönüm) hepsinde aynı; şiddet Ayarlar'dan.
class CairnId extends StatefulWidget {
  final String seed;
  final CobblestonePalette palette;
  final double size;
  final bool playing;

  const CairnId({
    super.key,
    required this.seed,
    required this.palette,
    this.size = 240,
    this.playing = true,
  });

  @override
  State<CairnId> createState() => _CairnIdState();
}

class _CairnIdState extends State<CairnId> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<int> _frame = ValueNotifier(0);

  late _CairnSim _sim;
  Duration _lastTick = Duration.zero;
  bool _touching = false;

  @override
  void initState() {
    super.initState();
    _sim = _CairnSim(_deriveSpec(widget.seed, widget.palette));
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(covariant CairnId oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seed != widget.seed) {
      _sim = _CairnSim(_deriveSpec(widget.seed, widget.palette));
      _lastTick = Duration.zero;
    } else if (oldWidget.palette != widget.palette) {
      // Tema morph'u sırasında fizik sıfırlanmasın; sadece renkler yerinde
      // değişsin (yumuşak geçişle uyumlu).
      final c = _deriveSpec(widget.seed, widget.palette).colors;
      for (var i = 0; i < 3 && i < c.length; i++) {
        _sim.spec.colors[i] = c[i];
      }
    }
  }

  void _onTick(Duration elapsed) {
    if (_lastTick != Duration.zero &&
        (elapsed - _lastTick).inMicroseconds < 33333) {
      return;
    }

    final dt = (_lastTick == Duration.zero)
        ? 0.033
        : ((elapsed - _lastTick).inMicroseconds / 1e6)
              .clamp(0.0, 0.05)
              .toDouble();
    _lastTick = elapsed;

    final level = AnimationLevelController.instance.levelNotifier.value;
    // Nabız açık + çalıyorken nefes müziğin enerjisiyle atar; nabız
    // kapalıyken eski sabit oran geçerli (birebir klasik davranış).
    final playBoost = widget.playing
        ? (cairnRhythmOn
              ? (0.78 + cairnRhythmLevel * 1.35 + cairnRhythmBass * 0.25)
              : 1.0)
        : 0.3;

    _sim.time += dt * level.speedFactor * playBoost * _sim.spec.tempo;
    _sim.touchPower +=
        ((_touching ? 1.0 : 0.0) - _sim.touchPower) *
        (dt * 9).clamp(0.0, 1.0).toDouble();

    const k = 110.0;
    final c = level.damping;
    final scale = widget.size / 240.0;
    final scatter = level.scatter * scale * _sim.touchPower;
    final rot = _sim.time * _sim.spec.spin;
    const sigma = 0.55;

    for (var i = 0; i < _sim.spec.barCount; i++) {
      var target = 0.0;
      if (scatter > 0.01) {
        final a = (i / _sim.spec.barCount) * math.pi * 2 + rot;
        final d = _angDist(a, _sim.touchAngle);
        target = scatter * math.exp(-(d * d) / (2 * sigma * sigma));
      }
      _sim.vel[i] += (k * (target - _sim.disp[i]) - c * _sim.vel[i]) * dt;
      _sim.disp[i] += _sim.vel[i] * dt;
    }

    _frame.value++;
  }

  void _updateTouch(Offset local) {
    final center = Offset(widget.size / 2, widget.size / 2);
    final d = local - center;
    if (d.distanceSquared < 4) return;
    _sim.touchAngle = math.atan2(d.dy, d.dx);
  }

  void _poke(Offset local) {
    _updateTouch(local);
    final scale = widget.size / 240.0;
    final rot = _sim.time * _sim.spec.spin;
    const sigma = 0.55;
    for (var i = 0; i < _sim.spec.barCount; i++) {
      final a = (i / _sim.spec.barCount) * math.pi * 2 + rot;
      final d = _angDist(a, _sim.touchAngle);
      _sim.vel[i] += 95 * scale * math.exp(-(d * d) / (2 * sigma * sigma));
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'CairnID',
      child: ValueListenableBuilder<Atmosfer>(
        valueListenable: ThemeController.instance.atmosferNotifier,
        builder: (context, _, _) {
          return ValueListenableBuilder<AnimLevel>(
            valueListenable: AnimationLevelController.instance.levelNotifier,
            builder: (context, level, _) {
              return SizedBox(
                width: widget.size,
                height: widget.size,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) {
                    _touching = true;
                    _poke(e.localPosition);
                    HapticFeedback.lightImpact();
                  },
                  onPointerMove: (e) => _updateTouch(e.localPosition),
                  onPointerUp: (_) => _touching = false,
                  onPointerCancel: (_) => _touching = false,
                  child: CustomPaint(
                    painter: _CairnPainter(
                      sim: _sim,
                      palette: widget.palette,
                      playing: widget.playing,
                      level: level,
                      style: ThemeController.instance.resolved,
                      repaint: _frame,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _CairnPainter extends CustomPainter {
  _CairnPainter({
    required this.sim,
    required this.palette,
    required this.playing,
    required this.level,
    required this.style,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final _CairnSim sim;
  final CobblestonePalette palette;
  final bool playing;
  final AnimLevel level;
  final Atmosfer style;

  Color _lerp3(double t) {
    final c = sim.spec.colors;
    if (t < 0.5) return Color.lerp(c[0], c[1], t * 2)!;
    return Color.lerp(c[1], c[2], (t - 0.5) * 2)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r0 = size.width * 0.30;
    final outer = size.width * 0.5 - size.width * 0.04;
    final maxBar = outer - r0;
    final base4 = playing ? 1.0 : 0.55;
    final dim = playing && cairnRhythmOn
        ? (base4 * (0.72 + cairnRhythmLevel * 0.4)).clamp(0.0, 1.0)
        : base4;

    switch (style) {
      case Atmosfer.gunduz:
        _paintRipples(canvas, center, r0, maxBar, dim);
        break;
      case Atmosfer.orman:
        _paintVines(canvas, size, center, r0, maxBar, dim);
        break;
      case Atmosfer.gece:
        _paintPlasma(canvas, center, r0, maxBar, dim);
        break;
      case Atmosfer.neon:
      case Atmosfer.auto:
        _paintBars(canvas, size, center, r0, maxBar, dim);
        break;
    }
  }

  /// ⚡ Neon: klasik çubuk halkası + çekirdek uçlar + kuyrukluyıldızlar.
  void _paintBars(
    Canvas canvas,
    Size size,
    Offset center,
    double r0,
    double maxBar,
    double dim,
  ) {
    final spec = sim.spec;
    final rot = sim.time * spec.spin;
    final count = spec.barCount;
    final double stroke = math.max(2.0, (2 * math.pi * r0 / count) * 0.55);
    final amp = level.amplitude;
    const sigma = 0.55;

    canvas.drawCircle(
      center,
      r0,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = palette.mute.withValues(alpha: (0.10 * dim).clamp(0.0, 1.0).toDouble(),),
    );

    for (var i = 0; i < count; i++) {
      final t = sim.time;
      final osc =
          0.5 +
          0.5 * math.sin(spec.freqA[i] * t + spec.phaseA[i]) +
          0.30 * math.sin(spec.freqB[i] * t + spec.phaseB[i]);
      final v = (osc / 1.8).clamp(0.0, 1.0).toDouble();

      final fill = (0.16 + 0.84 * v * amp).clamp(0.10, 1.0).toDouble();
      var len = maxBar * fill;
      len += sim.disp[i].clamp(-maxBar * 0.3, maxBar * 0.8).toDouble();
      if (len < 2.0) len = 2.0;

      final ang = (i / count) * math.pi * 2 + rot;
      final d = _angDist(ang, sim.touchAngle);
      final w = sim.touchPower * math.exp(-(d * d) / (2 * sigma * sigma));
      final skew = w * math.sin(sim.touchAngle - ang) * 0.5;

      final dirAng = ang + skew;
      final dir = Offset(math.cos(dirAng), math.sin(dirAng));
      final base = center + Offset(math.cos(ang), math.sin(ang)) * r0;
      final tip = base + dir * len;

      final color = _lerp3(v);
      // neon titremesi
      final flick = 0.9 + 0.1 * math.sin(t * 11 + i * 3.7);
      final alpha = (0.92 * dim * spec.bright[i] * flick)
          .clamp(0.0, 1.0)
          .toDouble();

      if (palette.neonGlow) {
        canvas.drawLine(
          base,
          tip,
          Paint()
            ..strokeCap = StrokeCap.round
            ..strokeWidth = stroke * 2.4
            ..color = color.withValues(alpha: (alpha * 0.22).clamp(0.0, 1.0).toDouble(),),
        );
      }
      canvas.drawLine(
        base,
        tip,
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = stroke
          ..color = color.withValues(alpha: alpha),
      );
      canvas.drawCircle(
        tip,
        stroke * 0.58,
        Paint()
          ..color = Color.lerp(
            color,
            Colors.white,
            0.40,
          )!.withValues(alpha: (alpha * 0.85).clamp(0.0, 1.0).toDouble()),
      );
    }

    if (level != AnimLevel.off) {
      for (var k = 0; k < 4; k++) {
        final dirS = (k.isEven) ? 1.0 : -1.0;
        final speed = 0.10 + 0.045 * k;
        final a0 = sim.time * dirS * speed + k * (math.pi / 2);
        final rr = r0 + maxBar * 0.60;
        const len = 0.9;
        final rect = Rect.fromCircle(center: center, radius: rr);
        canvas.drawArc(
          rect,
          a0 - len,
          len,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4
            ..strokeCap = StrokeCap.round
            ..shader = SweepGradient(
              startAngle: a0 - len,
              endAngle: a0,
              colors: [
                palette.orangeLight.withValues(alpha: 0.0),
                palette.orangeLight.withValues(alpha: (0.50 * dim).clamp(0.0, 1.0).toDouble(),),
              ],
            ).createShader(rect),
        );
        final head = center + Offset(math.cos(a0), math.sin(a0)) * rr;
        canvas.drawCircle(
          head,
          3.4,
          Paint()
            ..color = palette.orangeLight.withValues(alpha: (0.26 * dim).clamp(0.0, 1.0).toDouble(),),
        );
        canvas.drawCircle(
          head,
          1.5,
          Paint()
            ..color = Colors.white.withValues(alpha: (0.55 * dim).clamp(0.0, 1.0).toDouble(),),
        );
      }
    }
  }

  /// 🌌 Gece: iki plazma şeridi (aurora akışı).
  void _paintPlasma(
    Canvas canvas,
    Offset center,
    double r0,
    double maxBar,
    double dim,
  ) {
    final spec = sim.spec;
    final count = spec.barCount;
    final rot = sim.time * spec.spin;
    final amp = level.amplitude;
    final t = sim.time;

    // Merkez çekirdek
    canvas.drawCircle(
      center,
      r0 * 0.55,
      Paint()
        ..shader = RadialGradient(
          colors: [
            palette.accent2.withValues(alpha: (0.22 * dim).clamp(0.0, 1.0).toDouble(),),
            palette.accent2.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: r0 * 0.55)),
    );

    for (var r = 0; r < 2; r++) {
      final path = Path();
      final baseR = r0 * 1.05 + r * maxBar * 0.42;
      for (var i = 0; i <= 96; i++) {
        final ang = (i / 96) * math.pi * 2;
        final bi = ((i / 96) * (count - 1)).floor().clamp(0, count - 1);
        final osc =
            0.5 +
            0.5 *
                math.sin(
                  spec.freqA[bi] * (0.8 + r * 0.5) * t +
                      spec.phaseA[bi] +
                      r * 2.1,
                );
        final wob = 6 + amp * 10;
        final rr =
            baseR +
            (osc - 0.5) * 2 * wob +
            sim.disp[bi].clamp(-maxBar * 0.3, maxBar * 0.8).toDouble();
        final pt =
            center + Offset(math.cos(ang + rot), math.sin(ang + rot)) * rr;
        if (i == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      path.close();

      final col = r == 0 ? palette.orange : palette.accent2;
      final aBase = r == 0 ? 0.85 : 0.50;
      // önce blur'lu parlama, sonra keskin hat
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6.5
          ..strokeCap = StrokeCap.round
          ..color = col.withValues(alpha: (aBase * 0.35 * dim).clamp(0.0, 1.0).toDouble(),)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round
          ..color = Color.lerp(
            col,
            Colors.white,
            0.25,
          )!.withValues(alpha: (aBase * dim).clamp(0.0, 1.0).toDouble()),
      );
    }
  }

  /// ☀️ Gündüz: merkezden yayılan eşmerkezli su halkaları.
  void _paintRipples(
    Canvas canvas,
    Offset center,
    double r0,
    double maxBar,
    double dim,
  ) {
    final t = sim.time;
    final amp = level.amplitude;

    // Duruluk: ortada çok hafif su dolgusu
    canvas.drawCircle(
      center,
      r0 * 0.9,
      Paint()
        ..color = palette.accent2.withValues(alpha: (0.06 * dim).clamp(0.0, 1.0).toDouble(),),
    );

    for (var k = 0; k < 4; k++) {
      final phase = t * 0.55 + k * 1.35;
      final pulse = 0.5 + 0.5 * math.sin(phase);
      final touchPush = sim.touchPower * 10 * (k + 1) / 4;
      var rr = r0 * 0.35 + (maxBar * 0.30) * k + pulse * 7 * amp + touchPush;
      rr = rr.clamp(6.0, r0 + maxBar).toDouble();

      final bi = ((k / 4) * (sim.spec.barCount - 1)).floor().clamp(
        0,
        sim.spec.barCount - 1,
      );
      final extra = sim.disp[bi].clamp(0.0, maxBar * 0.5);
      final col = k.isEven ? palette.accent2 : palette.orange;
      final alpha = ((0.85 - k * 0.16) * dim).clamp(0.0, 1.0).toDouble();

      if (palette.neonGlow) {
        canvas.drawCircle(
          center,
          rr + extra * 0.4,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5.5
            ..color = col.withValues(alpha: (alpha * 0.18).clamp(0.0, 1.0).toDouble())
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      }
      canvas.drawCircle(
        center,
        rr + extra * 0.4,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = col.withValues(alpha: alpha),
      );
    }
  }

  /// 🍃 Orman: yaprak salkımları (daire içinde süzülen eğriler).
  void _paintVines(
    Canvas canvas,
    Size size,
    Offset center,
    double r0,
    double maxBar,
    double dim,
  ) {
    final spec = sim.spec;
    final t = sim.time;
    final amp = level.amplitude;
    final R = r0 + maxBar * 0.95;

    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: center, radius: R)),
    );

    for (var k = 0; k < 3; k++) {
      final y0 = center.dy + (k - 1) * maxBar * 0.62;
      final col = Color.lerp(palette.orange, palette.accent3, k / 2)!;
      final path = Path();
      for (var i = 0; i <= 44; i++) {
        final fx = i / 44.0;
        final x = center.dx - R + fx * 2 * R;
        final bi = (fx * (spec.barCount - 1)).floor().clamp(
          0,
          spec.barCount - 1,
        );
        final osc = math.sin(fx * math.pi * 3 + t * (0.7 + k * 0.35) + k * 2.0);
        final y =
            y0 +
            osc * (5 + amp * 7) +
            sim.disp[bi].clamp(-maxBar * 0.2, maxBar * 0.4).toDouble() * 0.35;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      final alpha = ((0.8 - k * 0.18) * dim).clamp(0.0, 1.0).toDouble();
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.5
          ..strokeCap = StrokeCap.round
          ..color = col.withValues(alpha: (alpha * 0.30).clamp(0.0, 1.0).toDouble())
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round
          ..color = Color.lerp(col, Colors.white, 0.2)!.withValues(alpha: alpha),
      );
    }

    // Çiy taneleri: orta salkım üstünde ışıldayan noktalar
    for (var i = 0; i < 8; i++) {
      final fx = (i + 0.5) / 8;
      final x = center.dx - R + fx * 2 * R;
      final y = center.dy + math.sin(fx * math.pi * 3 + t * 0.8 + i) * 5 - 6;
      final tw = 0.5 + 0.5 * math.sin(t * 1.7 + i * 2.3);
      canvas.drawCircle(
        Offset(x, y),
        1.7,
        Paint()
          ..color = palette.accent3.withValues(alpha: ((0.3 + 0.6 * tw) * dim).clamp(0.0, 1.0).toDouble(),),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CairnPainter oldDelegate) => true;
}

