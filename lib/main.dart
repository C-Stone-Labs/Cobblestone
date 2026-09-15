import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'models/song_item.dart';
import 'services/ui_events.dart';
import 'widgets/song_selection.dart';
import 'screens/player_screen.dart';
import 'screens/playlists_screen.dart';
import 'screens/folders_screen.dart';
import 'screens/smart_screen.dart';

import 'services/library_controller.dart';
import 'services/playlist_storage.dart';
import 'services/theme_controller.dart';
import 'services/fallback_art_controller.dart';
import 'services/notification_permission.dart';
import 'services/folder_watch.dart';
import 'services/song_storage.dart';
import 'services/player_controller.dart';
import 'services/eq_controller.dart';
import 'services/rhythm_controller.dart';
import 'services/stats_service.dart';
import 'services/error_log.dart';
import 'theme/palette.dart';
import 'widgets/cobble_toast.dart';
import 'widgets/ambient_layer.dart';
import 'screens/splash_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/report_screen.dart';
import 'widgets/mini_player.dart';

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      unawaited(logError('Flutter', details.exception, details.stack));
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(logError('Platform', error, stack));
      return true;
    };

    runApp(const CobblestoneApp());
  }, (error, stack) => unawaited(logError('Zone', error, stack)));
}

class CobblestoneApp extends StatefulWidget {
  const CobblestoneApp({super.key});
  @override
  State<CobblestoneApp> createState() => _CobblestoneAppState();
}

class _CobblestoneAppState extends State<CobblestoneApp>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applySystemBars();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _refresh());
    ThemeController.instance.paletteNotifier.addListener(_onPaletteChanged);
    // Kullanıcının SEÇTİĞİ atmosferi geri yükle (eskiden hiç çağrılmıyordu;
    // bu yüzden her açılışta "Otomatik"e dönüyordu).
    unawaited(ThemeController.instance.load());
    unawaited(FallbackArtController.instance.load());
    // Mini: native oturum splash bitmeden bağlansın.
    unawaited(() async {
      await LibraryController.instance.loadAll();
      await initAudioService();
    }());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    ThemeController.instance.paletteNotifier.removeListener(_onPaletteChanged);
    super.dispose();
  }

  void _onPaletteChanged() {
    if (mounted) {
      setState(() {});
      _applySystemBars();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
      ThemeController.instance.checkAutoRollover();
      unawaited(FolderWatch.instance.quickRescan());
      unawaited(LibraryController.instance.refreshPlaylists());
      unawaited(LibraryController.instance.refreshSongs());
      unawaited(adoptNativeSession());
      unawaited(
        StatsService.instance.ensureSmartSnapshot(
          LibraryController.instance.songsNotifier.value,
        ),
      );
    }
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {});
    _applySystemBars();
  }

  void _applySystemBars() {
    final p = ThemeController.instance.paletteNotifier.value;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: p.bg,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: p.bg,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeController.instance.paletteNotifier.value;
    return MaterialApp(
      title: 'Cobblestone',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [OverlayMenuObserver()],
      locale: const Locale('tr'),
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: p.bg,
        colorScheme: ColorScheme.dark(
          primary: p.orange,
          secondary: p.orangeLight,
          surface: p.card,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: p.bg,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
      home: SplashGate(palette: p),
    );
  }
}

class SplashGate extends StatefulWidget {
  final CobblestonePalette palette;
  const SplashGate({super.key, required this.palette});

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool _ready = false;

  Future<void> _complete() async {
    if (_ready || !mounted) return;
    await LibraryController.instance.loadAll();
    if (!mounted) return;
    context.findAncestorStateOfType<_CobblestoneAppState>()?._refresh();
    setState(() => _ready = true);
    Future.delayed(
      const Duration(milliseconds: 800),
      ensureNotificationPermissionOnce,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = ThemeController.instance.paletteNotifier.value;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 550),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: _ready
          ? HomeShell(key: const ValueKey('home'), palette: p)
          : SplashScreen(
              key: const ValueKey('splash'),
              palette: p,
              onDone: _complete,
            ),
    );
  }
}

class HomeShell extends StatefulWidget {
  final CobblestonePalette palette;
  const HomeShell({super.key, required this.palette});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  final GlobalKey<NavigatorState> _playlistsNavKey = GlobalKey<NavigatorState>();
  // v5.1.3: klasör/akıllı detaylar da sekme çerçevesinde kalır — alt
  // gezinme çubuğu görünmeye devam eder.
  final GlobalKey<NavigatorState> _foldersNavKey = GlobalKey<NavigatorState>();
  final GlobalKey<NavigatorState> _smartNavKey = GlobalKey<NavigatorState>();
  static const MethodChannel _reportChannel = MethodChannel('cobble/report');
  bool _reportPushed = false;
  static const _nativeChannel = MethodChannel('cobble/native');

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
    _wireReportChannel();
    playbackErrorNotifier.addListener(_onPlaybackError);
  }

  @override
  void dispose() {
    playbackErrorNotifier.removeListener(_onPlaybackError);
    super.dispose();
  }

  void _onPlaybackError() {
    final msg = playbackErrorNotifier.value;
    if (msg == null || !mounted) return;
    playbackErrorNotifier.value = null;
    final p = widget.palette;
    showCobbleToast(context, msg, icon: Icons.error_outline_rounded, accent: Colors.redAccent);
  }

  Future<void> _boot() async {
    await LibraryController.instance.loadAll();
    unawaited(initAudioService());
    unawaited(FolderWatch.instance.quickRescan());
    unawaited(EqController.instance.init());
    unawaited(RhythmController.instance.init());
    unawaited(() async {
      await StatsService.instance.init();
      // v5.1.3: ayni dosyanin cift kayitlarini birlestir (kume birlesimi).
      final merged = await SongStorage.mergeDuplicates();
      if (merged > 0) {
        await LibraryController.instance.refreshSongs();
      }
      await StatsService.instance.ensureSmartSnapshot(
        LibraryController.instance.songsNotifier.value,
      );
    }());
    unawaited(loadPlaybackPrefs());
  }

  void _wireReportChannel() {
    // Bildirim kartındaki ★ düğmesi Kotlin tarafında prefs'e yazar; buraya
    // haber gelir ve tüm ekranlar (Favoriler dahil) tazelenir.
    _nativeChannel.setMethodCallHandler((call) async {
      if (call.method == 'favoritesChanged') {
        // Kotlin zaten native kümeyi yazdı; yolları argüman olarak yollar.
        // Aynı kanaldan getFavorites çağırmıyoruz (kilitlenme olmasın).
        final args = call.arguments;
        if (args is List) {
          await PlaylistStorage.replaceFavorites(
            args.map((e) => e.toString()).toList(),
          );
          LibraryController.instance.playlistsNotifier.value =
              await PlaylistStorage.loadFromPrefsOnly();
        } else {
          await LibraryController.instance.refreshPlaylists();
        }
      } else if (call.method == 'openSongPath') {
        // Kullanıcı bir mp3'ü "Şununla aç → Cobblestone" ile seçti:
        // dosyayı kütüphaneye al ve Şarkılar sekmesine geç.
        await _handleOpenSong(call.arguments as Map?);
      }
      return null;
    });
    _reportChannel.setMethodCallHandler((call) async {
      if (call.method == 'openReport') unawaited(_pushReport());
      return null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportBootCheck());
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPendingOpenSong());
  }

  Future<void> _checkPendingOpenSong() async {
    try {
      // Uygulama bu dosyayla soğuk açıldıysa Kotlin tarafı bekletmişti.
      final payload = await _nativeChannel.invokeMethod<Map>('getPendingOpenSong');
      if (payload != null) await _handleOpenSong(payload);
    } catch (_) {}
  }

  Future<void> _handleOpenSong(Map? args) async {
    var path = args?['path'] as String?;
    final name = args?['name'] as String?;
    if (path == null || !mounted) return;
    try {
      var size = 0;
      try {
        size = await File(path).length();
      } catch (_) {}
      final existing = LibraryController.instance.songsNotifier.value;
      final base = p.basename(path).toLowerCase();
      final already = existing.indexWhere((s) {
        if (s.appPath == path || s.originalPath == path) return true;
        if (size > 0 && s.size == size) {
          final n = p.basename(s.appPath).toLowerCase();
          final o = (s.originalPath == null)
              ? ''
              : p.basename(s.originalPath!).toLowerCase();
          if (n == base || o == base) return true;
        }
        return false;
      });
      if (already >= 0) {
        if (mounted) {
          setState(() => _tab = 0);
          unawaited(playFromQueue(existing, already));
        }
        return;
      }
      // Dosya yöneticisinden gelen gerçek yol: kopyalama yok.
      // Cache'e düşmüş geçici kopyayı kütüphaneye alma.
      final isCache = path.contains('/cache/') || path.contains('/imported_');
      if (isCache) {
        if (mounted) {
          setState(() => _tab = 0);
          unawaited(
            playFromQueue([
              SongItem(
                title: (name?.isNotEmpty ?? false)
                    ? p.basenameWithoutExtension(name!)
                    : p.basenameWithoutExtension(path),
                appPath: path,
                size: size,
              ),
            ], 0),
          );
        }
        return;
      }
      final song = await SongStorage.importSong(
        sourcePath: path,
        title: (name?.isNotEmpty ?? false)
            ? p.basenameWithoutExtension(name!)
            : p.basenameWithoutExtension(path),
        size: size,
        copyToApp: false,
      );
      final songs = List<SongItem>.from(
        LibraryController.instance.songsNotifier.value,
      );
      // v5.1.3: importSong zaten var olan kaydı döndürdüyse klon ekleme.
      if (!songs.any((s) => s.appPath == song.appPath)) {
        songs.add(song);
      }
      await SongStorage.saveSongs(songs);
      await LibraryController.instance.refreshSongs();
      if (mounted) {
        setState(() => _tab = 0);
        unawaited(playFromQueue(songs, songs.length - 1));
      }
    } catch (_) {}
  }

  Future<void> _reportBootCheck() async {
    try {
      final action = await _reportChannel.invokeMethod<String>('getLaunchAction');
      if (action == 'report') {
        await _pushReport();
      }
    } catch (_) {}
  }

  Future<void> _pushReport() async {
    if (_reportPushed || !mounted) return;
    _reportPushed = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReportScreen(palette: widget.palette),
        ),
      );
    } catch (_) {}
    _reportPushed = false;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CobblestonePalette>(
      valueListenable: ThemeController.instance.paletteNotifier,
      builder: (context, p, _) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // v5.1.3: geri basıldıkça — seçim kapanır → iç sayfa kapanır →
        // Şarkılar sekmesine dönülür → yalnız orada basılırsa çıkılır.
        if (SongSelection.anyActive) {
          SongSelection.clearAll();
          return;
        }
        for (final k in [_playlistsNavKey, _foldersNavKey, _smartNavKey]) {
          if (k.currentState?.canPop() ?? false) {
            k.currentState?.maybePop();
            return;
          }
        }
        if (_tab != 0) {
          setState(() => _tab = 0);
          return;
        }
        const MethodChannel('cobble/native').invokeMethod('moveTaskToBack');
      },
      child: Scaffold(
        backgroundColor: p.bg,
        body: AmbientLayer(
          palette: p,
          child: Stack(
            children: [
              _TabFade(
                index: _tab,
                child: IndexedStack(
                index: _tab.clamp(0, 4),
                children: [
                  PlayerScreen(palette: p),
                  Navigator(
                    key: _playlistsNavKey,
                    observers: [OverlayMenuObserver()],
                    onGenerateRoute: (_) => MaterialPageRoute(
                      builder: (_) =>
                          _livePalette((pal) => PlaylistsScreen(palette: pal)),
                    ),
                  ),
                  Navigator(
                    key: _foldersNavKey,
                    observers: [OverlayMenuObserver()],
                    onGenerateRoute: (_) => MaterialPageRoute(
                      builder: (_) =>
                          _livePalette((pal) => FoldersScreen(palette: pal)),
                    ),
                  ),
                  Navigator(
                    key: _smartNavKey,
                    observers: [OverlayMenuObserver()],
                    onGenerateRoute: (_) => MaterialPageRoute(
                      builder: (_) =>
                          _livePalette((pal) => SmartScreen(palette: pal)),
                    ),
                  ),
                  SettingsScreen(palette: p),
                ],
              ),
              ),
              if (_tab != 4) MiniPlayer(palette: p),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          backgroundColor: p.card,
          indicatorColor: p.orange.withValues(alpha: 0.2),
          selectedIndex: _tab.clamp(0, 4),
          onDestinationSelected: (i) {
            // v5.1.3: sekme değişince açık tüm seçim modları biter —
            // mini oynatıcı da anında geri döner.
            SongSelection.clearAll();
            // v5.1.3: sekme değişince/liste sekmesine dönünce açık kalan
            // iç sayfa ve diyaloglar kapanır (ana Favoriler/Listeler görünür).
            for (final k
                in [_playlistsNavKey, _foldersNavKey, _smartNavKey]) {
              k.currentState?.popUntil((r) => r.isFirst);
            }
            setState(() => _tab = i);
          },
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            NavigationDestination(
              icon: Icon(Icons.music_note_rounded, color: p.mute),
              selectedIcon: Icon(Icons.music_note_rounded, color: p.orange),
              label: 'Şarkılar',
            ),
            NavigationDestination(
              icon: Icon(Icons.queue_music_rounded, color: p.mute),
              selectedIcon: Icon(Icons.queue_music_rounded, color: p.orange),
              label: 'Listeler',
            ),
            NavigationDestination(
              icon: Icon(Icons.folder_rounded, color: p.mute),
              selectedIcon: Icon(Icons.folder_rounded, color: p.orange),
              label: 'Klasörler',
            ),
            NavigationDestination(
              icon: Icon(Icons.auto_awesome_rounded, color: p.mute),
              selectedIcon: Icon(Icons.auto_awesome_rounded, color: p.orange),
              label: 'Akıllı',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_rounded, color: p.mute),
              selectedIcon: Icon(Icons.settings_rounded, color: p.orange),
              label: 'Ayarlar',
            ),
          ],
        ),
      ),
    );
      },
    );
  }
}


/// v5.1.3: iç gezgin sayfaları temayı CANLI izler — tema değişince
/// klasörler/akıllı listeler sekmeleri anında güncellenir (eski temada
/// takılı kalmaz).
Widget _livePalette(Widget Function(CobblestonePalette) child) {
  return ValueListenableBuilder<CobblestonePalette>(
    valueListenable: ThemeController.instance.paletteNotifier,
    builder: (_, pal, __) => child(pal),
  );
}

/// v5.1.3: sekme değişiminde yumuşak geçiş — kısa bir soluklanma ve
/// minicik yukarı süzülme. Sekmelerin durumu KORUNUR (IndexedStack).
class _TabFade extends StatefulWidget {
  const _TabFade({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_TabFade> createState() => _TabFadeState();
}

class _TabFadeState extends State<_TabFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  )..forward();

  @override
  void didUpdateWidget(covariant _TabFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) _c.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _c, curve: Curves.easeOut);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.012),
          end: Offset.zero,
        ).animate(curved),
        child: widget.child,
      ),
    );
  }
}
