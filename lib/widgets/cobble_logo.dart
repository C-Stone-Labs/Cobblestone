import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Seçilen uygulama logosu (L): turuncu C, play, nota.
class CobbleLogo extends StatelessWidget {
  final double size;
  const CobbleLogo({super.key, this.size = 26});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.asset(
        'assets/icon/logo.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

class AnimatedCobbleLogo extends StatefulWidget {
  final double size;
  final VoidCallback? onIntroDone;
  const AnimatedCobbleLogo({super.key, this.size = 160, this.onIntroDone});

  @override
  State<AnimatedCobbleLogo> createState() => _AnimatedCobbleLogoState();
}

class _AnimatedCobbleLogoState extends State<AnimatedCobbleLogo>
    with TickerProviderStateMixin {
  late final AnimationController _intro;
  late final AnimationController _breath;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) {
          _breath.repeat();
          widget.onIntroDone?.call();
        }
      })
      ..forward();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
  }

  @override
  void dispose() {
    _intro.dispose();
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_intro, _breath]),
      builder: (context, _) {
        final t = Curves.easeOutBack.transform(_intro.value.clamp(0.0, 1.0));
        final breath = 1.0 + 0.018 * math.sin(_breath.value * 2 * math.pi);
        final scale = (0.86 + 0.14 * t) * breath;
        return Opacity(
          opacity: Curves.easeOut.transform(_intro.value).clamp(0.0, 1.0),
          child: Transform.scale(
            scale: scale.clamp(0.7, 1.08),
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.size * 0.22),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF6B00).withValues(alpha: 0.28),
                    blurRadius: widget.size * 0.18,
                    spreadRadius: 1,
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset(
                'assets/icon/logo.png',
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        );
      },
    );
  }
}
