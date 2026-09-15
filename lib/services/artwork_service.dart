import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/cairn_id.dart' show stableSeedHash;
import 'id3_tags.dart';

/// Kapak önceliği: kullanıcı resmi → ID3 APIC → yok (yedek taş/nota).
/// Kullanıcı "kapağı kaldır" derse ID3 de gizlenir (yol [_hidden]'da).
class ArtworkService {
  ArtworkService._();
  static final ArtworkService instance = ArtworkService._();

  final Map<String, String> _memCache = {};
  final Set<String> _noArt = {};
  final Set<String> _hidden = {};
  Directory? _dirCache;
  bool _hiddenLoaded = false;

  final ValueNotifier<int> tick = ValueNotifier(0);

  static const _hiddenKey = 'hidden_covers_v1';

  Future<Directory?> _dir() async {
    final cached = _dirCache;
    if (cached != null) return cached;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final d = Directory(p.join(docs.path, 'covers'));
      if (!await d.exists()) await d.create(recursive: true);
      _dirCache = d;
      return d;
    } catch (_) {
      return null;
    }
  }

  Future<void> _ensureHidden() async {
    if (_hiddenLoaded) return;
    _hiddenLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _hidden.addAll(prefs.getStringList(_hiddenKey) ?? const []);
    } catch (_) {}
  }

  Future<void> _persistHidden() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_hiddenKey, _hidden.toList());
    } catch (_) {}
  }

  String _userFileName(String appPath) =>
      'user_${stableSeedHash(appPath).toRadixString(16)}_${appPath.length}.png';

  String _id3FileName(String appPath) =>
      'id3_${stableSeedHash(appPath).toRadixString(16)}_${appPath.length}.jpg';

  String? memCachedPath(String appPath) => _memCache[appPath];

  void forget(String appPath) {
    _memCache.remove(appPath);
    _noArt.remove(appPath);
    tick.value++;
  }

  Future<String?> storeCoverBytes(String appPath, List<int> bytes) async {
    try {
      final d = await _dir();
      if (d == null || bytes.isEmpty) return null;
      final out = File(p.join(d.path, _userFileName(appPath)));
      await out.writeAsBytes(bytes, flush: true);
      _hidden.remove(appPath);
      await _persistHidden();
      _noArt.remove(appPath);
      _memCache[appPath] = out.path;
      tick.value++;
      return out.path;
    } catch (_) {
      return null;
    }
  }

  /// Kullanıcı kapağını ve ID3 önbelleğini siler; ID3 bir daha gösterilmez
  /// (dosyadan da silinmediyse).
  Future<void> hideCover(String appPath) async {
    await _ensureHidden();
    _hidden.add(appPath);
    await _persistHidden();
    try {
      final d = await _dir();
      if (d != null) {
        final user = File(p.join(d.path, _userFileName(appPath)));
        if (await user.exists()) await user.delete();
        final id3 = File(p.join(d.path, _id3FileName(appPath)));
        if (await id3.exists()) await id3.delete();
      }
    } catch (_) {}
    _memCache.remove(appPath);
    _noArt.add(appPath);
    tick.value++;
  }

  Future<String?> resolvedPath(String appPath) async {
    await _ensureHidden();
    if (_hidden.contains(appPath)) return null;
    final hit = _memCache[appPath];
    if (hit != null) return hit;
    if (_noArt.contains(appPath)) return null;
    try {
      final d = await _dir();
      if (d == null) return null;
      final user = File(p.join(d.path, _userFileName(appPath)));
      if (await user.exists() && await user.length() > 0) {
        _memCache[appPath] = user.path;
        return user.path;
      }
      final id3File = File(p.join(d.path, _id3FileName(appPath)));
      if (await id3File.exists() && await id3File.length() > 0) {
        _memCache[appPath] = id3File.path;
        return id3File.path;
      }
      final extracted = await Id3Tags.readCover(appPath);
      if (extracted != null && extracted.isNotEmpty) {
        await id3File.writeAsBytes(extracted, flush: true);
        _memCache[appPath] = id3File.path;
        return id3File.path;
      }
    } catch (_) {}
    _noArt.add(appPath);
    return null;
  }

  Future<String?> coverForVisible(String appPath) => resolvedPath(appPath);

  Future<String?> coverForQueue(String appPath) => resolvedPath(appPath);
}
