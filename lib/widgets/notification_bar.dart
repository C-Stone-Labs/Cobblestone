import '../models/song_item.dart';
import 'package:flutter/material.dart';
import '../theme/palette.dart';
import '../services/player_controller.dart';
import 'cobble_toast.dart';
import '../services/library_controller.dart';

class NotificationControlBar extends StatelessWidget {
  final CobblestonePalette palette;
  final SongItem? song;
  final bool playing;
  const NotificationControlBar({
    super.key,
    required this.palette,
    required this.song,
    required this.playing,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final s = song;
    if (s == null) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: Colors.white),
            onPressed: () {},
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          Expanded(
            child: Text(
              s.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.star,
              color: LibraryController.instance.isFavorite(s.appPath)
                  ? p.orange
                  : p.mute,
              size: 20,
            ),
            onPressed: () async {
              final wasFav =
                  LibraryController.instance.isFavorite(s.appPath);
              await LibraryController.instance.toggleFavorite(s.appPath);
              if (context.mounted) {
                showCobbleToast(
                  context,
                  wasFav ? 'Favorilerden çıkarıldı.' : 'Favorilere eklendi.',
                  icon: wasFav
                      ? Icons.star_border_rounded
                      : Icons.star_rounded,
                );
              }
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          IconButton(
            icon: Icon(
              playing ? Icons.pause : Icons.play_arrow,
              color: p.orange,
              size: 24,
            ),
            onPressed: () {
              playing ? globalPlayer.pause() : globalPlayer.play();
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

