import 'package:path/path.dart' as p2;
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../screens/folder_picker_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song_item.dart';
import 'notification_permission.dart';
import '../widgets/cobble_toast.dart';
import '../widgets/cobble_page_route.dart';
import '../theme/palette.dart';
import 'library_controller.dart';
import 'song_storage.dart';

class FolderWatch {
  FolderWatch._();
  static final FolderWatch instance = FolderWatch._();

  static const _prefsKey = 'watch_folders_v1';
  static const _legacyKey = 'watch_folder_v1';
  static const _native = MethodChannel('cobble/native');
  /// Ses dosyası uzantıları — klasör seçici de bununla şarkı listeler.
  static const audioExts = {
    '.mp3',
    '.m4a',
    '.aac',
    '.flac',
    '.wav',
    '.ogg',
    '.oga',
    '.opus',
    '.amr',
    '.wma',
  };

  final ValueNotifier<String?> folderNotifier = ValueNotifier(null);
  final ValueNotifier<List<String>> foldersNotifier = ValueNotifier(const []);
  final ValueNotifier<String> lastScanNotifier = ValueNotifier(
    'Henüz taranmadı',
  );

  bool _loaded = false;
  bool _scanning = false;

  /// v5.1.3: klasör seçici tercihi — true: SİSTEM seçici kullanılır.
  final useSystemPicker = ValueNotifier<bool>(false);
  static const _systemPickerKey = 'folder_picker_system';

  Future<void> setSystemPicker(bool v) async {
    useSystemPicker.value = v;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_systemPickerKey, v);
    } catch (_) {}
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    try {
      useSystemPicker.value = prefs.getBool(_systemPickerKey) ?? false;
    } catch (_) {}
    var list = prefs.getStringList(_prefsKey) ?? <String>[];
    if (list.isEmpty) {
      final one = prefs.getString(_legacyKey);
      if (one != null && one.isNotEmpty) list = [one];
    }
    foldersNotifier.value = list;
    folderNotifier.value = list.isEmpty ? null : list.first;
  }

  Future<void> _persist(List<String> folders) async {
    foldersNotifier.value = folders;
    folderNotifier.value = folders.isEmpty ? null : folders.first;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, folders);
    if (folders.isNotEmpty) {
      await prefs.setString(_legacyKey, folders.first);
    } else {
      await prefs.remove(_legacyKey);
    }
  }

  /// v5.1.3: izlenen klasör telefonda yeniden adlandırıldı — kaydı
  /// yeni yola taşır.
  Future<void> renameWatched(String oldDir, String newDir) async {
    await load();
    final folders = List<String>.from(foldersNotifier.value);
    final i = folders.indexOf(oldDir);
    if (i >= 0) {
      folders[i] = newDir;
      await _persist(folders);
    }
  }

  Future<void> unwatch(String dir) async {
    await load();
    final folders = List<String>.from(foldersNotifier.value);
    folders.removeWhere(
      (w) => w == dir || dir.startsWith('$w/') || w.startsWith('$dir/'),
    );
    if (folders.length != foldersNotifier.value.length) {
      await _persist(folders);
    }
  }

  Future<bool> _ensureAudioPermission() async {
    var st = await Permission.audio.status;
    if (st.isGranted) return true;
    st = await Permission.audio.request();
    return st.isGranted;
  }

  Future<void> quickRescan() async {
    await load();
    if (foldersNotifier.value.isEmpty || _scanning) return;
    if (!await Permission.audio.isGranted) return;
    await _scanAll(skipDeleted: true);
  }

  /// v5.1.3: TEK klasörü tara (klasör ⋮ / Ayarlar çipi).
  Future<void> scanOne(BuildContext context, CobblestonePalette p, String dir) async {
    await load();
    if (_scanning) return;
    if (!await _ensureAudioPermission()) {
      if (context.mounted) {
        _toast(context, p, 'Müziklerine erişmek için izin gerekiyor', icon: Icons.lock_outline_rounded);
      }
      return;
    }
    _scanning = true;
    late final ({int added, int existing}) result;
    try {
      result = await _scan(dir, skipDeleted: false);
    } finally {
      _scanning = false;
    }
    if (context.mounted) {
      if (result.added > 0) {
        _toast(
          context,
          p,
          '${result.added == 1 ? 'Bir yeni şarkı' : '${result.added} yeni şarkı'} bulundu.'
              '${result.existing > 1 ? ' ${result.existing} tanesi zaten vardı.' : result.existing == 1 ? ' Diğeri zaten vardı.' : ''}',
          icon: Icons.library_music_rounded,
        );
      } else if (result.existing > 0) {
        _toast(context, p, 'Bu klasör zaten güncel.', icon: Icons.check_circle_rounded);
      } else {
        _toast(context, p, 'Klasörde ses dosyası bulunamadı', icon: Icons.info_rounded);
      }
    }
  }

  /// v5.1.3: müzik İÇEREN klasörlerin kümesi (üst klasörleriyle birlikte)
  /// — klasör seçici yalnız bunları listeler. MediaStore üzerinden: hızlı.
  static Future<Set<String>> musicFolderSet() async {
    try {
      final list = await _native.invokeMethod<List<dynamic>>('musicFolderSet');
      return list?.cast<String>().toSet() ?? <String>{};
    } catch (_) {
      return <String>{};
    }
  }

  /// v5.1.3: dosyalarından çoklu klasör ekle — seçilen şarkıların ANA
  /// klasörleri izlenenler arasına girer (aynı olanlar bir kez).
  static Future<void> pickAndScan(
    BuildContext context,
    CobblestonePalette p,
  ) async {
    final fw = instance;
    await fw.load();
    // v5.1.3: Ayarlar'dan "Sistem seçici" tercih edildiyse sistem ekranı
    // açılır (uygulama içi seçiciye dönmek isteyen ayarlardan değiştirir).
    if (fw.useSystemPicker.value) {
      final path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Müzik klasörünü seç',
      );
      if (path == null) return;
      await fw.addSelection(context, p, folders: [path]);
      return;
    }
    if (!await fw._ensureAudioPermission()) {
      if (context.mounted) {
        _toast(context, p, 'Müziklerine erişmek için izin gerekiyor', icon: Icons.lock_outline_rounded);
      }
      return;
    }
    // v5.1.3: "Tüm dosyalara erişim" varsa UYGULAMA İÇİ tarayıcı (çoklu
    // seçim dahil); yoksa kullanıcıya seçim sunulur.
    final granted = await isAllFilesGranted();
    if (granted) {
      if (!context.mounted) return;
      final res = await Navigator.of(context)
          .push<({List<String> folders, List<String> songs})>(
        CobblePageRoute(
          builder: (_) => FolderPickerScreen(palette: p),
        ),
      );
      if (res == null || (res.folders.isEmpty && res.songs.isEmpty)) return;
      await fw.addSelection(
        context,
        p,
        folders: res.folders,
        songPaths: res.songs,
      );
      return;
    }
    if (!context.mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.card,
        title: Text(
          'Kolay Klasör Seçme',
          style: TextStyle(color: p.orangeLight),
        ),
        content: Text(
          'Klasörleri uygulama içinde gezip tek dokunuşla seçmek için bir '
          'kereliğe "Tüm dosyalara erişim" izni ver. İstersen sistemin '
          'klasör seçicisini de kullanabilirsin.',
          style: const TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'system'),
            child: Text('Sistem Seçici', style: TextStyle(color: p.mute)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'grant'),
            style: FilledButton.styleFrom(backgroundColor: p.orange),
            child: const Text('İzin Ver'),
          ),
        ],
      ),
    );
    if (choice == 'grant') {
      await requestAllFilesAccess();
      // Ayarlardan dönünce: izin verildiyse seçiciyi DOĞRUDAN aç.
      final opened = await waitForSettingsReturn();
      if (!context.mounted) return;
      if (opened && await isAllFilesGranted()) {
        _toast(context, p, 'İzin verildi.', icon: Icons.check_circle_rounded);
        final res = await Navigator.of(context)
            .push<({List<String> folders, List<String> songs})>(
          CobblePageRoute(
            builder: (_) => FolderPickerScreen(palette: p),
          ),
        );
        if (res == null || (res.folders.isEmpty && res.songs.isEmpty)) return;
        await fw.addSelection(
          context,
          p,
          folders: res.folders,
          songPaths: res.songs,
        );
        return;
      }
      _toast(
        context,
        p,
        opened ? 'İzin hâlâ kapalı — istersen "Sistem Seçici"yi dene.' : 'İzin sayfası açılamadı.',
        icon: Icons.info_rounded,
      );
      return;
    }
    if (choice != 'system') return;
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Müzik klasörünü seç',
    );
    if (path == null) return;
    await fw.addSelection(context, p, folders: [path]);
  }

  /// v5.1.3: seçilen klasörleri VE tek tek seçilen şarkıları ekle —
  /// her koşulda tek, düzgün Türkçe özet kutusu. Zaten izlenen klasörler
  /// de YENİDEN TARANIR: uygulamadan silinmiş şarkılar geri gelir.
  Future<void> addSelection(
    BuildContext context,
    CobblestonePalette p, {
    List<String> folders = const [],
    List<String> songPaths = const [],
  }) async {
    await load();
    final existing = List<String>.from(foldersNotifier.value);

    // ── Klasörler: yeni mi, zaten izleniyor mu? ──
    final fresh = <String>[];
    final known = <String>[];
    for (final d in folders.toSet()) {
      if (existing.contains(d) || existing.any((e) => d.startsWith('$e/'))) {
        known.add(d);
      } else {
        fresh.add(d);
      }
    }
    var freshAdded = 0;
    var freshExisting = 0;
    var knownAdded = 0;
    if ((fresh.isNotEmpty || known.isNotEmpty) && !_scanning) {
      if (fresh.isNotEmpty) {
        existing.addAll(fresh);
        await _persist(existing);
      }
      _scanning = true;
      try {
        for (final d in fresh) {
          final r = await _scan(d, skipDeleted: false);
          freshAdded += r.added;
          freshExisting += r.existing;
        }
        // Zaten izlenenler de tazelensin — klasörü "tekrar ekleyerek"
        // silinmiş şarkıları geri getirebilirsin.
        for (final d in known) {
          final r = await _scan(d, skipDeleted: false);
          knownAdded += r.added;
        }
      } finally {
        _scanning = false;
      }
    }

    // ── Tek tek seçilen şarkılar ──
    var freshSongs = 0;
    var knownSongs = 0;
    if (songPaths.isNotEmpty) {
      // Klasör taraması listeyi güncelledi — güncel hâlinden bak.
      final current = List<SongItem>.from(
        LibraryController.instance.songsNotifier.value,
      );
      final keys = <String>{
        for (final s in current) s.appPath,
        for (final s in current)
          if (s.originalPath != null) s.originalPath!,
      };
      final nameSize = <String>{
        for (final s in current)
          if (s.size > 0)
            '${p2.basename(s.originalPath ?? s.appPath).toLowerCase()}|${s.size}',
      };
      for (final path in songPaths.toSet()) {
        var size = 0;
        try {
          size = await File(path).length();
        } catch (_) {}
        if (keys.contains(path) ||
            (size > 0 &&
                nameSize.contains('${p2.basename(path).toLowerCase()}|$size'))) {
          knownSongs++;
          continue;
        }
        final song = await SongStorage.importSong(
          sourcePath: path,
          title: p2.basenameWithoutExtension(path),
          size: size,
          copyToApp: true,
        );
        if (current.any((s) => s.appPath == song.appPath)) {
          knownSongs++;
        } else {
          current.add(song);
          keys.add(path);
          if (song.originalPath != null) keys.add(song.originalPath!);
          freshSongs++;
        }
      }
      if (freshSongs > 0) {
        await SongStorage.saveSongs(current);
        await LibraryController.instance.refreshSongs();
      }
    }

    // ── Özet kutusu: her koşulda düzgün, basit, sakin. ──
    final msg = _summaryMessage(
      fresh: fresh,
      known: known,
      freshAdded: freshAdded,
      freshExisting: freshExisting,
      knownAdded: knownAdded,
      freshSongs: freshSongs,
      knownSongs: knownSongs,
    );
    if (context.mounted) {
      _toast(context, p, msg, icon: Icons.library_music_rounded);
    }
  }

  static String _baseName(String d) {
    final b = d.split('/').last;
    return b.isEmpty ? d : b;
  }

  /// v5.1.3: ekleme özetini Türkçe doğru kurar (tekil/çoğul, sıfırlar,
  /// klasör adları).
  static String _summaryMessage({
    required List<String> fresh,
    required List<String> known,
    required int freshAdded,
    required int freshExisting,
    required int knownAdded,
    required int freshSongs,
    required int knownSongs,
  }) {
    final b = StringBuffer();
    if (fresh.isNotEmpty) {
      if (fresh.length == 1) {
        b.write('"${_baseName(fresh.first)}" eklendi');
      } else {
        b.write('${fresh.length} klasör eklendi');
      }
      if (freshAdded > 0) {
        b.write(
          ', ${freshAdded == 1 ? 'bir şarkı' : '$freshAdded şarkı'} alındı',
        );
      }
      b.write('.');
      if (freshAdded == 0 && freshExisting > 0) {
        b.write(' Şarkıları zaten kütüphanedeydi.');
      } else if (freshExisting > 0) {
        b.write(
          ' ${freshExisting == 1 ? 'Biri' : '$freshExisting tanesi'} '
          'zaten kütüphanedeydi.',
        );
      }
    }
    if (known.isNotEmpty) {
      if (b.isNotEmpty) b.write(' ');
      if (known.length == 1) {
        if (knownAdded > 0) {
          b.write(
            '"${_baseName(known.first)}" zaten izleniyordu — '
            '${knownAdded == 1 ? 'bir şarkı' : '$knownAdded şarkı'} '
            'geri eklendi.',
          );
        } else {
          b.write('"${_baseName(known.first)}" zaten izleniyor.');
        }
      } else if (knownAdded > 0) {
        b.write(
          'İzlenen klasörlerden '
          '${knownAdded == 1 ? 'bir şarkı' : '$knownAdded şarkı'} '
          'geri eklendi.',
        );
      } else {
        b.write('${known.length} klasör zaten izleniyor.');
      }
    }
    if (freshSongs > 0) {
      if (b.isNotEmpty) b.write(' ');
      b.write(
        freshSongs == 1
            ? 'Bir şarkı tek tek eklendi.'
            : '$freshSongs şarkı tek tek eklendi.',
      );
      if (knownSongs > 0) {
        b.write(
          ' ${knownSongs == 1 ? 'Biri' : '$knownSongs tanesi'} '
          'zaten kütüphanedeydi.',
        );
      }
    } else if (knownSongs > 0 && b.isEmpty) {
      b.write(
        knownSongs == 1
            ? 'Bu şarkı zaten kütüphanede.'
            : 'Bu şarkılar zaten kütüphanede.',
      );
    }
    if (b.isEmpty) b.write('Seçim zaten kütüphanedeydi.');
    return b.toString();
  }

  Future<void> manualScan(BuildContext context, CobblestonePalette p) async {
    await load();
    if (_scanning) return;
    if (foldersNotifier.value.isEmpty) {
      if (!context.mounted) return;
      _toast(context, p, 'Önce Klasörler sekmesinden bir klasör ekle', icon: Icons.folder_open_rounded);
      return;
    }
    if (!await _ensureAudioPermission()) return;
    final result = await _scanAll(skipDeleted: false);
    if (!context.mounted) return;
    if (result.added > 0) {
      _toast(context, p, '${result.added == 1 ? 'Bir şarkı' : '${result.added} yeni şarkı'} eklendi.', icon: Icons.library_music_rounded);
    } else {
      _toast(context, p, 'Kütüphane güncel.', icon: Icons.check_circle_rounded);
    }
  }

  static void _toast(
    BuildContext context,
    CobblestonePalette p,
    String msg, {
    IconData? icon,
    Color? accent,
  }) {
    showCobbleToast(context, msg, icon: icon, accent: accent);
  }

  /// v5.1.3: ad + boyut eşleşmesiyle izlenen klasörlerde gerçek dosyayı
  /// bulur (dosya seçici önbelleğinden gelen yollar için).
  Future<String?> findRealFile(String name, int size) async {
    await load();
    for (final folder in List<String>.from(foldersNotifier.value)) {
      try {
        if (!await Directory(folder).exists()) continue;
        final entries = await _listAudio(folder);
        for (final e in entries) {
          if (e.size == size &&
              p.basename(e.path).toLowerCase() == name.toLowerCase()) {
            return e.path;
          }
        }
      } catch (_) {}
    }
    return null;
  }

  Future<({int added, int existing})> _scanAll({
    required bool skipDeleted,
  }) async {
    if (_scanning) return (added: 0, existing: 0);
    _scanning = true;
    var added = 0, existing = 0;
    try {
      for (final folder in List<String>.from(foldersNotifier.value)) {
        final r = await _scan(folder, skipDeleted: skipDeleted);
        added += r.added;
        existing += r.existing;
      }
      lastScanNotifier.value = added > 0
          ? 'Son tarama: $added yeni şarkı alındı'
          : 'Kütüphane güncel';
    } finally {
      _scanning = false;
    }
    return (added: added, existing: existing);
  }

  Future<({int added, int existing})> _scan(
    String folderPath, {
    required bool skipDeleted,
  }) async {
    lastScanNotifier.value = 'Taranıyor…';
    var added = 0, existing = 0;
    try {
      if (!await Directory(folderPath).exists()) {
        lastScanNotifier.value = 'Klasör bulunamadı';
        return (added: 0, existing: 0);
      }
      try {
        await _native.invokeMethod('startScanKeepAlive');
      } catch (_) {}

      final entries = await _listAudio(folderPath);
      if (entries.isEmpty) {
        lastScanNotifier.value = 'Klasörde ses dosyası yok';
        return (added: 0, existing: 0);
      }
      lastScanNotifier.value = 'Taranıyor…';

      await LibraryController.instance.refreshSongs();
      final songs = List<SongItem>.from(
        LibraryController.instance.songsNotifier.value,
      );
      final known = <String>{
        for (final s in songs) s.appPath,
        for (final s in songs)
          if (s.originalPath != null) s.originalPath!,
      };
      // v5.1.3: yol yazimi farklari esitlenir (/sdcard = /storage/emulated/0)
      // ve ad+boyut eslesmesiyle kume birlesimi uygulanir.
      String normPath(String x) {
        var n = x.replaceAll('\\', '/').toLowerCase();
        n = n.replaceAll('/storage/emulated/0', '/sdcard');
        n = n.replaceAll('/storage/self/primary', '/sdcard');
        return n;
      }
      final normKnown = <String>{
        for (final s in songs) normPath(s.appPath),
        for (final s in songs)
          if (s.originalPath != null) normPath(s.originalPath!),
      };
      final nameSize = <String>{
        for (final s in songs)
          if (s.size > 0)
            '${p.basename(s.originalPath ?? s.appPath).toLowerCase()}|${s.size}',
      };
      final deleted = await SongStorage.deletedPathSet();
      var dirty = false;
      var sinceSave = 0;

      for (var i = 0; i < entries.length; i++) {
        final path = entries[i].path;
        final size = entries[i].size;
        try {
          if (deleted.contains(path)) {
            if (skipDeleted) {
              existing++;
              continue;
            }
            unawaited(SongStorage.unmarkDeleted(path));
          }
          final nKey = size > 0
              ? '${p.basename(path).toLowerCase()}|$size'
              : null;
          if (known.contains(path) ||
              normKnown.contains(normPath(path)) ||
              (nKey != null && nameSize.contains(nKey))) {
            existing++;
            continue;
          }
          final song = SongItem(
            title: p.basenameWithoutExtension(path),
            appPath: path,
            originalPath: path,
            size: size,
            addedMs: DateTime.now().millisecondsSinceEpoch,
          );
          known.add(song.appPath);
          normKnown.add(normPath(song.appPath));
          if (nKey != null) nameSize.add(nKey);
          songs.add(song);
          dirty = true;
          added++;
          sinceSave++;
        } catch (_) {}
        if (i % 50 == 49) {
          await Future<void>.delayed(Duration.zero);
        }
        if (sinceSave >= 200 && dirty) {
          await SongStorage.saveSongs(songs);
          LibraryController.instance.songsNotifier.value =
              List<SongItem>.from(songs);
          sinceSave = 0;
          dirty = false;
        }
      }

      if (dirty || added > 0) {
        await SongStorage.saveSongs(songs);
        LibraryController.instance.songsNotifier.value =
            List<SongItem>.from(songs);
      }
      lastScanNotifier.value = added > 0
          ? 'Son tarama: $added yeni şarkı alındı'
          : 'Kütüphane güncel';
      if (added > 0) {
        unawaited(LibraryController.instance.backfillId3());
      }
    } catch (e) {
      lastScanNotifier.value = 'Klasör taranırken bir sorun çıktı. Birazdan tekrar dene.';
    } finally {
      try {
        await _native.invokeMethod('stopScanKeepAlive');
      } catch (_) {}
    }
    return (added: added, existing: existing);
  }

  Future<List<({String path, int size})>> _listAudio(String folderPath) async {
    try {
      final out = await _native.invokeMethod<String>(
        'listAudioInFolder',
        {'path': folderPath},
      );
      if (out != null && out.isNotEmpty) {
        final raw = jsonDecode(await File(out).readAsString());
        if (raw is List) {
          return [
            for (final e in raw)
              if (e is Map)
                (
                  path: (e['path'] ?? '').toString(),
                  size: (e['size'] as num?)?.toInt() ?? 0,
                ),
          ].where((e) => e.path.isNotEmpty).toList();
        }
      }
    } catch (_) {}
    return _listAudioDart(folderPath);
  }

  Future<List<({String path, int size})>> _listAudioDart(
    String folderPath,
  ) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) return [];
    final out = <({String path, int size})>[];
    var listed = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File &&
          audioExts.contains(p.extension(entity.path).toLowerCase())) {
        var size = 0;
        try {
          size = await entity.length();
        } catch (_) {}
        out.add((path: entity.path, size: size));
      }
      listed++;
      if (listed % 80 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    return out;
  }
}
