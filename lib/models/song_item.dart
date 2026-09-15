class SongItem {
  final String title;
  final String appPath;
  final String? originalPath;
  final String? artist;
  final String? album;
  final int size;
  final bool metaEdited;
  final int addedMs;

  SongItem({
    required this.title,
    required this.appPath,
    required this.size,
    this.originalPath,
    this.artist,
    this.album,
    this.metaEdited = false,
    this.addedMs = 0,
  });

  /// Aynı dosyayı (kopya ya da orijinal) ikinci kez eklememek için.
  String get dedupeKey {
    final orig = originalPath;
    if (orig != null && orig.isNotEmpty) return orig;
    return appPath;
  }

  String get displayArtist {
    final a = artist?.trim();
    if (a == null || a.isEmpty) return '';
    return a;
  }

  String get displayAlbum {
    final a = album?.trim();
    if (a == null || a.isEmpty) return '';
    return a;
  }

  SongItem copyWith({
    String? title,
    String? appPath,
    String? originalPath,
    String? artist,
    String? album,
    int? size,
    bool? metaEdited,
    int? addedMs,
  }) {
    return SongItem(
      title: title ?? this.title,
      appPath: appPath ?? this.appPath,
      originalPath: originalPath ?? this.originalPath,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      size: size ?? this.size,
      metaEdited: metaEdited ?? this.metaEdited,
      addedMs: addedMs ?? this.addedMs,
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'appPath': appPath,
    'originalPath': originalPath,
    'artist': artist,
    'album': album,
    'size': size,
    'metaEdited': metaEdited,
  };

  factory SongItem.fromJson(Map<String, dynamic> json) {
    return SongItem(
      title: json['title'] as String,
      appPath: json['appPath'] as String,
      originalPath: json['originalPath'] as String?,
      artist: json['artist'] as String?,
      album: json['album'] as String?,
      size: json['size'] as int? ?? 0,
      metaEdited: json['metaEdited'] as bool? ?? false,
    );
  }
}
