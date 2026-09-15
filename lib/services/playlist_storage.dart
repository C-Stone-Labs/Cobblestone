import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/playlist_item.dart';

class PlaylistStorage {
  static const _prefsKey = 'saved_playlists_v1';
  static const _fileName = 'playlists_v1.json';
  static const _native = MethodChannel('cobble/native');

  // Favoriler, silinemeyen özel bir çalma listesi olarak saklanır.
  static const favoritesId = '__favorites__';
  static const favoritesName = 'Favoriler';

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _fileName));
  }

  static Future<List<PlaylistItem>> loadPlaylists() async {
    final list = await loadFromPrefsOnly();
    await _hydrateFromNative(list);
    return list;
  }

  /// Bildirim kanalı içinden çağrılır; tekrar native'e gitmez (kilitlenmesin).
  static Future<List<PlaylistItem>> loadFromPrefsOnly() async {
    final list = await _readLocal();
    if (!list.any((p) => p.id == favoritesId)) {
      list.insert(0, PlaylistItem(id: favoritesId, name: favoritesName));
      await savePlaylists(list, syncNative: false);
    }
    return list;
  }

  static Future<List<PlaylistItem>> _readLocal() async {
    final file = await _file();
    if (await file.exists()) {
      try {
        final raw = jsonDecode(await file.readAsString());
        if (raw is Map<String, dynamic>) {
          final list = raw['playlists'];
          if (list is List) {
            return [
              for (final e in list)
                if (e is Map)
                  PlaylistItem.fromJson(Map<String, dynamic>.from(e)),
            ];
          }
        }
      } catch (e) {
        debugPrint('playlists json okunamadı: $e');
      }
    }
    return _migrateFromPrefs();
  }

  static Future<List<PlaylistItem>> _migrateFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getStringList(_prefsKey);
    if (encoded == null || encoded.isEmpty) return [];
    final list = <PlaylistItem>[];
    for (final e in encoded) {
      try {
        list.add(PlaylistItem.fromJson(jsonDecode(e) as Map<String, dynamic>));
      } catch (_) {}
    }
    try {
      await savePlaylists(list, syncNative: false);
      await prefs.remove(_prefsKey);
    } catch (e) {
      debugPrint('playlists migrate: $e');
    }
    return list;
  }

  static Future<void> savePlaylists(
    List<PlaylistItem> playlists, {
    bool syncNative = true,
  }) async {
    final file = await _file();
    final payload = jsonEncode({
      'v': 1,
      'playlists': [for (final pl in playlists) pl.toJson()],
    });
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(payload, flush: true);
    try {
      await tmp.rename(file.path);
    } catch (_) {
      await file.writeAsString(payload, flush: true);
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
    }
    if (syncNative) await _syncNative(playlists);
    try {
      await _native.invokeMethod('notifyLibraryChanged');
    } catch (_) {}
  }

  static Future<PlaylistItem> createPlaylist(String name) async {
    final playlists = await loadPlaylists();
    final newPlaylist = PlaylistItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
    );
    playlists.add(newPlaylist);
    await savePlaylists(playlists);
    return newPlaylist;
  }

  static Future<void> deletePlaylist(String id) async {
    if (id == favoritesId) return; // Favoriler silinemez
    final playlists = await loadPlaylists();
    playlists.removeWhere((e) => e.id == id);
    await savePlaylists(playlists);
  }

  static Future<void> toggleSongInPlaylist(
    String playlistId,
    String songPath,
  ) async {
    final playlists = await loadPlaylists();
    final playlist = playlists.firstWhere((e) => e.id == playlistId);
    if (playlist.songPaths.contains(songPath)) {
      playlist.songPaths.remove(songPath);
    } else {
      playlist.songPaths.add(songPath);
    }
    await savePlaylists(playlists);
  }

  static Future<void> removeSongFromPlaylist(
    String playlistId,
    String songPath,
  ) async {
    final playlists = await loadPlaylists();
    final playlist = playlists.firstWhere((e) => e.id == playlistId);
    playlist.songPaths.remove(songPath);
    await savePlaylists(playlists);
  }

  /// v5.1.3 çoklu seçim: listeden YALNIZCA çıkarır.
  static Future<void> removeSongsFromPlaylist(
    String playlistId,
    List<String> songPaths,
  ) async {
    final playlists = await loadPlaylists();
    final playlist = playlists.firstWhere((e) => e.id == playlistId);
    playlist.songPaths.removeWhere(songPaths.contains);
    await savePlaylists(playlists);
  }

  /// v5.1.3: şarkı(lar) silindiğinde yollarını TÜM listelerden (favoriler
  /// dahil) temizler — sayaçlarda hayalet şarkı kalmasın.
  static Future<void> removePathsFromAllPlaylists(List<String> paths) async {
    if (paths.isEmpty) return;
    final playlists = await loadPlaylists();
    final dead = paths.toSet();
    var changed = false;
    for (final pl in playlists) {
      final before = pl.songPaths.length;
      pl.songPaths.removeWhere(dead.contains);
      if (pl.songPaths.length != before) changed = true;
    }
    if (changed) await savePlaylists(playlists);
  }

  static Future<bool> toggleFavorite(String songPath) async {
    final playlists = await loadPlaylists();
    final fav = playlists.firstWhere((e) => e.id == favoritesId);
    final isNowFavorite = !fav.songPaths.contains(songPath);
    if (isNowFavorite) {
      fav.songPaths.add(songPath);
    } else {
      fav.songPaths.remove(songPath);
    }
    await savePlaylists(playlists);
    return isNowFavorite;
  }

  /// v5.1.3: listeyi yeniden adlandırır.
  static Future<void> renamePlaylist(String id, String newName) async {
    final playlists = await loadPlaylists();
    try {
      playlists.firstWhere((p) => p.id == id).name = newName;
    } catch (_) {
      return;
    }
    await savePlaylists(playlists);
  }

  /// v5.1.3 çoklu seçim: favorilere YALNIZCA ekler (var olanı düşürmez).
  static Future<void> addSongsToFavorites(List<String> songPaths) async {
    final playlists = await loadPlaylists();
    final fav = playlists.firstWhere((e) => e.id == favoritesId);
    for (final p in songPaths) {
      if (!fav.songPaths.contains(p)) fav.songPaths.add(p);
    }
    await savePlaylists(playlists);
  }

  /// v5.1.3 çoklu seçim: favorilerden YALNIZCA çıkarır (olmayan dokunmaz).
  static Future<void> removeSongsFromFavorites(List<String> songPaths) async {
    final playlists = await loadPlaylists();
    final fav = playlists.firstWhere((e) => e.id == favoritesId);
    fav.songPaths.removeWhere(songPaths.toSet().contains);
    await savePlaylists(playlists);
  }

  /// v5.1.3 çoklu seçim: listeye YALNIZCA ekler (var olanı düşürmez).
  static Future<void> addSongsToPlaylist(
    String playlistId,
    List<String> songPaths,
  ) async {
    if (playlistId == favoritesId) return addSongsToFavorites(songPaths);
    final playlists = await loadPlaylists();
    final playlist = playlists.firstWhere((e) => e.id == playlistId);
    for (final p in songPaths) {
      if (!playlist.songPaths.contains(p)) playlist.songPaths.add(p);
    }
    await savePlaylists(playlists);
  }

  /// v5.1.3 yinelenenleri birleştirme: kaldırılan kopyanın yolu, kalan
  /// kaydın yoluna yönlendirilir (favoriler ve listeler kırılmasın).
  static Future<void> redirectSongPath(String from, String to) async {
    final playlists = await loadPlaylists();
    var changed = false;
    for (final pl in playlists) {
      final i = pl.songPaths.indexOf(from);
      if (i >= 0) {
        if (!pl.songPaths.contains(to)) {
          pl.songPaths[i] = to;
        } else {
          pl.songPaths.removeAt(i);
        }
        changed = true;
      }
    }
    if (changed) await savePlaylists(playlists);
  }

  /// Bildirim ★ sonucunu Flutter listesine yazar (native zaten güncel).
  static Future<void> replaceFavorites(List<String> paths) async {
    final list = await loadFromPrefsOnly();
    final fav = list.firstWhere((p) => p.id == favoritesId);
    fav.songPaths = List<String>.from(paths);
    await savePlaylists(list, syncNative: false);
  }

  static Future<void> _hydrateFromNative(List<PlaylistItem> list) async {
    try {
      final raw = await _native.invokeMethod<List<dynamic>>('getFavorites');
      final fav = list.firstWhere((p) => p.id == favoritesId);
      if (raw == null) {
        await _syncNative(list);
        return;
      }
      final native = raw.map((e) => e.toString()).toList();
      final a = fav.songPaths.toSet();
      final b = native.toSet();
      if (a.length == b.length && a.containsAll(b)) return;
      fav.songPaths = native;
      await savePlaylists(list, syncNative: false);
    } catch (_) {}
  }

  static Future<void> _syncNative(List<PlaylistItem> playlists) async {
    try {
      final fav = playlists.firstWhere(
        (p) => p.id == favoritesId,
        orElse: () => PlaylistItem(id: favoritesId, name: favoritesName),
      );
      await _native.invokeMethod('syncFavorites', {'paths': fav.songPaths});
    } catch (_) {}
  }
}
