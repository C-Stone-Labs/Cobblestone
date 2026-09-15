import 'package:flutter/material.dart';
import '../theme/palette.dart';
import '../widgets/ambient_layer.dart';
import '../widgets/artwork.dart';
import '../widgets/tap_scale.dart';
import '../models/song_item.dart';
import '../models/playlist_item.dart';
import '../services/library_controller.dart';
import '../services/playlist_storage.dart';
import '../widgets/song_search_field.dart';

/// v5.1.3: listeye şarkı ekle/çıkar — klasör seçiciyle aynı dil:
/// satıra dokun = işaretle, alçalan "Kaydet" düğmesi sayıyı söyler.
class AddSongsToPlaylistScreen extends StatefulWidget {
  final PlaylistItem playlist;
  final CobblestonePalette palette;
  const AddSongsToPlaylistScreen({
    super.key,
    required this.playlist,
    required this.palette,
  });

  @override
  State<AddSongsToPlaylistScreen> createState() =>
      _AddSongsToPlaylistScreenState();
}

class _AddSongsToPlaylistScreenState extends State<AddSongsToPlaylistScreen> {
  CobblestonePalette get _p => widget.palette;
  late Set<String> _selected;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.playlist.songPaths);
  }

  Future<void> _save() async {
    final all = List<PlaylistItem>.from(
      LibraryController.instance.playlistsNotifier.value,
    );
    final idx = all.indexWhere((p) => p.id == widget.playlist.id);
    if (idx != -1) {
      all[idx].songPaths = _selected.toList();
    }
    await PlaylistStorage.savePlaylists(all);
    await LibraryController.instance.refreshPlaylists();
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<SongItem>>(
      valueListenable: LibraryController.instance.songsNotifier,
      builder: (context, allSongs, _) {
        final filtered = _query.isEmpty
            ? allSongs
            : allSongs
                  .where(
                    (s) => s.title.toLowerCase().contains(_query.toLowerCase()),
                  )
                  .toList();

        return Scaffold(
          // v5.1.3: kendi temalı zemini + atmosfer — alttaki rota
          // çizilmez; saydamda siyah görünüyordu.
          backgroundColor: _p.bg,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.playlist.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Şarkı ekle / çıkar',
                  style: TextStyle(fontSize: 11, color: _p.mute),
                ),
              ],
            ),
          ),
          body: AmbientLayer(
            palette: _p,
            child: Column(
              children: [
                SongSearchField(
                  palette: _p,
                  onChanged: (v) => setState(() => _query = v),
                ),
                Expanded(
                  child: allSongs.isEmpty
                      ? Center(
                          child: Text(
                            'Önce "Şarkılar" sekmesinden müzik ekle',
                            style: TextStyle(color: _p.mute),
                          ),
                        )
                      : filtered.isEmpty
                      ? Center(
                          child: Text(
                            'Sonuç bulunamadı',
                            style: TextStyle(color: _p.mute),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(top: 8, bottom: 16),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final song = filtered[index];
                            final isSelected = _selected.contains(
                              song.appPath,
                            );
                            final artist = song.displayArtist.isEmpty
                                ? 'Bilinmeyen sanatçı'
                                : song.displayArtist;
                            return Container(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? _p.orange.withValues(alpha: 0.22)
                                    : _p.card,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isSelected
                                      ? _p.orange
                                      : _p.cardBorder,
                                  width: isSelected ? 1.2 : 1,
                                ),
                              ),
                              child: Material(
                                type: MaterialType.transparency,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () => setState(() {
                                    if (isSelected) {
                                      _selected.remove(song.appPath);
                                    } else {
                                      _selected.add(song.appPath);
                                    }
                                  }),
                                  child: SizedBox(
                                    height: 68,
                                    child: Row(
                                      children: [
                                        const SizedBox(width: 12),
                                        SongArtwork(
                                          palette: _p,
                                          size: 44,
                                          appPath: song.appPath,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                song.title,
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 14,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                artist,
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: _p.mute,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          width: 44,
                                          height: 44,
                                          alignment: Alignment.center,
                                          child: AnimatedContainer(
                                            duration: const Duration(
                                              milliseconds: 150,
                                            ),
                                            width: 24,
                                            height: 24,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: isSelected
                                                  ? _p.orange
                                                  : Colors.transparent,
                                              border: Border.all(
                                                color: isSelected
                                                    ? _p.orange
                                                    : _p.mute,
                                                width: 2,
                                              ),
                                            ),
                                            child: isSelected
                                                ? const Icon(
                                                    Icons.check_rounded,
                                                    size: 16,
                                                    color: Colors.white,
                                                  )
                                                : null,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
          ),
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_selected.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _selected.length == 1
                            ? '1 şarkı seçili'
                            : '${_selected.length} şarkı seçili',
                        style: TextStyle(color: _p.mute, fontSize: 12),
                      ),
                    ),
                  TapScale(
                    child: FilledButton(
                      onPressed: _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: _p.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      child: const Text('Kaydet'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
