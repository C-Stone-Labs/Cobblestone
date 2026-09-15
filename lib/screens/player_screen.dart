import '../services/stats_service.dart';
import '../services/folder_watch.dart';
import 'package:flutter/material.dart';

import '../models/song_item.dart';
import '../services/song_storage.dart';
import '../services/playlist_storage.dart';
import '../services/library_controller.dart';
import '../services/player_controller.dart';
import '../theme/palette.dart';
import '../widgets/cobble_toast.dart';
import '../widgets/cobble_logo.dart';
import '../widgets/song_search_field.dart';
import '../widgets/song_selection.dart';
import '../widgets/song_actions.dart';
import '../widgets/song_tile.dart';
import '../widgets/mini_player.dart';
import '../widgets/cobble_page_route.dart';
import '../screens/add_songs_to_playlist_screen.dart';
import '../screens/report_screen.dart';

class PlayerScreen extends StatefulWidget {
  final CobblestonePalette palette;
  const PlayerScreen({super.key, required this.palette});
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  CobblestonePalette get _p => widget.palette;
  String _query = '';
  final _sel = SongSelection();

  Future<String?> _createPlaylistDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _p.card,
        title: Text('Yeni Liste', style: TextStyle(color: _p.orangeLight)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Liste adı',
            hintStyle: TextStyle(color: _p.mute),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Vazgeç', style: TextStyle(color: _p.mute)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text('Oluştur', style: TextStyle(color: _p.orange)),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return null;
    return name;
  }

  Future<void> _showOptions(SongItem song) async {
    final isFav = LibraryController.instance.isFavorite(song.appPath);
    await showModalBottomSheet(
      context: context,
      backgroundColor: _p.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheet) {
        final bottom = MediaQuery.viewPaddingOf(sheet).bottom;
        return SafeArea(
        child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: bottom > 8 ? 12 : 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _p.mute.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Material(
              type: MaterialType.transparency,
              child: ListTile(
                leading: Icon(
                  isFav ? Icons.star_rounded : Icons.star_border_rounded,
                  color: _p.orange,
                ),
                title: Text(
                  isFav ? 'Favorilerden Çıkar' : 'Favorilere Ekle',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  final pageCtx = this.context;
                  final wasFav = isFav;
                  Navigator.pop(sheet);
                  await LibraryController.instance.toggleFavorite(song.appPath);
                  if (mounted) {
                    showCobbleToast(
                      pageCtx,
                      wasFav ? 'Favorilerden çıkarıldı.' : 'Favorilere eklendi.',
                      icon: wasFav
                          ? Icons.star_border_rounded
                          : Icons.star_rounded,
                    );
                  }
                },
              ),
            ),
            ...queueActionTiles(
              sheetContext: sheet,
              pageContext: this.context,
              song: song,
              palette: _p,
            ),
            Material(
              type: MaterialType.transparency,
              child: ListTile(
                leading: Icon(Icons.playlist_add, color: _p.orange),
                title: const Text(
                  'Çalma Listesine Ekle',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.pop(sheet);
                  await _showAddToPlaylist(song);
                },
              ),
            ),
            ...fileInfoAndShareTiles(
              sheetContext: sheet,
              pageContext: this.context,
              song: song,
              palette: _p,
            ),
            Material(
              type: MaterialType.transparency,
              child: ListTile(
                leading: Icon(Icons.delete_outline, color: Colors.amber),
                title: const Text(
                  'Sadece Uygulamadan Sil',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.pop(sheet);
                  await SongStorage.deleteFromAppOnly(song);
                  await LibraryController.instance.refreshSongs();
                  if (mounted) {
                    showCobbleToast(
                      this.context,
                      'Şarkı uygulamadan kaldırıldı.',
                      icon: Icons.delete_outline_rounded,
                    );
                  }
                },
              ),
            ),
            Material(
              type: MaterialType.transparency,
              child: ListTile(
                leading: const Icon(
                  Icons.delete_forever,
                  color: Colors.redAccent,
                ),
                title: const Text(
                  'Uygulamadan ve Telefondan Sil',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.pop(sheet);
                  try {
                    await SongStorage.deleteFromAppAndPhone(song);
                    await LibraryController.instance.refreshSongs();
                    if (mounted) {
                      showCobbleToast(this.context, 'Şarkı hem uygulamadan hem telefondan silindi.', icon: Icons.delete_rounded, accent: Colors.redAccent);
                    }
                  } catch (e) {
                    await LibraryController.instance.refreshSongs();
                    if (mounted) {
                      showCobbleToast(this.context, 'Şarkı telefondan silinemedi. Dosya başka bir uygulamada açık olabilir.', icon: Icons.error_outline_rounded, accent: Colors.redAccent);
                    }
                  }
                },
              ),
            ),
          ],
        ),
        ),
        );
      },
    );
  }

  Future<void> _showAddToPlaylist(SongItem song) async {
    var playlists = LibraryController.instance.playlistsNotifier.value;
    if (playlists.isEmpty) {
      if (!mounted) return;
      final wantsCreate = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: _p.card,
          title: Text('Henüz Liste Yok',
              style: TextStyle(color: _p.orangeLight)),
          content: const Text('Çalma listesi oluşturmak ister misin?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç')),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Oluştur')),
          ],
        ),
      );
      if (wantsCreate != true || !mounted) return;
      final name = await _createPlaylistDialog();
      if (name == null || !mounted) return;
      final newPlaylist = await PlaylistStorage.createPlaylist(name);
      await PlaylistStorage.toggleSongInPlaylist(newPlaylist.id, song.appPath);
      await LibraryController.instance.refreshPlaylists();
      final refreshed = LibraryController.instance.playlistsNotifier.value
          .firstWhere((pl) => pl.id == newPlaylist.id, orElse: () => newPlaylist);
      if (!mounted) return;
      await Navigator.push(
        context,
        CobblePageRoute(
          builder: (_) => AddSongsToPlaylistScreen(playlist: refreshed, palette: _p),
        ),
      );
      return;
    }
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: _p.card,
            title: Text('Listeye Ekle',
                style: TextStyle(color: _p.orangeLight)),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: [
                  Material(
                    type: MaterialType.transparency,
                    child: ListTile(
                      leading: Icon(Icons.add_circle_outline, color: _p.orange),
                      title: Text('Yeni Liste Oluştur',
                          style: TextStyle(color: _p.orange,
                              fontWeight: FontWeight.w600)),
                      onTap: () async {
                        final pageCtx = this.context;
                        Navigator.pop(context);
                        final name = await _createPlaylistDialog();
                        if (name == null || !mounted) return;
                        final newPl = await PlaylistStorage.createPlaylist(name);
                        await PlaylistStorage.toggleSongInPlaylist(
                          newPl.id,
                          song.appPath,
                        );
                        await LibraryController.instance.refreshPlaylists();
                        if (mounted) {
                          showCobbleToast(
                            pageCtx,
                            '"${newPl.name}" oluşturuldu ve şarkı eklendi.',
                            icon: Icons.add_circle_rounded,
                          );
                        }
                      },
                    ),
                  ),
                  ...playlists.map((pl) {
                    final isAdded = pl.songPaths.contains(song.appPath);
                    return Material(
                      type: MaterialType.transparency,
                      child: ListTile(
                        leading: Icon(
                          isAdded ? Icons.check_circle : Icons.circle_outlined,
                          color: isAdded ? _p.orange : _p.mute,
                        ),
                        title: Text(pl.name),
                        onTap: () async {
                          final pageCtx = this.context;
                          Navigator.pop(context);
                          // v5.1.3: zaten listedeyse EKLENMEZ (eski kod
                          // sessizce çıkarıyordu!); mesaj durumu söyler.
                          if (isAdded) {
                            if (mounted) {
                              showCobbleToast(
                                pageCtx,
                                'Bu şarkı zaten "${pl.name}" listesinde.',
                                icon: Icons.info_rounded,
                              );
                            }
                            return;
                          }
                          await PlaylistStorage.toggleSongInPlaylist(pl.id, song.appPath);
                          await LibraryController.instance.refreshPlaylists();
                          if (mounted) {
                            showCobbleToast(
                              pageCtx,
                              '"${pl.name}" listesine eklendi.',
                              icon: Icons.playlist_add_rounded,
                            );
                          }
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Vazgeç', style: TextStyle(color: _p.mute)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return ListenableBuilder(
      listenable: _sel,
      builder: (context, _) {
        return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: _sel.isActive
            ? GestureDetector(
                onTap: _sel.clear,
                child: Container(
                  width: double.infinity,
                  child: Text('${_sel.count} şarkı seçildi'),
                ),
              )
            : Row(
                children: [
                  const CobbleLogo(size: 26),
                  const SizedBox(width: 10),
                  const Text("Cobblestone"),
                ],
              ),
        actions: _sel.isActive
            ? [
                IconButton(
                  tooltip: 'Tümünü seç',
                  icon: const Icon(Icons.select_all_rounded),
                  onPressed: () {
                    final all = LibraryController
                        .instance.songsNotifier.value;
                    final q = _query.toLowerCase();
                    _sel.selectAllVisible(
                      q.isEmpty
                          ? all.map((x) => x.appPath)
                          : all
                                .where(
                                  (x) =>
                                      x.title.toLowerCase().contains(q) ||
                                      x.displayArtist.toLowerCase().contains(q),
                                )
                                .map((x) => x.appPath),
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Seçimi temizle',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: _sel.clear,
                ),
              ]
            : [
          IconButton(
            tooltip: 'Müzik klasörünü seç',
            icon: const Icon(Icons.folder_open_rounded),
            onPressed: () => FolderWatch.pickAndScan(context, p),
          ),
          ValueListenableBuilder<int>(
            valueListenable: StatsService.instance.reportSeenVersion,
            builder: (context, _, _) {
              return FutureBuilder<bool>(
                future: StatsService.instance.isReportSeenToday(),
                builder: (context, snap) {
                  final showDot = snap.data == false;
                  return IconButton(
                    tooltip: 'Rapor',
                    icon: showDot
                        ? Badge(
                            label: const Text(
                              '!',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 10,
                              ),
                            ),
                            backgroundColor: p.orange,
                            child: const Icon(Icons.bar_chart_rounded),
                          )
                        : const Icon(Icons.bar_chart_rounded),
                    onPressed: () => Navigator.of(context).push(
                      CobblePageRoute(
                        builder: (_) => ReportScreen(palette: p),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: ValueListenableBuilder<SongItem?>(
          valueListenable: nowPlayingNotifier,
          builder: (context, nowPlaying, _) {
            return ValueListenableBuilder<List<SongItem>>(
              valueListenable: LibraryController.instance.songsNotifier,
              builder: (context, allSongs, _) {
                final q = _query.toLowerCase();
                final songs = q.isEmpty
                    ? allSongs
                    : allSongs
                          .where((s) =>
                              s.title.toLowerCase().contains(q) ||
                              s.displayArtist.toLowerCase().contains(q))
                          .toList();
                return Column(
                  children: [
                    if (allSongs.isNotEmpty)
                      SongSearchField(
                        palette: p,
                        onChanged: (v) => setState(() => _query = v),
                      ),
                    Expanded(
                      child: GestureDetector(
                        onTap: _sel.isActive ? _sel.clear : null,
                        child: allSongs.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 28,
                                ),
                                child: Text(
                                  "Henüz şarkı yok — sağ üstteki klasör "
                                  "simgesiyle müzik ekle.",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: p.mute,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            )
                          : songs.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 28,
                                ),
                                child: Text(
                                  "Sonuç bulunamadı",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: p.mute,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            )
                          : ListView.builder(
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              padding: EdgeInsets.only(
                                bottom: miniPlayerListPadding(nowPlaying),
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
                                    FocusManager.instance.primaryFocus
                                        ?.unfocus();
                                    // v5.1.3: arama suzmesi yalnizca
                                    // ekranda; kuyruk TAM liste uzerinde.
                                    final full = allSongs.indexWhere(
                                      (x) => x.appPath == song.appPath,
                                    );
                                    playFromQueue(
                                      allSongs,
                                      full >= 0 ? full : index,
                                    );
                                  },
                                  onMore: () {
                                  if (_sel.isActive) _sel.clear();
                                  _showOptions(song);
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
                          await LibraryController.instance.refreshPlaylists();
                        },
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
        );
      },
    );
  }
}
