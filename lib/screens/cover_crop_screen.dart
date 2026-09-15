import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/palette.dart';

/// Albüm kapağı kırpıcı — kare çerçeve, pan/zoom, ızgara.
class CoverCropScreen extends StatefulWidget {
  final String imagePath;
  final CobblestonePalette palette;
  const CoverCropScreen({
    super.key,
    required this.imagePath,
    required this.palette,
  });

  @override
  State<CoverCropScreen> createState() => _CoverCropScreenState();
}

class _CoverCropScreenState extends State<CoverCropScreen> {
  final _boundary = GlobalKey();
  final _transform = TransformationController();
  bool _busy = false;

  Future<void> _confirm() async {
    setState(() => _busy = true);
    try {
      final ctx = _boundary.currentContext;
      if (ctx == null) return;
      final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2);
      final bd = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bd == null) return;
      if (!mounted) return;
      Navigator.pop(context, Uint8List.fromList(bd.buffer.asUint8List()));
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final side = MediaQuery.sizeOf(context).width - 32;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Kapağı kırp'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _confirm,
            child: Text(
              'Kullan',
              style: TextStyle(color: p.orange, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          Text(
            'Pinch ile yakınlaştır, sürükle, kareye sığdır',
            style: TextStyle(color: p.mute, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Center(
            child: SizedBox(
              width: side,
              height: side,
              child: Stack(
                children: [
                  ClipRect(
                    child: RepaintBoundary(
                      key: _boundary,
                      child: Container(
                        color: const Color(0xFF111111),
                        child: InteractiveViewer(
                          transformationController: _transform,
                          minScale: 0.4,
                          maxScale: 5,
                          constrained: false,
                          child: SizedBox(
                            width: side,
                            height: side,
                            child: Image.file(
                              File(widget.imagePath),
                              fit: BoxFit.cover,
                              width: side,
                              height: side,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  IgnorePointer(
                    child: CustomPaint(
                      size: Size(side, side),
                      painter: _GridPainter(color: p.orange.withValues(alpha: 0.35)),
                    ),
                  ),
                  IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: p.orange, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          if (_busy) LinearProgressIndicator(color: p.orange, minHeight: 3),
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              16 + MediaQuery.paddingOf(context).bottom,
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: p.cardBorder),
                    ),
                    child: const Text('Vazgeç'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : _confirm,
                    style: FilledButton.styleFrom(backgroundColor: p.orange),
                    child: const Text('Kırp ve kullan'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  final Color color;
  _GridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.8;
    for (var i = 1; i <= 2; i++) {
      final x = size.width * i / 3;
      final y = size.height * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => false;
}
