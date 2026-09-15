import '../services/theme_controller.dart';
import '../widgets/cobble_toast.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Android 13+ için POST_NOTIFICATIONS çalışma-zamanı izni.
///
/// Manifest bu izni zaten bildiriyor; ancak sistem, uygulama açıkken bir kez
/// SORULMASINI da zorunlu kılıyor. Kullanıcıya kurulum başına sadece BİR kez
/// sorulur; reddederse uygulama sessizce bildirimsiz çalışmaya devam eder
/// (müzik çalması bundan etkilenmez). Sonradan Ayarlar ekranından tekrar
/// istenebilir.
Future<void> ensureNotificationPermissionOnce() async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('notif_perm_asked_v1') == true) return;
    await prefs.setBool('notif_perm_asked_v1', true);

    final status = await Permission.notification.status;
    if (status.isGranted || status.isLimited) return;
    if (status.isPermanentlyDenied) return;
    await Permission.notification.request();
  } catch (_) {}
}

/// Bildirim izni şu an verili mi? (Ayarlar ekranının durum göstergesi için.)
Future<bool> isNotificationPermissionGranted() async {
  if (defaultTargetPlatform != TargetPlatform.android) return true;
  try {
    final s = await Permission.notification.status;
    return s.isGranted || s.isLimited;
  } catch (_) {
    return false;
  }
}

/// Ayarlar ekranındaki "İzin Ver" düğmesi: gerekirse sistem penceresini açar,
/// kalıcı reddedildiyse uygulama ayarlarına yönlendirir.
Future<bool> requestNotificationPermissionInteractive() async {
  if (defaultTargetPlatform != TargetPlatform.android) return true;
  try {
    final status = await Permission.notification.status;
    if (status.isGranted || status.isLimited) return true;
    if (status.isPermanentlyDenied) {
      await openAppSettings();
      return false;
    }
    final r = await Permission.notification.request();
    return r.isGranted || r.isLimited;
  } catch (_) {
    return false;
  }
}

/// "Batarya optimizasyonu dışında tut" izni verili mi?
/// Bazı telefonlar (özellikle agresif arayüzler) bu izin olmadan arka planda
/// çalan uygulamayı bir süre sonra DURDURUR — kullanıcının bildirdiği
/// "2-3 şarkı sonra susma" sorununun tipik ilacıdır.
Future<bool> isBatteryOptimizationIgnored() async {
  if (defaultTargetPlatform != TargetPlatform.android) return true;
  try {
    return await Permission.ignoreBatteryOptimizations.isGranted;
  } catch (_) {
    return false;
  }
}

/// Ayarlar ekranındaki "İzin Ver" düğmesi: sistemin "batarya optimizasyonunu
/// yoksay" penceresini açar; açılamıyorsa uygulama ayarlarına yönlendirir.
Future<bool> requestBatteryExemptionInteractive() async {
  if (defaultTargetPlatform != TargetPlatform.android) return true;
  try {
    final status = await Permission.ignoreBatteryOptimizations.status;
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) {
      await openAppSettings();
      return false;
    }
    final r = await Permission.ignoreBatteryOptimizations.request();
    return r.isGranted;
  } catch (_) {
    return false;
  }
}


/// v5.1.1: Android 9 ve altında etiket dosyaya yazma / telefondan silme,
/// çalışma zamanında WRITE_EXTERNAL_STORAGE ister (manifest'te var ama hiç
/// istenmiyordu → API < 29 cihazlarda yazım sessizce başarısız oluyordu).
/// Android 10+ scoped storage kullanır; burada dokunmaz.
/// v5.1.3: "Tüm dosyalara erişim" verildi mi? (Android 10- her zaman true)
Future<bool> isAllFilesGranted() async {
  try {
    const ch = MethodChannel('cobble/native');
    return await ch.invokeMethod<bool>('isAllFilesGranted') ?? false;
  } catch (_) {
    return false;
  }
}

/// v5.1.3: yazma/adlandırma başarısınca "Tüm dosyalara erişim" önerisi.
/// İzin zaten AÇIKSA diyalog gösterilmez ve false döner — sorun izin
/// değildir; çağıran dürüst bir hata iletisi vermelidir.
Future<bool> showAllFilesHelpDialog(BuildContext context) async {
  if (await isAllFilesGranted()) return false;
  final granted = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: ThemeController.instance.paletteNotifier.value.card,
      title: const Text('Bir izin gerekiyor',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      content: const Text(
        'Dosyalara yazmak ve klasörleri yeniden adlandırmak için bir kereliğine '
        '"Tüm dosyalara erişim" izni vermen gerekiyor. Ayarlar açılacak; oradan '
        'izni aktif et.',
        style: TextStyle(color: Colors.white70, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'no'),
          child: const Text('Vazgeç', style: TextStyle(color: Colors.grey)),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, 'grant'),
          child: const Text('İzin Ver'),
        ),
      ],
    ),
  );
  if (granted == 'grant') {
    await requestAllFilesAccess();
    // Ayarlar açıldı; kullanıcı dönünce sonucu söyle.
    final opened = await waitForSettingsReturn();
    if (!context.mounted) return true;
    if (!opened) {
      showCobbleToast(
        context,
        'İzin sayfası açılamadı. Ayarlar → Uygulamalar → Cobblestone '
        '→ İzinler yolundan da açabilirsin.',
        icon: Icons.info_rounded,
      );
      return true;
    }
    final ok = await isAllFilesGranted();
    showCobbleToast(
      context,
      ok ? 'İzin verildi — şimdi tekrar dene.' : 'İzin hâlâ kapalı.',
      icon: ok ? Icons.check_circle_rounded : Icons.info_rounded,
    );
  }
  return true;
}

/// v5.1.3: ayarlar açıldıktan sonra uygulama ön plana dönene kadar bekler
/// (en çok 60 sn). Döndürür: ayar sayfası hiç açıldı mı?
Future<bool> waitForSettingsReturn() async {
  final done = Completer<void>();
  final obs = _ResumeObserver(() {
    if (!done.isCompleted) done.complete();
  });
  WidgetsBinding.instance.addObserver(obs);
  try {
    await done.future.timeout(const Duration(seconds: 60));
  } catch (_) {}
  WidgetsBinding.instance.removeObserver(obs);
  return obs.sawPause;
}

class _ResumeObserver with WidgetsBindingObserver {
  _ResumeObserver(this.onResume);
  final void Function() onResume;
  bool sawPause = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) sawPause = true;
    if (state == AppLifecycleState.resumed) onResume();
  }
}

/// v5.1.3: sistem ayarlarından "Tüm dosyalara erişim" sayfasını açar.
Future<void> requestAllFilesAccess() async {
  try {
    const ch = MethodChannel('cobble/native');
    await ch.invokeMethod('requestAllFilesAccess');
  } catch (_) {}
}

Future<bool> ensureLegacyStoragePermission() async {
  if (defaultTargetPlatform != TargetPlatform.android) return true;
  try {
    const ch = MethodChannel('cobble/native');
    final sdk = await ch.invokeMethod<int>('sdkInt') ?? 99;
    if (sdk >= 29) return true;
    if (!Platform.isAndroid) return true;
    final status = await Permission.storage.status;
    if (status.isGranted) return true;
    final r = await Permission.storage.request();
    return r.isGranted;
  } catch (_) {
    // Sürüm okunamadı: engellemeyelim, native taraf zaten deneyecek.
    return true;
  }
}
