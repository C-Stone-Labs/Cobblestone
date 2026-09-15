import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/song_item.dart';
import 'library_controller.dart';
import 'error_log.dart';

enum LoopMode { off, one, all }

enum ProcessingState { idle, loading, buffering, ready, completed }

class PlayerState {
  final bool playing;
  final bool playWhenReady;
  final ProcessingState processingState;
  const PlayerState({
    required this.playing,
    required this.playWhenReady,
    required this.processingState,
  });

  /// İkon: buffering sırasında duraklatılmış gibi görünmesin.
  bool get showPauseIcon => playWhenReady || playing;
}

class NativePlayer {
  static const MethodChannel _methods = MethodChannel('cobble/player');
  static const EventChannel _state = EventChannel('cobble/player/state');

  final StreamController<PlayerState> _playerState =
      StreamController<PlayerState>.broadcast();
  final StreamController<Duration> _position =
      StreamController<Duration>.broadcast();
  final StreamController<int?> _currentIndex =
      StreamController<int?>.broadcast();

  Duration? duration;
  bool connected = false;
  bool _subscribed = false;
  int? _lastIndexSent;

  PlayerState? _lastState;
  Duration? _lastPosition;
  String? _lastPlayerError;

  Stream<PlayerState> get playerStateStream => _playerState.stream;
  Stream<Duration> get positionStream => _position.stream;
  Stream<int?> get currentIndexStream => _currentIndex.stream;

  bool get showPauseIcon =>
      _lastState?.showPauseIcon ?? nowPlayingNotifier.value != null;

  void ensureSubscribed() {
    if (_subscribed) return;
    _subscribed = true;
    _state.receiveBroadcastStream().listen(_onNativeState, onError: (e, st) {
      debugPrint('player state: $e');
      unawaited(logError('playerState', e, st is StackTrace ? st : null));
    });
  }

  void _onNativeState(dynamic ev) {
    if (ev is! Map) return;
    connected = ev['connected'] == true;

    final playing = ev['isPlaying'] == true;
    final playWhenReady = ev.containsKey('playWhenReady')
        ? ev['playWhenReady'] == true
        : playing;
    final pb = (ev['playbackState'] as num?)?.toInt() ?? 1;
    final ps = switch (pb) {
      2 => ProcessingState.buffering,
      3 => ProcessingState.ready,
      4 => ProcessingState.completed,
      _ => ProcessingState.idle,
    };
    _lastState = PlayerState(
      playing: playing,
      playWhenReady: playWhenReady,
      processingState: ps,
    );
    _playerState.add(_lastState!);

    final durMs = (ev['durationMs'] as num?)?.toInt() ?? 0;
    duration = durMs > 0 ? Duration(milliseconds: durMs) : null;
    _lastPosition = Duration(milliseconds: (ev['positionMs'] as num?)?.toInt() ?? 0);
    _position.add(_lastPosition!);

    final idx = (ev['currentIndex'] as num?)?.toInt();
    if (idx != null && idx != _lastIndexSent) {
      _lastIndexSent = idx;
      _currentIndex.add(idx);
    }

    final err = ev['error']?.toString();
    if (err == null || err.isEmpty) {
      _lastPlayerError = null;
    } else if (err != _lastPlayerError) {
      _lastPlayerError = err;
      debugPrint('playerError: $err');
      unawaited(logError('playerError', err, null));
      playbackErrorNotifier.value = 'Bu şarkı çalınamadı';
    }

    final itemCount = (ev['itemCount'] as num?)?.toInt() ?? -1;
    if (itemCount == 0 && !_playBusy && !_jumpBusy) {
      _clearSession();
      return;
    }

    final q = ev['queue'];
    if (q is List) {
      final items = <Map<String, String>>[
        for (final it in q)
          if (it is Map)
            {
              'path': (it['path'] ?? '').toString(),
              'title': (it['title'] ?? '').toString(),
            },
      ];
      _syncNativeQueue(items);
    }

    final path = ev['currentPath']?.toString();
    if (path != null && path.isNotEmpty) {
      _ensureNowPlaying(path, ev['currentTitle']?.toString() ?? '');
    }
  }

  Future<void> connect() async {
    final ok = await _methods.invokeMethod<bool>('connect');
    connected = ok == true;
    if (!connected) {
      throw StateError('Ses sistemine bağlanılamadı');
    }
  }

  Future<void> _safe(Future<dynamic> f, String name) async {
    try {
      await f;
    } catch (e, st) {
      debugPrint('player $name: $e');
      unawaited(logError(name, e, st));
    }
  }

  Future<void> play() => _safe(_methods.invokeMethod('play'), 'play');
  Future<void> pause() => _safe(_methods.invokeMethod('pause'), 'pause');
  Future<void> seek(Duration d) =>
      _safe(_methods.invokeMethod('seekTo', {'ms': d.inMilliseconds}), 'seek');
  /// Oynatma hızı (0.5x..2x). Perde yok.
  Future<void> setSpeed(double speed) =>
      _safe(_methods.invokeMethod('setSpeed', {'speed': speed}), 'setSpeed');

  Future<void> addNext({
    required String path,
    required String title,
    String? artist,
  }) => _safe(
    _methods.invokeMethod('addNext', {
      'path': path,
      'title': title,
      if (artist != null && artist.isNotEmpty) 'artist': artist,
    }),
    'addNext',
  );

  Future<void> addToQueue({
    required String path,
    required String title,
    String? artist,
  }) => _safe(
    _methods.invokeMethod('addToQueue', {
      'path': path,
      'title': title,
      if (artist != null && artist.isNotEmpty) 'artist': artist,
    }),
    'addToQueue',
  );

  Future<void> seekToNext() => _safe(_methods.invokeMethod('next'), 'next');
  Future<void> seekToPrevious() => _safe(_methods.invokeMethod('prev'), 'prev');
  Future<void> jumpToIndex(int index) =>
      _methods.invokeMethod('jumpToIndex', {'index': index});
  Future<void> setShuffleModeEnabled(bool enabled) =>
      _safe(_methods.invokeMethod('setShuffle', {'shuffle': enabled}), 'shuffle');
  Future<void> setLoopMode(LoopMode mode) => _safe(
    _methods.invokeMethod('setRepeat', {
      'repeat': mode == LoopMode.one ? 1 : (mode == LoopMode.all ? 2 : 0),
    }),
    'repeat',
  );

  Future<void> setQueue({
    required List<Map<String, String>> items,
    required int startIndex,
    required bool shuffle,
    required int repeat,
  }) async {
    // Binder TransactionTooLarge: binlerce Map + kapak baytı olmasın.
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/cobble_queue.json');
    await f.writeAsString(jsonEncode(items), flush: true);
    return _methods.invokeMethod('setQueue', {
      'file': f.path,
      'startIndex': startIndex,
      'shuffle': shuffle,
      'repeat': repeat,
    });
  }

  Future<Map<dynamic, dynamic>?> exportQueue() async {
    try {
      final r = await _methods.invokeMethod('exportQueue');
      if (r is Map) return r;
    } catch (_) {}
    return null;
  }

  /// Kuyruk kurulduktan SONRA kapak gelirse (geç çıkarım), ilgili öğenin
  /// bildirim/kilit ekranı kapağını yerinde günceller. Konum korunur.
  Future<void> updateArtwork(String path, String coverPath) =>
      _safe(_methods.invokeMethod('updateArtwork', {
        'path': path,
        'cover': coverPath,
      }), 'updateArtwork');

  /// Mini çarpı / durdur: kuyruk boşalır, bildirim kapanır.
  Future<void> closeSession() => _safe(_methods.invokeMethod('close'), 'close');
}

final NativePlayer globalPlayer = NativePlayer();

/// Kuyruğun nereden başlatıldığı (Şarkılar / Favoriler / çalma listesi).
class PlaybackOrigin {
  final String? id;
  final String? label;
  const PlaybackOrigin({this.id, this.label});

  bool get isLibrary => label == null || label!.isEmpty;
  bool get isFavorites => id == '__favorites__';

  static const library = PlaybackOrigin();
  static const favorites = PlaybackOrigin(
    id: '__favorites__',
    label: 'Favoriler',
  );
  static PlaybackOrigin playlist(String id, String name) =>
      PlaybackOrigin(id: id, label: name);
}

final ValueNotifier<SongItem?> nowPlayingNotifier = ValueNotifier(null);
final ValueNotifier<PlaybackOrigin> playbackOriginNotifier =
    ValueNotifier(PlaybackOrigin.library);
final ValueNotifier<bool> shuffleNotifier = ValueNotifier(false);
final ValueNotifier<bool> repeatNotifier = ValueNotifier(false);
final ValueNotifier<double> speedNotifier = ValueNotifier(1.0);
final ValueNotifier<String?> playbackErrorNotifier = ValueNotifier(null);
List<SongItem> currentQueue = [];
int currentQueueIndex = -1;

const _speedPrefsKey = 'playback_speed_v1';
const _originPrefsKey = 'playback_origin_v1';
const _shufflePrefsKey = 'playback_shuffle_v1';
const _repeatPrefsKey = 'playback_repeat_one_v1';
bool _speedLoaded = false;
bool _sessionClosing = false;
int _emptyQueueTicks = 0;

Future<void> loadPlaybackPrefs() async {
  if (_speedLoaded) return;
  _speedLoaded = true;
  try {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getDouble(_speedPrefsKey);
    if (v != null && v > 0 && v <= 3) speedNotifier.value = v;
    shuffleNotifier.value = prefs.getBool(_shufflePrefsKey) ?? false;
    repeatNotifier.value = prefs.getBool(_repeatPrefsKey) ?? false;
    await restoreOrigin();
  } catch (_) {}
}

Future<void> persistOrigin(PlaybackOrigin o) async {
  playbackOriginNotifier.value = o;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _originPrefsKey,
      jsonEncode({'id': o.id, 'label': o.label}),
    );
  } catch (_) {}
}

Future<void> restoreOrigin() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_originPrefsKey);
    if (raw == null || raw.isEmpty) return;
    final m = jsonDecode(raw);
    if (m is! Map) return;
    final label = m['label'] as String?;
    final id = m['id'] as String?;
    if (label != null && label.isNotEmpty) {
      playbackOriginNotifier.value = PlaybackOrigin(id: id, label: label);
    }
  } catch (_) {}
}

Future<void> clearOrigin() async {
  playbackOriginNotifier.value = PlaybackOrigin.library;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_originPrefsKey);
  } catch (_) {}
}

Future<void> persistSpeed(double v) async {
  speedNotifier.value = v;
  unawaited(globalPlayer.setSpeed(v));
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_speedPrefsKey, v);
  } catch (_) {}
}

/// Sıradaki: mevcut parçadan hemen sonra.
Future<void> playNextSong(SongItem song) async {
  if (!audioServiceReady.value) {
    await playFromQueue([song], 0);
    return;
  }
  if (currentQueue.isEmpty) {
    await playFromQueue([song], 0);
    return;
  }
  final at = (currentQueueIndex + 1).clamp(0, currentQueue.length);
  currentQueue.insert(at, song);
  await globalPlayer.addNext(
    path: song.appPath,
    title: song.title,
    artist: song.displayArtist,
  );
}

/// Kuyruğun sonuna ekle.
Future<void> enqueueSong(SongItem song) async {
  if (!audioServiceReady.value || currentQueue.isEmpty) {
    await playFromQueue([song], 0);
    return;
  }
  currentQueue.add(song);
  await globalPlayer.addToQueue(
    path: song.appPath,
    title: song.title,
    artist: song.displayArtist,
  );
}

void _syncNativeQueue(List<Map<String, String>> items) {
  if (items.isEmpty) {
    // setMediaItems sırasında kuyruk bir an 0 görünür; mini'yi öldürme.
    if (_playBusy || _jumpBusy) return;
    if (_sessionClosing) {
      _clearSession();
      return;
    }
    _emptyQueueTicks++;
    if (_emptyQueueTicks < 3) return;
    _clearSession();
    return;
  }
  _emptyQueueTicks = 0;
  _sessionClosing = false;

  final idx = globalPlayer._lastIndexSent ?? 0;
  final nativeCurrent = (idx >= 0 && idx < items.length)
      ? (items[idx]['path'] ?? '')
      : (items.first['path'] ?? '');
  if (currentQueue.isNotEmpty &&
      currentQueue.length == items.length &&
      nowPlayingNotifier.value?.appPath == nativeCurrent) {
    return;
  }

  final lib = LibraryController.instance.songsNotifier.value;
  SongItem match(String path, String title) {
    for (final s in lib) {
      if (s.appPath == path) return s;
    }
    return SongItem(
      title: title.isEmpty ? 'Bilinmeyen şarkı' : title,
      appPath: path,
      size: 0,
    );
  }

  currentQueue = [
    for (final m in items) match(m['path'] ?? '', m['title'] ?? ''),
  ];
  if (idx >= 0 && idx < currentQueue.length) {
    currentQueueIndex = idx;
    nowPlayingNotifier.value = currentQueue[idx];
  } else if (currentQueue.isNotEmpty) {
    currentQueueIndex = 0;
    nowPlayingNotifier.value = currentQueue.first;
  }
}

void _ensureNowPlaying(String path, String title) {
  if (_sessionClosing) return;
  if (path.isEmpty) return;
  if (nowPlayingNotifier.value?.appPath == path) return;
  for (var i = 0; i < currentQueue.length; i++) {
    if (currentQueue[i].appPath == path) {
      currentQueueIndex = i;
      nowPlayingNotifier.value = currentQueue[i];
      return;
    }
  }
  final lib = LibraryController.instance.songsNotifier.value;
  SongItem? found;
  for (final s in lib) {
    if (s.appPath == path) {
      found = s;
      break;
    }
  }
  found ??= SongItem(
    title: title.isEmpty ? 'Bilinmeyen şarkı' : title,
    appPath: path,
    size: 0,
  );
  if (currentQueue.isEmpty) {
    currentQueue = [found];
    currentQueueIndex = 0;
  }
  nowPlayingNotifier.value = found;
}

/// Uygulama öldükten sonra native oturum hâlâ çalıyorsa mini'yi geri al.
Future<void> adoptNativeSession() async {
  if (_sessionClosing) return;
  try {
    final raw = await globalPlayer.exportQueue();
    if (raw == null) return;
    final file = raw['file']?.toString();
    if (file == null || file.isEmpty) return;
    final decoded = jsonDecode(await File(file).readAsString());
    if (decoded is! List) return;
    final items = <Map<String, String>>[
      for (final it in decoded)
        if (it is Map)
          {
            'path': (it['path'] ?? '').toString(),
            'title': (it['title'] ?? '').toString(),
          },
    ];
    final idx = (raw['index'] as num?)?.toInt();
    if (idx != null) globalPlayer._lastIndexSent = idx;
    _syncNativeQueue(items);
  } catch (_) {}
}

void _clearSession() {
  if (currentQueue.isEmpty && nowPlayingNotifier.value == null) return;
  currentQueue = [];
  currentQueueIndex = -1;
  if (nowPlayingNotifier.value != null) nowPlayingNotifier.value = null;
  unawaited(clearOrigin());
}

final ValueNotifier<bool> audioServiceReady = ValueNotifier(false);
final ValueNotifier<String?> audioServiceStatus = ValueNotifier(null);

bool _listenersReady = false;
int _initAttempts = 0;

void setupPlayerListeners() {
  if (_listenersReady) return;
  _listenersReady = true;

  globalPlayer.currentIndexStream.listen((i) {
    if (i == null) return;
    if (i >= 0 && i < currentQueue.length) {
      currentQueueIndex = i;
      final song = currentQueue[i];
      if (nowPlayingNotifier.value != song) {
        nowPlayingNotifier.value = song;
      }
    }
  });

  shuffleNotifier.addListener(() {
    globalPlayer.setShuffleModeEnabled(shuffleNotifier.value);
    unawaited(_persistShuffleRepeat());
  });
  repeatNotifier.addListener(() {
    globalPlayer.setLoopMode(
      repeatNotifier.value ? LoopMode.one : LoopMode.all,
    );
    unawaited(_persistShuffleRepeat());
  });
}

Future<void> _persistShuffleRepeat() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_shufflePrefsKey, shuffleNotifier.value);
    await prefs.setBool(_repeatPrefsKey, repeatNotifier.value);
  } catch (_) {}
}

Future<void> initAudioService() async {
  if (audioServiceReady.value) return;
  if (_initAttempts >= 2) {
    audioServiceStatus.value =
        'Ses sistemi açılamadı. Uygulamayı kapatıp açınca yeniden denenir.';
    return;
  }
  _initAttempts++;
  audioServiceStatus.value = null;
  try {
    globalPlayer.ensureSubscribed();
    await globalPlayer.connect().timeout(const Duration(seconds: 12));
    audioServiceReady.value = true;
    audioServiceStatus.value = null;
    setupPlayerListeners();
    unawaited(globalPlayer.setShuffleModeEnabled(shuffleNotifier.value));
    unawaited(
      globalPlayer.setLoopMode(
        repeatNotifier.value ? LoopMode.one : LoopMode.all,
      ),
    );
    await adoptNativeSession();
    return;
  } catch (e) {
    audioServiceStatus.value = e.toString();
  }
  setupPlayerListeners();
}

bool _playBusy = false;
bool _jumpBusy = false;
int? _pendingJumpIndex;
List<SongItem>? _pendingSongs;
int? _pendingIndex;
PlaybackOrigin? _pendingOrigin;

Future<void> playFromQueue(
  List<SongItem> songs,
  int index, {
  PlaybackOrigin origin = PlaybackOrigin.library,
}) async {
  if (index < 0 || index >= songs.length) return;
  HapticFeedback.selectionClick();
  _sessionClosing = false;
  _emptyQueueTicks = 0;
  playbackOriginNotifier.value = origin;
  unawaited(persistOrigin(origin));

    if (audioServiceReady.value && _sameQueue(songs)) {
    currentQueueIndex = index;
    final jumpSong = songs[index];
    nowPlayingNotifier.value = jumpSong;
    if (_jumpBusy) {
      _pendingJumpIndex = index;
      return;
    }

    _jumpBusy = true;

    var jumpedTo = index;
    try {
      // Aynı karedeki peş peşe tıklamalar son indekse çöksün.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      jumpedTo = _pendingJumpIndex ?? index;
      _pendingJumpIndex = null;
      await globalPlayer.jumpToIndex(jumpedTo);
    } catch (e, st) {
      debugPrint('jumpToIndex: $e');
      unawaited(logError('jumpToIndex', e, st));
      playbackErrorNotifier.value = 'Bu şarkı çalınamadı';
    } finally {
      _jumpBusy = false;

      final pending = _pendingJumpIndex;
      _pendingJumpIndex = null;

      if (pending != null && pending != jumpedTo) {
        unawaited(playFromQueue(songs, pending, origin: origin));
      }
    }

    return;
  }

  if (_playBusy) {
    _pendingSongs = songs;
    _pendingIndex = index;
    _pendingOrigin = origin;
    return;
  }
  _playBusy = true;

  if (!audioServiceReady.value) {
    if (_initAttempts == 0) unawaited(initAudioService());
    try {
      globalPlayer.ensureSubscribed();
      await globalPlayer.connect().timeout(const Duration(seconds: 8));
    } catch (e, st) {
      debugPrint('connect: $e');
      unawaited(logError('connect', e, st));
    }
  }

  currentQueue = List<SongItem>.from(songs);
  currentQueueIndex = index;
  final song = songs[index];
  nowPlayingNotifier.value = song;
  try {
    globalPlayer._lastIndexSent = null;
    final items = <Map<String, String>>[
      for (final s in songs)
        <String, String>{
          'path': s.appPath,
          'title': s.title,
          if (s.displayArtist.isNotEmpty) 'artist': s.displayArtist,
        },
    ];

    await globalPlayer.setQueue(
      items: items,
      startIndex: index,
      shuffle: shuffleNotifier.value,
      repeat: repeatNotifier.value ? 1 : 2,
    );
    await globalPlayer.setSpeed(speedNotifier.value);
    await globalPlayer.play();
    audioServiceReady.value = true;
  } catch (e, st) {
    debugPrint('playFromQueue: $e');
    unawaited(logError('playFromQueue', e, st));
    playbackErrorNotifier.value = 'Bu şarkı çalınamadı';
    nowPlayingNotifier.value = null;
    currentQueue = [];
    currentQueueIndex = -1;
  } finally {
    _playBusy = false;
    final nextSongs = _pendingSongs;
    final nextIndex = _pendingIndex;
    final nextOrigin = _pendingOrigin;
    _pendingSongs = null;
    _pendingIndex = null;
    _pendingOrigin = null;
    if (nextSongs != null && nextIndex != null) {
      unawaited(
        playFromQueue(
          nextSongs,
          nextIndex,
          origin: nextOrigin ?? PlaybackOrigin.library,
        ),
      );
    }
  }
}

void playNext() {
  if (currentQueue.isEmpty) return;
  globalPlayer.seekToNext();
}

void playPrevious() {
  if (currentQueue.isEmpty) return;
  globalPlayer.seekToPrevious();
}

/// Mini çarpı: müzik durur, kuyruk boşalır, bildirim kapanır, mini kaybolur.
Future<void> stopPlayback() async {
  _sessionClosing = true;
  _emptyQueueTicks = 0;
  nowPlayingNotifier.value = null;
  currentQueue = [];
  currentQueueIndex = -1;
  unawaited(clearOrigin());
  await globalPlayer.closeSession();
}

bool _sameQueue(List<SongItem> songs) {
  if (songs.length != currentQueue.length) {
    return false;
  }

  for (var i = 0; i < songs.length; i++) {
    if (songs[i].appPath != currentQueue[i].appPath) {
      return false;
    }
  }

  return true;
}

extension NativePlayerExt on NativePlayer {
  Duration? get position => _lastPosition;
  PlayerState? get state => _lastState;
}
