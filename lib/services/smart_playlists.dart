import 'package:flutter/material.dart';

import '../models/song_item.dart';
import 'stats_service.dart';

class SmartPlaylist {
  final String id;
  final String name;
  final String subtitle;
  final String emptyHint;
  final IconData icon;
  final List<SongItem> songs;
  const SmartPlaylist({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.emptyHint,
    required this.icon,
    required this.songs,
  });
}

class SmartPlaylists {
  static const mostId = '__smart_most__';
  static const leastId = '__smart_least__';
  static const neverId = '__smart_never__';

  static List<SmartPlaylist> all(List<SongItem> library) {
    final byPath = {for (final s in library) s.appPath: s};
    List<SongItem> resolve(List<String> paths) => [
          for (final p in paths)
            if (byPath[p] != null) byPath[p]!,
        ];

    final ready = StatsService.instance.hasSmartSnapshot;
    final range = StatsService.instance.frozen?.rangeLabel;
    final sub = ready && range != null
        ? 'Rapor · $range'
        : 'Son haftalık rapora göre';
    return [
      SmartPlaylist(
        id: mostId,
        name: 'En çok dinlenenler',
        subtitle: sub,
        emptyHint: ready
            ? 'Geçen haftanın raporunda çok dinlenen parça yok.'
            : 'Pazartesi raporu kilitlenince dolar.',
        icon: Icons.local_fire_department_rounded,
        songs: ready ? resolve(StatsService.instance.smartMost) : const [],
      ),
      SmartPlaylist(
        id: leastId,
        name: 'Az dinlenenler',
        subtitle: sub,
        emptyHint: ready
            ? 'Geçen haftanın raporunda az dinlenen parça yok.'
            : 'Pazartesi raporu kilitlenince dolar.',
        icon: Icons.hourglass_bottom_rounded,
        songs: ready ? resolve(StatsService.instance.smartLeast) : const [],
      ),
      SmartPlaylist(
        id: neverId,
        name: 'Hiç dinlenmeyenler',
        subtitle: sub,
        emptyHint: ready
            ? 'Geçen hafta dinlenmemiş parça kalmamış.'
            : 'Pazartesi raporu kilitlenince dolar.',
        icon: Icons.music_off_rounded,
        songs: ready ? resolve(StatsService.instance.smartNever) : const [],
      ),
    ];
  }
}
