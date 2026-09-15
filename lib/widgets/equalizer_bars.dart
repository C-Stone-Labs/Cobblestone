import 'package:flutter/material.dart';

class EqualizerBars extends StatefulWidget {
  final Color color;
  final bool animate;
  const EqualizerBars({super.key, required this.color, required this.animate});

  @override
  State<EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<EqualizerBars>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (i) {
      final c = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 350 + i * 120),
      );
      if (widget.animate) c.repeat(reverse: true);
      return c;
    });
  }

  @override
  void didUpdateWidget(covariant EqualizerBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate != oldWidget.animate) {
      for (final c in _controllers) {
        if (widget.animate) {
          c.repeat(reverse: true);
        } else {
          c.stop();
        }
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 18,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: _controllers.map((c) {
          return AnimatedBuilder(
            animation: c,
            builder: (context, child) {
              final value = widget.animate ? c.value : 0.25;
              return Container(
                width: 3.5,
                height: 5 + (value * 13),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            },
          );
        }).toList(),
      ),
    );
  }
}

