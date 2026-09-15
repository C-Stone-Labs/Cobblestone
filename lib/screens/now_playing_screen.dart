import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/palette.dart';
import '../widgets/marquee_text.dart';
import '../models/song_item.dart';
import '../services/library_controller.dart';
import '../services/player_controller.dart';
import '../widgets/ambient_layer.dart';
import '../widgets/artwork.dart';

class NowPlayingScreen extends StatefulWidget {
  final CobblestonePalette palette;
  const NowPlayingScreen({super.key, required this.palette});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  CobblestonePalette get _p => widget.palette;
  double? _dragValue;
  bool _speedOpen = false;

  Widget _buildSpeedSelector() {
    return ValueListenableBuilder<double>(
      valueListenable: speedNotifier,
      builder: (context, current, _) {
        final label = current == 1.0
            ? '1×'
            : '${current.toStringAsFixed(current % 1 == 0 ? 0 : 2)}×';
        return Column(
          children: [
            Center(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _speedOpen = !_speedOpen);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.speed_rounded,
                          color: _speedOpen ? _p.orange : _p.mute,
                          size: 22,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: TextStyle(
                            color: _p.orangeLight,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              child: _speedOpen
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 12,
                          ),
                        ),
                        child: Slider(
                          value: current.clamp(0.5, 2.0),
                          min: 0.5,
                          max: 2.0,
                          divisions: 6,
                          activeColor: _p.orange,
                          inactiveColor: _p.mute.withValues(alpha: 0.25),
                          onChanged: (v) {
                            speedNotifier.value = v;
                            unawaited(globalPlayer.setSpeed(v));
                          },
                          onChangeEnd: (v) {
                            HapticFeedback.selectionClick();
                            unawaited(persistSpeed(v));
                          },
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildArtArea(SongItem song) {
    return Container(
      width: 260,
      height: 260,
      decoration: BoxDecoration(
        color: _p.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _p.cardBorder),
        boxShadow: [
          BoxShadow(
            color: _p.orange.withValues(alpha: _p.neonGlow ? 0.34 : 0.20),
            blurRadius: 30,
            spreadRadius: 1,
          ),
          ...buildGlow(_p, _p.orange, blur: 38, spread: 2),
        ],
      ),
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      child: SongArtwork(
        palette: _p,
        size: 260,
        appPath: song.appPath,
        radius: 24,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SongItem?>(
      valueListenable: nowPlayingNotifier,
      builder: (context, song, _) {
        if (song == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          });
          return Scaffold(
            backgroundColor: _p.bg,
            body: const SizedBox.shrink(),
          );
        }
        return Scaffold(
          backgroundColor: _p.bg,
          body: AmbientLayer(
            palette: _p,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                        Expanded(
                          child: ValueListenableBuilder<PlaybackOrigin>(
                            valueListenable: playbackOriginNotifier,
                            builder: (context, origin, _) {
                              final src = origin.label;
                              return Column(
                                children: [
                                  Text(
                                    'ŞİMDİ ÇALIYOR',
                                    style: TextStyle(
                                      color: _p.mute,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  if (src != null && src.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      src,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: _p.orangeLight,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),
                        ),
                        ValueListenableBuilder<List>(
                          valueListenable:
                              LibraryController.instance.playlistsNotifier,
                          builder: (context, _, _) {
                            final fav = LibraryController.instance
                                .isFavorite(song.appPath);
                            return IconButton(
                              icon: Icon(
                                fav
                                    ? Icons.star_rounded
                                    : Icons.star_border_rounded,
                                color: fav ? _p.orange : Colors.white,
                              ),
                              onPressed: () => LibraryController.instance
                                  .toggleFavorite(song.appPath),
                            );
                          },
                        ),
                      ],
                    ),
                    const Spacer(),
                    _buildArtArea(song),
                    const Spacer(),
                    MarqueeText(
                      song.title,
                      align: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      song.displayArtist.isEmpty
                          ? 'Bilinmeyen sanatçı'
                          : song.displayArtist,
                      style: TextStyle(color: _p.mute, fontSize: 14),
                    ),
                    const SizedBox(height: 28),
                    StreamBuilder<Duration>(
                      stream: globalPlayer.positionStream,
                      builder: (context, posSnap) {
                        final posMs = (posSnap.data ?? Duration.zero)
                            .inMilliseconds
                            .toDouble();
                        final maxMs = (globalPlayer.duration ??
                                const Duration(seconds: 1))
                            .inMilliseconds
                            .toDouble();
                        final safeMax = maxMs <= 0 ? 1.0 : maxMs;
                        return Column(
                          children: [
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 4,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 7,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 16,
                                ),
                              ),
                              child: Slider(
                                value: (_dragValue ?? posMs)
                                    .clamp(0, safeMax)
                                    .toDouble(),
                                max: safeMax,
                                activeColor: _p.orange,
                                inactiveColor: _p.mute.withValues(alpha: 0.25),
                                onChangeStart: (v) =>
                                    setState(() => _dragValue = v),
                                onChanged: (v) =>
                                    setState(() => _dragValue = v),
                                onChangeEnd: (v) async {
                                  await globalPlayer.seek(
                                    Duration(milliseconds: v.toInt()),
                                  );
                                  setState(() => _dragValue = null);
                                },
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _formatMmSs(
                                      Duration(
                                        milliseconds:
                                            (_dragValue ?? posMs).toInt(),
                                      ),
                                    ),
                                    style: TextStyle(
                                      color: _p.mute,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    _formatMmSs(
                                      globalPlayer.duration ?? Duration.zero,
                                    ),
                                    style: TextStyle(
                                      color: _p.mute,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildSpeedSelector(),
                    const SizedBox(height: 16),
                    StreamBuilder<PlayerState>(
                      stream: globalPlayer.playerStateStream,
                      builder: (context, stateSnap) {
                        final pauseIcon =
                            stateSnap.data?.showPauseIcon ?? true;
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            ValueListenableBuilder<bool>(
                              valueListenable: shuffleNotifier,
                              builder: (context, shuffle, _) => IconButton(
                                icon: Icon(
                                  Icons.shuffle_rounded,
                                  color: shuffle ? _p.orange : _p.mute,
                                  size: 26,
                                ),
                                onPressed: () => shuffleNotifier.value =
                                    !shuffleNotifier.value,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.skip_previous_rounded,
                                color: Colors.white,
                                size: 42,
                              ),
                              onPressed: playPrevious,
                            ),
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: _p.orange,
                                shape: BoxShape.circle,
                                boxShadow: buildGlow(
                                  _p,
                                  _p.orange,
                                  blur: 24,
                                  spread: 2,
                                ),
                              ),
                              child: IconButton(
                                icon: Icon(
                                  pauseIcon
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 40,
                                ),
                                onPressed: () => pauseIcon
                                    ? globalPlayer.pause()
                                    : globalPlayer.play(),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.skip_next_rounded,
                                color: Colors.white,
                                size: 42,
                              ),
                              onPressed: playNext,
                            ),
                            ValueListenableBuilder<bool>(
                              valueListenable: repeatNotifier,
                              builder: (context, repeat, _) => IconButton(
                                icon: Icon(
                                  repeat
                                      ? Icons.repeat_one_rounded
                                      : Icons.repeat_rounded,
                                  color: repeat ? _p.orange : _p.mute,
                                  size: 26,
                                ),
                                onPressed: () => repeatNotifier.value =
                                    !repeatNotifier.value,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatMmSs(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }
}
