import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/song_item.dart';
import '../screens/file_info_screen.dart';
import '../services/library_controller.dart';
import '../services/theme_controller.dart';
import '../services/notification_permission.dart';
import '../services/player_controller.dart';
import '../services/song_storage.dart';
import '../theme/palette.dart';
import 'cobble_toast.dart';
import 'cobble_page_route.dart';

const _native = MethodChannel('cobble/native');

Future<void> openFileInfo(
  BuildContext context,
  SongItem song,
  CobblestonePalette palette,
) async {
  if (!context.mounted) return;
  await Navigator.of(context).push(
    CobblePageRoute(
      builder: (_) => FileInfoScreen(song: song, palette: palette),
    ),
  );
}

/// v5.1.3: "hazırlanıyor" penceresi — ne olduğu kullanıcı dilinde.
class _ZipProgressDialog extends StatelessWidget {
  const _ZipProgressDialog({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final p = ThemeController.instance.paletteNotifier.value;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: p.cardBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 42,
              height: 42,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(color: p.mute, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> shareSong(SongItem song, [BuildContext? context]) async {
  try {
    await _native.invokeMethod('shareFile', {'path': song.appPath});
  } catch (_) {
    final ctx = context;
    if (ctx != null && ctx.mounted) {
      showCobbleToast(
        ctx,
        'Paylaşılamadı — dosya bulunamadı ya da izin yok.',
        icon: Icons.error_outline_rounded,
        accent: Colors.redAccent,
      );
    }
  }
}

/// v5.1.3: şarkıları paylaş. Tek şarkı → düz dosya; birden çok →
/// şık adlandırılmış tek ZIP (klasör gibi). [zipName]: klasör/liste adı.
Future<void> shareSongs(
  List<SongItem> songs, [
  BuildContext? context,
  String? zipName,
]) async {
  if (songs.isEmpty) {
    // v5.1.3: boş liste sessizce kapanmasın — nedeni söyle.
    if (context != null && context.mounted) {
      showCobbleToast(
        context,
        'Paylaşılacak şarkı yok.',
        icon: Icons.info_rounded,
      );
    }
    return;
  }
  // Aynı şarkı bir kez girer (liste + klasör kesişimi vb.).
  final seen = <String>{};
  final unique = <SongItem>[];
  for (final s in songs) {
    if (seen.add(s.appPath)) unique.add(s);
  }
  final ctx0 = context;
  if (unique.length == 1 || ctx0 == null || !ctx0.mounted) {
    // Tek şarkı: doğrudan dosya.
    try {
      await _native.invokeMethod('shareFile', {
        'path': unique.first.appPath,
      });
    } catch (_) {
      _shareFail(ctx0);
    }
    return;
  }
  // Çoklu: kullanıcı seçer — tek ZIP (toplu, taşınabilir) ya da ayrı
  // ses dosyaları (tek tuşla açılır, WhatsApp'ta ayrı ayrı görünür).
  final asZip = await showModalBottomSheet<bool>(
    context: ctx0,
    backgroundColor: ThemeController.instance.paletteNotifier.value.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheet) => _ShareChoiceSheet(
      count: unique.length,
      name: zipName ?? '${unique.length} şarkı',
    ),
  );
  if (asZip == null) return;
  final name = zipName ?? '${unique.length} şarkı';
  final paths = unique.map((s) => s.appPath).toList();
  // v5.1.3: hazırlık zaman alır — dönen göstergeli pencere; parmak yolu
  // keser, çift basılamaz, geri tuşu kapatamaz. AYRI dosyalar da
  // kopyalanıyor: o yolda da gösterilir.
  await _withPreparingDialog(
    ctx0,
    asZip ? '"$name.zip" hazırlanıyor…' : 'Şarkılar hazırlanıyor…',
    asZip ? 'Şarkılar tek dosyada toplanıyor' : 'Dosyalar paylaşım için kopyalanıyor',
    () async {
      try {
        if (asZip) {
          await _native.invokeMethod('shareFilesAsZip', {
            'paths': paths,
            'name': name,
          });
        } else {
          await _native.invokeMethod('shareFiles', {'paths': paths});
        }
      } catch (_) {
        if (ctx0.mounted) _shareFail(ctx0);
      }
    },
  );
}

/// v5.1.3: iş bitene kadar dönen göstergeli "hazırlanıyor" penceresi.
Future<void> _withPreparingDialog(
  BuildContext ctx,
  String title,
  String subtitle,
  Future<void> Function() job,
) async {
  if (!ctx.mounted) {
    await job();
    return;
  }
  final nav = Navigator.of(ctx, rootNavigator: true);
  final dialog = showDialog(
    context: ctx,
    useRootNavigator: true,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    builder: (_) => PopScope(
      canPop: false,
      child: _ZipProgressDialog(title: title, subtitle: subtitle),
    ),
  );
  try {
    await job();
  } finally {
    nav.pop();
    await dialog;
  }
}

void _shareFail(BuildContext? ctx) {
  if (ctx != null && ctx.mounted) {
    showCobbleToast(
      ctx,
      'Paylaşılamadı — dosya bulunamadı ya da izin yok.',
      icon: Icons.error_outline_rounded,
      accent: Colors.redAccent,
    );
  }
}

/// v5.1.3: çoklu paylaşım biçimi seçimi — ZIP ya da ayrı dosyalar.
class _ShareChoiceSheet extends StatelessWidget {
  const _ShareChoiceSheet({required this.count, required this.name});

  final int count;
  final String name;

  @override
  Widget build(BuildContext context) {
    final p = ThemeController.instance.paletteNotifier.value;
    Widget option({
      required IconData icon,
      required String title,
      required String subtitle,
      required bool value,
    }) {
      return ListTile(
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: p.orange.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: p.orange, size: 21),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: p.mute, fontSize: 12, height: 1.35),
        ),
        onTap: () => Navigator.pop(context, value),
      );
    }

    return SafeArea(
      top: false,
      child: Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: p.mute.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '$count şarkıyı nasıl paylaşmak istersin?',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          option(
            icon: Icons.audio_file_rounded,
            title: 'Ayrı Ses Dosyaları',
            subtitle: 'Tek tuşla açılır — her şarkı ayrı gider',
            value: false,
          ),
          option(
            icon: Icons.folder_zip_rounded,
            title: 'Tek ZIP Dosyası',
            subtitle: '"$name.zip" — toplu ve düzenli',
            value: true,
          ),
        ],
      ),
      ),
    );
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

List<Widget> queueActionTiles({
  required BuildContext sheetContext,
  required BuildContext pageContext,
  required SongItem song,
  required CobblestonePalette palette,
}) {
  return [
    Material(
      type: MaterialType.transparency,
      child: ListTile(
        leading: Icon(Icons.playlist_play_rounded, color: palette.orange),
        title: const Text('Sonra çal', style: TextStyle(color: Colors.white)),
        subtitle: Text(
          'Sıradaki parça bu olsun',
          style: TextStyle(color: palette.mute, fontSize: 12),
        ),
        onTap: () async {
          Navigator.pop(sheetContext);
          await playNextSong(song);
          if (pageContext.mounted) {
            _snack(pageContext, palette, 'Sıradaki: ${song.title}', icon: Icons.queue_music_rounded);
          }
        },
      ),
    ),
    Material(
      type: MaterialType.transparency,
      child: ListTile(
        leading: Icon(Icons.queue_rounded, color: palette.orange),
        title: const Text('Sıraya ekle', style: TextStyle(color: Colors.white)),
        subtitle: Text(
          'Kuyruğun sonuna ekle',
          style: TextStyle(color: palette.mute, fontSize: 12),
        ),
        onTap: () async {
          Navigator.pop(sheetContext);
          await enqueueSong(song);
          if (pageContext.mounted) {
            _snack(pageContext, palette, 'Kuyruğa eklendi', icon: Icons.playlist_add_rounded);
          }
        },
      ),
    ),
  ];
}

List<Widget> fileInfoAndShareTiles({
  required BuildContext sheetContext,
  required BuildContext pageContext,
  required SongItem song,
  required CobblestonePalette palette,
}) {
  return [
    Material(
      type: MaterialType.transparency,
      child: ListTile(
        leading: Icon(Icons.info_outline_rounded, color: palette.orange),
        title: const Text(
          'Dosya bilgileri',
          style: TextStyle(color: Colors.white),
        ),
        subtitle: Text(
          'Ad, sanatçı, albüm, kapak',
          style: TextStyle(color: palette.mute, fontSize: 12),
        ),
        onTap: () {
          Navigator.pop(sheetContext);
          openFileInfo(pageContext, song, palette);
        },
      ),
    ),
    Material(
      type: MaterialType.transparency,
      child: ListTile(
        leading: Icon(Icons.share_rounded, color: palette.orange),
        title: const Text(
          'Parçayı paylaş',
          style: TextStyle(color: Colors.white),
        ),
        subtitle: Text(
          'WhatsApp, Bluetooth, Drive…',
          style: TextStyle(color: palette.mute, fontSize: 12),
        ),
        onTap: () {
          Navigator.pop(sheetContext);
          shareSong(song, pageContext);
        },
      ),
    ),
  ];
}

/// Ortak ⋮ menü (Şarkılar / Klasör / Akıllı listeler).
Future<void> showSongOptionsSheet({
  required BuildContext context,
  required SongItem song,
  required CobblestonePalette palette,
  bool showDelete = true,
}) async {
  final isFav = LibraryController.instance.isFavorite(song.appPath);
  final pageContext = context;
  await showModalBottomSheet(
    context: context,
    backgroundColor: palette.card,
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
                color: palette.mute.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            Material(
              type: MaterialType.transparency,
              child: ListTile(
                leading: Icon(
                  isFav ? Icons.star_rounded : Icons.star_border_rounded,
                  color: palette.orange,
                ),
                title: Text(
                  isFav ? 'Favorilerden Çıkar' : 'Favorilere Ekle',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  final wasFav = isFav;
                  Navigator.pop(sheet);
                  await LibraryController.instance.toggleFavorite(song.appPath);
                  if (pageContext.mounted) {
                    showCobbleToast(
                      pageContext,
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
              pageContext: pageContext,
              song: song,
              palette: palette,
            ),
            ...fileInfoAndShareTiles(
              sheetContext: sheet,
              pageContext: pageContext,
              song: song,
              palette: palette,
            ),
            if (showDelete) ...[
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
                    if (pageContext.mounted) {
                      showCobbleToast(
                        pageContext,
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
                  leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
                  title: const Text(
                    'Uygulamadan ve Telefondan Sil',
                    style: TextStyle(color: Colors.white),
                  ),
                onTap: () async {
                  Navigator.pop(sheet);
                  try {
                    // v5.1.1: Android 9- cihazlarda silme öncesi depolama izni.
                    await ensureLegacyStoragePermission();
                    await SongStorage.deleteFromAppAndPhone(song);
                    await LibraryController.instance.refreshSongs();
                  } catch (e) {
                      await LibraryController.instance.refreshSongs();
                      if (pageContext.mounted) {
                        _snack(
                          pageContext,
                          palette,
                          'Şarkı telefondan silinemedi. Dosya başka bir uygulamada açık olabilir.',
                          icon: Icons.error_outline_rounded,
                          accent: Colors.redAccent,
                        );
                      }
                    }
                  },
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
      );
    },
  );
}

/// Klasör / akıllı liste sağındaki çal-duraklat.
Widget originPlayPauseButton({
  required String originId,
  required String originName,
  required List<SongItem> songs,
  required Color color,
}) {
  return ValueListenableBuilder<PlaybackOrigin>(
    valueListenable: playbackOriginNotifier,
    builder: (context, origin, _) {
      return ValueListenableBuilder<SongItem?>(
        valueListenable: nowPlayingNotifier,
        builder: (context, now, _) {
          return StreamBuilder<PlayerState>(
            stream: globalPlayer.playerStateStream,
            builder: (context, snap) {
              final isThis = origin.id == originId &&
                  now != null &&
                  songs.any((s) => s.appPath == now.appPath);
              final pause = isThis &&
                  (snap.data?.showPauseIcon ?? globalPlayer.showPauseIcon);
              return IconButton(
                tooltip: pause ? 'Duraklat' : 'Çal',
                icon: Icon(
                  pause ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: color,
                ),
                onPressed: songs.isEmpty
                    ? null
                    : () {
                        if (isThis && pause) {
                          globalPlayer.pause();
                        } else if (isThis && !pause) {
                          globalPlayer.play();
                        } else {
                          playFromQueue(
                            songs,
                            0,
                            origin: PlaybackOrigin.playlist(
                              originId,
                              originName,
                            ),
                          );
                        }
                      },
              );
            },
          );
        },
      );
    },
  );
}
