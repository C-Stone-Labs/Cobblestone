import 'dart:async';

import 'package:flutter/material.dart';

/// v5.1.3: uzun şarkı adları kayar (marquee); sığan adlar sabit durur.
/// Modern çalar standardı: kesmek yerine akıştır.
/// v5.1.3 (2. sürüm): OverflowBox yerine SizedBox + Stack + Transform —
/// taşma durumunda patlaması imkânsız, deterministik yerleşim.
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final TextAlign? align;
  final double speedPerTick;

  const MarqueeText(
    this.text, {
    super.key,
    required this.style,
    this.align,
    this.speedPerTick = 0.55,
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  Timer? _timer;
  double _offset = 0;
  double _distance = -1;

  /// İki kopya arasındaki boşluk — döngü bu genişlikte kayar.
  static const double _gap = 36;

  @override
  void didUpdateWidget(covariant MarqueeText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      // ListView satır geri dönüşümü: yeni metin → kaydırmayı baştan başlat.
      _offset = 0;
      _distance = -1;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _offset = 0;
    _distance = -1;
  }

  void _start() {
    _timer ??= Timer.periodic(const Duration(milliseconds: 33), _tick);
  }

  void _tick(_) {
    if (!mounted) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    // v5.1.3: kesintisiz akış — mod ile döngü; duraklama ve başa ışınlanma
    // yok. Metin iki kopya yan yana: soldan çıkan kopya sağdan girer.
    _offset = (_offset + widget.speedPerTick) % _distance;
    setState(() {});
  }

  Widget _loopCopy() {
    return Text(
      widget.text,
      style: widget.style,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth) {
          return Text(
            widget.text,
            style: widget.style,
            textAlign: widget.align,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        }
        final tp = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        final boxW = constraints.maxWidth;
        if (tp.width <= boxW) {
          _stop();
          return Text(
            widget.text,
            style: widget.style,
            textAlign: widget.align,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        }
        _distance = tp.width + _gap;
        _start();
        return SizedBox(
          height: tp.height,
          child: ClipRect(
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Transform.translate(
                  offset: Offset(-_offset, 0),
                  child: _loopCopy(),
                ),
                Transform.translate(
                  offset: Offset(-_offset + _distance, 0),
                  child: _loopCopy(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
