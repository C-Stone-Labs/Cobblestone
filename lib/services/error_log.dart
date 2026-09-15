import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

Future<File> _logFile() async {
  final dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}/hata_gunlugu.txt');
}

Future<void> logError(String source, Object error, StackTrace? stack) async {
  debugPrint('ERROR $source: $error');
  try {
    final f = await _logFile();
    // v5.1.1: günlük sınırsız büyümesin — 256 KB üstünde son 96 KB tutulur.
    const maxLen = 256 * 1024;
    const keepLen = 96 * 1024;
    var existing = '';
    if (await f.exists() && await f.length() > maxLen) {
      try {
        final raw = await f.readAsString();
        existing = raw.length > keepLen ? raw.substring(raw.length - keepLen) : raw;
      } catch (_) {}
      await f.writeAsString(
        '--- günlük döndürüldü (eski kayıtlar kırpıldı) ---\n$existing',
        flush: true,
      );
    }
    await f.writeAsString(
      '--- ${DateTime.now()} — $source ---\n$error\n$stack\n\n',
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {}
}

Future<String> readErrorLog() async {
  try {
    final f = await _logFile();
    if (!await f.exists()) return 'Kayıtlı hata yok.';
    return await f.readAsString();
  } catch (_) {
    return 'Günlük okunamadı.';
  }
}

Future<void> clearErrorLog() async {
  try {
    final f = await _logFile();
    if (await f.exists()) await f.delete();
  } catch (_) {}
}
