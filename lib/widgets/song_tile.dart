import 'package:flutter/material.dart';

import '../models/song_item.dart';
import '../services/player_controller.dart';
import '../theme/palette.dart';
import 'artwork.dart';
import 'equalizer_bars.dart';
import 'marquee_text.dart';

/// Sabit yükseklik: başlık + sanatçı her satırda aynı kalır (modern çalarlar gibi).
class CobbleSongTile extends StatelessWidget {
  final SongItem song;
  final CobblestonePalette palette;
  final VoidCallback onTap;
  final VoidCallback onMore;

  /// v5.1.3 coklu secim: basili tutma ve secili gorunumu.
  final VoidCallback? onLongPress;
  final bool selected;

  static const double rowHeight = 72;
  static const double artSize = 44;

  const CobbleSongTile({
    super.key,
    required this.song,
    required this.palette,
    required this.onTap,
    required this.onMore,
    this.onLongPress,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SongItem?>(
      valueListenable: nowPlayingNotifier,
      builder: (context, nowPlaying, _) {
        final isCurrent = nowPlaying?.appPath == song.appPath;
        final p = palette;
        final artist = song.displayArtist.isEmpty
            ? 'Bilinmeyen sanatçı'
            : song.displayArtist;
        return Container(
          height: rowHeight,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: selected
                ? p.orange.withValues(alpha: 0.22)
                : isCurrent
                ? p.orange.withValues(alpha: 0.16)
                : p.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? p.orange
                  : isCurrent
                  ? p.orange.withValues(alpha: 0.6)
                  : p.cardBorder,
              width: selected || isCurrent ? 1.2 : 1,
            ),
            boxShadow: isCurrent && !selected
                ? buildGlow(p, p.orange, blur: 14, spread: 0)
                : const [],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              onLongPress: onLongPress,
              child: Padding(
                padding: const EdgeInsets.only(left: 12, right: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: artSize,
                      height: artSize,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (isCurrent && !selected)
                            StreamBuilder<PlayerState>(
                              stream: globalPlayer.playerStateStream,
                              builder: (context, snap) {
                                final playing = snap.data?.playing ?? false;
                                final ready =
                                    snap.data?.processingState ==
                                    ProcessingState.ready;
                                return Center(
                                  child: EqualizerBars(
                                    color: p.orange,
                                    animate: playing && ready,
                                  ),
                                );
                              },
                            )
                          else
                            SongArtwork(
                              palette: p,
                              size: artSize,
                              appPath: song.appPath,
                            ),
                          IgnorePointer(
                            child: AnimatedOpacity(
                              opacity: selected ? 1 : 0,
                              duration: const Duration(milliseconds: 240),
                              child: Container(
                                width: artSize,
                                height: artSize,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.check_circle_rounded,
                                  color: Colors.white,
                                  size: 26,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isCurrent)
                            MarqueeText(
                              song.title,
                              style: TextStyle(
                                color: p.orangeLight,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                height: 1.2,
                              ),
                            )
                          else
                            Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                                fontSize: 15,
                                height: 1.2,
                              ),
                            ),
                          const SizedBox(height: 3),
                          Text(
                            artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: p.mute,
                              fontSize: 12,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.more_vert, color: p.mute),
                      onPressed: onMore,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
