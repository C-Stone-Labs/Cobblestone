import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cobblestone/services/id3_tags.dart';

List<int> _frame(String id, List<int> body) {
  final size = body.length;
  return [
    ...id.codeUnits,
    (size >> 24) & 0xFF,
    (size >> 16) & 0xFF,
    (size >> 8) & 0xFF,
    size & 0xFF,
    0,
    0,
    ...body,
  ];
}

List<int> _id3(List<int> frames) {
  final size = frames.length;
  final synch = [
    (size >> 21) & 0x7F,
    (size >> 14) & 0x7F,
    (size >> 7) & 0x7F,
    size & 0x7F,
  ];
  return [0x49, 0x44, 0x33, 0x03, 0x00, 0x00, ...synch, ...frames];
}

/// ID3v2.2: 6 bayt kare başlığı (3 ID + 3 boyut).
List<int> _frame22(String id, List<int> body) {
  final size = body.length;
  return [
    ...id.codeUnits,
    (size >> 16) & 0xFF,
    (size >> 8) & 0xFF,
    size & 0xFF,
    ...body,
  ];
}

List<int> _id3v22(List<int> frames) {
  final size = frames.length;
  final synch = [
    (size >> 21) & 0x7F,
    (size >> 14) & 0x7F,
    (size >> 7) & 0x7F,
    size & 0x7F,
  ];
  return [0x49, 0x44, 0x33, 0x02, 0x00, 0x00, ...synch, ...frames];
}

/// v2.3 genişletilmiş başlık (6 bayt) + kareler.
/// Not: etiket boyutuna (syncsafe) ext-header da dahildir.
List<int> _id3WithExtHeader(List<int> frames) {
  final total = 6 + frames.length;
  final synch = [
    (total >> 21) & 0x7F,
    (total >> 14) & 0x7F,
    (total >> 7) & 0x7F,
    total & 0x7F,
  ];
  return [
    0x49, 0x44, 0x33, 0x03, 0x00, 0x40, ...synch,
    0, 0, 0, 6, // ext header boyutu = 6 (kendisi hariç)
    0, 0, // ext header bayrakları
    ...frames,
  ];
}

const _tinyJpeg = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46];

List<int> _apicBody() => [0x00, ...'image/jpeg'.codeUnits, 0x00, 0x03, 0x00, ..._tinyJpeg];

List<int> _picBody() => [0x00, ...'JPG'.codeUnits, 0x03, 0x00, ..._tinyJpeg];

void main() {
  test('ID3v2.3 TIT2 ve TPE1 okunur', () {
    final tit2 = _frame('TIT2', [0, ...'Montagem Batchi'.codeUnits]);
    final tpe1 = _frame('TPE1', [0, ...'DJ Test'.codeUnits]);
    final tags = Id3Tags.parse(_id3([...tit2, ...tpe1]));
    expect(tags.title, 'Montagem Batchi');
    expect(tags.artist, 'DJ Test');
  });

  test('ID3 yoksa boş döner', () {
    final tags = Id3Tags.parse([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
    expect(tags.title, isNull);
    expect(tags.artist, isNull);
  });

  test('Windows-1254 Türkçe başlık', () {
    // "Şarkı" in Windows-1254: Ş=0xDE a r k ı=0xFD
    final tit2 = _frame('TIT2', [0, 0xDE, 0x61, 0x72, 0x6B, 0xFD]);
    final tags = Id3Tags.parse(_id3(tit2));
    expect(tags.title, 'Şarkı');
  });

  test('v5.1.3: ID3v2.2 TT2 başlığı okunur', () {
    final tt2 = _frame22('TT2', [0, ...'Eski Sarki'.codeUnits]);
    final tags = Id3Tags.parse(_id3v22(tt2));
    expect(tags.title, 'Eski Sarki');
  });

  test('v5.1.3: genişletilmiş başlıklı v2.3 etikette başlık okunur', () {
    final tit2 = _frame('TIT2', [0, ...'Ext Header Test'.codeUnits]);
    final tags = Id3Tags.parse(_id3WithExtHeader(tit2));
    expect(tags.title, 'Ext Header Test');
  });

  test('v5.1.3: genişletilmiş başlıklı v2.3 etiketten kapak (APIC) çıkar', () async {
    final f = File(
      '${Directory.systemTemp.path}/test_ext_apic_${DateTime.now().millisecondsSinceEpoch}.mp3',
    );
    await f.writeAsBytes([..._id3WithExtHeader(_frame('APIC', _apicBody())), 0xFF, 0xFB, 1, 2, 3]);
    final cover = await Id3Tags.readCover(f.path);
    expect(cover, isNotNull);
    expect(cover!.length, greaterThanOrEqualTo(_tinyJpeg.length));
    expect(cover[0], 0xFF);
    expect(cover[1], 0xD8);
    await f.delete();
  });

  test('v5.1.3: ID3v2.2 PIC karesinden kapak çıkar', () async {
    final f = File(
      '${Directory.systemTemp.path}/test_v22_pic_${DateTime.now().millisecondsSinceEpoch}.mp3',
    );
    await f.writeAsBytes([..._id3v22(_frame22('PIC', _picBody())), 0xFF, 0xFB, 1, 2, 3]);
    final cover = await Id3Tags.readCover(f.path);
    expect(cover, isNotNull);
    expect(cover![0], 0xFF);
    expect(cover[1], 0xD8);
    await f.delete();
  });

  /// Minimal MP4: ftyp + moov(udta(meta(ilst(©nam,©ART,©alb,covr))))
  List<int> _atom(String type, List<int> body) {
    final size = body.length + 8;
    return [
      (size >> 24) & 0xFF, (size >> 16) & 0xFF, (size >> 8) & 0xFF, size & 0xFF,
      ...type.codeUnits,
      ...body,
    ];
  }

  List<int> _dataAtom(int flag, List<int> payload) {
    final body = [0, 0, 0, flag, 0, 0, 0, 0, ...payload];
    return _atom('data', body);
  }

  List<int> _miniMp4() {
    final ftyp = _atom(
      'ftyp',
      [...'isom'.codeUnits, 0, 0, 2, 0, ...'isomiso2mp41'.codeUnits],
    );
    final ilst = _atom('ilst', [
      ..._atom('©nam', _dataAtom(1, utf8.encode('Ajda Pekkan'))),
      ..._atom('©ART', _dataAtom(1, utf8.encode('Süper Star'))),
      ..._atom('©alb', _dataAtom(1, utf8.encode('1976'))),
      ..._atom('covr', _dataAtom(13, _tinyJpeg)),
    ]);
    final meta = _atom('meta', [0, 0, 0, 0, ...ilst]);
    final udta = _atom('udta', meta);
    final moov = _atom('moov', udta);
    return [...ftyp, ...moov];
  }

  test('v5.1.3: M4A başlık/sanatçı/albüm okunur', () async {
    final f = File(
      '${Directory.systemTemp.path}/test_m4a_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );
    await f.writeAsBytes(_miniMp4());
    final tags = await Id3Tags.read(f.path);
    expect(tags.title, 'Ajda Pekkan');
    expect(tags.artist, 'Süper Star');
    expect(tags.album, '1976');
    await f.delete();
  });

  test('v5.1.3: M4A kapağı (covr) okunur', () async {
    final f = File(
      '${Directory.systemTemp.path}/test_m4a_covr_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );
    await f.writeAsBytes(_miniMp4());
    final cover = await Id3Tags.readCover(f.path);
    expect(cover, isNotNull);
    expect(cover![0], 0xFF);
    expect(cover[1], 0xD8);
    await f.delete();
  });
}
