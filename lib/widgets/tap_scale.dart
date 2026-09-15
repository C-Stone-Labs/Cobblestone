import 'package:flutter/material.dart';

/// v5.1.3: butonlara hafif dokunuş animasyonu — basılınca yüzde üç
/// küçülür, bırakınca yumuşakça geri döner. "Fark edilir ama fark
/// edildiği fark edilmez."
class TapScale extends StatefulWidget {
  const TapScale({super.key, required this.child});

  final Widget child;

  @override
  State<TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<TapScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) {
        if (mounted) setState(() => _down = true);
      },
      onPointerUp: (_) {
        if (mounted) setState(() => _down = false);
      },
      onPointerCancel: (_) {
        if (mounted) setState(() => _down = false);
      },
      child: AnimatedScale(
        scale: _down ? 0.965 : 1,
        duration: const Duration(milliseconds: 110),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}
