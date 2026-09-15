class PlaylistItem {
  final String id;
  String name;
  List<String> songPaths;

  PlaylistItem({required this.id, required this.name, List<String>? songPaths})
    : songPaths = songPaths ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'songPaths': songPaths,
  };

  factory PlaylistItem.fromJson(Map<String, dynamic> json) {
    return PlaylistItem(
      id: json['id'] as String,
      name: json['name'] as String,
      songPaths: (json['songPaths'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
    );
  }
}

