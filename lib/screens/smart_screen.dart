import 'dart:async';

import 'package:flutter/material.dart';

import '../models/song_item.dart';
import '../services/library_controller.dart';
import '../services/player_controller.dart';
import '../services/smart_playlists.dart';
import '../services/stats_service.dart';
import '../services/theme_controller.dart';
import '../theme/palette.dart';
import '../widgets/cobble_logo.dart';
import '../widgets/mini_player.dart';
import '../widgets/cobble_toast.dart';
import '../widgets/song_actions.dart';
import '../widgets/song_search_field.dart';
import '../widgets/song_tile.dart';
import '../widgets/cobble_page_route.dart';
import '../widgets/tap_scale.dart';
import '../widgets/ambient_layer.dart';
import '../widgets/song_selection.dart';

/// Haftalık rapora kilitli akıllı listeler — kullanıcı ekleyemez / çıkaramaz.
class SmartScreen extends StatefulWidget {
  final CobblestonePalette palette;
  const SmartScreen({super.key, required this.palette});

  @override
  State<SmartScreen> createState() => _SmartScreenState();
}

class _SmartScreenState extends State<SmartScreen> {
  // v5.1.3: liste seçimi — listeler sekmesindeki gibi, yalnız PAYLAŞ.
  final _listSel = SongSelection();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        StatsService.instance.ensureSmartSnapshot(
          LibraryController.instance.songsNotifier.value,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CobblestonePalette>(
      valueListenable: ThemeController.instance.paletteNotifier,
      builder: (context, p, _) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            title: ListenableBuilder(
              listenable: _listSel,
              builder: (context, _) => _listSel.isActive
                  ? GestureDetector(
                      onTap: _listSel.clear,
                      child: SizedBox(
                        width: double.infinity,
                        child: Text(
                          _listSel.count == 1
                              ? '1 liste seçildi'
                              : '${_listSel.count} liste seçildi',
                        ),
                      ),
                    )
                  : const Row(
                      children: [
                        CobbleLogo(size: 26),
                        SizedBox(width: 10),
                        Text('Akıllı'),
                      ],
                    ),
            ),
            actions: [
              ListenableBuilder(
                listenable: _listSel,
                builder: (context, _) => _listSel.isActive
                    ? IconButton(
                        tooltip: 'Seçimden çık',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: _listSel.clear,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
          bottomNavigationBar: ListenableBuilder(
            listenable: _listSel,
            builder: (context, _) =>
                _listSel.isActive ? _shareSelectedBar(p) : const SizedBox.shrink(),
          ),
          body: ValueListenableBuilder<int>(
            valueListenable: StatsService.instance.smartVersion,
            builder: (context, _, __) {
              return ValueListenableBuilder<List<SongItem>>(
                valueListenable: LibraryController.instance.songsNotifier,
                builder: (context, allSongs, _) {
                  final lists = SmartPlaylists.all(allSongs);
                  return ValueListenableBuilder<SongItem?>(
                    valueListenable: nowPlayingNotifier,
                    builder: (context, nowPlaying, _) {
                      return GestureDetector(
                    onTap: _listSel.isActive ? _listSel.clear : null,
                    child: ListView.builder(
                        padding: EdgeInsets.only(
                          top: 8,
                          bottom: miniPlayerListPadding(nowPlaying),
                        ),
                        itemCount: lists.length + 1,
                        itemBuilder: (context, i) {
                          if (i == lists.length) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                              child: Text(
                                StatsService.instance.hasSmartSnapshot
                                    ? 'Bu üç liste geçen haftanın raporuna kilitli. '
                                        'Gelecek Pazartesi yenilenir. Şarkı eklenemez.'
                                    : 'Pazartesi raporu kilitlenince bu üç liste otomatik dolar.',
                                style: TextStyle(
                                  color: p.mute,
                                  fontSize: 12,
                                  height: 1.45,
                                ),
                              ),
                            );
                          }
                          final pl = lists[i];
                          return Container(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _listSel.isSelected(pl.id)
                                  ? p.orange.withValues(alpha: 0.22)
                                  : p.card,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _listSel.isSelected(pl.id)
                                    ? p.orange
                                    : p.cardBorder,
                              ),
                            ),
                            child: Material(
                              type: MaterialType.transparency,
                              child: ListTile(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                leading: Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: p.orange.withValues(alpha: 0.14),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    pl.icon,
                                    color: p.orange,
                                    size: 21,
                                  ),
                                ),
                                title: Text(
                                  pl.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  pl.songs.isEmpty
                                      ? pl.emptyHint
                                      : '${pl.songs.length} şarkı · ${pl.subtitle}',
                                  style: TextStyle(color: p.mute, fontSize: 12),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    originPlayPauseButton(
                                      originId: pl.id,
                                      originName: pl.name,
                                      songs: pl.songs,
                                      color: p.orange,
                                    ),
                                    _listMenu(pl, p),
                                  ],
                                ),
                                onLongPress: () => _listSel.isActive
                                    ? _listSel.toggle(pl.id)
                                    : _listSel.begin(pl.id),
onTap: () {
                                  if (_listSel.isActive) {
                                    _listSel.toggle(pl.id);
                                    return;
                                  }
                                  Navigator.push(
                                  context,
                                  CobblePageRoute(
                                    builder: (_) => SmartPlaylistDetailScreen(
                                      playlist: pl,
                                      palette: p,
                                    ),
                                  ),
                                );
                                },
                              ),
                            ),
                          );
                        },
                      ),
                  );
                    },
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  /// v5.1.3: akıllı liste ⋮ menüsü — yalnız PAYLAŞ.
  Widget _listMenu(SmartPlaylist pl, CobblestonePalette p) {
    return IconButton(
      icon: Icon(Icons.more_vert_rounded, color: p.mute),
      onPressed: () {
        if (_listSel.isActive) {
          _listSel.toggle(pl.id);
          return;
        }
        showModalBottomSheet(
          context: context,
          backgroundColor: p.card,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (sheet) => SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: p.mute.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: Icon(Icons.share_rounded, color: p.orange),
                  title: const Text(
                    'Paylaş',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    pl.songs.isEmpty
                        ? 'Liste boş'
                        : 'Listedeki şarkıların tamamı',
                    style: TextStyle(color: p.mute, fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.pop(sheet);
                    _shareSmartList(pl);
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  void _shareSmartList(SmartPlaylist pl) {
    if (pl.songs.isEmpty) {
      showCobbleToast(
        context,
        'Paylaşılacak şarkı yok.',
        icon: Icons.info_rounded,
      );
      return;
    }
    shareSongs(pl.songs, context, pl.name);
  }

  /// Seçim çubuğu — yalnız PAYLAŞ (akıllı listelerde başka eylem yok).
  Widget _shareSelectedBar(CobblestonePalette p) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: TapScale(
          child: FilledButton.icon(
            onPressed: () {
              final lists = SmartPlaylists.all(
                LibraryController.instance.songsNotifier.value,
              );
              final ids = _listSel.paths.toSet();
              final seen = <String>{};
              final songs = <SongItem>[];
              String? singleName;
              for (final pl in lists) {
                if (!ids.contains(pl.id)) continue;
                if (ids.length == 1) singleName ??= pl.name;
                for (final s in pl.songs) {
                  if (seen.add(s.appPath)) songs.add(s);
                }
              }
              if (songs.isEmpty) {
                showCobbleToast(
                  context,
                  'Paylaşılacak şarkı yok.',
                  icon: Icons.info_rounded,
                );
                return;
              }
              shareSongs(
                songs,
                context,
                singleName ?? 'Akıllı listeler',
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: p.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            icon: const Icon(Icons.share_rounded, size: 20),
            label: const Text('Paylaş'),
          ),
        ),
      ),
    );
  }
}

class SmartPlaylistDetailScreen extends StatefulWidget {
  final SmartPlaylist playlist;
  final CobblestonePalette palette;
  const SmartPlaylistDetailScreen({
    super.key,
    required this.playlist,
    required this.palette,
  });

  @override
  State<SmartPlaylistDetailScreen> createState() =>
      _SmartPlaylistDetailScreenState();
}

class _SmartPlaylistDetailScreenState extends State<SmartPlaylistDetailScreen> {
  String _query = '';
  final _sel = SongSelection();

  @override
  void initState() {
    super.initState();
    // v5.1.3: canlı tema — akıllı liste detayı anında güncellenir.
    ThemeController.instance.paletteNotifier.addListener(_onPal);
  }

  @override
  void dispose() {
    ThemeController.instance.paletteNotifier.removeListener(_onPal);
    super.dispose();
  }

  void _onPal() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeController.instance.paletteNotifier.value;
    return ValueListenableBuilder<int>(
      valueListenable: StatsService.instance.smartVersion,
      builder: (context, _, __) {
        return ValueListenableBuilder<List<SongItem>>(
          valueListenable: LibraryController.instance.songsNotifier,
          builder: (context, lib, __) {
            final lists = SmartPlaylists.all(lib);
            SmartPlaylist playlist = widget.playlist;
            for (final pl in lists) {
              if (pl.id == widget.playlist.id) {
                playlist = pl;
                break;
              }
            }
            return ListenableBuilder(
              listenable: _sel,
              builder: (_, __) => _detailBody(p, playlist),
            );
          },
        );
      },
    );
  }

  Widget _detailBody(CobblestonePalette p, SmartPlaylist playlist) {
    final all = playlist.songs;
    final q = _query.toLowerCase();
    final songs = q.isEmpty
        ? all
        : all
            .where(
              (s) =>
                  s.title.toLowerCase().contains(q) ||
                  s.displayArtist.toLowerCase().contains(q),
            )
            .toList();
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        title: _sel.isActive
            ? GestureDetector(
                onTap: _sel.clear,
                child: Container(
                  width: double.infinity,
                  child: Text('${_sel.count} şarkı seçildi'),
                ),
              )
            : Text(playlist.name),
        actions: _sel.isActive
            ? [
                IconButton(
                  tooltip: 'Tümünü seç',
                  icon: const Icon(Icons.select_all_rounded),
                  onPressed: () => _sel.selectAllVisible(
                    songs.map((x) => x.appPath),
                  ),
                ),
                IconButton(
                  tooltip: 'Seçimi temizle',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: _sel.clear,
                ),
              ]
            : [
          originPlayPauseButton(
            originId: playlist.id,
            originName: playlist.name,
            songs: all,
            color: p.orange,
          ),
        ],
      ),
      body: AmbientLayer(
        palette: p,
        child: ValueListenableBuilder<SongItem?>(
        valueListenable: nowPlayingNotifier,
        builder: (context, np, _) => Stack(
          children: [
            all.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  playlist.emptyHint,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.mute, height: 1.5),
                ),
              ),
            )
          : Column(
              children: [
                SongSearchField(
                  palette: p,
                  onChanged: (v) => setState(() => _query = v),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: _sel.isActive ? _sel.clear : null,
                    child: songs.isEmpty
                      ? Center(
                          child: Text(
                            'Sonuç bulunamadı',
                            style: TextStyle(color: p.mute),
                          ),
                        )
                      : ListView.builder(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: EdgeInsets.only(
                            bottom: overlayListBottom(context) +
                                (np == null ? 0 : kMiniPlayerReserve),
                          ),
                          itemCount: songs.length,
                          itemBuilder: (context, index) {
                            final song = songs[index];
                            return CobbleSongTile(
                              song: song,
                              palette: p,
                              selected: _sel.isSelected(song.appPath),
                              onLongPress: () =>
                                  _sel.begin(song.appPath),
                              onTap: () {
                                if (_sel.isActive) {
                                  _sel.toggle(song.appPath);
                                  return;
                                }
                                final full = all.indexWhere(
                                  (x) => x.appPath == song.appPath,
                                );
                                playFromQueue(
                                  all,
                                  full >= 0 ? full : index,
                                  origin: PlaybackOrigin.playlist(
                                    playlist.id,
                                    playlist.name,
                                  ),
                                );
                              },
                              onMore: () {
                                if (_sel.isActive) _sel.clear();
                                showSongOptionsSheet(
                                  context: context,
                                  song: song,
                                  palette: p,
                                );
                              },
                            );
                          },
                        ),
                      ),
                ),
                    SelectionBottomBar(
                        palette: p,
                        selection: _sel,
                        visibleSongs: songs,
                        onChanged: () async {
                          await LibraryController.instance.refreshSongs();
                        },
                      ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }
}
