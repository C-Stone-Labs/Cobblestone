import 'package:flutter/material.dart';
import '../theme/palette.dart';
import '../widgets/cobble_logo.dart';

class SplashScreen extends StatelessWidget {
  final CobblestonePalette palette;
  final VoidCallback? onDone;
  const SplashScreen({super.key, required this.palette, this.onDone});

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      color: p.bg,
      child: Center(
        child: AnimatedCobbleLogo(
          size: 120,
          onIntroDone: onDone,
        ),
      ),
    );
  }
}

