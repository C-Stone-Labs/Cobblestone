import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/song_item.dart';
import '../services/artwork_service.dart';
import '../services/id3_tags.dart';
import '../services/library_controller.dart';
import '../services/error_log.dart';
import '../services/notification_permission.dart';
import '../services/player_controller.dart';
import '../theme/palette.dart';
import '../widgets/cobble_toast.dart';
import '../widgets/tap_scale.dart';
import '../widgets/ambient_layer.dart';
import '../widgets/artwork.dart';
import 'cover_crop_screen.dart';

class FileInfoScreen extends StatefulWidget {
  final SongItem song;
  final CobblestonePalette palette;
  const FileInfoScreen({super.key, required this.song, required this.palette});

  @override
  State<FileInfoScreen> createState() => _FileInfoScreenState();
}

class _FileInfoScreenState extends State<FileInfoScreen> {
  CobblestonePalette get _p => widget.palette;
  late final TextEditingController _title;
  late final TextEditingController _artist;
  late final TextEditingController _album;
  String? _coverPreview;
  List<int>? _newCoverBytes;
  bool _removeCover = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.song.title);
    _artist = TextEditingController(text: widget.song.displayArtist);
    _album = TextEditingController(text: widget.song.displayAlbum);
    ArtworkService.instance.coverForVisible(widget.song.appPath).then((c) {
      if (mounted) setState(() => _coverPreview = c);
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _album.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = result?.files.single.path;
    if (path == null || !mounted) return;
    final cropped = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => CoverCropScreen(imagePath: path, palette: _p),
      ),
    );
    List<int>? bytes = cropped;
    bytes ??= await _coverBytes(path);
    if (bytes == null || bytes.isEmpty) return;
    setState(() {
      _newCoverBytes = bytes;
      _coverPreview = path;
      _removeCover = false;
    });
  }

  Future<List<int>?> _coverBytes(String path) async {
    try {
      final raw = await File(path).readAsBytes();
      if (raw.isEmpty) return null;
      if (raw.length < 400 * 1024) return raw;
      final codec = await ui.instantiateImageCodec(raw, targetWidth: 512);
      final frame = await codec.getNextFrame();
      final bd = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      return bd?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  InputDecoration _dec(String hint) => InputDecoration(
    labelText: hint,
    labelStyle: TextStyle(color: _p.mute),
    filled: true,
    fillColor: _p.card,
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: _p.cardBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: _p.orange),
    ),
  );

  Future<void> _save({required bool writeFile}) async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    setState(() => _saving = true);
    final artist = _artist.text.trim();
    final album = _album.text.trim();

    // v5.1.3: M4A/MP4 kapsayıcısına ID3 yazılamaz; değişiklik yalnızca
    // uygulama içinde geçerli olur (dosyaya dokunulmaz).
    final ext = p.extension(widget.song.appPath).toLowerCase();
    final isMp4 =
        ext == '.m4a' || ext == '.mp4' || ext == '.m4b' || ext == '.aac';

    if (writeFile) {
      // v5.1.1: Android 9- cihazlarda dosyaya yazım öncesi klasik depolama
      // izni (yoksa yazım sessizce başarısız oluyordu).
      final granted = await ensureLegacyStoragePermission();
      if (!granted) {
        if (!mounted) return;
        setState(() => _saving = false);
        showCobbleToast(context, 'Etiketi dosyaya yazmak için depolama izni gerekiyor.', icon: Icons.lock_outline_rounded);
        return;
      }
    }

    final wrote = isMp4
        ? await Id3Tags.writeMp4(
            path: widget.song.appPath,
            title: title,
            artist: artist.isEmpty ? null : artist,
            album: album.isEmpty ? null : album,
            coverJpeg: _removeCover ? const [] : _newCoverBytes,
            keepExistingCover: !_removeCover && _newCoverBytes == null,
          )
        : await Id3Tags.write(
            path: widget.song.appPath,
            title: title,
            artist: artist.isEmpty ? null : artist,
            album: album.isEmpty ? null : album,
            coverJpeg: _removeCover ? const [] : _newCoverBytes,
            keepExistingCover: !_removeCover && _newCoverBytes == null,
          );

    if (!wrote) {
      if (!mounted) return;
      setState(() => _saving = false);
      // v5.1.3: hata NEDENİ kayda geçer ve kullanıcıya söylenir —
      // "yazılamadı" belirsizliği bitti.
      final reason = Id3Tags.lastWriteError;
      logError('dosyaya_yaz', reason.isEmpty ? 'bilinmeyen' : reason, null);
      // İzin gerçekten eksikse izin diyalogu; izin açıksa neden-söyleyen
      // dürüst hata — "izin ver" diye yanıltma.
      final shown = await showAllFilesHelpDialog(context);
      if (!shown && mounted) {
        String msg;
        final r = reason.length > 90 ? reason.substring(0, 90) : reason;
        if (reason.contains('m4a') || reason.contains('moov') ||
            reason.contains('mp4')) {
          msg =
              'Bu dosyanın biçimi (m4a) etiket yazımını desteklemiyor. '
              'Değişiklik yalnızca uygulamada geçerli.';
        } else if (reason.contains('dosya bulunamadı')) {
          msg = 'Dosya bulunamadı — taşınmış ya da silinmiş olabilir.';
        } else if (reason.contains('denied') ||
            reason.contains('Permission') ||
            reason.contains('EROFS') ||
            reason.contains('Read-only')) {
          msg =
              'Yazma izni yok. Ayarlar → Uygulamalar → Cobblestone → '
              'İzinler yolundan "Tüm dosyalara erişim"i aç.';
        } else if (r.isEmpty) {
          msg = 'Dosyaya yazılamadı. Tekrar dene.';
        } else {
          msg = 'Dosyaya yazılamadı ($r). Tekrar dene.';
        }
        showCobbleToast(context, msg, icon: Icons.info_rounded);
      }
      return;
    }

    if (_removeCover) {
      await ArtworkService.instance.hideCover(widget.song.appPath);
    } else if (_newCoverBytes != null) {
      await ArtworkService.instance.storeCoverBytes(
        widget.song.appPath,
        _newCoverBytes!,
      );
      try {
        await globalPlayer.updateArtwork(
          widget.song.appPath,
          ArtworkService.instance.memCachedPath(widget.song.appPath) ?? '',
        );
      } catch (_) {}
    } else {
      // v5.1.3: dosya yeniden yazıldı (etiket v2.3 olarak yeniden kurulur,
      // varsa eski biçimdeki kapak APIC'e taşınır) — "kapak yok" kararı
      // eskide kalmasın, yeniden çıkarılsın.
      ArtworkService.instance.forget(widget.song.appPath);
    }

    final updated = widget.song.copyWith(
      title: title,
      artist: artist.isEmpty ? '' : artist,
      album: album.isEmpty ? '' : album,
      metaEdited: true,
    );
    await LibraryController.instance.updateSong(updated);
    if (nowPlayingNotifier.value?.appPath == updated.appPath) {
      nowPlayingNotifier.value = updated;
      final qi = currentQueue.indexWhere((s) => s.appPath == updated.appPath);
      if (qi >= 0) currentQueue[qi] = updated;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    showCobbleToast(context, 'Dosyaya yazıldı.', icon: Icons.check_circle_rounded);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.song;
    final ext = p.extension(song.appPath).toLowerCase();
    final mb = song.size / (1024 * 1024);
    final sizeText = mb >= 10
        ? '${mb.toStringAsFixed(0)} MB'
        : '${mb.toStringAsFixed(1)} MB';
    // v5.1.3: boş bir yere dokununca klavye kapanır, imleç kalkar.
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
      backgroundColor: _p.bg,
      appBar: AppBar(
        backgroundColor: _p.bg,
        title: const Text('Dosya bilgileri'),
      ),
      body: AmbientLayer(
        palette: _p,
        child: ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          32 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          // ── Kapak: gölgeli, yuvarlak, düzen rozetli ──
          Center(
            child: GestureDetector(
              onTap: _pickCover,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: SizedBox(
                    width: 200,
                    height: 200,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _removeCover
                            ? SongArtwork(
                                palette: _p,
                                size: 200,
                                appPath: null,
                              )
                            : _newCoverBytes != null
                                ? Image.memory(
                                    Uint8List.fromList(_newCoverBytes!),
                                    fit: BoxFit.cover,
                                  )
                                : _coverPreview != null
                                    ? Image.file(
                                        File(_coverPreview!),
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => SongArtwork(
                                          palette: _p,
                                          size: 200,
                                          appPath: song.appPath,
                                        ),
                                      )
                                    : SongArtwork(
                                        palette: _p,
                                        size: 200,
                                        appPath: song.appPath,
                                      ),
                        Positioned(
                          right: 10,
                          bottom: 10,
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: _p.orange,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _p.bg,
                                width: 2.5,
                              ),
                            ),
                            child: const Icon(
                              Icons.edit_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'Kapağa dokun — galeriden seç, kırp, uygula',
              style: TextStyle(color: _p.mute, fontSize: 12),
            ),
          ),
          Center(
            child: _removeCover || _newCoverBytes != null
                ? OutlinedButton.icon(
                    onPressed: () {
                      // Geri al: kaldırma/yeni kapak iptal, özgün kapak
                      // geri yüklenir.
                      setState(() {
                        _removeCover = false;
                        _newCoverBytes = null;
                        _coverPreview = null;
                      });
                      ArtworkService.instance
                          .coverForVisible(widget.song.appPath)
                          .then((c) {
                        if (mounted) setState(() => _coverPreview = c);
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: _p.orange),
                      foregroundColor: _p.orange,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.restart_alt_rounded, size: 15),
                    label: const Text(
                      'Geri al',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  )
                : OutlinedButton.icon(
                    onPressed: () => setState(() {
                      _removeCover = true;
                      _newCoverBytes = null;
                      _coverPreview = null;
                    }),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: _p.orange),
                      foregroundColor: _p.orange,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(
                      Icons.image_not_supported_outlined,
                      size: 15,
                    ),
                    label: const Text(
                      'Kapağı kaldır',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
          ),
          const SizedBox(height: 6),
          // ── Bilgi çipleri ──
          Center(
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                _chip(
                  ext.replaceFirst('.', '').toUpperCase(),
                  Icons.graphic_eq_rounded,
                ),
                _chip(sizeText, Icons.save_outlined),
                if (song.metaEdited)
                  _chip('Uygulamada düzenlendi', Icons.edit_outlined),
              ],
            ),
          ),
          const SizedBox(height: 18),
          // ── Etiket kartı ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _p.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _p.cardBorder),
            ),
            child: Column(
              children: [
                TextField(
                  controller: _title,
                  style: const TextStyle(color: Colors.white),
                  decoration: _dec('Başlık'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _artist,
                  style: const TextStyle(color: Colors.white),
                  decoration: _dec('Sanatçı'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _album,
                  style: const TextStyle(color: Colors.white),
                  decoration: _dec('Albüm'),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(
                      Icons.description_outlined,
                      color: _p.mute,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        p.basename(song.appPath),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _p.mute, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // ── Kaydet ──
          TapScale(
            child: FilledButton.icon(
            onPressed: _saving ? null : () => _save(writeFile: true),
            style: FilledButton.styleFrom(
              backgroundColor: _p.orange,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_rounded),
            label: const Text('Dosyaya yaz'),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Bilgiler dosyanın içine yazılır — diğer uygulamalarda da '
            'görünür. Yazılamazsa hiçbir şey değişmez.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _p.mute, fontSize: 12, height: 1.45),
          ),
        ],
      ),
      ),
      ),
    );
  }

  /// Küçük bilgi çipi (biçim / boyut / durum).
  Widget _chip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _p.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _p.cardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: _p.mute),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: _p.mute,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
