import 'package:flutter/material.dart';
import '../app_info.dart';
import '../models/song_item.dart';
import '../theme/palette.dart';
import '../services/theme_controller.dart';
import '../services/notification_permission.dart';
import '../services/folder_watch.dart';
import '../services/song_storage.dart';
import '../widgets/cobble_logo.dart';
import '../widgets/cobble_toast.dart';
import '../widgets/tap_scale.dart';
import '../services/eq_controller.dart';
import '../services/fallback_art_controller.dart';
import '../services/library_controller.dart';

class SettingsScreen extends StatefulWidget {
  final CobblestonePalette palette;
  const SettingsScreen({super.key, required this.palette});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<bool> _statusFuture = _loadStatus();

  CobblestonePalette get p => widget.palette;

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sekmeye her dönüşte izin durumlarını taze oku.
    _reload();
  }

  void _reload() {
    final f = _loadStatus();
    if (mounted) {
      setState(() {
        _statusFuture = f;
      });
    } else {
      _statusFuture = f;
    }
  }

  static Future<bool> _loadStatus() async {
    return await isBatteryOptimizationIgnored();
  }

  Future<void> _askBattery() async {
    await requestBatteryExemptionInteractive();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final p = this.p;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Row(
          children: [
            CobbleLogo(size: 26),
            SizedBox(width: 10),
            Text('Ayarlar'),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          _section(p, Icons.palette_rounded, 'Görünüm',
            info: 'Tema, saate göre kendiliğinden değişir. Gece aurora ışıkları, gündüz duru su parıltısı kullanılır.'),
          _card(
            p,
            ValueListenableBuilder<Atmosfer>(
              valueListenable: ThemeController.instance.atmosferNotifier,
              builder: (context, sel, _) {
                const opts = [
                  (
                    Atmosfer.auto,
                    Icons.brightness_auto_rounded,
                    'Otomatik',
                    'Saate göre',
                  ),
                  (
                    Atmosfer.gece,
                    Icons.nightlight_round,
                    'Gece',
                    'Aurora',
                  ),
                  (
                    Atmosfer.gunduz,
                    Icons.wb_sunny_rounded,
                    'Gündüz',
                    'Duru Su',
                  ),
                ];
                return Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      for (final (v, icon, label, sub) in opts)
                        Expanded(
                          child: _OptionCard(
                            palette: p,
                            icon: icon,
                            label: label,
                            subtitle: sub,
                            selected: sel == v,
                            onTap: () =>
                                ThemeController.instance.setAtmosfer(v),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          _section(p, Icons.image_rounded, 'Kapak yoksa',
            info: 'Şarkının albüm kapağı yoksa listede, çalma ekranında ve bildirimde görünecek yedek görseli seçersin.'),
          _card(
            p,
            ValueListenableBuilder<FallbackArt>(
              valueListenable: FallbackArtController.instance.modeNotifier,
              builder: (context, mode, _) {
                const opts = [
                  (
                    FallbackArt.stone,
                    Icons.landscape_rounded,
                    'Taş resmi',
                    'Üç taş',
                  ),
                  (
                    FallbackArt.note,
                    Icons.music_note_rounded,
                    'Nota',
                    'Bildirimde net',
                  ),
                ];
                return Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      for (final (v, icon, label, sub) in opts)
                        Expanded(
                          child: _OptionCard(
                            palette: p,
                            icon: icon,
                            label: label,
                            subtitle: sub,
                            selected: mode == v,
                            onTap: () =>
                                FallbackArtController.instance.setMode(v),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          _section(p, Icons.graphic_eq_rounded, 'Ses',
            info: 'Arka plan koruması açıkken sistem, ekran kapalıyken bile çalmayı durdurmaz.'),
          _card(
            p,
            FutureBuilder<bool>(
              future: _statusFuture,
              builder: (context, snap) {
                final battery = snap.data ?? false;
                return ListTile(
                  leading: _badge(
                    p,
                    battery
                        ? Icons.battery_charging_full_rounded
                        : Icons.battery_alert_rounded,
                    battery ? p.orange : p.mute,
                  ),
                  title: const Text(
                    'Arka plan koruması',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    battery
                        ? 'Açık — sistem çalmayı durdurmaz'
                        : 'Kapalı — telefon birkaç şarkı sonra çalmayı kesebilir',
                    style: TextStyle(color: p.mute, fontSize: 12),
                  ),
                  trailing: battery
                      ? Icon(Icons.check_circle_rounded, color: p.orange)
                      : FilledButton(
                          onPressed: _askBattery,
                          style: FilledButton.styleFrom(
                            backgroundColor: p.orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            textStyle: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: const Text('İzin Ver'),
                        ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          _section(p, Icons.library_music_rounded, 'Kütüphane',
            info: 'İzlediğin klasörlerdeki müzik kütüphaneye alınır. Klasöre yeni şarkı atarsan uygulama açılışta ve öne geldiğinde otomatik tarar.'),
          _card(p, _libraryCard(p)),
          const SizedBox(height: 24),
          _section(p, Icons.folder_open_rounded, 'Klasör Seçici',
            info: 'Müzik eklerken hangi klasör seçicinin açılacağını '
                'seçersin. Cobblestone Seçici: klasörlerin içine girer, '
                'şarkıları kapaklarıyla görürsün; tek tek ya da klasör '
                "halinde seçersin. Sistemin kendi seçicisi: Android'in "
                'klasör seçme ekranı açılır.'),
          _card(p, _pickerCard(p)),
          const SizedBox(height: 24),
          _section(p, Icons.equalizer_rounded, 'Ekolayzır',
            info: '10 bant ekolayzır, bas ve genişlik ayarı — sesi dilediğin gibi şekillendirirsin. Hazır ayarlardan hızlıca seçebilirsin.'),
          _card(p, _eqCard(p)),
          const SizedBox(height: 24),
          _section(p, Icons.info_outline_rounded, 'Hakkında'),
          _card(p, _aboutCard(p)),
        ],
      ),
    );
  }

  Widget _section(
    CobblestonePalette p,
    IconData icon,
    String title, {
    String? info,
  }) {
    final row = Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: p.orange.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: p.orange, size: 15),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(
            color: Colors.white,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (info != null) ...[
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: p.card,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                title: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                content: Text(
                  info,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13.5,
                    height: 1.55,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Anladım',
                      style: TextStyle(
                        color: p.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            child: Icon(
              Icons.info_outline_rounded,
              color: p.mute,
              size: 15,
            ),
          ),
        ],
      ],
    );
    return row;
  }

  Widget _card(CobblestonePalette p, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.cardBorder),
        ),
        child: child,
      ),
    );
  }

  Widget _badge(CobblestonePalette p, IconData icon, Color color) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 19),
    );
  }

  Widget _libraryCard(CobblestonePalette p) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _badge(p, Icons.folder_rounded, p.orange),
              const SizedBox(width: 12),
              const Text(
                'İzlenen müzik klasörleri',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              ValueListenableBuilder<List<String>>(
                valueListenable: FolderWatch.instance.foldersNotifier,
                builder: (context, folders, _) => Text(
                  '${folders.length} klasör',
                  style: TextStyle(color: p.mute, fontSize: 11.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<List<String>>(
            valueListenable: FolderWatch.instance.foldersNotifier,
            builder: (context, folders, _) {
              if (folders.isEmpty) {
                return Text(
                  'Klasörler sekmesindeki + düğmesiyle müzik klasörü ekle.',
                  style: TextStyle(color: p.mute, fontSize: 12.5, height: 1.4),
                );
              }
              return ValueListenableBuilder<List<SongItem>>(
                valueListenable: LibraryController.instance.songsNotifier,
                builder: (context, allSongs, _) => Column(
                  children: [
                    for (final f in folders)
                      _watchedFolderRow(p, f, allSongs),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          Divider(color: p.cardBorder, height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              TapScale(
                child: FilledButton.icon(
                onPressed: () => FolderWatch.instance.manualScan(context, p),
                style: FilledButton.styleFrom(
                  backgroundColor: p.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: const Text('Tümünü Tara'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => FolderWatch.pickAndScan(context, p),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: p.orange),
                  foregroundColor: p.orange,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                icon: const Icon(Icons.add_rounded, size: 17),
                label: const Text('Klasör Ekle'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// v5.1.3: klasör seçici tercihi — iki şık seçenek kartı.
  /// v5.1.3: izlenen klasör kartı — ad, şarkı sayısı, tara, kaldır.
  Widget _watchedFolderRow(
    CobblestonePalette p,
    String dir,
    List<SongItem> allSongs,
  ) {
    final name = dir.split('/').where((s) => s.isNotEmpty).last;
    final count = allSongs
        .where(
          (s) =>
              s.appPath.startsWith('$dir/') ||
              (s.originalPath ?? '').startsWith('$dir/'),
        )
        .length;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: p.bg2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.cardBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              leading: Icon(Icons.folder_rounded, color: p.orange, size: 22),
              title: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              subtitle: Text(
                count == 0
                    ? 'şarkı yok — dokun ve tara'
                    : count == 1
                        ? '1 şarkı'
                        : '$count şarkı',
                style: TextStyle(color: p.mute, fontSize: 11),
              ),
              onTap: () => FolderWatch.instance.scanOne(context, p, dir),
            ),
          ),
          IconButton(
            tooltip: 'Yeniden tara',
            icon: Icon(Icons.sync_rounded, color: p.mute, size: 18),
            onPressed: () => FolderWatch.instance.scanOne(context, p, dir),
          ),
          IconButton(
            tooltip: 'Uygulamadan kaldır',
            icon: Icon(
              Icons.delete_outline_rounded,
              color: Colors.redAccent,
              size: 19,
            ),
            onPressed: () => _removeWatchedFolder(p, dir, name),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  /// v5.1.3: klasörü UYGULAMADAN kaldır — izleme biter, şarkılar
  /// kütüphaneden çıkar; telefondaki dosyalar yerinde kalır.
  Future<void> _removeWatchedFolder(
    CobblestonePalette p,
    String dir,
    String name,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.card,
        title: Text(
          '"$name" kaldırılsın mı?',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Klasör izlemeden çıkar ve içindeki şarkıları uygulamadan '
          'kaldırır. Telefondaki dosyalar yerinde kalır.',
          style: const TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Kaldır',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final songs = LibraryController.instance.songsNotifier.value
        .where(
          (s) =>
              s.appPath.startsWith('$dir/') ||
              (s.originalPath ?? '').startsWith('$dir/'),
        )
        .toList();
    for (final s in songs) {
      await SongStorage.deleteFromAppOnly(s);
    }
    await FolderWatch.instance.unwatch(dir);
    await LibraryController.instance.refreshSongs();
    await LibraryController.instance.refreshPlaylists();
    if (mounted) {
      showCobbleToast(
        context,
        '"$name" uygulamadan kaldırıldı.',
        icon: Icons.folder_off_rounded,
      );
    }
  }

  Widget _pickerCard(CobblestonePalette p) {
    return ValueListenableBuilder<bool>(
      valueListenable: FolderWatch.instance.useSystemPicker,
      builder: (context, sys, _) => Column(
        children: [
          ListTile(
            leading: _badge(
              p,
              Icons.folder_open_rounded,
              sys ? p.mute : p.orange,
            ),
            title: const Text(
              'Cobblestone Seçici',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              'Klasörlere gir, şarkıları görerek seç',
              style: TextStyle(color: p.mute, fontSize: 12),
            ),
            trailing: sys
                ? null
                : Icon(Icons.check_circle_rounded, color: p.orange),
            onTap: () => FolderWatch.instance.setSystemPicker(false),
          ),
          Divider(color: p.cardBorder, height: 1, indent: 56),
          ListTile(
            leading: _badge(
              p,
              Icons.phone_android_rounded,
              sys ? p.orange : p.mute,
            ),
            title: const Text(
              'Sistemin kendi seçicisi',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              "Android'in klasör seçme ekranı açılır",
              style: TextStyle(color: p.mute, fontSize: 12),
            ),
            trailing: sys
                ? Icon(Icons.check_circle_rounded, color: p.orange)
                : null,
            onTap: () => FolderWatch.instance.setSystemPicker(true),
          ),
        ],
      ),
    );
  }

  Widget _eqCard(CobblestonePalette p) {
    return ValueListenableBuilder<bool>(
      valueListenable: EqController.instance.supportedNotifier,
      builder: (context, supported, _) {
        if (!supported) {
          return ListTile(
            leading: _badge(p, Icons.graphic_eq_rounded, p.mute),
            title: const Text(
              'Ekolayzer',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              'Ekolayzır açılıyor… Şarkı çalmaya başlayınca hazır olur.',
              style: TextStyle(color: p.mute, fontSize: 12),
            ),
            trailing: TextButton(
              onPressed: () => EqController.instance.probe(),
              child: Text(
                'Tekrar Dene',
                style: TextStyle(
                  color: p.orange,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }
        return Column(
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: EqController.instance.enabledNotifier,
              builder: (context, enabled, _) {
                return SwitchListTile(
                  activeThumbColor: p.orange,
                  value: enabled,
                  onChanged: (v) => EqController.instance.setEnabled(v),
                  secondary: _badge(
                    p,
                    Icons.graphic_eq_rounded,
                    enabled ? p.orange : p.mute,
                  ),
                  title: const Text(
                    'Ekolayzer',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    enabled
                        ? 'Açık — 10 bant ekolayzır, bas ve genişlik'
                        : 'Kapalı — ses dokunulmadan geçiyor',
                    style: TextStyle(color: p.mute, fontSize: 12),
                  ),
                );
              },
            ),
            ValueListenableBuilder<bool>(
              valueListenable: EqController.instance.enabledNotifier,
              builder: (context, enabled, _) {
                if (!enabled) return const SizedBox.shrink();
                return Column(
                  children: [
                    Divider(color: p.cardBorder, height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final name in EqController.presets.keys)
                            ActionChip(
                              label: Text(
                                name,
                                style: const TextStyle(fontSize: 12),
                              ),
                              backgroundColor: p.bg2,
                              side: BorderSide(color: p.cardBorder),
                              labelStyle: TextStyle(color: p.orangeLight),
                              onPressed: () => EqController.instance
                                  .applyPreset(name),
                            ),
                        ],
                      ),
                    ),
                    _BandSliders(palette: p),
                    if (EqController.instance.bassSupported)
                      _BassSlider(palette: p),
                    if (EqController.instance.virtSupported)
                      _VirtSlider(palette: p),
                    const SizedBox(height: 12),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _aboutCard(CobblestonePalette p) {
    return Column(
      children: [
        Material(
          type: MaterialType.transparency,
          child: ListTile(
            leading: _badge(p, Icons.headphones_rounded, p.orange),
            title: const Text(
              'Cobblestone Hakkında',
              style: TextStyle(color: Colors.white),
            ),
            trailing: Icon(Icons.chevron_right_rounded, color: p.mute),
            onTap: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: p.card,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                title: Row(
                  children: [
                    Icon(Icons.headphones_rounded, color: p.orange, size: 28),
                    const SizedBox(width: 10),
                    const Text(
                      'Cobblestone',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cobblestone telefonundaki müziği hiçbir gürültü olmadan dinlemen için var. '
                      'İnternet yok, hesap oluşturmak yok, reklam yok. Sadece sen ve müziğin.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Divider(color: p.cardBorder),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.code_rounded, color: p.orange, size: 18),
                        const SizedBox(width: 8),
                        Text('Geliştirici',
                            style: TextStyle(color: p.mute, fontSize: 13)),
                        const Spacer(),
                        const Text(
                          'C-Stone Labs',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.new_releases_outlined,
                            color: p.orange, size: 18),
                        const SizedBox(width: 8),
                        Text('Versiyon',
                            style: TextStyle(color: p.mute, fontSize: 13)),
                        const Spacer(),
                        const Text(
                          kAppVersion,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Kapat',
                      style: TextStyle(
                        color: p.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Divider(color: p.cardBorder, height: 1),
        Material(
          type: MaterialType.transparency,
          child: ListTile(
            leading: _badge(p, Icons.privacy_tip_outlined, p.orange),
            title: const Text(
              'Gizlilik',
              style: TextStyle(color: Colors.white),
            ),
            trailing: Icon(Icons.chevron_right_rounded, color: p.mute),
            onTap: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: p.card,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                title: const Text(
                  'Gizlilik',
                  style: TextStyle(color: Colors.white),
                ),
                content: const Text(
                  'Cobblestone internete bağlanmaz, hesap istemez ve reklam göstermez.\n\n'
                  'Müzik dosyaların yalnızca bu cihazda, senin seçtiğin klasörden okunur. '
                  'Dinleme istatistikleri de yalnızca telefonda saklanır.\n\n'
                  'Hiçbir veri dışarı gönderilmez.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.55,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Kapat',
                      style: TextStyle(
                        color: p.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Divider(color: p.cardBorder, height: 1),
        Material(
          type: MaterialType.transparency,
          child: ListTile(
            leading: _badge(p, Icons.tag_rounded, p.mute),
            title: const Text(
              'Versiyon',
              style: TextStyle(color: Colors.white),
            ),
            trailing: Text(
              kAppVersion,
              style: TextStyle(color: p.mute, fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }
}

/// Seçilebilir seçenek kartı (tema / yedek görsel).
class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.palette,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final CobblestonePalette palette;
  final IconData icon;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? p.orange.withValues(alpha: 0.12) : p.bg2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? p.orange : p.cardBorder,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: selected
                    ? p.orange.withValues(alpha: 0.18)
                    : p.card,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: selected ? p.orange : p.mute, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.mute, fontSize: 10.5),
            ),
            if (selected) ...[
              const SizedBox(height: 6),
              Icon(Icons.check_circle_rounded, color: p.orange, size: 14),
            ],
          ],
        ),
      ),
    );
  }
}

/// Bant kaydırıcıları: cihazın bant sayısına göre dikey mini sliderlar.
class _BandSliders extends StatelessWidget {
  final CobblestonePalette palette;
  const _BandSliders({required this.palette});

  String _freqLabel(int hz) {
    if (hz >= 1000) {
      final k = hz / 1000;
      return '${k == k.roundToDouble() ? k.toInt() : k.toStringAsFixed(1)}K';
    }
    return '$hz';
  }

  @override
  Widget build(BuildContext context) {
    final eq = EqController.instance;
    return ValueListenableBuilder<List<int>>(
      valueListenable: eq.levelsNotifier,
      builder: (context, levels, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (var b = 0; b < levels.length; b++)
                SizedBox(
                  width: 40,
                  height: 160,
                  child: Column(
                    children: [
                      Text(
                        '${(levels[b] / 100).toStringAsFixed(0)} dB',
                        style: TextStyle(color: palette.mute, fontSize: 9.5),
                      ),
                      Expanded(
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 5.5,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 12,
                              ),
                            ),
                            child: Slider(
                              value: levels[b].toDouble().clamp(
                                eq.minLevel.toDouble(),
                                eq.maxLevel.toDouble(),
                              ),
                              min: eq.minLevel.toDouble(),
                              max: eq.maxLevel.toDouble(),
                              activeColor: palette.orange,
                              inactiveColor: palette.mute.withValues(alpha: 0.25),
                              onChanged: (v) =>
                                  EqController.instance.setBand(b, v.round()),
                            ),
                          ),
                        ),
                      ),
                      Text(
                        b < eq.freqs.length
                            ? _freqLabel(eq.freqs[b])
                            : '${b + 1}',
                        style: TextStyle(
                          color: palette.mute,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            ),
          ),
        );
      },
    );
  }
}

/// Bas güçlendirici kaydırıcısı.
class _BassSlider extends StatelessWidget {
  final CobblestonePalette palette;
  const _BassSlider({required this.palette});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: EqController.instance.bassNotifier,
      builder: (context, bass, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(
                Icons.speaker_rounded,
                color: bass > 0 ? palette.orange : palette.mute,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Bas',
                style: TextStyle(
                  color: palette.orangeLight,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 13,
                    ),
                  ),
                  child: Slider(
                    value: bass.toDouble(),
                    min: 0,
                    max: 1000,
                    activeColor: palette.orange,
                    inactiveColor: palette.mute.withValues(alpha: 0.25),
                    onChanged: (v) => EqController.instance.setBass(v.round()),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Sanallaştırıcı kaydırıcısı (bas'ın yanında).
class _VirtSlider extends StatelessWidget {
  final CobblestonePalette palette;
  const _VirtSlider({required this.palette});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: EqController.instance.virtNotifier,
      builder: (context, virt, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(
                Icons.surround_sound_rounded,
                color: virt > 0 ? palette.orange : palette.mute,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Sanallaştır',
                style: TextStyle(
                  color: palette.orangeLight,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 13,
                    ),
                  ),
                  child: Slider(
                    value: virt.toDouble(),
                    min: 0,
                    max: 1000,
                    activeColor: palette.orange,
                    inactiveColor: palette.mute.withValues(alpha: 0.25),
                    onChanged: (v) =>
                        EqController.instance.setVirtualizer(v.round()),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
