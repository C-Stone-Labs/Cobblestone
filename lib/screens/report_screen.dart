import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/song_item.dart';
import '../services/library_controller.dart';
import '../services/player_controller.dart';
import '../services/stats_service.dart';
import '../theme/palette.dart';
import '../widgets/ambient_layer.dart';
import '../widgets/mini_player.dart';

class ReportScreen extends StatefulWidget {
  final CobblestonePalette palette;
  const ReportScreen({super.key, required this.palette});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  CobblestonePalette get p => widget.palette;

  @override
  void initState() {
    super.initState();
    unawaited(() async {
      await StatsService.instance.ensureSmartSnapshot(
        LibraryController.instance.songsNotifier.value,
      );
      await StatsService.instance.markReportSeen();
      if (mounted) setState(() {});
    }());
  }

  String _hm(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '$h sa $m dk';
    return '$m dk';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Rapor'),
      ),
      body: AmbientLayer(
        palette: p,
        child: ValueListenableBuilder<int>(
        valueListenable: StatsService.instance.smartVersion,
        builder: (context, _, _) {
          return ValueListenableBuilder<int>(
            valueListenable: StatsService.instance.version,
            builder: (context, _, _) {
              final r = StatsService.instance.frozen;
              if (r == null) {
                return Center(
                  child: Text(
                    'Rapor hazırlanıyor…',
                    style: TextStyle(color: p.mute),
                  ),
                );
              }
              return _body(r);
            },
          );
        },
      ),
      ),
    );
  }

  Widget _body(FrozenReport r) {
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, overlayListBottom(context)),
      children: [
        if (!r.hasAny) ...[
          Container(
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: p.cardBorder),
            ),
            padding: const EdgeInsets.all(16),
            child: Text(
              'Rapor, geçen Pazartesi–Pazar dinlemeni özetler. '
              'Yeni kurulumda henüz kilitlenecek bir hafta yok; '
              'gelecek Pazartesi dolmaya başlar.',
              style: TextStyle(color: p.mute, fontSize: 13.5, height: 1.5),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Container(
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: p.cardBorder),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Geçen Hafta',
                style: TextStyle(
                  color: p.mute,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                r.rangeLabel,
                style: TextStyle(
                  color: p.orangeLight,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _statPill('Çalma', '${r.plays}'),
                  const SizedBox(width: 10),
                  _statPill('Süre', _hm(r.seconds)),
                  const SizedBox(width: 10),
                  _statPill('Parça', '${r.uniqueSongs}'),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 110,
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _WeekBarsPainter(data: r.bars, palette: p),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        _sectionTitle('En Çok Dinlenenler'),
        const SizedBox(height: 8),
        _trackBlock(
          r.most,
          empty: 'Geçen hafta çok dinlenen parça yok.',
          showPlays: true,
          bars: true,
        ),
        const SizedBox(height: 28),
        _sectionTitle('Az Dinlenenler'),
        const SizedBox(height: 8),
        _trackBlock(
          r.least,
          empty: 'Geçen hafta az dinlenen parça yok.',
          showPlays: true,
        ),
        const SizedBox(height: 28),
        _sectionTitle('Hiç Dinlenmeyenler'),
        const SizedBox(height: 8),
        _trackBlock(
          r.never,
          empty: 'Geçen hafta dinlenmemiş parça kalmamış.',
          showPlays: false,
        ),
      ],
    );
  }

  Widget _sectionTitle(String t) {
    return Text(
      t,
      style: TextStyle(
        color: p.mute,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
      ),
    );
  }

  Widget _trackBlock(
    List<ReportTrack> tracks, {
    required String empty,
    required bool showPlays,
    bool bars = false,
  }) {
    if (tracks.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.cardBorder),
        ),
        child: Text(
          empty,
          style: TextStyle(color: p.mute, fontSize: 13, height: 1.5),
          textAlign: TextAlign.center,
        ),
      );
    }
    final maxPlays = tracks.fold<int>(0, (a, t) => math.max(a, t.plays));
    return Container(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.cardBorder),
      ),
      child: Column(
        children: [
          for (var i = 0; i < tracks.length; i++) ...[
            if (i > 0) Divider(color: p.cardBorder, height: 1),
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () => _playTracks(tracks, i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 24,
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(
                                color: i == 0 ? p.orange : p.mute,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              tracks[i].title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (showPlays)
                            Text(
                              '${tracks[i].plays}×',
                              style: TextStyle(
                                color: p.orangeLight,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                      if (bars && maxPlays > 0) ...[
                        const SizedBox(height: 6),
                        LayoutBuilder(
                          builder: (context, c) {
                            final frac = tracks[i].plays / maxPlays;
                            return Stack(
                              children: [
                                Container(
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: p.cardBorder.withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                                FractionallySizedBox(
                                  widthFactor: frac.clamp(0.02, 1.0),
                                  child: Container(
                                    height: 5,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(3),
                                      gradient: LinearGradient(
                                        colors: i == 0
                                            ? [p.orange, p.orangeLight]
                                            : [
                                                p.orange.withValues(alpha: 0.55),
                                                p.orangeLight.withValues(
                                                  alpha: 0.55,
                                                ),
                                              ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _playTracks(List<ReportTrack> tracks, int index) {
    final lib = LibraryController.instance.songsNotifier.value;
    final by = {for (final s in lib) s.appPath: s};
    final songs = <SongItem>[
      for (final t in tracks)
        if (by[t.path] != null) by[t.path]!,
    ];
    if (songs.isEmpty) return;
    var start = 0;
    if (index >= 0 && index < tracks.length) {
      final i = songs.indexWhere((s) => s.appPath == tracks[index].path);
      if (i >= 0) start = i;
    }
    playFromQueue(
      songs,
      start,
      origin: const PlaybackOrigin(id: '__report__', label: 'Rapor'),
    );
  }

  Widget _statPill(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: p.bg2.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.cardBorder),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                color: p.orangeLight,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: p.mute, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _WeekBarsPainter extends CustomPainter {
  _WeekBarsPainter({required this.data, required this.palette});

  final List<MapEntry<String, int>> data;
  final CobblestonePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final maxSec = data.fold<int>(0, (a, e) => math.max(a, e.value));
    final n = data.length;
    final slot = size.width / n;
    final barW = slot * 0.52;
    final baseY = size.height - 16;
    final maxH = size.height - 34;

    for (var i = 0; i < n; i++) {
      final secs = data[i].value;
      final frac = maxSec <= 0 ? 0.0 : secs / maxSec;
      final h = secs <= 0 ? 3.0 : math.max(6.0, maxH * frac);
      final centerX = slot * i + slot / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(centerX - barW / 2, baseY - h, barW, h),
        const Radius.circular(5),
      );
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: secs > 0
              ? [
                  palette.orange.withValues(alpha: 0.85),
                  palette.orange.withValues(alpha: 0.45),
                ]
              : [
                  palette.cardBorder.withValues(alpha: 0.6),
                  palette.cardBorder.withValues(alpha: 0.6),
                ],
        ).createShader(rect.outerRect);
      canvas.drawRRect(rect, paint);

      final tp = TextPainter(
        text: TextSpan(
          text: data[i].key,
          style: TextStyle(
            color: palette.mute,
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(centerX - tp.width / 2, size.height - 13));
    }
  }

  @override
  bool shouldRepaint(_WeekBarsPainter old) =>
      old.data != data || old.palette != palette;
}
