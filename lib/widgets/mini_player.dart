import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/ui_events.dart';
import 'song_selection.dart';

import '../models/song_item.dart';
import '../screens/now_playing_screen.dart';
import '../services/player_controller.dart';
import '../theme/palette.dart';
import 'marquee_text.dart';
import 'artwork.dart';

/// Liste son satırının mini oynatıcının altında kalmaması için.
const double kMiniPlayerReserve = 112;

double miniPlayerListPadding(SongItem? nowPlaying) =>
    nowPlaying == null ? 8 : kMiniPlayerReserve;

/// Tam ekran detay (Akıllı/Klasör içi): MiniPlayer örtülür, Samsung nav
/// son satırı yemesin.
double overlayListBottom(BuildContext context) {
  final sys = MediaQuery.viewPaddingOf(context).bottom;
  return (sys > 12 ? sys : 28) + 24;
}

/// Şarkılar + Listeler (Favoriler / çalma listesi içi) ortak mini oynatıcı.
/// Ayarlar sekmesinde gösterilmez. Kaynak (Favoriler / liste adı) görünür.
class MiniPlayer extends StatefulWidget {
  final CobblestonePalette palette;
  const MiniPlayer({super.key, required this.palette});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  double _lift = 0;
  double _cardH = 0;
  static const _liftKey = 'mini_player_lift_v1';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      setState(() => _lift = prefs.getDouble(_liftKey) ?? 0);
    });
  }

  @override
  void dispose() {
    // v5.1.3: mini oynatıcı ekrandan gitince bildirim kutusu rayı boşalır.
    miniRailPx.value = 0;
    super.dispose();
  }

  void _openNowPlaying() {
    HapticFeedback.selectionClick();
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => NowPlayingScreen(palette: widget.palette),
        fullscreenDialog: true,
      ),
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required VoidCallback onTap,
    double size = 24,
    Color? color,
  }) {
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        icon: Icon(icon, color: color ?? Colors.white, size: size),
        onPressed: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return ValueListenableBuilder<SongItem?>(
      valueListenable: nowPlayingNotifier,
      builder: (context, currentSong, _) {
        if (currentSong == null) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => miniRailPx.value = 0,
          );
          return const SizedBox.shrink();
        }
        final maxLift = MediaQuery.sizeOf(context).height - 280;
        final lift = _lift.clamp(0.0, maxLift);
        // v5.1.3: tam ekran detaylarda sistem alt çubuğunun ÜSTÜNDE dur
        // (kök kullanımda inset 0'dır, davranış değişmez).
        final sysBottom = MediaQuery.viewPaddingOf(context).bottom;
        final normalBottom = 8 + lift + sysBottom;
        return ListenableBuilder(
          // v5.1.3: seçim modu VEYA üstte açık menü varken mini oynatıcı
          // kayarak iner. Bildirim kutusu açıksa GİZLENMEZ; kutuyla temas
          // etmeyecek kadar kendini yukarı alır (yol verir).
          listenable: Listenable.merge([
            SongSelection.activityVersion,
            overlayMenuCount,
            toastTopPx,
          ]),
          builder: (context, _) {
            // v5.1.3: bildirim kutusu açıkken mini oynatıcı, seçim
            // modu/menülerdeki AYNISİNİ yapar: gizlenir. Kutu parmakla
            // atılabilir; kapanınca mini geri döner. Kutu ile ray artık
            // birbirini beslemez — geri besleme döngüsü kökten kesildi.
            final hide = SongSelection.anyActive ||
                overlayMenuCount.value > 0 ||
                toastTopPx.value > 0;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              final ro = context.findRenderObject();
              if (ro is RenderBox && ro.hasSize && ro.size.height > 4) {
                _cardH = ro.size.height;
              }
              // Alt ray EKRAN koordinatında (navbar + sistem dahil) —
              // kutunun zemini ile aynı ölçü.
              final rail = hide
                  ? 0.0
                  : 80 + sysBottom + normalBottom + _cardH;
              if (miniRailPx.value != rail) miniRailPx.value = rail;
            });
            return AnimatedPositioned(
              left: 10,
              right: 10,
              bottom: normalBottom,
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              child: AnimatedSlide(
                offset: hide ? const Offset(0, 1.8) : Offset.zero,
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: hide ? 0 : 1,
                  duration: const Duration(milliseconds: 240),
                  child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: _openNowPlaying,
              onVerticalDragUpdate: (d) {
                setState(() {
                  _lift = (_lift - d.delta.dy).clamp(0.0, maxLift);
                });
              },
              onVerticalDragEnd: (_) {
                SharedPreferences.getInstance().then((prefs) {
                  prefs.setDouble(_liftKey, _lift);
                });
              },
              child: Container(
                decoration: BoxDecoration(
                  color: p.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: p.cardBorder),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 16,
                      offset: const Offset(0, -4),
                    ),
                    ...buildGlow(p, p.orange, blur: 18, spread: 0),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StreamBuilder<Duration>(
                      stream: globalPlayer.positionStream,
                      builder: (context, snap) {
                        final pos =
                            (snap.data ?? Duration.zero).inMilliseconds;
                        final dur = (globalPlayer.duration ?? Duration.zero)
                            .inMilliseconds;
                        final t = dur <= 0
                            ? 0.0
                            : (pos / dur).clamp(0.0, 1.0);
                        return ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(16),
                          ),
                          child: LinearProgressIndicator(
                            value: t,
                            minHeight: 2.5,
                            backgroundColor: p.mute.withValues(alpha: 0.18),
                            color: p.orange,
                          ),
                        );
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                      child: Row(
                        children: [
                          SongArtwork(
                            palette: p,
                            size: 48,
                            appPath: currentSong.appPath,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ValueListenableBuilder<PlaybackOrigin>(
                              valueListenable: playbackOriginNotifier,
                              builder: (context, origin, _) {
                                final artist = currentSong.displayArtist.isEmpty
                                    ? 'Bilinmeyen sanatçı'
                                    : currentSong.displayArtist;
                                final src = origin.label;
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    MarqueeText(
                                      currentSong.title,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: p.mute,
                                        fontSize: 12,
                                      ),
                                    ),
                                    if (src != null && src.isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Row(
                                        children: [
                                          Icon(
                                            origin.isFavorites
                                                ? Icons.star_rounded
                                                : Icons.queue_music_rounded,
                                            size: 13,
                                            color: p.orange,
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              src,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: p.orangeLight,
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                );
                              },
                            ),
                          ),
                          _iconBtn(
                            icon: Icons.skip_previous_rounded,
                            size: 26,
                            onTap: playPrevious,
                          ),
                          StreamBuilder<PlayerState>(
                            stream: globalPlayer.playerStateStream,
                            builder: (context, stateSnap) {
                              final pauseIcon =
                                  stateSnap.data?.showPauseIcon ?? true;
                              return Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: p.orange,
                                  shape: BoxShape.circle,
                                  boxShadow: buildGlow(
                                    p,
                                    p.orange,
                                    blur: 12,
                                    spread: 0,
                                  ),
                                ),
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  icon: Icon(
                                    pauseIcon
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                  onPressed: () => pauseIcon
                                      ? globalPlayer.pause()
                                      : globalPlayer.play(),
                                ),
                              );
                            },
                          ),
                          _iconBtn(
                            icon: Icons.skip_next_rounded,
                            size: 26,
                            onTap: playNext,
                          ),
                          _iconBtn(
                            icon: Icons.close_rounded,
                            size: 20,
                            color: p.mute,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              unawaitedStop();
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void unawaitedStop() {
    stopPlayback();
  }
}
