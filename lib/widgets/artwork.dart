import 'dart:io';

import 'package:flutter/material.dart';

import '../services/artwork_service.dart';
import '../services/fallback_art_controller.dart';
import '../theme/palette.dart';

/// Şarkı kapağı: kullanıcı / ID3 / yedek (taş veya nota).
class SongArtwork extends StatelessWidget {
  final CobblestonePalette palette;
  final double size;
  final String? appPath;
  final double radius;

  const SongArtwork({
    super.key,
    required this.palette,
    this.size = 40,
    this.appPath,
    this.radius = -1,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final r = radius < 0 ? size * 0.30 : radius;
    final path = appPath;
    if (path == null) return _fallback(p, r);
    return ValueListenableBuilder<int>(
      valueListenable: ArtworkService.instance.tick,
      builder: (context, _, _) {
        return FutureBuilder<String?>(
          future: ArtworkService.instance.coverForVisible(path),
          builder: (context, snap) {
            final cover = snap.data;
            if (cover == null) return _fallback(p, r);
            return ClipRRect(
              borderRadius: BorderRadius.circular(r),
              child: Image.file(
                File(cover),
                width: size,
                height: size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => _fallback(p, r),
              ),
            );
          },
        );
      },
    );
  }

  Widget _fallback(CobblestonePalette p, double r) {
    return ValueListenableBuilder<FallbackArt>(
      valueListenable: FallbackArtController.instance.modeNotifier,
      builder: (context, mode, _) {
        if (mode == FallbackArt.stone) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(r),
            child: Image.asset(
              'assets/icon/stone.jpg',
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _noteBadge(p, r),
            ),
          );
        }
        return _noteBadge(p, r);
      },
    );
  }

  Widget _noteBadge(CobblestonePalette p, double r) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(r),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(p.orange.withValues(alpha: 0.10), p.card),
            p.bg2,
          ],
        ),
        border: Border.all(color: p.cardBorder),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.music_note_rounded,
        color: p.orangeLight.withValues(alpha: 0.85),
        size: size * 0.55,
      ),
    );
  }
}
