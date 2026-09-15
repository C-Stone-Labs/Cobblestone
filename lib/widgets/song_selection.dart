import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/song_item.dart';
import '../services/library_controller.dart';
import '../services/notification_permission.dart';
import '../services/playlist_storage.dart';
import '../models/playlist_item.dart';
import '../services/song_storage.dart';
import '../theme/palette.dart';
import 'cobble_toast.dart';
import 'tap_scale.dart';
import 'song_actions.dart';
import '../services/ui_events.dart';

/// v5.1.3: Çoklu seçim durumu — basılı tut ile başlar, dokunarak büyür.
/// Arama değişse de seçim KORUNUR (aratıp aratıp seçmek için).
class SongSelection extends ChangeNotifier {
  static final List<SongSelection> _instances = [];

  SongSelection() {
    _instances.add(this);
  }

  /// Geri tuşu / boş alana dokunma: aktif seçimleri kapatır.
  static bool get anyActive => _instances.any((s) => s._active);

  /// v5.1.3: mini oynatıcı seçim modundan KAÇAR — her seçim değişikliğinde
  /// artar, mini oynatıcı bunu dinler (aktifken kayarak iner, sonra döner).
  static final ValueNotifier<int> activityVersion = ValueNotifier<int>(0);
  static void clearAll() {
    for (final s in List<SongSelection>.from(_instances)) {
      if (s._active) s.clear();
    }
  }

  final Set<String> _paths = {};
  bool _active = false;

  @override
  void notifyListeners() {
    SongSelection.activityVersion.value++;
    super.notifyListeners();
  }

  bool get isActive => _active;
  int get count => _paths.length;
  bool isSelected(String p) => _paths.contains(p);
  Iterable<String> get paths => _paths;

  /// Uzun basma: seçim modu KAPALIYSA açar; zaten AÇIKSA basılı tutulan
  /// şarkıyı seçime EKLER/çıkarır — aratıp aratıp seçme akışında seçim
  /// asla istemsiz sıfırlanmaz.
  void begin(String path) {
    if (_active) {
      toggle(path);
      return;
    }
    _paths
      ..clear()
      ..add(path);
    _active = true;
    notifyListeners();
  }

  void toggle(String path) {
    if (_paths.contains(path)) {
      _paths.remove(path);
      if (_paths.isEmpty) _active = false;
    } else {
      _paths.add(path);
    }
    notifyListeners();
  }

  /// "Tümünü seç": görünen şarkıları MEVCUT seçime EKLER (birleşim) —
  /// arama yaparak parça parça seçme akışı desteklenir.
  void selectAllVisible(Iterable<String> visible) {
    _paths.addAll(visible);
    _active = _paths.isNotEmpty;
    notifyListeners();
  }

  void clear() {
    _paths.clear();
    _active = false;
    notifyListeners();
  }
}

void _snack(
  BuildContext context,
  CobblestonePalette p,
  String msg, {
  IconData? icon,
  Color? accent,
}) {
  showCobbleToast(context, msg, icon: icon, accent: accent);
}

Future<String?> _newPlaylistNameDialog(
  BuildContext context,
  CobblestonePalette p,
) async {
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: p.card,
      title: Text('Yeni Liste', style: TextStyle(color: p.orangeLight)),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Liste adı',
          hintStyle: TextStyle(color: p.mute),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Vazgeç', style: TextStyle(color: p.mute)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: Text('Oluştur', style: TextStyle(color: p.orange)),
        ),
      ],
    ),
  );
  if (name == null || name.isEmpty) return null;
  return name;
}

/// Akıllı mesaj yardımcıları: 1 → "Bir şarkı", n → "3 şarkı".
String _countTr(int n, String word, {bool cap = true}) =>
    n == 1 ? '${cap ? 'B' : 'b'}ir $word' : '$n $word';

Set<String> _favoritePaths() {
  final pls = LibraryController.instance.playlistsNotifier.value;
  for (final pl in pls) {
    if (pl.id == PlaylistStorage.favoritesId) {
      return pl.songPaths.toSet();
    }
  }
  return <String>{};
}

/// v5.1.3: ⋮ menüsündeki "Çalma Listesine Ekle" diyaloğunun aynısı,
/// çoklu seçim için. (Aynı tasarım: Yeni Liste Oluştur + liste listesi.)
Future<void> showAddToPlaylistDialog(
  BuildContext context,
  CobblestonePalette palette,
  List<SongItem> songs,
) async {
  final p = palette;
  // Diyalog kapanınca iç context ölür — sayfa context'ini sakla.
  final pageCtx = context;
  final playlists = LibraryController.instance.playlistsNotifier.value
      .where((pl) => pl.id != PlaylistStorage.favoritesId)
      .toList();
  if (playlists.isEmpty) {
    final wantsCreate = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: p.card,
        title: Text('Henüz Liste Yok', style: TextStyle(color: p.orangeLight)),
        content: const Text('Çalma listesi oluşturmak ister misin?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Oluştur'),
          ),
        ],
      ),
    );
    if (wantsCreate != true || !context.mounted) return;
    final name = await _newPlaylistNameDialog(context, p);
    if (name == null || !context.mounted) return;
    final newPl = await PlaylistStorage.createPlaylist(name);
    await PlaylistStorage.addSongsToPlaylist(
      newPl.id,
      songs.map((s) => s.appPath).toList(),
    );
    await LibraryController.instance.refreshPlaylists();
    if (pageCtx.mounted) {
      _snack(
        pageCtx,
        p,
        '"$name" oluşturuldu ve ${_countTr(songs.length, 'şarkı', cap: false)} eklendi.',
        icon: Icons.add_circle_rounded,
      );
    }
    return;
  }
  await showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: p.card,
      title: Text('Listeye Ekle', style: TextStyle(color: p.orangeLight)),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            Material(
              type: MaterialType.transparency,
              child: ListTile(
                leading: Icon(Icons.add_circle_outline, color: p.orange),
                title: Text(
                  'Yeni Liste Oluştur',
                  style: TextStyle(
                    color: p.orange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  final name = await _newPlaylistNameDialog(context, p);
                  if (name == null || !context.mounted) return;
                  final newPl = await PlaylistStorage.createPlaylist(name);
                  await PlaylistStorage.addSongsToPlaylist(
                    newPl.id,
                    songs.map((s) => s.appPath).toList(),
                  );
                  await LibraryController.instance.refreshPlaylists();
                  if (pageCtx.mounted) {
                    _snack(
                      pageCtx,
                      p,
                      '"$name" oluşturuldu ve ${_countTr(songs.length, 'şarkı', cap: false)} eklendi.',
                      icon: Icons.add_circle_rounded,
                    );
                  }
                },
              ),
            ),
            ...playlists.map((pl) {
              final allIn = songs.every((s) => pl.songPaths.contains(s.appPath));
              return Material(
                type: MaterialType.transparency,
                child: ListTile(
                  leading: Icon(
                    allIn ? Icons.check_circle : Icons.circle_outlined,
                    color: allIn ? p.orange : p.mute,
                  ),
                  title: Text(
                    pl.name,
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    // v5.1.3: zaten listede olanlar eklenmez, mesaj akıllı.
                    final toAdd = songs
                        .where((s) => !pl.songPaths.contains(s.appPath))
                        .toList();
                    final already = songs.length - toAdd.length;
                    if (toAdd.isEmpty) {
                      if (pageCtx.mounted) {
                        _snack(
                          pageCtx,
                          p,
                          songs.length == 1
                              ? 'Bu şarkı zaten "${pl.name}" listesinde.'
                              : 'Seçilen şarkılar zaten "${pl.name}" listesinde.',
                          icon: Icons.info_rounded,
                        );
                      }
                      return;
                    }
                    await PlaylistStorage.addSongsToPlaylist(
                      pl.id,
                      toAdd.map((s) => s.appPath).toList(),
                    );
                    await LibraryController.instance.refreshPlaylists();
                    if (pageCtx.mounted) {
                      _snack(
                        pageCtx,
                        p,
                        '"${pl.name}" listesine ${_countTr(toAdd.length, 'şarkı', cap: false)} eklendi.'
                        '${already == 1 ? ' Diğeri zaten listedeydi.' : already > 1 ? ' $already tanesi zaten listedeydi.' : ''}',
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
          child: Text('Vazgeç', style: TextStyle(color: p.mute)),
        ),
      ],
    ),
  );
}

/// Seçim modundaki aksiyon çubuğu: Favori · Liste · Paylaş · Sil.
/// Düz ve tam genişlik (üst köşeleri yuvarlak, kenar süsü yok — listeyi
/// kapatmaz). İlk aksiyon akıllıdır: seçilenlerin HEPSİ favoriyse
/// "Çıkar", değilse "Favori" olur.
/// [removeFromPlaylistId]: liste detayında ikinci aksiyon
/// "Listeden Çıkar" olur.
class SelectionBottomBar extends StatelessWidget {
  final CobblestonePalette palette;
  final SongSelection selection;
  final List<SongItem> visibleSongs;
  final Future<void> Function() onChanged;
  final String? removeFromPlaylistId;

  /// v5.1.3: YALNIZCA Favoriler sekmesinde "Çıkar" (favorilerden) düğmesi
  /// görünür. Favori/liste EKLEME seçim çubuğundan kaldırıldı — ekleme
  /// yalnız ⋮ menüsünde. Liste detayında "Listeden Çıkar" (bkz.
  /// [removeFromPlaylistId]), her yerde Paylaş + Sil kalır.
  final bool showRemoveFavorite;

  const SelectionBottomBar({
    super.key,
    required this.palette,
    required this.selection,
    required this.visibleSongs,
    required this.onChanged,
    this.removeFromPlaylistId,
    this.showRemoveFavorite = false,
  });

  List<SongItem> get _selected =>
      visibleSongs.where((s) => selection.isSelected(s.appPath)).toList();

  /// Ray yazıcısı: yalnızca aktif çubuk yazar; kapatan (son yazan) temizler.
  static Object? _railWriter;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      final ro = context.findRenderObject();
      final h = ro is RenderBox && ro.hasSize ? ro.size.height : 0.0;
      if (selection.isActive && h > 4) {
        _railWriter = context;
        selectionRailPx.value =
            80 + MediaQuery.viewPaddingOf(context).bottom + h + 14;
      } else if (_railWriter == context && selectionRailPx.value != 0) {
        _railWriter = null;
        selectionRailPx.value = 0;
      }
    });
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.25),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      child: selection.isActive
          ? Padding(
              // Mini oynatıcı seçim modundayken kaçar; alta boşluk gerekmez.
              padding: const EdgeInsets.only(bottom: 14),
              child: _barContent(context, p),
            )
          : const SizedBox.shrink(key: ValueKey('hidden')),
    );
  }

  Widget _barContent(BuildContext context, CobblestonePalette p) {
    return Container(
      key: const ValueKey('visible'),
      // v5.1.3: düz ve tam genişlik — kenar boşluğu/gölge yok, üst köşe
      // yuvarlak; şarkı listesinin üstünü örtmez.
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(
          top: BorderSide(color: p.orange.withValues(alpha: 0.45)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
          child: Row(
            children: [
              for (final a in _actions(context)) Expanded(child: _btn(a)),
            ],
          ),
        ),
      ),
    );
  }

  /// v5.1.3: ekrana göre DEREDEN aksiyonlar. Favorilere/listeye EKLEME
  /// yalnız ⋮ menüsündedir; seçim çubuğu güç işlerine (paylaş/sil) ve
  /// bulunuş yerine özgü çıkarmaya odaklanır.
  List<({IconData icon, String label, Color color, VoidCallback onTap})>
      _actions(BuildContext context) {
    final p = palette;
    return [
      if (showRemoveFavorite)
        (
          icon: Icons.remove_circle_outline,
          label: 'Çıkar',
          color: p.orange,
          onTap: () => _removeFromFavorites(context),
        ),
      if (removeFromPlaylistId != null)
        (
          icon: Icons.playlist_remove_rounded,
          label: 'Listeden Çıkar',
          color: p.orange,
          onTap: () => _removeFromPlaylist(context),
        ),
      (
        icon: Icons.share_rounded,
        label: 'Paylaş',
        color: p.orange,
        onTap: () => _share(context),
      ),
      (
        icon: Icons.delete_rounded,
        label: 'Sil',
        color: Colors.redAccent,
        onTap: () => _delete(context),
      ),
    ];
  }

  Widget _btn(
    ({IconData icon, String label, Color color, VoidCallback onTap}) a,
  ) {
    final p = palette;
    return TapScale(
      child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: a.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: a.color.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(a.icon, color: a.color, size: 22),
            ),
            const SizedBox(height: 4),
            // Uzun etiket ("Listeden Çıkar") taşmaz — ölçeklenir.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                a.label,
                maxLines: 1,
                style: TextStyle(
                  color: a.color == Colors.redAccent ? a.color : p.mute,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    ));}
  Future<void> _removeFromFavorites(BuildContext context) async {
    final songs = _selected;
    if (songs.isEmpty) return;
    // v5.1.3: yalnızca favori OLANLAR çıkar; toggle tuzağı kapatıldı.
    final fav = _favoritePaths();
    final toRemove =
        songs.where((s) => fav.contains(s.appPath)).toList();
    final others = songs.length - toRemove.length;
    if (toRemove.isNotEmpty) {
      await PlaylistStorage.removeSongsFromFavorites(
        toRemove.map((s) => s.appPath).toList(),
      );
    }
    selection.clear();
    await onChanged();
    if (context.mounted) {
      _snack(
        context,
        palette,
        toRemove.isEmpty
            ? 'Seçilen şarkılar zaten favorilerde değildi.'
            : '${_countTr(toRemove.length, 'şarkı')} favorilerden çıkarıldı.'
              '${others == 1 ? ' Diğeri zaten favorilerde değildi.' : others > 1 ? ' $others tanesi zaten favorilerde değildi.' : ''}',
        icon: Icons.star_border_rounded,
      );
    }
  }

  Future<void> _removeFromPlaylist(BuildContext context) async {
    final id = removeFromPlaylistId;
    if (id == null) return;
    final songs = _selected;
    if (songs.isEmpty) return;
    await PlaylistStorage.removeSongsFromPlaylist(
      id,
      songs.map((s) => s.appPath).toList(),
    );
    selection.clear();
    await onChanged();
    if (context.mounted) {
      _snack(context, palette, '${songs.length == 1 ? 'Bir şarkı' : '${songs.length} şarkı'} listeden çıkarıldı.', icon: Icons.playlist_remove_rounded);
    }
  }
  Future<void> _share(BuildContext context) async {
    final songs = _selected;
    if (songs.isEmpty) return;
    // Tek → düz dosya; çok → "n şarkı" adlı ZIP.
    await shareSongs(songs, context);
    selection.clear();
  }

  Future<void> _delete(BuildContext context) async {
    final songs = _selected;
    if (songs.isEmpty) return;
    final mode = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: palette.card,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.amber),
              title: const Text(
                'Sadece Uygulamadan Sil',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(ctx, 'app'),
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_forever,
                color: Colors.redAccent,
              ),
              title: const Text(
                'Uygulamadan ve Telefondan Sil',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(ctx, 'phone'),
            ),
          ],
        ),
      ),
    );
    if (mode == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.card,
        title: Text(
          '${songs.length} şarkı silinsin mi?',
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          mode == 'app'
              ? 'Şarkılar yalnızca uygulama kütüphanesinden kaldırılır; '
                    'telefondaki dosyalar durur.'
              : 'Şarkılar hem uygulama kütüphanesinden hem telefondan '
                    'kalıcı olarak silinir.',
          style: TextStyle(color: palette.mute, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Vazgeç', style: TextStyle(color: palette.mute)),
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
    try {
      if (mode == 'app') {
        for (final s in songs) {
          await SongStorage.deleteFromAppOnly(s);
        }
      } else {
        // v5.1.3: telefon silme TEK onayla — parmak ağrımaz.
        await ensureLegacyStoragePermission();
        await SongStorage.deleteManyFromAppAndPhone(songs);
      }
      // Budama SongStorage içinde yapılır (tek merkez).
    } catch (_) {}
    selection.clear();
    await onChanged();
    if (context.mounted) {
      _snack(context, palette, '${songs.length == 1 ? 'Bir şarkı' : '${songs.length} şarkı'} silindi.', icon: Icons.delete_rounded, accent: Colors.redAccent);
    }
  }
}
