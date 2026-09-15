import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/song_item.dart';
import '../models/playlist_item.dart';
import 'id3_tags.dart';
import 'song_storage.dart';
import 'playlist_storage.dart';

/// Şarkı ve çalma listesi verisinin TEK ortak kaynağı.
/// Her ekran kendi kopyasını tutup manuel yenilemek yerine bunu dinler;
/// bir yerde değişiklik olduğunda TÜM ekranlar (arka plandaki sekmeler dahil)
/// otomatik güncellenir.
class LibraryController {
  LibraryController._();
  static final LibraryController instance = LibraryController._();

  final ValueNotifier<List<SongItem>> songsNotifier = ValueNotifier([]);
  final ValueNotifier<List<PlaylistItem>> playlistsNotifier = ValueNotifier([]);

  bool _backfillRunning = false;

  Future<void> loadAll() async {
    songsNotifier.value = await SongStorage.loadSongs();
    playlistsNotifier.value = await PlaylistStorage.loadPlaylists();
    unawaited(backfillId3());
  }

  Future<void> updateSong(SongItem updated) async {
    final songs = List<SongItem>.from(songsNotifier.value);
    final i = songs.indexWhere((s) => s.appPath == updated.appPath);
    if (i < 0) return;
    songs[i] = updated;
    await SongStorage.saveSongs(songs);
    songsNotifier.value = songs;
  }

  /// Kayıtlı başlık dosya adından kısaysa / ID3 daha doluysa bir kez onar.
  /// Büyük kütüphanede 50'şer parti; her partide UI'ye nefes.
  Future<void> backfillId3() async {
    if (_backfillRunning) return;
    _backfillRunning = true;
    try {
      const batch = 50;
      var songs = List<SongItem>.from(songsNotifier.value);
      var dirty = false;
      for (var i = 0; i < songs.length; i++) {
        // Tarama/ekleme sırasında liste değişmiş olabilir.
        if (i >= songsNotifier.value.length) break;
        if (songs[i].appPath != songsNotifier.value[i].appPath) {
          songs = List<SongItem>.from(songsNotifier.value);
          if (i >= songs.length) break;
        }
        final s = songs[i];
        if (s.metaEdited) continue;
        try {
          if (!await File(s.appPath).exists()) continue;
          final tags = await Id3Tags.read(s.appPath);
          final fileStem = p.basenameWithoutExtension(s.appPath);
          var title = s.title;
          var artist = s.artist;
          var album = s.album;
          if (tags.title != null &&
              tags.title!.isNotEmpty &&
              (title.trim().isEmpty ||
                  title == fileStem ||
                  tags.title!.length > title.length + 2)) {
            title = tags.title!;
          }
          if ((artist == null || artist.isEmpty) &&
              tags.artist != null &&
              tags.artist!.isNotEmpty) {
            artist = tags.artist;
          }
          if ((album == null || album.isEmpty) &&
              tags.album != null &&
              tags.album!.isNotEmpty) {
            album = tags.album;
          }
          if (title != s.title || artist != s.artist || album != s.album) {
            songs[i] = s.copyWith(title: title, artist: artist, album: album);
            dirty = true;
          }
        } catch (_) {}
        if (i % batch == batch - 1) {
          if (dirty) {
            await _commitBackfill(songs);
            dirty = false;
            songs = List<SongItem>.from(songsNotifier.value);
          }
          await Future<void>.delayed(Duration.zero);
        }
      }
      if (dirty) {
        await _commitBackfill(songs);
      }
    } finally {
      _backfillRunning = false;
    }
  }

  /// Tarama yeni şarkı eklerken backfill'in eski listeyi üzerine yazmasını önler.
  Future<void> _commitBackfill(List<SongItem> updated) async {
    final live = List<SongItem>.from(songsNotifier.value);
    final byPath = {for (final s in updated) s.appPath: s};
    var changed = false;
    for (var i = 0; i < live.length; i++) {
      final u = byPath[live[i].appPath];
      if (u == null) continue;
      if (u.title != live[i].title ||
          u.artist != live[i].artist ||
          u.album != live[i].album) {
        live[i] = live[i].copyWith(
          title: u.title,
          artist: u.artist,
          album: u.album,
        );
        changed = true;
      }
    }
    if (!changed) return;
    await SongStorage.saveSongs(live);
    songsNotifier.value = live;
  }

  Future<void> refreshSongs() async {
    songsNotifier.value = await SongStorage.loadSongs();
  }

  Future<void> refreshPlaylists() async {
    playlistsNotifier.value = await PlaylistStorage.loadPlaylists();
  }

  PlaylistItem? favoritesPlaylist() {
    for (final pl in playlistsNotifier.value) {
      if (pl.id == PlaylistStorage.favoritesId) return pl;
    }
    return null;
  }

  bool isFavorite(String songPath) {
    return favoritesPlaylist()?.songPaths.contains(songPath) ?? false;
  }

  Future<void> toggleFavorite(String songPath) async {
    await PlaylistStorage.toggleFavorite(songPath);
    await refreshPlaylists();
  }
}
