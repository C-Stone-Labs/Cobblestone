import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song_item.dart';
import 'id3_tags.dart';
import 'playlist_storage.dart';
import 'stats_service.dart';

class SongStorage {
  static const _prefsKey = 'saved_songs_v1';
  static const _deletedPrefKey = 'deleted_songs_v1';
  static const _fileName = 'library_v1.json';

  static Set<String>? _deletedCache;

  static Future<Directory> _musicDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'music'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<File> _libraryFile() async {
    final appDir = await getApplicationDocumentsDirectory();
    return File(p.join(appDir.path, _fileName));
  }

  /// [copyToApp]: file picker / "şununla aç" geçici dosyaları için true.
  /// Klasör taramasında false — orijinal dosya çalınır, depolama ikiye katlanmaz.
  static Future<SongItem> importSong({
    required String sourcePath,
    required String title,
    required int size,
    bool copyToApp = true,
  }) async {
    String targetPath = sourcePath;
    if (copyToApp) {
      // v5.1.3: ayni dosya (ad+boyut) zaten kutuphanedeyse KOPYA YOK —
      // mevcut kayit doner; numarali ikinci kopya uretimi kokten biter.
      final dupe = await findExisting(
        sourcePath: sourcePath,
        size: size,
      );
      if (dupe != null) {
        await unmarkDeleted(dupe.appPath);
        return dupe;
      }
      final musicDir = await _musicDir();
      final fileName = p.basename(sourcePath);
      targetPath = p.join(musicDir.path, fileName);

      int counter = 1;
      while (await File(targetPath).exists()) {
        final nameWithoutExt = p.basenameWithoutExtension(fileName);
        final ext = p.extension(fileName);
        targetPath = p.join(musicDir.path, '${nameWithoutExt}_$counter$ext');
        counter++;
      }

      await File(sourcePath).copy(targetPath);
    }

    var resolvedSize = size;
    if (resolvedSize <= 0) {
      try {
        resolvedSize = await File(targetPath).length();
      } catch (_) {}
    }

    final tags = await Id3Tags.read(targetPath);
    final resolvedTitle = (tags.title != null && tags.title!.isNotEmpty)
        ? tags.title!
        : (title.trim().isNotEmpty
              ? title
              : p.basenameWithoutExtension(sourcePath));

    await unmarkDeleted(sourcePath);
    await unmarkDeleted(targetPath);

    return SongItem(
      title: resolvedTitle,
      appPath: targetPath,
      // v5.1.3: dosya seçici önbellek yolu klasör görünümüne sızmasın.
      originalPath: sourcePath.contains('/cache/') ? null : sourcePath,
      artist: tags.artist,
      album: tags.album,
      size: resolvedSize,
      addedMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  static bool _isAppPrivateDir(String dir) {
    final n = dir.replaceAll('\\', '/').toLowerCase();
    return n.contains('/app_flutter/') ||
        n.contains('/files/music') ||
        n.contains('/cache/') ||
        (n.contains('/data/user/') && n.contains('/music'));
  }

  static String _realPathOf(SongItem s) {
    final orig = s.originalPath;
    if (orig != null &&
        orig.isNotEmpty &&
        !_isAppPrivateDir(p.dirname(orig))) {
      return orig;
    }
    return s.appPath;
  }

  /// v5.1.3: ayni dosya kutuphanede var mi?
  /// Eslesme: birebir yol YADA ayni ad + ayni boyut (kume birlesimi).
  static Future<SongItem?> findExisting({
    required String sourcePath,
    required int size,
  }) async {
    final songs = await loadSongs();
    for (final s in songs) {
      if (s.appPath == sourcePath || s.originalPath == sourcePath) {
        return s;
      }
    }
    if (size <= 0) return null;
    final key = '${p.basename(sourcePath).toLowerCase()}|$size';
    for (final s in songs) {
      if (s.size > 0 &&
          '${p.basename(_realPathOf(s)).toLowerCase()}|${s.size}' == key) {
        return s;
      }
    }
    return null;
  }

  /// v5.1.3 onarim: ayni dosyanin (ad+boyut) birden cok kaydi varsa
  /// birlestirir. Kalan: orijinal konumdaki kayit (uygulama-ici kopya
  /// degil). Favoriler, listeler ve istatistikler kalan kayda yonlendirilir.
  static Future<int> mergeDuplicates() async {
    try {
      final songs = await loadSongs();
      if (songs.length < 2) return 0;
      final groups = <String, List<SongItem>>{};
      for (final s in songs) {
        if (s.size <= 0) continue;
        final key =
            '${p.basename(_realPathOf(s)).toLowerCase()}|${s.size}';
        groups.putIfAbsent(key, () => []).add(s);
      }
      final removed = <SongItem, SongItem>{};
      for (final g in groups.values) {
        if (g.length < 2) continue;
        final originals = g
            .where((s) => !_isAppPrivateDir(p.dirname(_realPathOf(s))))
            .toList();
        final keeper = originals.isNotEmpty ? originals.first : g.first;
        for (final s in g) {
          if (!identical(s, keeper)) removed[s] = keeper;
        }
      }
      if (removed.isEmpty) return 0;
      final result = songs.where((s) => !removed.containsKey(s)).toList();
      await saveSongs(result);
      for (final e in removed.entries) {
        try {
          await PlaylistStorage.redirectSongPath(
            e.key.appPath,
            e.value.appPath,
          );
          StatsService.instance.redirectPath(
            e.key.appPath,
            e.value.appPath,
          );
          await unmarkDeleted(e.key.appPath);
        } catch (_) {}
      }
      return removed.length;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> saveSongs(List<SongItem> songs) async {
    final file = await _libraryFile();
    final payload = jsonEncode({
      'v': 1,
      'songs': [for (final s in songs) s.toJson()],
    });
    await _atomicWrite(file, payload);
    try {
      const ch = MethodChannel('cobble/native');
      await ch.invokeMethod('notifyLibraryChanged');
    } catch (_) {}
  }

  /// Diskteki kayıt (silinenler hariç). exists süzmesi yok — yok sayılan
  /// dosyayı JSON'dan silmez (SD kart / tarama sırasında veri kaybı olmasın).
  static Future<List<SongItem>> loadSongs() async {
    final songs = await _readLibrary();
    final deleted = await deletedPathSet();
    if (deleted.isEmpty) return songs;
    return [
      for (final song in songs)
        if (!deleted.contains(song.appPath) &&
            (song.originalPath == null ||
                song.originalPath!.isEmpty ||
                !deleted.contains(song.originalPath)))
          song,
    ];
  }

  static Future<List<SongItem>> _readLibrary() async {
    final file = await _libraryFile();
    if (await file.exists()) {
      try {
        final raw = jsonDecode(await file.readAsString());
        if (raw is Map<String, dynamic>) {
          final list = raw['songs'];
          if (list is List) {
            return [
              for (final e in list)
                if (e is Map)
                  SongItem.fromJson(Map<String, dynamic>.from(e)),
            ];
          }
        }
      } catch (e) {
        debugPrint('library json okunamadı: $e');
      }
    }
    return _migrateFromPrefs();
  }

  static Future<List<SongItem>> _migrateFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getStringList(_prefsKey);
    if (encoded == null || encoded.isEmpty) return [];
    final songs = <SongItem>[];
    for (final e in encoded) {
      try {
        songs.add(SongItem.fromJson(jsonDecode(e) as Map<String, dynamic>));
      } catch (_) {}
    }
    try {
      await saveSongs(songs);
      await prefs.remove(_prefsKey);
    } catch (e) {
      debugPrint('library migrate kaydı: $e');
    }
    return songs;
  }

  static Future<void> deleteFromAppOnly(SongItem song) async {
    final songs = await loadSongs();
    songs.removeWhere(
      (e) =>
          e.appPath == song.appPath ||
          (song.originalPath != null && e.originalPath == song.originalPath),
    );
    await saveSongs(songs);
    // DÜZELTME (v5.1.1): dosya diskte durduğu için açılıştaki quickRescan
    // şarkıyı geri ekliyordu. Yolu "silinmiş" olarak işaretle; böylece
    // yalnızca Ayarlar → "Şimdi tara" (skipDeleted: false) geri getirir.
    await markDeleted(song.appPath, song.originalPath);
    // Telefondaki dosyaya dokunma. "Şimdi tara" ile geri gelir.
    final copied = song.originalPath != null &&
        song.originalPath != song.appPath &&
        song.appPath.contains('/music/');
    if (copied) {
      final file = File(song.appPath);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
    // v5.1.3: yolu TÜM listelerden (favoriler dahil) süpür — sayaçlarda
    // hayalet şarkı kalmasın.
    await PlaylistStorage.removePathsFromAllPlaylists([song.appPath]);
  }

  static Future<void> deleteFromAppAndPhone(SongItem song) async {
    final phonePath = song.originalPath ?? song.appPath;
    await markDeleted(song.appPath, song.originalPath);
    final songs = await loadSongs();
    songs.removeWhere(
      (e) => e.appPath == song.appPath || e.appPath == phonePath,
    );
    await saveSongs(songs);
    final copied = song.originalPath != null &&
        song.originalPath != song.appPath &&
        song.appPath.contains('/music/');
    if (copied) {
      try {
        final f = File(song.appPath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    final ok = await deletePhoneFile(phonePath);
    if (!ok) {
      throw const FileSystemException(
        'Şarkı telefondan silinemedi. İstersen telefonun Dosyalar '
        'uygulamasından silebilirsin.',
      );
    }
  }

  /// v5.1.3: çoklu "uygulamadan ve telefondan sil" — telefon tarafı
  /// TEK sistem onayıyla (Android 11+). Uygulama tarafı sessiz.
  static Future<void> deleteManyFromAppAndPhone(List<SongItem> songs) async {
    if (songs.isEmpty) return;
    final all = await loadSongs();
    final keys = songs.map((s) => s.appPath).toSet();
    final phoneKeys = songs.map((s) => s.originalPath ?? s.appPath).toSet();
    all.removeWhere((e) => keys.contains(e.appPath) || phoneKeys.contains(e.appPath));
    for (final s in songs) {
      await markDeleted(s.appPath, s.originalPath);
      final copied = s.originalPath != null &&
          s.originalPath != s.appPath &&
          s.appPath.contains('/music/');
      if (copied) {
        try {
          final f = File(s.appPath);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
    await saveSongs(all);
    // v5.1.3: yolları TÜM listelerden (favoriler dahil) süpür —
    // sayaçlarda hayalet şarkı kalmasın.
    await PlaylistStorage.removePathsFromAllPlaylists(
      songs.map((s) => s.appPath).toList(),
    );
    final phonePaths = songs.map((s) => s.originalPath ?? s.appPath).toList();
    var ok = false;
    try {
      const ch = MethodChannel('cobble/native');
      ok = await ch.invokeMethod<bool>('deletePhoneFiles', {
            'paths': phonePaths,
          }) ==
          true;
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      throw const FileSystemException(
        'Şarkılar telefondan silinemedi. İstersen telefonun Dosyalar '
        'uygulamasından silebilirsin.',
      );
    }
  }

  static Future<bool> deletePhoneFile(String path) async {
    try {
      const ch = MethodChannel('cobble/native');
      final ok = await ch.invokeMethod<bool>('deleteFromPhone', {'path': path});
      if (ok == true) return true;
    } catch (_) {}
    try {
      final f = File(path);
      if (await f.exists()) {
        await f.delete();
        return !await f.exists();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<Set<String>> deletedPathSet() async {
    final cached = _deletedCache;
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    final set = (prefs.getStringList(_deletedPrefKey) ?? []).toSet();
    _deletedCache = set;
    return set;
  }

  static Future<void> _writeDeleted(Set<String> deleted) async {
    _deletedCache = deleted;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_deletedPrefKey, deleted.toList());
  }

  static Future<void> unmarkDeleted(String path) async {
    final deleted = await deletedPathSet();
    if (deleted.remove(path)) {
      await _writeDeleted(deleted);
    }
  }

  static Future<void> unmarkDeletedMany(Iterable<String> paths) async {
    final deleted = await deletedPathSet();
    var changed = false;
    for (final path in paths) {
      if (deleted.remove(path)) changed = true;
    }
    if (changed) await _writeDeleted(deleted);
  }

  static Future<void> markDeleted(String appPath, String? originalPath) async {
    final deleted = await deletedPathSet();
    var changed = false;
    for (final path in [appPath, ?originalPath]) {
      if (deleted.add(path)) changed = true;
    }
    if (changed) await _writeDeleted(deleted);
  }

  static Future<bool> isDeleted(String path) async {
    return (await deletedPathSet()).contains(path);
  }
}

Future<void> _atomicWrite(File file, String payload) async {
  final tmp = File('${file.path}.tmp');
  await tmp.writeAsString(payload, flush: true);
  try {
    await tmp.rename(file.path);
    return;
  } catch (_) {}
  try {
    await file.writeAsString(payload, flush: true);
  } finally {
    try {
      if (await tmp.exists()) await tmp.delete();
    } catch (_) {}
  }
}
