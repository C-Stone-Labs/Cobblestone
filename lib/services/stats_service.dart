import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song_item.dart';
import '../services/player_controller.dart';
import 'error_log.dart';

/// Haftalık rapordaki bir parça.
class ReportTrack {
  final String path;
  final String title;
  final int plays;
  const ReportTrack({
    required this.path,
    required this.title,
    required this.plays,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'title': title,
        'plays': plays,
      };

  static ReportTrack fromJson(Map m) => ReportTrack(
        path: (m['path'] ?? '').toString(),
        title: (m['title'] ?? '').toString(),
        plays: _asInt(m['plays']),
      );
}

/// Pazartesi kilitlenen, hafta boyunca gösterilen döküm.
class FrozenReport {
  final String weekKey;
  final DateTime from;
  final DateTime to;
  final int plays;
  final int seconds;
  final List<MapEntry<String, int>> bars;
  final List<ReportTrack> most;
  final List<ReportTrack> least;
  final List<ReportTrack> never;
  final int uniqueSongs;

  const FrozenReport({
    required this.weekKey,
    required this.from,
    required this.to,
    required this.plays,
    required this.seconds,
    required this.bars,
    required this.most,
    required this.least,
    required this.never,
    this.uniqueSongs = 0,
  });

  bool get hasAny =>
      most.isNotEmpty || least.isNotEmpty || never.isNotEmpty || plays > 0;

  String get rangeLabel {
    const months = [
      'Ocak',
      'Şubat',
      'Mart',
      'Nisan',
      'Mayıs',
      'Haziran',
      'Temmuz',
      'Ağustos',
      'Eylül',
      'Ekim',
      'Kasım',
      'Aralık',
    ];
    if (from.month == to.month && from.year == to.year) {
      return '${from.day}–${to.day} ${months[from.month - 1]}';
    }
    return '${from.day} ${months[from.month - 1]} – ${to.day} ${months[to.month - 1]}';
  }
}

int _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? 0;
}

class StatsService {
  StatsService._();
  static final StatsService instance = StatsService._();

  final version = ValueNotifier<int>(0);
  final reportSeenVersion = ValueNotifier<int>(0);
  final smartVersion = ValueNotifier<int>(0);
  final Map<String, Map<String, dynamic>> songs = {};
  final Map<String, Map<String, dynamic>> days = {};
  final Map<String, Map<String, dynamic>> weeks = {};

  FrozenReport? frozen;
  bool _smartLoaded = false;
  List<String> smartMost = const [];
  List<String> smartLeast = const [];
  List<String> smartNever = const [];

  bool get hasSmartSnapshot => frozen != null;

  bool _initialized = false;
  String? _currentPath;
  String? _currentTitle;
  bool _counted = true;
  Duration _lastPos = Duration.zero;
  int _listenedMs = 0;
  double _pendingSeconds = 0;

  static const _flushEvery = Duration(seconds: 20);
  Timer? _flushTimer;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await _load();
    await _loadSmart();

    SongItem? last;
    nowPlayingNotifier.addListener(() {
      final s = nowPlayingNotifier.value;
      if (s?.appPath == last?.appPath) return;
      last = s;
      _beginSong(s);
    });

    globalPlayer.currentIndexStream.listen((_) {
      final s = nowPlayingNotifier.value;
      _beginSong(s);
    });
    _beginSong(nowPlayingNotifier.value);

    globalPlayer.positionStream.listen(_onPosition);

    _flushTimer = Timer.periodic(_flushEvery, (_) => _save());
    unawaited(ensureSmartSnapshot(null));
  }

  void _beginSong(SongItem? s) {
    if (s != null && s.appPath == _currentPath) return;
    if (_currentPath != null && _pendingSeconds >= 0.5) {
      _addListenSeconds(_pendingSeconds.round());
    }
    _currentPath = s?.appPath;
    _currentTitle = s?.title;
    _counted = s == null;
    _lastPos = Duration.zero;
    _listenedMs = 0;
    _pendingSeconds = 0;
  }

  void _onPosition(Duration pos) {
    if (_currentPath == null) {
      _lastPos = pos;
      return;
    }

    // Döngü / başa sarma: yeni bir çalma fırsatı.
    if (_lastPos.inMilliseconds > 2000 &&
        pos.inMilliseconds + 2000 < _lastPos.inMilliseconds) {
      _counted = false;
      _listenedMs = 0;
      _pendingSeconds = 0;
      _lastPos = pos;
      return;
    }

    final delta = pos - _lastPos;
    _lastPos = pos;
    final st = globalPlayer.state;
    if (st != null && !st.playing && !st.playWhenReady) return;
    if (delta <= Duration.zero || delta >= const Duration(milliseconds: 2000)) {
      return;
    }

    _listenedMs += delta.inMilliseconds;
    _pendingSeconds += delta.inMilliseconds / 1000.0;
    if (_pendingSeconds >= 1) {
      final whole = _pendingSeconds.floor();
      _pendingSeconds -= whole;
      _addListenSeconds(whole);
    }

    if (!_counted && _qualifiesPlay(_listenedMs, globalPlayer.duration)) {
      _counted = true;
      _countPlay(_currentPath!, _currentTitle ?? 'Bilinmeyen şarkı');
    }
  }

  /// Spotify / Apple Music / Amazon / Tidal: 30 sn gerçek dinleme = 1 çalma.
  /// 30 sn’den kısa parça: sürenin %90’ı dinlenince sayılır.
  static bool _qualifiesPlay(int listenedMs, Duration? dur) {
    final durMs = dur?.inMilliseconds ?? 0;
    if (durMs > 0 && durMs < 30000) {
      return listenedMs >= math.max(1, (durMs * 0.90).round());
    }
    return listenedMs >= 30000;
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime mondayOf(DateTime d) {
    final day = _dateOnly(d);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  String dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Pazartesi 00:00 ile başlayan hafta — ISO yıl kayması yok.
  String weekKey(DateTime d) => dayKey(mondayOf(d));

  /// Eski kayıtlardaki ISO hafta anahtarı (2026-W35).
  String isoWeekKey(DateTime d) {
    final thursday = d.add(Duration(days: 3 - ((d.weekday + 6) % 7)));
    final firstThursday = DateTime(thursday.year, 1, 4);
    final firstWeekThursday = firstThursday.add(
      Duration(days: 3 - ((firstThursday.weekday + 6) % 7)),
    );
    final week =
        ((thursday.difference(firstWeekThursday).inDays) / 7).floor() + 1;
    return '${thursday.year}-W${week.toString().padLeft(2, '0')}';
  }

  void _countPlay(String path, String title) {
    final now = DateTime.now();
    final s = songs.putIfAbsent(
      path,
      () => {'title': title, 'plays': 0, 'lastMs': 0},
    );
    s['title'] = title;
    s['plays'] = _asInt(s['plays']) + 1;
    s['lastMs'] = now.millisecondsSinceEpoch;

    final de = days.putIfAbsent(dayKey(now), () => {'plays': 0, 'seconds': 0});
    de['plays'] = _asInt(de['plays']) + 1;

    final we = weeks.putIfAbsent(
      weekKey(now),
      () => <String, dynamic>{
        'plays': 0,
        'seconds': 0,
        'songs': <String, dynamic>{},
      },
    );
    we['plays'] = _asInt(we['plays']) + 1;
    final ws = we.putIfAbsent('songs', () => <String, dynamic>{}) as Map;
    final se = ws.putIfAbsent(path, () => {'title': title, 'plays': 0}) as Map;
    se['title'] = title;
    se['plays'] = _asInt(se['plays']) + 1;

    version.value++;
    unawaited(_save());
  }

  void _addListenSeconds(int seconds) {
    final now = DateTime.now();
    for (final entry in [
      MapEntry(days, dayKey(now)),
      MapEntry(weeks, weekKey(now)),
    ]) {
      final e = entry.key.putIfAbsent(
        entry.value,
        () => {'plays': 0, 'seconds': 0},
      );
      e['seconds'] = _asInt(e['seconds']) + seconds;
    }
  }

  bool isReportDay() => DateTime.now().weekday == DateTime.monday;

  int daysUntilMonday() => (DateTime.monday - DateTime.now().weekday + 7) % 7;

  DateTime completedWeekStart() =>
      mondayOf(DateTime.now()).subtract(const Duration(days: 7));

  DateTime completedWeekEnd() =>
      completedWeekStart().add(const Duration(days: 6));

  String completedWeekKey() => weekKey(completedWeekStart());

  Map<String, dynamic>? _completedWeekMap() {
    final start = completedWeekStart();
    return weeks[weekKey(start)] ?? weeks[isoWeekKey(start)];
  }

  List<MapEntry<String, int>> completedWeekBars() {
    const labels = ['Pt', 'Sa', 'Ça', 'Pe', 'Cu', 'Ct', 'Pz'];
    final start = completedWeekStart();
    return List.generate(7, (i) {
      final d = start.add(Duration(days: i));
      final secs = _asInt(days[dayKey(d)]?['seconds']);
      return MapEntry(labels[i], secs);
    });
  }

  List<MapEntry<String, Map<String, dynamic>>> completedWeekSongs() {
    final e = _completedWeekMap();
    final m = (e?['songs'] as Map?) ?? const {};
    final list = m.entries
        .map(
          (en) => MapEntry(
            en.key.toString(),
            Map<String, dynamic>.from(en.value as Map),
          ),
        )
        .toList()
      ..sort(
        (a, b) => _asInt(b.value['plays']).compareTo(_asInt(a.value['plays'])),
      );
    return list;
  }

  Future<bool> isReportSeenToday() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('rapor_seen_week_v1') == completedWeekKey();
    } catch (_) {
      return true;
    }
  }

  Future<void> markReportSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('rapor_seen_week_v1', completedWeekKey());
      reportSeenVersion.value++;
    } catch (_) {}
    await ensureSmartSnapshot(null);
  }

  /// v5.1.3: birlesen kopyanin haftalik calma sayilari kalan kayda gecer.
  void redirectPath(String from, String to) {
    var changed = false;
    for (final week in weeks.values) {
      final songs = week['songs'];
      if (songs is Map && songs[from] != null) {
        final data = songs.remove(from);
        if (songs[to] is Map) {
          final t = songs[to] as Map;
          t['plays'] = _asInt(t['plays']) + _asInt(data['plays']);
        } else {
          songs[to] = data;
        }
        changed = true;
      }
    }
    if (changed) unawaited(_save());
  }

  Future<void>? _ensureInflight;

  /// Tamamlanan hafta değişince (Pazartesi) raporu ve akıllı listeleri kilitler.
  Future<void> ensureSmartSnapshot(List<SongItem>? library) {
    final inflight = _ensureInflight;
    if (inflight != null) return inflight;
    final f = _ensureSmartSnapshotBody(library);
    _ensureInflight = f;
    f.whenComplete(() {
      if (identical(_ensureInflight, f)) _ensureInflight = null;
    });
    return f;
  }

  Future<void> _ensureSmartSnapshotBody(List<SongItem>? library) async {
    try {
      await _loadSmart();
      final week = completedWeekKey();
      if (frozen != null && frozen!.weekKey == week) {
        // v5.1.3 düzeltme: aynı hafta yeniden kilitlenmez, ANCAK hafta verisi
        // kilitlendikten sonra değiştiyse (tarih/saat düzeltmesi, test amaçlı
        // zaman atlama, yedek dönüşü) rapor güncel veriyle yeniden üretilir —
        // eski boş rapor takılı kalmaz. Gerçek hayatta tamamlanmış haftanın
        // verisi değişmeyeceği için bu yol normalde hiç tetiklenmez.
        final m = _completedWeekMap();
        final playsNow = _asInt(m?['plays']);
        final secondsNow = _asInt(m?['seconds']);
        if (playsNow == frozen!.plays && secondsNow == frozen!.seconds) {
          smartMost = [for (final t in frozen!.most) t.path];
          smartLeast = [for (final t in frozen!.least) t.path];
          smartNever = [for (final t in frozen!.never) t.path];
          return;
        }
        final libRes = library ?? await _libraryFallback();
        await _generateSmart(libRes, week);
        return;
      }
      final lib = library ?? await _libraryFallback();
      await _generateSmart(lib, week);
    } catch (e, st) {
      unawaited(logError('StatsService.ensureSmartSnapshot', e, st));
    }
  }

  Future<List<SongItem>> _libraryFallback() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final f = File(p.join(docs.path, 'library_v1.json'));
      if (!await f.exists()) return const [];
      final j = jsonDecode(await f.readAsString());
      if (j is! Map) return const [];
      final list = j['songs'];
      if (list is! List) return const [];
      return [
        for (final e in list)
          if (e is Map) SongItem.fromJson(Map<String, dynamic>.from(e)),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _generateSmart(List<SongItem> library, String week) async {
    final weekSongs = completedWeekSongs();
    final plays = <String, int>{
      for (final e in weekSongs) e.key: _asInt(e.value['plays']),
    };
    final titleOf = <String, String>{
      for (final e in weekSongs)
        e.key: (e.value['title'] ?? '').toString(),
      for (final s in library) s.appPath: s.title,
    };

    final played = weekSongs
        .where((e) => _asInt(e.value['plays']) > 0)
        .toList()
      ..sort(
        (a, b) => _asInt(b.value['plays']).compareTo(_asInt(a.value['plays'])),
      );

    // En çok: üst yarı (en az 1, en fazla 25). Az: kalan çalınanlar.
    final n = played.length;
    final mostN = n == 0 ? 0 : math.max(1, math.min(25, (n / 2).ceil()));
    final mostTracks = [
      for (final e in played.take(mostN))
        ReportTrack(
          path: e.key,
          title: titleOf[e.key] ?? e.key,
          plays: _asInt(e.value['plays']),
        ),
    ];
    final mostSet = {for (final t in mostTracks) t.path};
    final leastTracks = [
      for (final e in played.reversed)
        if (!mostSet.contains(e.key))
          ReportTrack(
            path: e.key,
            title: titleOf[e.key] ?? e.key,
            plays: _asInt(e.value['plays']),
          ),
    ].take(25).toList();

    final neverTracks = [
      for (final s in library)
        if ((plays[s.appPath] ?? 0) == 0)
          ReportTrack(path: s.appPath, title: s.title, plays: 0),
    ]..sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
    final neverCapped = neverTracks.take(80).toList();

    final start = completedWeekStart();
    final end = completedWeekEnd();
    final weekMap = _completedWeekMap();
    frozen = FrozenReport(
      weekKey: week,
      from: start,
      to: end,
      plays: _asInt(weekMap?['plays']),
      seconds: _asInt(weekMap?['seconds']),
      bars: completedWeekBars(),
      most: mostTracks,
      least: leastTracks,
      never: neverCapped,
      uniqueSongs: played.length,
    );
    smartMost = [for (final t in mostTracks) t.path];
    smartLeast = [for (final t in leastTracks) t.path];
    smartNever = [for (final t in neverCapped) t.path];
    await _saveSmart();
    smartVersion.value++;
    version.value++;
  }

  Future<File> _smartFile() async {
    final docs = await getApplicationDocumentsDirectory();
    return File(p.join(docs.path, 'smart_snapshot_v1.json'));
  }

  Future<void> _loadSmart() async {
    if (_smartLoaded) return;
    _smartLoaded = true;
    try {
      final f = await _smartFile();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map) return;
      final week = j['weekKey'] as String?;
      if (week == null || week.isEmpty) return;

      List<ReportTrack> tracks(String key) {
        final raw = j[key];
        if (raw is List && raw.isNotEmpty && raw.first is Map) {
          return [
            for (final e in raw)
              if (e is Map) ReportTrack.fromJson(e),
          ];
        }
        // Eski biçim: sadece yol listesi.
        if (raw is List) {
          return [
            for (final e in raw)
              ReportTrack(path: e.toString(), title: e.toString(), plays: 0),
          ];
        }
        return const [];
      }

      DateTime parseDay(String? s, DateTime fallback) {
        if (s == null || s.length < 10) return fallback;
        return DateTime.tryParse(s) ?? fallback;
      }

      final start = parseDay(j['from'] as String?, completedWeekStart());
      final end = parseDay(j['to'] as String?, completedWeekEnd());
      const labels = ['Pt', 'Sa', 'Ça', 'Pe', 'Cu', 'Ct', 'Pz'];
      final barsRaw = j['bars'];
      final bars = <MapEntry<String, int>>[];
      if (barsRaw is List) {
        for (var i = 0; i < barsRaw.length && i < 7; i++) {
          final e = barsRaw[i];
          if (e is Map) {
            bars.add(
              MapEntry(
                (e['l'] ?? labels[i]).toString(),
                _asInt(e['s']),
              ),
            );
          }
        }
      }
      frozen = FrozenReport(
        weekKey: week,
        from: start,
        to: end,
        plays: _asInt(j['plays']),
        seconds: _asInt(j['seconds']),
        bars: bars.length == 7 ? bars : completedWeekBars(),
        most: tracks('mostMeta').isNotEmpty ? tracks('mostMeta') : tracks('most'),
        least:
            tracks('leastMeta').isNotEmpty ? tracks('leastMeta') : tracks('least'),
        never:
            tracks('neverMeta').isNotEmpty ? tracks('neverMeta') : tracks('never'),
        uniqueSongs: () {
          final n = _asInt(j['uniqueSongs']);
          if (n > 0) return n;
          final mostN = tracks('mostMeta').isNotEmpty
              ? tracks('mostMeta').length
              : tracks('most').length;
          final leastN = tracks('leastMeta').isNotEmpty
              ? tracks('leastMeta').length
              : tracks('least').length;
          return mostN + leastN;
        }(),
      );
      smartMost = [for (final t in frozen!.most) t.path];
      smartLeast = [for (final t in frozen!.least) t.path];
      smartNever = [for (final t in frozen!.never) t.path];
      smartVersion.value++;
    } catch (e, st) {
      unawaited(logError('StatsService._loadSmart', e, st));
    }
  }

  Future<void> _saveSmart() async {
    final r = frozen;
    if (r == null) return;
    try {
      final f = await _smartFile();
      await f.writeAsString(
        jsonEncode({
          'weekKey': r.weekKey,
          'from': dayKey(r.from),
          'to': dayKey(r.to),
          'plays': r.plays,
          'seconds': r.seconds,
          'uniqueSongs': r.uniqueSongs,
          'bars': [
            for (final e in r.bars) {'l': e.key, 's': e.value},
          ],
          'most': [for (final t in r.most) t.path],
          'least': [for (final t in r.least) t.path],
          'never': [for (final t in r.never) t.path],
          'mostMeta': [for (final t in r.most) t.toJson()],
          'leastMeta': [for (final t in r.least) t.toJson()],
          'neverMeta': [for (final t in r.never) t.toJson()],
        }),
        flush: true,
      );
    } catch (e, st) {
      unawaited(logError('StatsService._saveSmart', e, st));
    }
  }

  Future<File> _file() async {
    final docs = await getApplicationDocumentsDirectory();
    return File(p.join(docs.path, 'stats.json'));
  }

  Future<void> _load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      for (final e
          in (j['songs'] as Map?)?.entries ??
              const <MapEntry<dynamic, dynamic>>[]) {
        songs[e.key as String] = Map<String, dynamic>.from(e.value as Map);
      }
      for (final e
          in (j['days'] as Map?)?.entries ??
              const <MapEntry<dynamic, dynamic>>[]) {
        days[e.key as String] = Map<String, dynamic>.from(e.value as Map);
      }
      for (final e
          in (j['weeks'] as Map?)?.entries ??
              const <MapEntry<dynamic, dynamic>>[]) {
        weeks[e.key as String] = Map<String, dynamic>.from(e.value as Map);
      }
      version.value++;
    } catch (e, st) {
      unawaited(logError('StatsService._load', e, st));
    }
  }

  Future<void> _save() async {
    try {
      final f = await _file();
      await f.writeAsString(
        jsonEncode({'songs': songs, 'days': days, 'weeks': weeks}),
        flush: true,
      );
    } catch (e, st) {
      unawaited(logError('StatsService._save', e, st));
    }
  }

  void dispose() {
    _flushTimer?.cancel();
  }
}
