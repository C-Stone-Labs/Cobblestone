import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'notification_permission.dart';

/// MP3 dosyasının başındaki ID3v2 etiketlerinden başlık, sanatçı, albüm.
class Id3Tags {
  /// v5.1.3: son yazma hatasının NEDENİ (dosya bilgisi ekranı ve hata
  /// günlüğü bunu okur — "yazılamadı" belirsizliği biter).
  static String lastWriteError = '';
  final String? title;
  final String? artist;
  final String? album;

  const Id3Tags({this.title, this.artist, this.album});

  static const int _maxBytes = 8 * 1024 * 1024;

  // ── v5.1.3: MP4/M4A (iTunes stili) etiket desteği ──

  static bool _isMp4Header(List<int> h) =>
      h.length >= 12 &&
      h[4] == 0x66 && h[5] == 0x74 && h[6] == 0x79 && h[7] == 0x70; // 'ftyp'

  static int _u32b(List<int> x, int off) =>
      ((x[off] & 0xFF) << 24) |
      ((x[off + 1] & 0xFF) << 16) |
      ((x[off + 2] & 0xFF) << 8) |
      (x[off + 3] & 0xFF);

  /// Üst düzey atomlarda gezinip moov gövdesini okur (en çok 8 MB).
  static Future<List<int>?> _mp4Moov(File file, int length) async {
    final raf = await file.open(mode: FileMode.read);
    try {
      var pos = 0;
      while (pos + 8 <= length) {
        await raf.setPosition(pos);
        final hdr = await raf.read(8);
        if (hdr.length < 8) return null;
        var size = _u32b(hdr, 0);
        var headLen = 8;
        if (size == 1) {
          final ext = await raf.read(8);
          if (ext.length < 8) return null;
          size = (_u32b(ext, 0) << 32) | _u32b(ext, 4);
          headLen = 16;
        } else if (size == 0) {
          size = length - pos;
        }
        if (size < headLen) return null;
        final type = String.fromCharCodes(hdr.sublist(4, 8));
        if (type == 'moov') {
          final want = (size - headLen).clamp(0, _maxBytes);
          return await raf.read(want);
        }
        pos += size;
      }
      return null;
    } finally {
      await raf.close();
    }
  }

  static List<int>? _mp4Atom(List<int> b, String name, {int skip = 0}) {
    var off = skip;
    while (off + 8 <= b.length) {
      final size = _u32b(b, off);
      if (size < 8 || off + size > b.length) return null;
      final t = String.fromCharCodes(b.sublist(off + 4, off + 8));
      if (t == name) return b.sublist(off + 8, off + size);
      off += size;
    }
    return null;
  }

  static List<int>? _mp4Ilst(List<int> moov) {
    // v5.1.3 düzeltme: 4 baytlık sürüm/bayrak öneki konteynerde değil,
    // meta atomunun GÖVDESİNİN başındadır. Önce meta'yı bul, sonra öneki atla.
    List<int>? meta = _mp4Atom(moov, 'meta');
    final udta = _mp4Atom(moov, 'udta');
    if (udta != null) {
      final m = _mp4Atom(udta, 'meta');
      if (m != null) meta = m;
    }
    if (meta == null || meta.length <= 4) return null;
    return _mp4Atom(meta.sublist(4), 'ilst');
  }

  static String? _mp4Text(List<int> ilst, String name) {
    final item = _mp4Atom(ilst, name);
    if (item == null) return null;
    final data = _mp4Atom(item, 'data');
    if (data == null || data.length <= 8) return null;
    final s = utf8
        .decode(data.sublist(8), allowMalformed: true)
        .replaceAll('\u0000', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return s.isEmpty ? null : s;
  }

  static Future<Id3Tags> _readMp4(File file, int length) async {
    try {
      final moov = await _mp4Moov(file, length);
      if (moov == null || moov.isEmpty) return const Id3Tags();
      final ilst = _mp4Ilst(moov);
      if (ilst == null) return const Id3Tags();
      return Id3Tags(
        title: _mp4Text(ilst, '©nam'),
        artist: _mp4Text(ilst, '©ART'),
        album: _mp4Text(ilst, '©alb'),
      );
    } catch (_) {
      return const Id3Tags();
    }
  }

  static Future<List<int>?> _readMp4Cover(File file, int length) async {
    try {
      final moov = await _mp4Moov(file, length);
      if (moov == null || moov.isEmpty) return null;
      final ilst = _mp4Ilst(moov);
      if (ilst == null) return null;
      final covr = _mp4Atom(ilst, 'covr');
      if (covr == null) return null;
      final data = _mp4Atom(covr, 'data');
      if (data == null || data.length <= 8) return null;
      return data.sublist(8);
    } catch (_) {
      return null;
    }
  }

  /// Dosyadaki APIC (albüm kapağı) baytları; yoksa null.
  /// v5.1.3: MP4/M4A dosyalarında covr atomundan okur.
  static Future<List<int>?> readCover(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final length = await file.length();
      if (length < 12) return null;
      final header = await file.openRead(0, 16).fold<BytesBuilder>(
        BytesBuilder(copy: false),
        (b, c) => b..add(c),
      );
      final h = header.takeBytes();
      if (_isMp4Header(h)) {
        final covr = await _readMp4Cover(file, length);
        if (covr != null && covr.isNotEmpty) return covr;
        return null;
      }
      if (h.length < 10 || h[0] != 0x49 || h[1] != 0x44 || h[2] != 0x33) {
        return null;
      }
      final tagSize = _syncSafe(h, 6);
      final end = (10 + tagSize).clamp(10, length);
      final toRead = end > _maxBytes ? _maxBytes : end;
      final builder = BytesBuilder(copy: false);
      // v5.1.3 düzeltme: üst bilgi 16 bayt okundu (MP4 algısı için) —
      // tampona yalnız ilk 10 baytı koy, 10'dan sonrası tek kez eklenir.
      builder.add(h.sublist(0, 10));
      if (toRead > 10) {
        await for (final chunk in file.openRead(10, toRead)) {
          builder.add(chunk);
        }
      }
      return _extractJpeg(builder.takeBytes());
    } catch (_) {
      return null;
    }
  }

  static Future<Id3Tags> read(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return const Id3Tags();
      final length = await file.length();
      if (length < 12) return const Id3Tags();
      final header = await file.openRead(0, 16).fold<BytesBuilder>(
        BytesBuilder(copy: false),
        (b, c) => b..add(c),
      );
      final h = header.takeBytes();
      // v5.1.3: MP4/M4A → iTunes stili ilst etiketleri.
      if (_isMp4Header(h)) return _readMp4(file, length);
      if (h.length < 10 || h[0] != 0x49 || h[1] != 0x44 || h[2] != 0x33) {
        return const Id3Tags();
      }
      final tagSize = _syncSafe(h, 6);
      final end = (10 + tagSize).clamp(10, length);
      final toRead = end > _maxBytes ? _maxBytes : end;
      final builder = BytesBuilder(copy: false);
      // v5.1.3 düzeltme: 16 baytlık üst bilgiden yalnız ilk 10 bayt tampona.
      builder.add(h.sublist(0, 10));
      if (toRead > 10) {
        await for (final chunk in file.openRead(10, toRead)) {
          builder.add(chunk);
        }
      }
      return parse(builder.takeBytes());
    } catch (_) {
      return const Id3Tags();
    }
  }

  static int _syncSafe(List<int> x, int off) =>
      ((x[off] & 0x7F) << 21) |
      ((x[off + 1] & 0x7F) << 14) |
      ((x[off + 2] & 0x7F) << 7) |
      (x[off + 3] & 0x7F);

  static int _u32(List<int> x, int off) =>
      ((x[off] & 0xFF) << 24) |
      ((x[off + 1] & 0xFF) << 16) |
      ((x[off + 2] & 0xFF) << 8) |
      (x[off + 3] & 0xFF);

  static Id3Tags parse(List<int> b) {
    if (b.length < 10 || b[0] != 0x49 || b[1] != 0x44 || b[2] != 0x33) {
      return const Id3Tags();
    }
    final verMajor = b[3];
    final flags = b[5];
    final tagSize = _syncSafe(b, 6);
    var off = 10;
    // v5.1.3: genişletilmiş başlık yalnız v2.3+ için vardır (v2.2'de bu bit
    // sıkıştırma bayrağıdır — atlanmaz).
    if (verMajor >= 3 && (flags & 0x40) != 0 && off + 4 <= b.length) {
      final ext = verMajor >= 4 ? _syncSafe(b, off) : _u32(b, off);
      if (ext > 4) off += ext;
    }
    final end = 10 + tagSize;
    final v22 = verMajor == 2;
    final headLen = v22 ? 6 : 10;
    String? title;
    String? artist;
    String? album;
    while (off + headLen <= b.length && off < end) {
      if (b[off] == 0) break;
      if (v22) {
        // v5.1.3: ID3v2.2 — 3 harf kimlik + 3 bayt boyut (6 bayt başlık).
        final id = ascii.decode(b.sublist(off, off + 3), allowInvalid: true);
        if (!_looksLikeFrameId(id, 3)) {
          off++;
          continue;
        }
        final size = ((b[off + 3] & 0xFF) << 16) |
            ((b[off + 4] & 0xFF) << 8) |
            (b[off + 5] & 0xFF);
        if (size <= 0 || size > 8 * 1024 * 1024) {
          off++;
          continue;
        }
        if (off + 6 + size > b.length) break;
        if (id == 'TT2' || id == 'TP1' || id == 'TAL') {
          final text = _decodeText(b.sublist(off + 6, off + 6 + size));
          if (text != null && text.isNotEmpty) {
            if (id == 'TT2') title ??= text;
            if (id == 'TP1') artist ??= text;
            if (id == 'TAL') album ??= text;
          }
        }
        off += 6 + size;
        continue;
      }
      final id = ascii.decode(b.sublist(off, off + 4), allowInvalid: true);
      if (!_looksLikeFrameId(id)) {
        off++;
        continue;
      }
      final size = (verMajor >= 4)
          ? _syncSafe(b, off + 4)
          : _u32(b, off + 4);
      if (size <= 0 || size > 8 * 1024 * 1024) {
        off++;
        continue;
      }
      if (off + 10 + size > b.length) break;
      if (id == 'TIT2' ||
          id == 'TPE1' ||
          id == 'TALB' ||
          id == 'TT2' ||
          id == 'TP1' ||
          id == 'TAL') {
        final text = _decodeText(b.sublist(off + 10, off + 10 + size));
        if (text != null && text.isNotEmpty) {
          if (id == 'TIT2' || id == 'TT2') title ??= text;
          if (id == 'TPE1' || id == 'TP1') artist ??= text;
          if (id == 'TALB' || id == 'TAL') album ??= text;
        }
      }
      off += 10 + size;
    }
    return Id3Tags(title: title, artist: artist, album: album);
  }

  static bool _looksLikeFrameId(String id, [int len = 4]) {
    if (id.length != len) return false;
    for (final c in id.codeUnits) {
      final ok = (c >= 65 && c <= 90) || (c >= 48 && c <= 57);
      if (!ok) return false;
    }
    return true;
  }

  static String? _decodeText(List<int> f) {
    if (f.isEmpty) return null;
    final enc = f[0];
    var bytes = f.sublist(1);
    while (bytes.isNotEmpty && bytes.last == 0) {
      bytes = bytes.sublist(0, bytes.length - 1);
    }
    if (bytes.isEmpty) return null;
    try {
      String raw;
      switch (enc) {
        case 0:
          raw = _latinOrTurkish(bytes);
          break;
        case 1:
          raw = _utf16(bytes, bigEndian: null);
          break;
        case 2:
          raw = _utf16(bytes, bigEndian: true);
          break;
        case 3:
          raw = utf8.decode(bytes, allowMalformed: true);
          break;
        default:
          raw = utf8.decode(bytes, allowMalformed: true);
      }
      final cleaned = raw
          .replaceAll('\u0000', ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      return cleaned.isEmpty ? null : cleaned;
    } catch (_) {
      return null;
    }
  }

  /// Encoding 0: çoğu Türkçe etiket Windows-1254 / ISO-8859-9;
  /// bazıları da aslında UTF-8 olup 0 diye işaretlenmiş.
  static String _latinOrTurkish(List<int> bytes) {
    if (bytes.every((c) => c < 128)) return ascii.decode(bytes);
    final asUtf8 = utf8.decode(bytes, allowMalformed: true);
    final malformed = asUtf8.contains('\uFFFD');
    if (!malformed && asUtf8.codeUnits.any((c) => c > 127)) {
      return asUtf8;
    }
    const map = {
      0xD0: 0x011E, // Ğ
      0xF0: 0x011F, // ğ
      0xDD: 0x0130, // İ
      0xFD: 0x0131, // ı
      0xDE: 0x015E, // Ş
      0xFE: 0x015F, // ş
      0xC7: 0x00C7, // Ç
      0xE7: 0x00E7, // ç
      0xD6: 0x00D6, // Ö
      0xF6: 0x00F6, // ö
      0xDC: 0x00DC, // Ü
      0xFC: 0x00FC, // ü
    };
    final codes = <int>[];
    for (final b in bytes) {
      codes.add(map[b] ?? b);
    }
    return String.fromCharCodes(codes);
  }

  static String _utf16(List<int> bytes, {required bool? bigEndian}) {
    var be = bigEndian ?? true;
    var start = 0;
    if (bytes.length >= 2) {
      if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
        be = false;
        start = 2;
      } else if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
        be = true;
        start = 2;
      }
    }
    final codes = <int>[];
    for (var i = start; i + 1 < bytes.length; i += 2) {
      final c = be
          ? ((bytes[i] << 8) | bytes[i + 1])
          : ((bytes[i + 1] << 8) | bytes[i]);
      if (c != 0) codes.add(c);
    }
    return String.fromCharCodes(codes);
  }

  /// Mevcut ses verisini koruyarak ID3v2.3 yazar (TIT2/TPE1/TALB/APIC).
  static Future<bool> write({
    required String path,
    required String title,
    String? artist,
    String? album,
    List<int>? coverJpeg,
    bool keepExistingCover = true,
  }) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        lastWriteError = 'dosya bulunamadı: $path';
        return false;
      }
      // v5.1.3: MP4/M4A kapsayıcısına ID3 yazılamaz — dosyaya dokunma.
      final head = await file.openRead(0, 12).fold<BytesBuilder>(
        BytesBuilder(copy: false),
        (b, c) => b..add(c),
      );
      if (_isMp4Header(head.takeBytes())) {
        lastWriteError = 'mp4 kapsayıcı — yanlış yol';
        return false;
      }
      final raf = await file.open(mode: FileMode.read);
      List<int> existingCover = const [];
      var audioStart = 0;
      try {
        final h = await raf.read(10);
        if (h.length == 10 && h[0] == 0x49 && h[1] == 0x44 && h[2] == 0x33) {
          audioStart = 10 + _syncSafe(h, 6);
          if (keepExistingCover && (coverJpeg == null || coverJpeg.isEmpty)) {
            final tagLen = audioStart.clamp(0, _maxBytes);
            await raf.setPosition(0);
            final tagBytes = await raf.read(tagLen);
            existingCover = _extractJpeg(tagBytes) ?? const [];
          }
        }
      } finally {
        await raf.close();
      }

      final jpeg = (coverJpeg != null && coverJpeg.isNotEmpty)
          ? coverJpeg
          : existingCover;

      final frames = BytesBuilder();
      frames.add(_textFrame('TIT2', title));
      if (artist != null && artist.trim().isNotEmpty) {
        frames.add(_textFrame('TPE1', artist.trim()));
      }
      if (album != null && album.trim().isNotEmpty) {
        frames.add(_textFrame('TALB', album.trim()));
      }
      if (jpeg.isNotEmpty) {
        frames.add(_apicFrame(jpeg));
      }
      final body = frames.takeBytes();
      final size = body.length;
      final header = <int>[
        0x49, 0x44, 0x33, 0x03, 0x00, 0x00,
        (size >> 21) & 0x7F,
        (size >> 14) & 0x7F,
        (size >> 7) & 0x7F,
        size & 0x7F,
      ];

      // Scoped storage: müzik klasörüne .tmp yazılamaz. Önce uygulama
      // önbelleğine yaz, sonra native MediaStore ile asıl dosyaya kopyala.
      final tmp = File(
        '${Directory.systemTemp.path}/cobble-id3-${DateTime.now().millisecondsSinceEpoch}.mp3',
      );
      final out = tmp.openWrite();
      out.add(header);
      out.add(body);
      await for (final chunk in file.openRead(audioStart)) {
        out.add(chunk);
      }
      await out.close();
      // Müzik klasörüne Dart File.copy yapma: scoped storage dosyayı
      // boşaltabiliyor. Tam etiketli kopya uygulama önbelleğinde;
      // native createWriteRequest + tam yazım asıl dosyayı değiştirir.
      if (!await tmp.exists() || await tmp.length() < 128) {
        try {
          if (await tmp.exists()) await tmp.delete();
        } catch (_) {}
        lastWriteError = 'geçici etiket dosyası oluşturulamadı';
        return false;
      }
      // v5.1.3: DOĞRUDAN Dart yazımı — izin KOŞULSUZ denenir (izin yoksa
      // burada düşer, native zinciri devralır). İki deneme + kısa bekleme:
      // dosya geçici olarak meşgulse ikincide geçer. Neden kayda geçer.
      // v5.1.3: DOĞRUDAN Dart yazımı — iki strateji, üç tur:
      //   A) doğrudan üzerine yaz
      //   B) yanına geçici yaz + AD DEĞİŞTİRME (rename) — dosya başka bir
      //      süreçte açıkken (oynatıcı/tarayıcı) bile geçen, tamamen
      //      farklı bir sistem çağrısı yoludur.
      // Hata NEDENİ (errno dahil) kayda geçer.
      var directErr = '';
      for (var attempt = 0; attempt < 3; attempt++) {
        if (attempt > 0) {
          await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
        }
        // A) üzerine yaz
        try {
          final bytes = await tmp.readAsBytes();
          await File(path).writeAsBytes(bytes, flush: true);
          if (await File(path).length() == bytes.length) {
            try {
              const chScan = MethodChannel('cobble/native');
              await chScan.invokeMethod('scanAudioFile', {
                'path': path,
                'title': title,
                'artist': artist,
                'album': album,
              });
            } catch (_) {}
            try {
              if (await tmp.exists()) await tmp.delete();
            } catch (_) {}
            lastWriteError = '';
            return true;
          }
          directErr = 'üzerine yazma: boyut doğrulanamadı';
        } catch (e) {
          directErr = 'üzerine yazma: $e';
        }
        // B) geçici + rename
        try {
          final bytes = await tmp.readAsBytes();
          final side = File('$path.cobbletmp');
          await side.writeAsBytes(bytes, flush: true);
          try {
            await side.rename(path);
            if (await File(path).length() == bytes.length) {
              try {
                const chScan2 = MethodChannel('cobble/native');
                await chScan2.invokeMethod('scanAudioFile', {
                  'path': path,
                  'title': title,
                  'artist': artist,
                  'album': album,
                });
              } catch (_) {}
              try {
                if (await tmp.exists()) await tmp.delete();
              } catch (_) {}
              lastWriteError = '';
              return true;
            }
            directErr = 'rename: boyut doğrulanamadı';
          } catch (e) {
            directErr = 'rename: $e';
            try {
              if (await side.exists()) await side.delete();
            } catch (_) {}
          }
        } catch (e) {
          directErr = 'yanına yazma: $e';
        }
      }
      lastWriteError = 'doğrudan yazım: $directErr';
      try {
        const ch = MethodChannel('cobble/native');
        final ok = await ch.invokeMethod<bool>('writeAudioFile', {
          'src': tmp.path,
          'dest': path,
          'title': title,
          'artist': artist,
          'album': album,
        });
        try {
          if (await tmp.exists()) await tmp.delete();
        } catch (_) {}
        if (ok != true) lastWriteError = 'native yazma zinciri';
        return ok == true;
      } catch (e) {
        try {
          if (await tmp.exists()) await tmp.delete();
        } catch (_) {}
        lastWriteError = 'native kanal: $e';
        return false;
      }
    } catch (e) {
      lastWriteError = 'beklenmedik: $e';
      return false;
    }
  }

  static List<int> _textFrame(String id, String text) {
    final payload = <int>[0x03, ...utf8.encode(text), 0x00];
    return _frame(id, payload);
  }

  static List<int> _apicFrame(List<int> jpeg) {
    final isPng = jpeg.length > 8 && jpeg[0] == 0x89 && jpeg[1] == 0x50;
    final mime = isPng ? 'image/png' : 'image/jpeg';
    final payload = <int>[
      0x00,
      ...ascii.encode(mime),
      0x00,
      0x03, // front cover
      0x00, // empty description
      ...jpeg,
    ];
    return _frame('APIC', payload);
  }

  static List<int> _frame(String id, List<int> payload) {
    final size = payload.length;
    return [
      ...id.codeUnits,
      (size >> 24) & 0xFF,
      (size >> 16) & 0xFF,
      (size >> 8) & 0xFF,
      size & 0xFF,
      0,
      0,
      ...payload,
    ];
  }

  static List<int>? _extractJpeg(List<int> b) {
    if (b.length < 20) return null;
    final verMajor = b[3];
    final flags = b[5];
    final tagSize = _syncSafe(b, 6);
    var off = 10;
    // v5.1.3 DÜZELTMESİ: genişletilmiş başlığı atla — parse() yapıyordu,
    // burada eksikti; ext-header'lı dosyalarda kapak hiç bulunamıyordu.
    if (verMajor >= 3 && (flags & 0x40) != 0 && off + 4 <= b.length) {
      final ext = verMajor >= 4 ? _syncSafe(b, off) : _u32(b, off);
      if (ext > 4) off += ext;
    }
    final end = 10 + tagSize;
    final v22 = verMajor == 2;
    final headLen = v22 ? 6 : 10;
    while (off + headLen <= b.length && off < end) {
      if (b[off] == 0) break;
      if (v22) {
        // v5.1.3: ID3v2.2 — kapak "PIC" karesinde (3 harf ID, 3 bayt boyut).
        final id = ascii.decode(b.sublist(off, off + 3), allowInvalid: true);
        if (!_looksLikeFrameId(id, 3)) {
          off++;
          continue;
        }
        final size = ((b[off + 3] & 0xFF) << 16) |
            ((b[off + 4] & 0xFF) << 8) |
            (b[off + 5] & 0xFF);
        if (size <= 0 || size > 8 * 1024 * 1024) {
          off++;
          continue;
        }
        if (off + 6 + size > b.length) break;
        if (id == 'PIC') {
          return _picImage(b.sublist(off + 6, off + 6 + size));
        }
        off += 6 + size;
        continue;
      }
      final id = ascii.decode(b.sublist(off, off + 4), allowInvalid: true);
      if (!_looksLikeFrameId(id)) {
        off++;
        continue;
      }
      final size = verMajor >= 4 ? _syncSafe(b, off + 4) : _u32(b, off + 4);
      if (size <= 0 || size > 8 * 1024 * 1024) {
        off++;
        continue;
      }
      if (off + 10 + size > b.length) break;
      if (id == 'APIC') {
        return _apicImage(b.sublist(off + 10, off + 10 + size));
      }
      off += 10 + size;
    }
    return null;
  }

  /// ID3v2.2 PIC kare gövdesi: kodlama(1) + biçim(3, "JPG"/"PNG") +
  /// resim türü(1) + açıklama + veri.
  static List<int>? _picImage(List<int> f) {
    if (f.length < 6) return null;
    final enc = f[0];
    var i = 5; // 1 kodlama + 3 biçim + 1 tür
    if (enc == 1 || enc == 2) {
      while (i + 1 < f.length && !(f[i] == 0 && f[i + 1] == 0)) {
        i++;
      }
      i += 2;
    } else {
      while (i < f.length && f[i] != 0) {
        i++;
      }
      i++;
    }
    if (i >= f.length) return null;
    for (var s = i; s + 1 < f.length && s < i + 24; s++) {
      if (f[s] == 0xFF && f[s + 1] == 0xD8) return f.sublist(s);
      if (f[s] == 0x89 && f[s + 1] == 0x50) return f.sublist(s);
    }
    return f.sublist(i);
  }

  static List<int>? _apicImage(List<int> f) {
    if (f.isEmpty) return null;
    final enc = f[0];
    var i = 1;
    final mimeEnd = f.indexOf(0, i);
    if (mimeEnd < 0) return null;
    i = mimeEnd + 1;
    if (i >= f.length) return null;
    i++; // picture type
    if (enc == 1 || enc == 2) {
      while (i + 1 < f.length && !(f[i] == 0 && f[i + 1] == 0)) {
        i++;
      }
      i += 2;
    } else {
      final descEnd = f.indexOf(0, i);
      if (descEnd < 0) return null;
      i = descEnd + 1;
    }
    for (var s = i; s + 1 < f.length && s < i + 24; s++) {
      if (f[s] == 0xFF && f[s + 1] == 0xD8) return f.sublist(s);
      if (f[s] == 0x89 && f[s + 1] == 0x50) return f.sublist(s);
    }
    return i < f.length ? f.sublist(i) : null;
  }

  // ═══════════════════ MP4/M4A YAZMA (v5.1.3) ═══════════════════

  static void _put32(List<int> b, int v) {
    b
      ..add((v >> 24) & 0xFF)
      ..add((v >> 16) & 0xFF)
      ..add((v >> 8) & 0xFF)
      ..add(v & 0xFF);
  }

  static List<int> _atom(String type, List<int> body) {
    final h = <int>[];
    _put32(h, 8 + body.length);
    // v5.1.3 DÜZELTME (asıl "dosyaya yazılamadı" nedeni): atom adları
    // '©nam'/'©ART'/'©alb' gibi © (U+00A9) içerir — ASCII DEĞİL, Latin-1
    // ile kodlanmalı. ascii.encode burada çakılıyor, m4a yazımı daha
    // dosyaya dokunmadan düşüyordu (izin/MediaStore ile ilgisi yoktu).
    h.addAll(latin1.encode(type));
    h.addAll(body);
    return h;
  }

  /// 'data' atomu: 4B sürüm/bayrak (1=metin, 13=JPEG, 14=PNG) + 4B yerel
  /// kodu (0) + yük. Okuyucu tarafı (_mp4Text/_readMp4Cover) 8 baytı atlar.
  static List<int> _dataAtom(List<int> payload, int flags) {
    return _atom('data', [0, 0, 0, flags, 0, 0, 0, 0, ...payload]);
  }

  static List<int> _ilstItem(String name, List<int> payload, int flags) {
    return _atom(name, _dataAtom(payload, flags));
  }

  /// Üst düzey (ya da herhangi bir) atom gövdesindeki çocuk aralıkları.
  static List<(int, int)> _atomChildren(List<int> b) {
    final out = <(int, int)>[];
    var off = 0;
    while (off + 8 <= b.length) {
      final size = _u32b(b, off);
      if (size < 8 || off + size > b.length) break;
      out.add((off, off + size));
      off += size;
    }
    return out;
  }

  static List<int> _hdlrAtom() {
    return _atom('hdlr', [
      0, 0, 0, 0, // ön tanımlı
      ...ascii.encode('mdir'),
      ...ascii.encode('appl'),
      0, 0, 0, 0, 0, 0, 0, 0, // ayrılmış
      0, // boş isim
    ]);
  }

  static List<int> _buildIlst({
    required String title,
    String? artist,
    String? album,
    List<int>? cover,
  }) {
    final body = <int>[];
    void add(String name, List<int> payload, int flags) {
      body.addAll(_ilstItem(name, payload, flags));
    }

    add('©nam', utf8.encode(title), 1);
    if (artist != null && artist.isNotEmpty) {
      add('©ART', utf8.encode(artist), 1);
    }
    if (album != null && album.isNotEmpty) {
      add('©alb', utf8.encode(album), 1);
    }
    if (cover != null && cover.isNotEmpty) {
      final isJpeg =
          cover.length > 4 && cover[0] == 0xFF && cover[1] == 0xD8;
      add('covr', cover, isJpeg ? 13 : 14);
    }
    return _atom('ilst', body);
  }

  /// meta gövdesini (4B önek + çocuklar) ilst ile yeniden kurar.
  static List<int> _rebuildMeta(List<int> meta, List<int> ilst) {
    final kids = _atomChildren(meta.sublist(4));
    final out = <int>[0, 0, 0, 0];
    var handled = false;
    for (final (s, e) in kids) {
      final type = String.fromCharCodes(
        meta.sublist(4 + s + 4, 4 + s + 8),
      );
      if (type == 'ilst') {
        out.addAll(ilst);
        handled = true;
      } else {
        out.addAll(meta.sublist(4 + s, 4 + e));
      }
    }
    if (!handled) out.addAll(ilst);
    return _atom('meta', out);
  }

  static List<int> _rebuildUdta(List<int> udta, List<int> ilst) {
    final kids = _atomChildren(udta);
    final out = <int>[];
    var handled = false;
    for (final (s, e) in kids) {
      final type = String.fromCharCodes(udta.sublist(s + 4, s + 8));
      if (type == 'meta') {
        out.addAll(_rebuildMeta(udta.sublist(s + 8, e), ilst));
        handled = true;
      } else {
        out.addAll(udta.sublist(s, e));
      }
    }
    if (!handled) {
      out.addAll(
        _atom('meta', [0, 0, 0, 0, ..._hdlrAtom(), ...ilst]),
      );
    }
    return _atom('udta', out);
  }

  static List<int> _rebuildMoov(List<int> moov, List<int> ilst) {
    final kids = _atomChildren(moov);
    final out = <int>[];
    var handled = false;
    for (final (s, e) in kids) {
      final type = String.fromCharCodes(moov.sublist(s + 4, s + 8));
      if (type == 'udta') {
        out.addAll(_rebuildUdta(moov.sublist(s + 8, e), ilst));
        handled = true;
      } else {
        out.addAll(moov.sublist(s, e));
      }
    }
    if (!handled) {
      out.addAll(
        _atom('udta', _atom('meta', [0, 0, 0, 0, ..._hdlrAtom(), ...ilst])),
      );
    }
    return _atom('moov', out);
  }

  /// Üst düzey atom tablosu: (başlangıç, gövdeBaşı, son, tip).
  /// 64-bit geniş boyutlu (size==1) atomları da anlar.
  static List<(int, int, int, String)> _topAtoms(List<int> b) {
    final out = <(int, int, int, String)>[];
    var off = 0;
    while (off + 8 <= b.length) {
      final size = _u32b(b, off);
      final type = String.fromCharCodes(b.sublist(off + 4, off + 8));
      var end = -1;
      var body = off + 8;
      if (size == 1 && off + 16 <= b.length) {
        final hi = _u32b(b, off + 8);
        final lo = _u32b(b, off + 12);
        final big = (hi * 4294967296) + lo;
        if (big >= 16 && off + big <= b.length) {
          end = off + big;
          body = off + 16;
        }
      } else if (size >= 8 && off + size <= b.length) {
        end = off + size;
      }
      if (end < 0) break;
      out.add((off, body, end, type));
      off = end;
    }
    return out;
  }

  /// MP4/M4A etiketlerini (moov/udta/meta/ilst) dosyaya yazar. Tam yeni
  /// dosya önbellekte kurulur; asıl dosyaya yazım MP3 yolundaki gibi
  /// native writeAudioFile (yedekli + geri alınabilir) üzerinden olur.
  static Future<bool> writeMp4({
    required String path,
    required String title,
    String? artist,
    String? album,
    List<int>? coverJpeg,
    bool keepExistingCover = true,
  }) async {
    try {
      final file = File(path);
      if (!await file.exists()) return false;
      final src = await file.readAsBytes();
      if (src.length < 128) {
        lastWriteError = 'm4a: dosya çok küçük';
        return false;
      }

      // Yeni kapak verilmediyse eski kapağı koru.
      List<int>? cover = coverJpeg;
      if (keepExistingCover && (cover == null || cover.isEmpty)) {
        final old = await _readMp4Cover(file, src.length);
        if (old != null && old.isNotEmpty) cover = old;
      }

      // Üst düzey atomlarda moov'u bul (64-bit boyutlar dahil).
      final tops = _topAtoms(src);
      (int, int, int, String)? moov;
      for (final t in tops) {
        if (t.$4 == 'moov') {
          moov = t;
          break;
        }
      }
      if (moov == null) {
        lastWriteError = 'm4a: moov bölümü bulunamadı (biçim)';
        return false;
      }

      final ilst = _buildIlst(
        title: title,
        artist: artist,
        album: album,
        cover: _removeCoverFlag(coverJpeg) ? null : cover,
      );
      final newMoov = _rebuildMoov(
        src.sublist(moov.$2, moov.$3),
        ilst,
      );

      // Tüm dosyayı yeniden akıt: moov'un yerine yenisi.
      final out = BytesBuilder(copy: false);
      var replaced = false;
      var lastEnd = 0;
      for (final (start, _, end, type) in tops) {
        if (type == 'moov') {
          out.add(newMoov);
          replaced = true;
        } else {
          out.add(src.sublist(start, end));
        }
        lastEnd = end;
      }
      if (lastEnd < src.length) out.add(src.sublist(lastEnd));
      if (!replaced) {
        lastWriteError = 'm4a: moov yeniden kurulamadı (biçim)';
        return false;
      }

      final tmp = File(
        '${Directory.systemTemp.path}'
        '/cobble-mp4-${DateTime.now().millisecondsSinceEpoch}.m4a',
      );
      await tmp.writeAsBytes(out.takeBytes(), flush: true);
      if (await tmp.length() < 128) {
        try {
          if (await tmp.exists()) await tmp.delete();
        } catch (_) {}
        lastWriteError = 'm4a: geçici dosya oluşturulamadı';
        return false;
      }
      // v5.1.3: DOĞRUDAN Dart yazımı — izin KOŞULSUZ denenir (izin yoksa
      // burada düşer, native zinciri devralır). İki deneme + kısa bekleme:
      // dosya geçici olarak meşgulse ikincide geçer. Neden kayda geçer.
      // v5.1.3: DOĞRUDAN Dart yazımı — iki strateji, üç tur:
      //   A) doğrudan üzerine yaz
      //   B) yanına geçici yaz + AD DEĞİŞTİRME (rename) — dosya başka bir
      //      süreçte açıkken (oynatıcı/tarayıcı) bile geçen, tamamen
      //      farklı bir sistem çağrısı yoludur.
      // Hata NEDENİ (errno dahil) kayda geçer.
      var directErr = '';
      for (var attempt = 0; attempt < 3; attempt++) {
        if (attempt > 0) {
          await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
        }
        // A) üzerine yaz
        try {
          final bytes = await tmp.readAsBytes();
          await File(path).writeAsBytes(bytes, flush: true);
          if (await File(path).length() == bytes.length) {
            try {
              const chScan = MethodChannel('cobble/native');
              await chScan.invokeMethod('scanAudioFile', {
                'path': path,
                'title': title,
                'artist': artist,
                'album': album,
              });
            } catch (_) {}
            try {
              if (await tmp.exists()) await tmp.delete();
            } catch (_) {}
            lastWriteError = '';
            return true;
          }
          directErr = 'üzerine yazma: boyut doğrulanamadı';
        } catch (e) {
          directErr = 'üzerine yazma: $e';
        }
        // B) geçici + rename
        try {
          final bytes = await tmp.readAsBytes();
          final side = File('$path.cobbletmp');
          await side.writeAsBytes(bytes, flush: true);
          try {
            await side.rename(path);
            if (await File(path).length() == bytes.length) {
              try {
                const chScan2 = MethodChannel('cobble/native');
                await chScan2.invokeMethod('scanAudioFile', {
                  'path': path,
                  'title': title,
                  'artist': artist,
                  'album': album,
                });
              } catch (_) {}
              try {
                if (await tmp.exists()) await tmp.delete();
              } catch (_) {}
              lastWriteError = '';
              return true;
            }
            directErr = 'rename: boyut doğrulanamadı';
          } catch (e) {
            directErr = 'rename: $e';
            try {
              if (await side.exists()) await side.delete();
            } catch (_) {}
          }
        } catch (e) {
          directErr = 'yanına yazma: $e';
        }
      }
      lastWriteError = 'doğrudan yazım: $directErr';
      try {
        const ch = MethodChannel('cobble/native');
        final ok = await ch.invokeMethod<bool>('writeAudioFile', {
          'src': tmp.path,
          'dest': path,
          'title': title,
          'artist': artist,
          'album': album,
        });
        try {
          if (await tmp.exists()) await tmp.delete();
        } catch (_) {}
        if (ok != true) lastWriteError = 'native yazma zinciri';
        return ok == true;
      } catch (e) {
        try {
          if (await tmp.exists()) await tmp.delete();
        } catch (_) {}
        lastWriteError = 'native kanal: $e';
        return false;
      }
    } catch (e) {
      lastWriteError = 'beklenmedik: $e';
      return false;
    }
  }

  /// "Kapağı kaldır" bayrağı: boş liste verildiyse kapak silinsin.
  static bool _removeCoverFlag(List<int>? coverJpeg) =>
      coverJpeg != null && coverJpeg.isEmpty;
}
