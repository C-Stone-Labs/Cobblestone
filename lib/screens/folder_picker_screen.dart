import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as pname;

import '../models/song_item.dart';
import '../services/folder_watch.dart';
import '../services/library_controller.dart';
import '../theme/palette.dart';
import '../widgets/ambient_layer.dart';
import '../widgets/artwork.dart';
import '../widgets/tap_scale.dart';

/// v5.1.3: UYGULAMA İÇİ müzik seçici — yalnız müzik içeren klasörler
/// listelenir. Klasöre dokun: içi AÇILIR (alt klasörler + ŞARKILAR kapak
/// ve adlarıyla). Şarkıya dokun: seç. Klasörü basılı tut: klasörü seç.
/// Boşluğa dokun / ✕ / geri: seçimden çık. Seçim boşalınca seçim modu
/// kendiliğinden biter. Geri tuşu seçim yokken bir üst klasöre çıkar,
/// en başta ekran kapanır. Klasör geçişlerinde hafif bir kayma + solma
/// animasyonu — neye bastığını sezersin, gözünü rahatsız etmez.
class FolderPickerScreen extends StatefulWidget {
  const FolderPickerScreen({super.key, required this.palette});

  final CobblestonePalette palette;

  @override
  State<FolderPickerScreen> createState() => _FolderPickerScreenState();
}

class _FolderPickerScreenState extends State<FolderPickerScreen> {
  static const _start = '/storage/emulated/0';

  /// Sistem ses klasörleri: müzik ararken gürültü olurlar.
  static const _hiddenAtRoot = {'Android', 'Alarms', 'Notifications', 'Ringtones'};

  String _dir = _start;
  int _navDir = 1; // +1: içeri, -1: dışarı (animasyon yönü)
  final Set<String> _selFolders = {};
  final Set<String> _selSongs = {};
  bool _selMode = false;
  Set<String> _musicDirs = <String>{};
  Map<String, SongItem> _byPath = {};
  bool _loading = true;

  CobblestonePalette get p => widget.palette;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final set = await FolderWatch.musicFolderSet();
    final byPath = <String, SongItem>{};
    for (final s in LibraryController.instance.songsNotifier.value) {
      byPath[s.appPath] = s;
      if (s.originalPath != null) byPath[s.originalPath!] = s;
    }
    if (!mounted) return;
    setState(() {
      _musicDirs = set;
      _byPath = byPath;
      _loading = false;
    });
  }

  List<Directory> get _subs {
    try {
      final dirs = Directory(_dir)
          .listSync(followLinks: false)
          .whereType<Directory>()
          .where((d) => !d.path.split('/').last.startsWith('.'))
          .where((d) => _musicDirs.contains(d.path))
          .toList()
        ..sort(
          (a, b) => a.path
              .split('/')
              .last
              .toLowerCase()
              .compareTo(b.path.split('/').last.toLowerCase()),
        );
      if (_dir == _start) {
        dirs.removeWhere(
          (d) => _hiddenAtRoot.contains(d.path.split('/').last),
        );
      }
      return dirs;
    } catch (_) {
      return const [];
    }
  }

  List<File> get _songs {
    try {
      final files = Directory(_dir)
          .listSync(followLinks: false)
          .whereType<File>()
          .where((f) => !f.path.split('/').last.startsWith('.'))
          .where(
            (f) => FolderWatch.audioExts.contains(
              pname.extension(f.path).toLowerCase(),
            ),
          )
          .toList()
        ..sort(
          (a, b) => a.path
              .split('/')
              .last
              .toLowerCase()
              .compareTo(b.path.split('/').last.toLowerCase()),
        );
      return files;
    } catch (_) {
      return const [];
    }
  }

  bool get _isStart => _dir == _start;

  int get _selCount => _selFolders.length + _selSongs.length;

  void _descend(String d) => setState(() {
        _navDir = 1;
        _dir = d;
      });

  void _startSel({String? folder, String? song}) => setState(() {
        _selMode = true;
        if (folder != null) _selFolders.add(folder);
        if (song != null) _selSongs.add(song);
      });

  void _exitSel() => setState(() {
        _selMode = false;
        _selFolders.clear();
        _selSongs.clear();
      });

  /// Seçim BOŞALINCA seçim modu kendiliğinden biter — tek şarkıyı seçip
  /// geri alınca modda takılı kalmazsın.
  void _afterToggle() {
    if (_selCount == 0) {
      _selMode = false;
      _selFolders.clear();
      _selSongs.clear();
    }
  }

  void _toggleFolder(String d) => setState(() {
        if (!_selFolders.remove(d)) _selFolders.add(d);
        _afterToggle();
      });

  void _toggleSong(String s) => setState(() {
        if (!_selSongs.remove(s)) _selSongs.add(s);
        _afterToggle();
      });

  void _selectAll() => setState(() {
        _selMode = true;
        for (final d in _subs) {
          _selFolders.add(d.path);
        }
        for (final f in _songs) {
          _selSongs.add(f.path);
        }
      });

  void _up() {
    if (_isStart) return;
    setState(() {
      _navDir = -1;
      _dir = Directory(_dir).parent.path;
    });
  }

  void _done() {
    if (_selCount == 0) return;
    Navigator.of(context).pop(
      (folders: _selFolders.toList(), songs: _selSongs.toList()),
    );
  }

  String get _btnLabel {
    final f = _selFolders.length;
    final s = _selSongs.length;
    if (f == 0 && s == 0) return 'Seç';
    if (s == 0) return f == 1 ? 'Klasörü Ekle' : '$f Klasörü Ekle';
    if (f == 0) return s == 1 ? 'Şarkıyı Ekle' : '$s Şarkı Ekle';
    return '${f == 1 ? 'Klasör' : '$f Klasör'} + '
        '${s == 1 ? 'Şarkı' : '$s Şarkı'} Ekle';
  }

  @override
  Widget build(BuildContext context) {
    final dirs = _subs;
    final songs = _songs;
    return PopScope(
      // Geri: seçim modundaysa SEÇİMİ bırakır; değilse bir üst klasöre
      // çıkar; en başta ekran kapanır.
      canPop: _isStart && !_selMode,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_selMode) {
          _exitSel();
        } else {
          _up();
        }
      },
      child: Scaffold(
        // v5.1.3: kendi temalı zemini + atmosfer — alttaki rota çizilmediği
        // için saydam zeminde SİYAH kalıyordu (tema karışması bundandı).
        backgroundColor: p.bg,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: _selMode
              ? GestureDetector(
                  onTap: _exitSel,
                  child: SizedBox(
                    width: double.infinity,
                    child: Text('$_selCount seçili'),
                  ),
                )
              : Text(_isStart ? 'Müzik Klasörleri' : _dir.split('/').last),
          actions: _selMode
              ? [
                  IconButton(
                    tooltip: 'Tümünü seç',
                    icon: const Icon(Icons.select_all_rounded),
                    onPressed: _selectAll,
                  ),
                  IconButton(
                    tooltip: 'Seçimden çık',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: _exitSel,
                  ),
                ]
              : null,
        ),
        body: AmbientLayer(
          palette: p,
          child: _loading
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: p.orange),
                      const SizedBox(height: 14),
                      Text(
                        'Müzik klasörleri aranıyor…',
                        style: TextStyle(color: p.mute, fontSize: 13),
                      ),
                    ],
                  ),
                )
              // v5.1.3: seçim modunda alt düğme nav çubuğundan yukarı
              // taşır (SafeArea kendi halleder); normal gezerken listenin
              // SON SATIRI sistem nav çubuğunun ALTINDA kalmaz.
              : SafeArea(
                  top: false,
                  bottom: !_selMode,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    reverseDuration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, anim) {
                      final slide = Tween<Offset>(
                        begin: Offset(_navDir * 0.10, 0),
                        end: Offset.zero,
                      ).animate(anim);
                      return FadeTransition(
                        opacity: anim,
                        child: SlideTransition(position: slide, child: child),
                      );
                    },
                    child: KeyedSubtree(
                      key: ValueKey(_dir),
                      child: GestureDetector(
                        // Seçim modunda boşluğa dokunmak seçimden çıkarır.
                        onTap: _selMode ? _exitSel : null,
                        child: dirs.isEmpty && songs.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 32,
                                  ),
                                  child: Text(
                                    _isStart
                                        ? 'Müzik içeren klasör bulunamadı.'
                                        : 'Bu klasörde müzik yok.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: p.mute,
                                      fontSize: 13,
                                      height: 1.6,
                                    ),
                                  ),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.only(
                                  top: 4,
                                  bottom: 16,
                                ),
                                itemCount: dirs.length + songs.length + 1,
                                itemBuilder: (context, i) {
                                  // İlk satır: küçük kullanım ipucu —
                                  // seçim modunda da kalır.
                                  if (i == 0) {
                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        top: 6,
                                        bottom: 2,
                                      ),
                                      child: Text(
                                        'Dokun: seç · Klasörü basılı '
                                        'tut: içine gir',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: p.mute.withValues(
                                            alpha: 0.75,
                                          ),
                                          fontSize: 11,
                                        ),
                                      ),
                                    );
                                  }
                                  final k = i - 1;
                                  if (k < dirs.length) {
                                    return _folderRow(dirs[k]);
                                  }
                                  return _songRow(songs[k - dirs.length]);
                                },
                              ),
                      ),
                    ),
                  ),
                ),
        ),
        bottomNavigationBar: _selMode
            ? SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: TapScale(
                    child: FilledButton.icon(
                      onPressed: _selCount == 0 ? null : _done,
                      style: FilledButton.styleFrom(
                        backgroundColor: p.orange,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: p.card,
                        disabledForegroundColor: p.mute,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: Text(_btnLabel),
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }

  Widget _folderRow(Directory d) {
    final name = d.path.split('/').last;
    final selected = _selFolders.contains(d.path);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: selected ? p.orange.withValues(alpha: 0.22) : p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? p.orange : p.cardBorder,
          width: selected ? 1.2 : 1,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          // v5.1.3: klasörde DOKUN = SEÇ (şarkılarla aynı mekanik),
          // BASILI TUT = içine gir.
          onTap: () {
            if (_selMode) {
              _toggleFolder(d.path);
            } else {
              _startSel(folder: d.path);
            }
          },
          onLongPress: () => _descend(d.path),
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(Icons.folder_rounded, color: p.orange, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (_selMode && selected)
                  const Padding(
                    padding: EdgeInsets.only(right: 16),
                    child: Icon(
                      Icons.check_circle_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _songRow(File f) {
    final lib = _byPath[f.path];
    final title = lib?.title ?? pname.basenameWithoutExtension(f.path);
    final artist = lib?.displayArtist;
    final selected = _selSongs.contains(f.path);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: selected ? p.orange.withValues(alpha: 0.22) : p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? p.orange : p.cardBorder,
          width: selected ? 1.2 : 1,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (_selMode) {
              _toggleSong(f.path);
            } else {
              _startSel(song: f.path);
            }
          },
          onLongPress: () {
            if (!_selMode) {
              _startSel(song: f.path);
            } else {
              _toggleSong(f.path);
            }
          },
          child: SizedBox(
            height: 68,
            child: Row(
              children: [
                const SizedBox(width: 12),
                SongArtwork(
                  palette: p,
                  size: 44,
                  appPath: lib?.appPath ?? f.path,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      if (artist != null && artist.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: p.mute, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_selMode && selected)
                  const Padding(
                    padding: EdgeInsets.only(right: 16),
                    child: Icon(
                      Icons.check_circle_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
