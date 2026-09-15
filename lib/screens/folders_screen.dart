import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import '../models/song_item.dart';
import '../services/folder_watch.dart';
import '../services/notification_permission.dart';
import '../services/playlist_storage.dart';
import '../services/theme_controller.dart';
import '../services/library_controller.dart';
import '../services/player_controller.dart';
import '../services/song_storage.dart';
import '../theme/palette.dart';
import '../widgets/cobble_toast.dart';
import '../widgets/cobble_logo.dart';
import '../widgets/mini_player.dart';
import '../widgets/ambient_layer.dart';
import '../widgets/song_actions.dart';
import '../widgets/song_search_field.dart';
import '../widgets/song_tile.dart';
import '../widgets/song_selection.dart';
import '../widgets/cobble_page_route.dart';

/// Samsung Music / Musicolet / Poweramp gibi: her dosya yalnızca
/// bulunduğu klasörde bir kez. Uygulama kopyası ayrı klasör sayılmaz.
class FoldersScreen extends StatefulWidget {
  final CobblestonePalette palette;
  const FoldersScreen({super.key, required this.palette});

  @override
  State<FoldersScreen> createState() => _FoldersScreenState();
}

class _FoldersScreenState extends State<FoldersScreen> {
  CobblestonePalette get _p => widget.palette;
  String _query = '';
  final _folderSel = SongSelection();

  @override
  void initState() {
    super.initState();
    // v5.1.3: klasör seçimi ekranı anında tazelesin.
    _folderSel.addListener(_onSelChange);
  }

  @override
  void dispose() {
    _folderSel.removeListener(_onSelChange);
    super.dispose();
  }

  void _onSelChange() {
    if (mounted) setState(() {});
  }

  String _norm(String p) {
    var s = p.replaceAll('\\', '/');
    s = s.replaceAll('/storage/emulated/0', '/sdcard');
    s = s.replaceAll('/storage/self/primary', '/sdcard');
    return s.toLowerCase();
  }

  bool _isAppPrivate(String dir) {
    final n = _norm(dir);
    return n.contains('/app_flutter/') ||
        n.contains('/files/music') ||
        (n.contains('/data/user/') && n.contains('/music'));
  }

  String _realPath(SongItem s) {
    final orig = s.originalPath;
    if (orig != null && orig.isNotEmpty && !_isAppPrivate(path.dirname(orig))) {
      return orig;
    }
    return s.appPath;
  }

  Map<String, List<SongItem>> _group(List<SongItem> songs) {
    final map = <String, List<SongItem>>{};
    final seenPath = <String>{};
    final seenNameSize = <String>{};
    for (final s in songs) {
      final real = _realPath(s);
      final id = _norm(s.dedupeKey);
      if (!seenPath.add(id)) continue;
      if (s.size > 0) {
        final ns = '${path.basename(real).toLowerCase()}|${s.size}';
        if (!seenNameSize.add(ns)) continue;
      }
      final dir = path.dirname(real);
      if (_isAppPrivate(dir) && s.originalPath != null && s.originalPath!.isNotEmpty) {
        final origDir = path.dirname(s.originalPath!);
        if (!_isAppPrivate(origDir)) {
          map.putIfAbsent(origDir, () => []).add(s);
          continue;
        }
      }
      map.putIfAbsent(dir, () => []).add(s);
    }
    final keys = map.keys.toList()
      ..sort(
        (a, b) => path
            .basename(a)
            .toLowerCase()
            .compareTo(path.basename(b).toLowerCase()),
      );
    return {for (final k in keys) k: map[k]!};
  }

  Future<void> _removeFolder(String dir, List<SongItem> songs) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _p.card,
        title: Text(
          'Klasör kaldırılsın mı?',
          style: TextStyle(color: _p.orangeLight),
        ),
        content: Text(
          '"${path.basename(dir)}" uygulamanın kütüphanesinden çıkarılacak. '
          'Telefondaki dosyalara dokunulmaz.',
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
              'Kaldır',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    for (final s in songs) {
      await SongStorage.deleteFromAppOnly(s);
    }
    await FolderWatch.instance.unwatch(dir);
    await LibraryController.instance.refreshSongs();
    if (!mounted) return;
    showCobbleToast(context, '${songs.length == 1 ? 'Bir şarkı' : '${songs.length} şarkı'} uygulamadan kaldırıldı.', icon: Icons.delete_outline_rounded);
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: _folderSel.isActive
            ? GestureDetector(
                onTap: _folderSel.clear,
                child: Container(
                  width: double.infinity,
                  child: Text('${_folderSel.count} klasör seçildi'),
                ),
              )
            : const Row(
                children: [
                  CobbleLogo(size: 26),
                  SizedBox(width: 10),
                  Text('Klasörler'),
                ],
              ),
        actions: _folderSel.isActive
            ? [
                IconButton(
                  tooltip: 'Tümünü seç',
                  icon: const Icon(Icons.select_all_rounded),
                  onPressed: () => _folderSel.selectAllVisible(
                    FolderWatch.instance.foldersNotifier.value,
                  ),
                ),
                IconButton(
                  tooltip: 'Seçimi temizle',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: _folderSel.clear,
                ),
              ]
            : [
                IconButton(
                  tooltip: 'Tümünü tara',
                  icon: Icon(Icons.sync_rounded, color: p.orange),
                  onPressed: () =>
                      FolderWatch.instance.manualScan(context, p),
                ),
                IconButton(
                  tooltip: 'Klasör ekle',
                  icon: Icon(Icons.add_rounded, color: p.orange),
                  onPressed: () => FolderWatch.pickAndScan(context, p),
                ),
              ],
      ),
      body: ValueListenableBuilder<SongItem?>(
        valueListenable: nowPlayingNotifier,
        builder: (context, nowPlaying, _) {
          return ValueListenableBuilder<List<SongItem>>(
            valueListenable: LibraryController.instance.songsNotifier,
            builder: (context, all, _) {
              final grouped = _group(all);
              final q = _query.toLowerCase();
              final entries = grouped.entries.where((e) {
                if (q.isEmpty) return true;
                return path.basename(e.key).toLowerCase().contains(q) ||
                    e.key.toLowerCase().contains(q);
              }).toList();
              return Column(
                children: [
                  if (all.isNotEmpty)
                    SongSearchField(
                      palette: p,
                      hintText: 'Klasör ara',
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  Expanded(
                    child: GestureDetector(
                      onTap: _folderSel.isActive ? _folderSel.clear : null,
                      child: all.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(28),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 104,
                                    height: 104,
                                    decoration: BoxDecoration(
                                      color: p.orange.withValues(alpha: 0.10),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.folder_rounded,
                                      size: 52,
                                      color: p.mute,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Klasör eklemek için sağ üstteki + düğmesine bas. '
                                    'Seçtiğin klasördeki şarkılar kütüphaneye alınır.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: p.mute,
                                      height: 1.45,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : entries.isEmpty
                            ? Center(
                                child: Text(
                                  'Klasör bulunamadı',
                                  style: TextStyle(color: p.mute),
                                ),
                              )
                            : ListView.builder(
                                padding: EdgeInsets.only(
                                  bottom: miniPlayerListPadding(nowPlaying),
                                  top: 8,
                                ),
                                itemCount: entries.length,
                                itemBuilder: (context, i) {
                                  final dir = entries[i].key;
                                  final songs = entries[i].value;
                                  final name = path.basename(dir).isEmpty
                                      ? dir
                                      : path.basename(dir);
                                  return Container(
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _folderSel.isSelected(dir)
                                          ? p.orange.withValues(alpha: 0.22)
                                          : p.card,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: _folderSel.isSelected(dir)
                                            ? p.orange
                                            : p.cardBorder,
                                      ),
                                    ),
                                    child: Material(
                                      type: MaterialType.transparency,
                                      child: ListTile(
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                        leading: Icon(
                                          Icons.folder_rounded,
                                          color: p.orange,
                                        ),
                                        title: Text(
                                          name,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        subtitle: Text(
                                          '${songs.length} şarkı · $dir',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: p.mute,
                                            fontSize: 12,
                                          ),
                                        ),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            originPlayPauseButton(
                                              originId: 'folder:$dir',
                                              originName: name,
                                              songs: songs,
                                              color: p.orange,
                                            ),
                                            IconButton(
                                              tooltip: 'Klasör menüsü',
                                              icon: Icon(
                                                Icons.more_vert_rounded,
                                                color: p.mute,
                                              ),
                                              onPressed: () =>
                                                  _folderMenu(dir, name, songs),
                                            ),
                                          ],
                                        ),
                                        onTap: () {
                                          if (_folderSel.isActive) {
                                            _folderSel.toggle(dir);
                                            return;
                                          }
                                          Navigator.of(context).push(
                                            CobblePageRoute(
                                              builder: (_) =>
                                                  FolderSongsScreen(
                                                folderPath: dir,
                                                songs: songs,
                                                palette: p,
                                              ),
                                            ),
                                          );
                                        },
                                        onLongPress: () =>
                                            _folderSel.begin(dir),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                  ),
                _foldersBar(p),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _foldersBar(CobblestonePalette p) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      child: _folderSel.isActive
          ? Container(
              key: const ValueKey('foldbar'),
              // v5.1.3: yüzen kapsül — alttaki sekmelere bitişik değil.
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: p.orange.withValues(alpha: 0.45),
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
                        '${_folderSel.count} klasör seçildi',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          // Seçili klasörlerdeki TÜM şarkıları, klasör
                          // adını taşıyan tek ZIP olarak paylaş.
                          final dirs = _folderSel.paths.toList();
                          final name = dirs.length == 1
                              ? path.basename(dirs.first)
                              : '${dirs.length} klasör';
                          final all = LibraryController
                              .instance.songsNotifier.value;
                          final grouped = _group(all);
                          final songs = <SongItem>[];
                          for (final d in dirs) {
                            songs.addAll(grouped[d] ?? const <SongItem>[]);
                          }
                          if (songs.isEmpty) {
                            showCobbleToast(
                              context,
                              'Klasörde paylaşılabilecek şarkı yok.',
                              icon: Icons.info_rounded,
                            );
                            return;
                          }
                          shareSongs(songs, context, name);
                        },
                        child: Text(
                          'Paylaş',
                          style: TextStyle(color: p.orange),
                        ),
                      ),
                      TextButton(
                        onPressed: _removeSelectedFolders,
                        child: const Text(
                          'Kaldır',
                          style: TextStyle(color: Colors.redAccent),
                        ),
                      ),
                      TextButton(
                        onPressed: _folderSel.clear,
                        child: Text('Vazgeç', style: TextStyle(color: p.mute)),
                      ),
                    ],
                  ),
                ),
            )
          : const SizedBox.shrink(key: ValueKey('foldbaroff')),
    );
  }

  /// v5.1.3: klasör ⋮ menüsü — yeniden adlandır / kaldır.
  void _folderMenu(String dir, String name, List<SongItem> songs) {
    if (_folderSel.isActive) _folderSel.clear();
    final pl = ThemeController.instance.paletteNotifier.value;
    showModalBottomSheet(
      context: context,
      backgroundColor: pl.card,
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
              color: pl.mute.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: Icon(Icons.sync_rounded, color: pl.orange),
            title: const Text(
              'Bu Klasörü Tara',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              'Yeni şarkıları kontrol et',
              style: TextStyle(color: pl.mute, fontSize: 12),
            ),
            onTap: () {
              Navigator.pop(sheet);
              FolderWatch.instance.scanOne(context, pl, dir);
            },
          ),
          ListTile(
            leading: Icon(Icons.share_rounded, color: pl.orange),
            title: const Text(
              'Paylaş',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              songs.isEmpty
                  ? 'Klasör boş'
                  : 'Klasördeki şarkıların tamamı',
              style: TextStyle(color: pl.mute, fontSize: 12),
            ),
            onTap: () {
              Navigator.pop(sheet);
              if (songs.isEmpty) {
                showCobbleToast(
                  context,
                  'Paylaşılacak şarkı yok.',
                  icon: Icons.info_rounded,
                );
                return;
              }
              shareSongs(songs, context, name);
            },
          ),
          ListTile(
            leading: Icon(
              Icons.drive_file_rename_outline_rounded,
              color: pl.orange,
            ),
            title: const Text(
              'Yeniden Adlandır',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              'Telefondaki klasörün adı değişir',
              style: TextStyle(color: pl.mute, fontSize: 12),
            ),
            onTap: () {
              Navigator.pop(sheet);
              _renameFolder(dir);
            },
          ),
          ListTile(
            leading: const Icon(
              Icons.remove_circle_outline,
              color: Colors.redAccent,
            ),
            title: const Text(
              'Kaldır',
              style: TextStyle(color: Colors.white),
            ),
            onTap: () {
              Navigator.pop(sheet);
              _removeFolder(dir, songs);
            },
          ),
          const SizedBox(height: 12),
        ],
        ),
      ),
    );
  }

  Future<void> _renameFolder(String dir) async {
    final pl = ThemeController.instance.paletteNotifier.value;
    final oldName = path.basename(dir);
    final controller = TextEditingController(text: oldName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: pl.card,
        title: Text(
          'Klasörü Yeniden Adlandır',
          style: TextStyle(color: pl.orangeLight),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Klasör adı',
                labelStyle: TextStyle(color: pl.mute),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Telefondaki gerçek klasörün adı değişir; içindeki şarkılar '
              'kütüphanede kalır.',
              style: TextStyle(
                color: pl.mute,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Vazgeç',
                style: TextStyle(color: pl.mute)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(
              'Kaydet',
              style: TextStyle(color: pl.orange),
            ),
          ),
        ],
      ),
    );
    if (name == null ||
        name.isEmpty ||
        name.contains('/') ||
        name == oldName) {
      return;
    }
    final parent = path.dirname(dir);
    final newDir = '$parent/$name';
    bool ok = false;
    try {
      ok = await const MethodChannel('cobble/native').invokeMethod<bool>(
            'renameFolder',
            {'old': dir, 'new': newDir},
          ) ==
          true;
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      if (mounted) {
        // v5.1.3: izin gerçekten eksikse izin diyalogu; açıksa dürüst hata.
        final shown = await showAllFilesHelpDialog(context);
        if (!shown && mounted) {
          showCobbleToast(
            context,
            'Klasör adı değiştirilemedi.',
            icon: Icons.info_rounded,
          );
        }
      }
      return;
    }
    // Klasör kaydını yeni yola taşı.
    await FolderWatch.instance.renameWatched(dir, newDir);
    // Şarkı yollarını güncelle (appPath + originalPath ön ekleri).
    final songs = await SongStorage.loadSongs();
    final updated = songs.map((s) {
      var ns = s;
      if (s.appPath.startsWith('$dir/')) {
        ns = ns.copyWith(
          appPath: '$newDir/${s.appPath.substring(dir.length + 1)}',
        );
      }
      if ((s.originalPath ?? '').startsWith('$dir/')) {
        ns = ns.copyWith(
          originalPath: '$newDir/${s.originalPath!.substring(dir.length + 1)}',
        );
      }
      return ns;
    }).toList();
    await SongStorage.saveSongs(updated);
    // Listelerdeki yolları da güncelle.
    final pls = await PlaylistStorage.loadPlaylists();
    for (final pl in pls) {
      for (var i = 0; i < pl.songPaths.length; i++) {
        if (pl.songPaths[i].startsWith('$dir/')) {
          pl.songPaths[i] =
              '$newDir/${pl.songPaths[i].substring(dir.length + 1)}';
        }
      }
    }
    await PlaylistStorage.savePlaylists(pls);
    await LibraryController.instance.refreshSongs();
    await LibraryController.instance.refreshPlaylists();
    if (mounted) {
      showCobbleToast(
        context,
        'Klasörün adı "$oldName" → "$name" oldu.',
        icon: Icons.drive_file_rename_outline_rounded,
      );
    }
  }

  Future<void> _removeSelectedFolders() async {
    final dirs = _folderSel.paths.toList();
    if (dirs.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _p.card,
        title: Text(
          '${dirs.length} klasör kaldırılsın mı?',
          style: TextStyle(color: _p.orangeLight),
        ),
        content: Text(
          'Seçili klasörler uygulamanın kütüphanesinden çıkarılır. '
          'Telefondaki dosyalara dokunulmaz.',
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
              'Kaldır',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final grouped = _group(LibraryController.instance.songsNotifier.value);
    for (final dir in dirs) {
      final songs = grouped[dir] ?? const <SongItem>[];
      for (final s in songs) {
        await SongStorage.deleteFromAppOnly(s);
      }
      await FolderWatch.instance.unwatch(dir);
    }
    _folderSel.clear();
    await LibraryController.instance.refreshSongs();
    if (mounted) {
      showCobbleToast(context, '${dirs.length == 1 ? 'Bir klasör' : '${dirs.length} klasör'} kaldırıldı.', icon: Icons.folder_off_rounded);
    }
  }

}

class FolderSongsScreen extends StatefulWidget {
  final String folderPath;
  final List<SongItem> songs;
  final CobblestonePalette palette;
  const FolderSongsScreen({
    super.key,
    required this.folderPath,
    required this.songs,
    required this.palette,
  });

  @override
  State<FolderSongsScreen> createState() => _FolderSongsScreenState();
}

class _FolderSongsScreenState extends State<FolderSongsScreen> {
  bool _didUnwatch = false;
  String _query = '';
  final _sel = SongSelection();

  @override
  void initState() {
    super.initState();
    // v5.1.3: canlı tema — klasör içi tema değişiminde anında güncellenir.
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
    final folderPath = widget.folderPath;
    final name = path.basename(folderPath);
    final q = _query.toLowerCase();
    return ListenableBuilder(
      listenable: Listenable.merge([
        _sel,
        LibraryController.instance.songsNotifier,
      ]),
      builder: (context, _) {
        // v5.1.3: şarkılar BURADA canlı okunur — silinen anında düşer.
        // (Eski kod listeyi build DIŞINDA hesaplayıp dinleyici kapanışına
        // esir düşürüyordu: silinse bile eski liste yeniden çiziliyordu.)
        final all = LibraryController.instance.songsNotifier.value
            .where(
              (s) =>
                  s.appPath.startsWith('$folderPath/') ||
                  (s.originalPath ?? '').startsWith('$folderPath/'),
            )
            .toList();
        final songs = q.isEmpty
            ? all
            : all
                .where(
                  (s) =>
                      s.title.toLowerCase().contains(q) ||
                      s.displayArtist.toLowerCase().contains(q),
                )
                .toList();
        if (all.isEmpty && !_didUnwatch) {
          _didUnwatch = true;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            await FolderWatch.instance.unwatch(folderPath);
            if (mounted) {
              showCobbleToast(
                context,
                'Klasör boşaldığı için izlemeden çıkarıldı.',
                icon: Icons.folder_off_rounded,
              );
              Navigator.of(context).pop();
            }
          });
        }
        return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.bg,
        title: _sel.isActive
            ? GestureDetector(
                onTap: _sel.clear,
                child: Container(
                  width: double.infinity,
                  child: Text('${_sel.count} şarkı seçildi'),
                ),
              )
            : Text(name),
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
            originId: 'folder:$folderPath',
            originName: name,
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
              child: Text(
                'Bu klasörde şarkı yok',
                style: TextStyle(color: p.mute),
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
                          itemBuilder: (context, i) {
                            final song = songs[i];
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
                                  full >= 0 ? full : i,
                                  origin: PlaybackOrigin.playlist(
                                    'folder:$folderPath',
                                    name,
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
      },
    );
  }
}
