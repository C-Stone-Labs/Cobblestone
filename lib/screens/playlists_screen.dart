import 'package:flutter/material.dart';

import '../models/playlist_item.dart';
import '../models/song_item.dart';
import '../services/library_controller.dart';
import '../services/player_controller.dart';
import '../services/playlist_storage.dart';
import '../services/song_storage.dart';
import '../services/theme_controller.dart';
import '../theme/palette.dart';
import '../widgets/cobble_toast.dart';
import '../widgets/ambient_layer.dart';
import '../widgets/tap_scale.dart';
import '../widgets/cobble_logo.dart';
import '../widgets/song_search_field.dart';
import '../widgets/song_actions.dart';
import '../widgets/song_tile.dart';
import '../widgets/song_selection.dart';
import '../widgets/cobble_page_route.dart';
import '../widgets/mini_player.dart';
import 'add_songs_to_playlist_screen.dart';

class PlaylistsScreen extends StatefulWidget {
  final CobblestonePalette palette;
  const PlaylistsScreen({super.key, required this.palette});
  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  CobblestonePalette get _p =>
      ThemeController.instance.paletteNotifier.value;
  String _favQuery = '';
  final _favSel = SongSelection();
  final _listSel = SongSelection();
  String _listQuery = '';
  /// v5.1.3: aktif iç sekme (0 Favoriler, 1 Listeler) — AppBar'daki
  /// paylaş düğmesi yalnız Favoriler'de görünür.
  final ValueNotifier<int> _tabIdx = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    ThemeController.instance.paletteNotifier.addListener(_onPalette);
    // v5.1.3: liste seçimi ekranı anında tazelesin (AppBar + alt çubuk).
    _favSel.addListener(_onPalette);
    _listSel.addListener(_onPalette);
  }

  @override
  void dispose() {
    ThemeController.instance.paletteNotifier.removeListener(_onPalette);
    _favSel.removeListener(_onPalette);
    _listSel.removeListener(_onPalette);
    _tabIdx.dispose();
    super.dispose();
  }

  void _onPalette() {
    if (mounted) setState(() {});
  }

  Future<void> _create() async {
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
    if (name == null || name.trim().isEmpty) return;
    final newPl = await PlaylistStorage.createPlaylist(name.trim());
    await LibraryController.instance.refreshPlaylists();
    if (!mounted) return;
    await Navigator.push(
      context,
      CobblePageRoute(
        builder: (_) =>
            AddSongsToPlaylistScreen(playlist: newPl, palette: _p),
      ),
    );
    await LibraryController.instance.refreshPlaylists();
  }

  Future<void> _addSongsToFavorites() async {
    final playlists = LibraryController.instance.playlistsNotifier.value;
    final fav = playlists.firstWhere(
      (p) => p.id == PlaylistStorage.favoritesId,
      orElse: () => PlaylistItem(
        id: PlaylistStorage.favoritesId,
        name: PlaylistStorage.favoritesName,
      ),
    );
    if (!mounted) return;
    await Navigator.push(
      context,
      CobblePageRoute(
        builder: (_) => AddSongsToPlaylistScreen(playlist: fav, palette: _p),
      ),
    );
    await LibraryController.instance.refreshPlaylists();
  }

  void _showFavOptions(SongItem song) {
    final isFav = LibraryController.instance.isFavorite(song.appPath);
    showModalBottomSheet(
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
            ...fileInfoAndShareTiles(
              sheetContext: sheet,
              pageContext: this.context,
              song: song,
              palette: _p,
            ),
            Material(
              type: MaterialType.transparency,
              child: ListTile(
                leading: Icon(Icons.phone_android, color: _p.mute),
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
                  } catch (e) {
                    await LibraryController.instance.refreshSongs();
                    if (this.context.mounted) {
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

  Widget _buildFavoritesTab() {
    return ValueListenableBuilder<List<PlaylistItem>>(
      valueListenable: LibraryController.instance.playlistsNotifier,
      builder: (context, playlists, _) {
        final fav = playlists.firstWhere(
          (pl) => pl.id == PlaylistStorage.favoritesId,
          orElse: () => PlaylistItem(
            id: PlaylistStorage.favoritesId,
            name: PlaylistStorage.favoritesName,
          ),
        );
        return ValueListenableBuilder<List<SongItem>>(
          valueListenable: LibraryController.instance.songsNotifier,
          builder: (context, allSongs, _) {
            final allFav = allSongs
                .where((s) => fav.songPaths.contains(s.appPath))
                .toList();
            final q = _favQuery.toLowerCase();
            final favSongs = q.isEmpty
                ? allFav
                : allFav
                    .where(
                      (s) =>
                          s.title.toLowerCase().contains(q) ||
                          s.displayArtist.toLowerCase().contains(q),
                    )
                    .toList();
            if (allFav.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 104,
                      height: 104,
                      decoration: BoxDecoration(
                        color: _p.orange.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.star_border_rounded,
                        size: 52,
                        color: _p.mute,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Henüz favori şarkı yok',
                        style: TextStyle(color: _p.mute)),
                    const SizedBox(height: 8),
                    Text(
                      'Aşağıdaki + ile veya bildirimdeki ★ ile ekleyebilirsin.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _p.mute.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: _addSongsToFavorites,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _p.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Şarkı Ekle'),
                    ),
                  ],
                ),
              );
            }
            return ValueListenableBuilder<SongItem?>(
              valueListenable: nowPlayingNotifier,
              builder: (context, nowPlaying, _) {
                return Column(
                  children: [
                    SongSearchField(
                      palette: _p,
                      onChanged: (v) => setState(() => _favQuery = v),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: _favSel.isActive ? _favSel.clear : null,
                        child: favSongs.isEmpty
                          ? Center(
                              child: Text(
                                'Sonuç bulunamadı',
                                style: TextStyle(color: _p.mute),
                              ),
                            )
                          : ListView.builder(
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              padding: EdgeInsets.only(
                                top: 8,
                                bottom: miniPlayerListPadding(nowPlaying),
                              ),
                              itemCount: favSongs.length,
                              itemBuilder: (context, index) {
                                final song = favSongs[index];
                                return CobbleSongTile(
                                  song: song,
                                  palette: _p,
                                  selected: _favSel.isSelected(song.appPath),
                                  onLongPress: () =>
                                      _favSel.begin(song.appPath),
                                  onTap: () {
                                    if (_favSel.isActive) {
                                      _favSel.toggle(song.appPath);
                                      return;
                                    }
                                    final full = allFav.indexWhere(
                                      (x) => x.appPath == song.appPath,
                                    );
                                    playFromQueue(
                                      allFav,
                                      full >= 0 ? full : index,
                                      origin: PlaybackOrigin.favorites,
                                    );
                                  },
                                  onMore: () {
                                  if (_favSel.isActive) _favSel.clear();
                                  _showFavOptions(song);
                                },
                                );
                              },
                            ),
                      ),
                    ),
                    SelectionBottomBar(
                        showRemoveFavorite: true,
                        palette: _p,
                        selection: _favSel,
                        visibleSongs: favSongs,
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
        );
      },
    );
  }

  Widget _listsBar() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      child: _listSel.isActive
          ? Container(
              key: const ValueKey('listsbar'),
              // v5.1.3: yüzen kapsül — alttaki sekmelere bitişik değil.
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              decoration: BoxDecoration(
                color: _p.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _p.orange.withValues(alpha: 0.45),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Text(
                        '${_listSel.count} liste seçildi',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          // Seçili listelerin TÜM şarkılarını, liste adını
                          // taşıyan tek ZIP olarak paylaş.
                          final selected = LibraryController
                              .instance.playlistsNotifier.value
                              .where((pl) => _listSel.isSelected(pl.id))
                              .toList();
                          final name = selected.length == 1
                              ? selected.first.name
                              : '${selected.length} liste';
                          final all =
                              LibraryController.instance.songsNotifier.value;
                          final byPath = {
                            for (final s in all) s.appPath: s,
                          };
                          final songs = <SongItem>[];
                          for (final pl in selected) {
                            for (final path in pl.songPaths) {
                              final s = byPath[path];
                              if (s != null) songs.add(s);
                            }
                          }
                          if (songs.isEmpty) {
                            showCobbleToast(
                              context,
                              'Listede paylaşılabilecek şarkı yok.',
                              icon: Icons.info_rounded,
                            );
                            return;
                          }
                          shareSongs(songs, context, name);
                        },
                        child: Text(
                          'Paylaş',
                          style: TextStyle(color: _p.orange),
                        ),
                      ),
                      TextButton(
                        onPressed: _removeSelectedLists,
                        child: const Text(
                          'Sil',
                          style: TextStyle(color: Colors.redAccent),
                        ),
                      ),
                      TextButton(
                        onPressed: _listSel.clear,
                        child: Text('Vazgeç', style: TextStyle(color: _p.mute)),
                      ),
                    ],
                  ),
                ),
            )
          : const SizedBox.shrink(key: ValueKey('listsbaroff')),
    );
  }

  Future<void> _removeSelectedLists() async {
    final ids = _listSel.paths.toList();
    if (ids.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _p.card,
        title: Text(
          '${ids.length} liste silinsin mi?',
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          'Seçili listeler ve içerikleri kalıcı olarak silinecek.',
          style: TextStyle(color: _p.mute),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Vazgeç', style: TextStyle(color: _p.mute)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Sil',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    for (final id in ids) {
      await PlaylistStorage.deletePlaylist(id);
    }
    _listSel.clear();
    await LibraryController.instance.refreshPlaylists();
    if (mounted) {
      showCobbleToast(context, '${ids.length == 1 ? 'Bir liste' : '${ids.length} liste'} silindi.', icon: Icons.delete_sweep_rounded, accent: Colors.redAccent);
    }
  }

  /// v5.1.3: liste ⋮ menüsü — yeniden adlandır / sil.
  Widget _listMenu(PlaylistItem pl) {
    return IconButton(
      icon: Icon(Icons.more_vert_rounded, color: _p.mute),
      onPressed: () {
        if (_listSel.isActive) _listSel.clear();
        showModalBottomSheet(
          context: context,
          backgroundColor: _p.card,
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
                  color: _p.mute.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Icon(
                  Icons.playlist_add_rounded,
                  color: _p.orange,
                ),
                title: const Text(
                  'Şarkı Ekle',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.pop(sheet);
                  await Navigator.push(
                    context,
                    CobblePageRoute(
                      builder: (_) => AddSongsToPlaylistScreen(
                        playlist: pl,
                        palette: _p,
                      ),
                    ),
                  );
                  await LibraryController.instance.refreshPlaylists();
                },
              ),
              ListTile(
                leading: Icon(Icons.share_rounded, color: _p.orange),
                title: const Text(
                  'Paylaş',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.pop(sheet);
                  final byPath = {
                    for (final s
                        in LibraryController.instance.songsNotifier.value)
                      s.appPath: s,
                  };
                  final songs = pl.songPaths
                      .map((e) => byPath[e])
                      .whereType<SongItem>()
                      .toList();
                  await shareSongs(songs, context, pl.name);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.drive_file_rename_outline_rounded,
                  color: _p.orange,
                ),
                title: const Text(
                  'Yeniden Adlandır',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(sheet);
                  _renameList(pl);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                ),
                title: const Text(
                  'Sil',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(sheet);
                  _deleteList(pl);
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

  Future<void> _deleteList(PlaylistItem pl) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _p.card,
        title: Text(
          'Liste silinsin mi?',
          style: TextStyle(color: _p.orangeLight),
        ),
        content: Text(
          '"${pl.name}" kalıcı olarak silinecek.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Vazgeç', style: TextStyle(color: _p.mute)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Sil',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await PlaylistStorage.deletePlaylist(pl.id);
    await LibraryController.instance.refreshPlaylists();
  }

  Future<void> _renameList(PlaylistItem pl) async {
    final controller = TextEditingController(text: pl.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _p.card,
        title: Text(
          'Yeniden Adlandır',
          style: TextStyle(color: _p.orangeLight),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Liste adı',
            labelStyle: TextStyle(color: _p.mute),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Vazgeç', style: TextStyle(color: _p.mute)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(
              'Kaydet',
              style: TextStyle(color: _p.orange),
            ),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == pl.name) return;
    await PlaylistStorage.renamePlaylist(pl.id, name);
    await LibraryController.instance.refreshPlaylists();
    if (mounted) {
      showCobbleToast(
        context,
        'Liste yeniden adlandırıldı.',
        icon: Icons.drive_file_rename_outline_rounded,
      );
    }
  }

  /// v5.1.3: favorilerin TAMAMINI paylaş (seçim gerekmez).
  Future<void> _shareFavorites() async {
    final pls = LibraryController.instance.playlistsNotifier.value;
    final fav = pls.firstWhere(
      (pl) => pl.id == PlaylistStorage.favoritesId,
    );
    if (fav.songPaths.isEmpty) {
      showCobbleToast(
        context,
        'Favorilerde şarkı yok.',
        icon: Icons.info_rounded,
      );
      return;
    }
    final byPath = {
      for (final s in LibraryController.instance.songsNotifier.value)
        s.appPath: s,
    };
    final songs = fav.songPaths
        .map((p) => byPath[p])
        .whereType<SongItem>()
        .toList();
    await shareSongs(songs, context, 'Favoriler');
  }

  Widget _buildListsTab() {
    return ValueListenableBuilder<List<PlaylistItem>>(
      valueListenable: LibraryController.instance.playlistsNotifier,
      builder: (context, playlists, _) {
        final allLists = playlists
            .where((pl) => pl.id != PlaylistStorage.favoritesId)
            .toList();
        // v5.1.3: sayaç kütüphanede VAR OLAN şarkıyı gösterir — silinmiş
        // yollar listede hayalet kalmaz.
        final known = {
          for (final s in LibraryController.instance.songsNotifier.value)
            s.appPath,
        };
        final q = _listQuery.toLowerCase();
        final lists = q.isEmpty
            ? allLists
            : allLists
                .where((pl) => pl.name.toLowerCase().contains(q))
                .toList();
        if (allLists.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    color: _p.orange.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.queue_music_rounded,
                    size: 52,
                    color: _p.mute,
                  ),
                ),
                const SizedBox(height: 16),
                Text('Henüz liste yok', style: TextStyle(color: _p.mute)),
                const SizedBox(height: 20),
                TapScale(
                  child: ElevatedButton.icon(
                  onPressed: _create,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _p.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Liste Oluştur'),
                  ),
                ),
              ],
            ),
          );
        }
        return ValueListenableBuilder<SongItem?>(
          valueListenable: nowPlayingNotifier,
          builder: (context, nowPlaying, _) {
            return Column(
              children: [
                SongSearchField(
                  palette: _p,
                  hintText: 'Liste ara',
                  onChanged: (v) => setState(() => _listQuery = v),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: _listSel.isActive ? _listSel.clear : null,
                    child: lists.isEmpty
                      ? Center(
                          child: Text(
                            'Liste bulunamadı',
                            style: TextStyle(color: _p.mute),
                          ),
                        )
                      : ListView.builder(
          padding: EdgeInsets.only(
            bottom: miniPlayerListPadding(nowPlaying),
            top: 8,
          ),
          itemCount: lists.length,
          itemBuilder: (context, index) {
            final pl = lists[index];
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _listSel.isSelected(pl.id)
                    ? _p.orange.withValues(alpha: 0.22)
                    : _p.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _listSel.isSelected(pl.id)
                      ? _p.orange
                      : _p.cardBorder,
                ),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  leading: Icon(Icons.queue_music_rounded, color: _p.orange),
                  onLongPress: () => _listSel.begin(pl.id),
                  title: Text(
                    pl.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    '${pl.songPaths.where(known.contains).length} şarkı',
                    style: TextStyle(color: _p.mute, fontSize: 12),
                  ),
                  onTap: () async {
                    if (_listSel.isActive) {
                      _listSel.toggle(pl.id);
                      return;
                    }
                    await Navigator.push(
                      context,
                      CobblePageRoute(
                        builder: (_) =>
                            PlaylistDetailScreen(playlist: pl, palette: _p),
                      ),
                    );
                    await LibraryController.instance.refreshPlaylists();
                  },
                  trailing: _listMenu(pl),
                ),
              ),
            );
          },
            ),
                ),
                ),
                _listsBar(),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CobblestonePalette>(
      valueListenable: ThemeController.instance.paletteNotifier,
      builder: (context, _, __) {
        return DefaultTabController(
      length: 2,
      child: Builder(
        builder: (context) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              title: _favSel.isActive
                  ? GestureDetector(
                      onTap: _favSel.clear,
                      child: Container(
                        width: double.infinity,
                        child: Text('${_favSel.count} şarkı seçildi'),
                      ),
                    )
                  : _listSel.isActive
                  ? GestureDetector(
                      onTap: _listSel.clear,
                      child: Container(
                        width: double.infinity,
                        child: Text('${_listSel.count} liste seçildi'),
                      ),
                    )
                  : const Row(
                      children: [
                        CobbleLogo(size: 26),
                        SizedBox(width: 10),
                        Text("Listeler"),
                      ],
                    ),
              actions: (_favSel.isActive || _listSel.isActive)
                  ? [
                      IconButton(
                        tooltip: 'Tümünü seç',
                        icon: const Icon(Icons.select_all_rounded),
                        onPressed: () {
                          if (_favSel.isActive) {
                            final pls = LibraryController
                                .instance.playlistsNotifier.value;
                            final fav = pls.firstWhere(
                              (pl) => pl.id == PlaylistStorage.favoritesId,
                              orElse: () => PlaylistItem(
                                id: PlaylistStorage.favoritesId,
                                name: PlaylistStorage.favoritesName,
                              ),
                            );
                            _favSel.selectAllVisible(fav.songPaths);
                          } else if (_listSel.isActive) {
                            final q = _listQuery.toLowerCase();
                            _listSel.selectAllVisible(
                              LibraryController
                                  .instance.playlistsNotifier.value
                                  .where(
                                    (pl) =>
                                        pl.id != PlaylistStorage.favoritesId,
                                  )
                                  .where(
                                    (pl) =>
                                        q.isEmpty ||
                                        pl.name.toLowerCase().contains(q),
                                  )
                                  .map((pl) => pl.id),
                            );
                          }
                        },
                      ),
                      IconButton(
                        tooltip: 'Seçimi temizle',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _favSel.clear();
                          _listSel.clear();
                        },
                      ),
                    ]
                  : [
                      ValueListenableBuilder<int>(
                        valueListenable: _tabIdx,
                        builder: (_, idx, __) => idx == 0
                            ? IconButton(
                                tooltip: 'Favorileri paylaş',
                                icon: Icon(
                                  Icons.share_rounded,
                                  color: _p.orange,
                                ),
                                onPressed: _shareFavorites,
                              )
                            : const SizedBox.shrink(),
                      ),
                      IconButton(
                        tooltip: 'Ekle',
                        icon: const Icon(Icons.add_rounded),
                        onPressed: () {
                          if (_tabIdx.value == 0) {
                            _addSongsToFavorites();
                          } else if (_tabIdx.value == 1) {
                            _create();
                          }
                        },
                      ),
                    ],
              bottom: TabBar(
                indicatorColor: _p.orange,
                labelColor: _p.orange,
                unselectedLabelColor: _p.mute,
                indicatorSize: TabBarIndicatorSize.label,
                tabs: const [
                  Tab(text: 'Favoriler'),
                  Tab(text: 'Listeler'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _TabIdxReporter(
                  index: 0,
                  notifier: _tabIdx,
                  child: ListenableBuilder(
                    listenable: _favSel,
                    builder: (_, __) => _buildFavoritesTab(),
                  ),
                ),
                _TabIdxReporter(
                  index: 1,
                  notifier: _tabIdx,
                  child: _buildListsTab(),
                ),
              ],
            ),
          );
        },
      ),
        );
      },
    );
  }
}

class PlaylistDetailScreen extends StatefulWidget {
  final PlaylistItem playlist;
  final CobblestonePalette palette;
  const PlaylistDetailScreen({
    super.key,
    required this.playlist,
    required this.palette,
  });
  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  CobblestonePalette get _p =>
      ThemeController.instance.paletteNotifier.value;
  String _query = '';
  final _sel = SongSelection();

  @override
  void initState() {
    super.initState();
    ThemeController.instance.paletteNotifier.addListener(_onPalette);
  }

  @override
  void dispose() {
    ThemeController.instance.paletteNotifier.removeListener(_onPalette);
    super.dispose();
  }

  void _onPalette() {
    if (mounted) setState(() {});
  }

  void _showOptions(SongItem song) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _p.card,
      isScrollControlled: true,
      builder: (sheet) {
        final bottom = MediaQuery.viewPaddingOf(sheet).bottom;
        return SafeArea(
        child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: bottom > 8 ? 12 : 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...queueActionTiles(
              sheetContext: sheet,
              pageContext: this.context,
              song: song,
              palette: _p,
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
                leading: const Icon(
                  Icons.remove_circle_outline,
                  color: Colors.redAccent,
                ),
                title: const Text(
                  'Bu Listeden Çıkar',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.pop(sheet);
                  await PlaylistStorage.removeSongFromPlaylist(
                    widget.playlist.id,
                    song.appPath,
                  );
                  await LibraryController.instance.refreshPlaylists();
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

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CobblestonePalette>(
      valueListenable: ThemeController.instance.paletteNotifier,
      builder: (context, _, __) {
        return ListenableBuilder(
          listenable: _sel,
          builder: (context, _) => Scaffold(
      // v5.1.3: kendi temalı zemini — alttaki rota çizilmez; saydamda
      // siyah kalıyordu. Atmosfer gövdeyi sarar, dönüş akıcı olur.
      backgroundColor: _p.bg,
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
            : Text(widget.playlist.name),
        actions: _sel.isActive
            ? [
                IconButton(
                  tooltip: 'Tümünü seç',
                  icon: const Icon(Icons.select_all_rounded),
                  onPressed: () {
                    final pls = LibraryController
                        .instance.playlistsNotifier.value;
                    final cur = pls.firstWhere(
                      (pl) => pl.id == widget.playlist.id,
                      orElse: () => widget.playlist,
                    );
                    _sel.selectAllVisible(cur.songPaths);
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
                  icon: const Icon(Icons.add),
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      CobblePageRoute(
                        builder: (_) => AddSongsToPlaylistScreen(
                          playlist: widget.playlist,
                          palette: _p,
                        ),
                      ),
                    );
                    await LibraryController.instance.refreshPlaylists();
                  },
                ),
              ],
      ),
      body: AmbientLayer(
        palette: _p,
        child: ValueListenableBuilder<List<PlaylistItem>>(
        valueListenable: LibraryController.instance.playlistsNotifier,
        builder: (context, allPlaylists, _) {
          final current = allPlaylists.firstWhere(
            (pl) => pl.id == widget.playlist.id,
            orElse: () => widget.playlist,
          );
          return ValueListenableBuilder<List<SongItem>>(
            valueListenable: LibraryController.instance.songsNotifier,
            builder: (context, allSongs, _) {
              final inPlaylist = allSongs
                  .where((s) => current.songPaths.contains(s.appPath))
                  .toList();
              final songs = _query.isEmpty
                  ? inPlaylist
                  : inPlaylist
                      .where(
                        (s) => s.title.toLowerCase().contains(
                          _query.toLowerCase(),
                        ),
                      )
                      .toList();

              return Column(
                children: [
                  if (inPlaylist.isNotEmpty)
                    SongSearchField(
                      palette: _p,
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  Expanded(
                    child: GestureDetector(
                      onTap: _sel.isActive ? _sel.clear : null,
                      child: inPlaylist.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Bu listede şarkı yok',
                                  style: TextStyle(color: _p.mute),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    await Navigator.push(
                                      context,
                                      CobblePageRoute(
                                        builder: (_) =>
                                            AddSongsToPlaylistScreen(
                                              playlist: widget.playlist,
                                              palette: _p,
                                            ),
                                      ),
                                    );
                                    await LibraryController.instance
                                        .refreshPlaylists();
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _p.orange,
                                    foregroundColor: Colors.white,
                                  ),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Şarkı Ekle'),
                                ),
                              ],
                            ),
                          )
                        : songs.isEmpty
                        ? Center(
                            child: Text(
                              'Sonuç bulunamadı',
                              style: TextStyle(color: _p.mute),
                            ),
                          )
                        : ValueListenableBuilder<SongItem?>(
                            valueListenable: nowPlayingNotifier,
                            builder: (context, nowPlaying, _) {
                              return ListView.builder(
                            padding: EdgeInsets.only(
                              bottom: miniPlayerListPadding(nowPlaying),
                            ),
                            itemCount: songs.length,
                            itemBuilder: (context, index) {
                              final song = songs[index];
                              return CobbleSongTile(
                                song: song,
                                palette: _p,
                                selected: _sel.isSelected(song.appPath),
                                onLongPress: () =>
                                    _sel.begin(song.appPath),
                                onTap: () {
                                  if (_sel.isActive) {
                                    _sel.toggle(song.appPath);
                                    return;
                                  }
                                  final full = inPlaylist.indexWhere(
                                    (x) => x.appPath == song.appPath,
                                  );
                                  playFromQueue(
                                    inPlaylist,
                                    full >= 0 ? full : index,
                                    origin: PlaybackOrigin.playlist(
                                      widget.playlist.id,
                                      widget.playlist.name,
                                    ),
                                  );
                                },
                                onMore: () {
                                  if (_sel.isActive) _sel.clear();
                                  _showOptions(song);
                                },
                              );
                            },
                          );
                            },
                          ),
                      ),
                  ),
                SelectionBottomBar(
                    removeFromPlaylistId: widget.playlist.id,
                    palette: _p,
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
          ),
        );
      },
    );
  }
}


/// Görünür iç sekmeyi bildirir (AppBar'daki paylaşı düğmesi için).
class _TabIdxReporter extends StatelessWidget {
  const _TabIdxReporter({
    required this.index,
    required this.notifier,
    required this.child,
  });

  final int index;
  final ValueNotifier<int> notifier;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (notifier.value != index) notifier.value = index;
    return child;
  }
}
