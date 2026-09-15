package com.cobblestone.cobblestone

import android.content.Context
import android.os.Bundle
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.util.UnstableApi
import java.io.File

/**
 * Android Auto / MediaBrowser ağacı — Samsung Music düzenine yakın:
 * Şarkılar, Albümler, Sanatçılar, Klasörler, Listeler, Favoriler, Akıllı.
 */
@OptIn(UnstableApi::class)
object BrowseTree {
    const val ROOT = "cobble:root"
    const val SONGS = "cobble:songs"
    const val ALBUMS = "cobble:albums"
    const val ARTISTS = "cobble:artists"
    const val FOLDERS = "cobble:folders"
    const val PLAYLISTS = "cobble:playlists"
    const val FAVORITES = "cobble:favorites"
    const val SMART = "cobble:smart"
    const val SMART_MOST = "cobble:smart:most"
    const val SMART_LEAST = "cobble:smart:least"
    const val SMART_NEVER = "cobble:smart:never"
    const val RECENT = "cobble:recent"

    /** Auto bir şarkıya basınca kardeş kuyruğu için son tarama ebeveyni. */
    @Volatile
    var lastBrowseParent: String = SONGS

    private const val ALBUM_P = "cobble:album:"
    private const val ARTIST_P = "cobble:artist:"
    private const val FOLDER_P = "cobble:folder:"
    private const val PLAYLIST_P = "cobble:playlist:"

    fun isBrowsableId(id: String): Boolean =
        id == ROOT || id == SONGS || id == ALBUMS || id == ARTISTS ||
            id == FOLDERS || id == PLAYLISTS || id == FAVORITES ||
            id == SMART || id == SMART_MOST ||
            id == SMART_LEAST || id == SMART_NEVER ||
            id == RECENT ||
            id.startsWith(ALBUM_P) || id.startsWith(ARTIST_P) ||
            id.startsWith(FOLDER_P) || id.startsWith(PLAYLIST_P)

    fun rootItem(ctx: Context): MediaItem =
        folderItem(ROOT, "Cobblestone", MediaMetadata.MEDIA_TYPE_FOLDER_MIXED, ctx)

    fun children(ctx: Context, parentId: String): List<MediaItem> {
        if (parentId != ROOT) lastBrowseParent = parentId
        val songs = LibraryStore.songs(ctx)
        return when (parentId) {
            ROOT -> listOf(
                folderItem(SONGS, "Şarkılar", MediaMetadata.MEDIA_TYPE_FOLDER_MIXED, ctx, songs.size, playable = true, grid = false),
                folderItem(ALBUMS, "Albümler", MediaMetadata.MEDIA_TYPE_FOLDER_ALBUMS, ctx, LibraryStore.groupedAlbums(songs).size, grid = true),
                folderItem(ARTISTS, "Sanatçılar", MediaMetadata.MEDIA_TYPE_FOLDER_ARTISTS, ctx, LibraryStore.groupedArtists(songs).size, grid = true),
                folderItem(PLAYLISTS, "Listeler", MediaMetadata.MEDIA_TYPE_FOLDER_PLAYLISTS, ctx, grid = true),
                folderItem(FAVORITES, "Favoriler", MediaMetadata.MEDIA_TYPE_PLAYLIST, ctx, FavoritesStore.get(ctx).size, playable = true, grid = false),
                folderItem(FOLDERS, "Klasörler", MediaMetadata.MEDIA_TYPE_FOLDER_MIXED, ctx, LibraryStore.groupedFolders(songs).size, grid = true),
                folderItem(SMART, "Akıllı listeler", MediaMetadata.MEDIA_TYPE_FOLDER_PLAYLISTS, ctx, grid = true)
            )
            RECENT -> recentSongs(ctx)
            SONGS -> songs.sortedWith { a, b -> LibraryStore.compareTitle(a.title, b.title) }
                .map { songItem(ctx, it) }
            ALBUMS -> LibraryStore.groupedAlbums(songs).entries
                .sortedWith { a, b -> LibraryStore.compareTitle(a.key, b.key) }
                .map { folderItem(ALBUM_P + it.key, it.key, MediaMetadata.MEDIA_TYPE_ALBUM, ctx, it.value.size, playable = true) }
            ARTISTS -> LibraryStore.groupedArtists(songs).entries
                .sortedWith { a, b -> LibraryStore.compareTitle(a.key, b.key) }
                .map { folderItem(ARTIST_P + it.key, it.key, MediaMetadata.MEDIA_TYPE_ARTIST, ctx, it.value.size, playable = true) }
            FOLDERS -> LibraryStore.groupedFolders(songs).entries
                .sortedWith { a, b -> LibraryStore.compareTitle(File(a.key).name, File(b.key).name) }
                .map {
                    val name = File(it.key).name.ifBlank { it.key }
                    folderItem(FOLDER_P + it.key, name, MediaMetadata.MEDIA_TYPE_FOLDER_MIXED, ctx, it.value.size, playable = true)
                }
            PLAYLISTS -> LibraryStore.playlists(ctx)
                .filter { it.id != "__favorites__" }
                .map { folderItem(PLAYLIST_P + it.id, it.name, MediaMetadata.MEDIA_TYPE_PLAYLIST, ctx, it.paths.size, playable = true) }
            FAVORITES -> songsForPaths(ctx, songs, FavoritesStore.get(ctx).toList())
            SMART -> listOf(
                folderItem(SMART_MOST, "En çok dinlenenler", MediaMetadata.MEDIA_TYPE_PLAYLIST, ctx, playable = true),
                folderItem(SMART_LEAST, "Az dinlenenler", MediaMetadata.MEDIA_TYPE_PLAYLIST, ctx, playable = true),
                folderItem(SMART_NEVER, "Hiç dinlenmeyenler", MediaMetadata.MEDIA_TYPE_PLAYLIST, ctx, playable = true)
            )
            SMART_MOST -> snapshotSongs(ctx, songs, "most").map { songItem(ctx, it) }
            SMART_LEAST -> snapshotSongs(ctx, songs, "least").map { songItem(ctx, it) }
            SMART_NEVER -> snapshotSongs(ctx, songs, "never").map { songItem(ctx, it) }
            else -> when {
                parentId.startsWith(ALBUM_P) -> {
                    val name = parentId.removePrefix(ALBUM_P)
                    songs.filter { it.album.ifBlank { "Bilinmeyen albüm" } == name }
                        .sortedWith { a, b -> LibraryStore.compareTitle(a.title, b.title) }
                        .map { songItem(ctx, it) }
                }
                parentId.startsWith(ARTIST_P) -> {
                    val name = parentId.removePrefix(ARTIST_P)
                    songs.filter { it.artist.ifBlank { "Bilinmeyen sanatçı" } == name }
                        .sortedWith { a, b -> LibraryStore.compareTitle(a.title, b.title) }
                        .map { songItem(ctx, it) }
                }
                parentId.startsWith(FOLDER_P) -> {
                    val folder = parentId.removePrefix(FOLDER_P)
                    songs.filter { (File(it.path).parent ?: "/") == folder }
                        .sortedWith { a, b -> LibraryStore.compareTitle(a.title, b.title) }
                        .map { songItem(ctx, it) }
                }
                parentId.startsWith(PLAYLIST_P) -> {
                    val id = parentId.removePrefix(PLAYLIST_P)
                    val pl = LibraryStore.playlists(ctx).firstOrNull { it.id == id }
                    songsForPaths(ctx, songs, pl?.paths ?: emptyList())
                }
                else -> emptyList()
            }
        }
    }

    fun item(ctx: Context, mediaId: String): MediaItem? {
        if (isBrowsableId(mediaId)) {
            children(ctx, ROOT).firstOrNull { it.mediaId == mediaId }?.let { return it }
            return folderItem(mediaId, labelOf(mediaId), MediaMetadata.MEDIA_TYPE_FOLDER_MIXED, ctx, playable = true)
        }
        val s = LibraryStore.songByPath(ctx, mediaId) ?: LibSong(mediaId, File(mediaId).nameWithoutExtension, "", "")
        return songItem(ctx, s)
    }

    data class PlayRequest(
        val items: List<MediaItem>,
        val index: Int,
        val positionMs: Long = 0L
    )

    /**
     * Auto tek şarkı gönderince çalma kuyruğunu kurar.
     * v5.1.3 düzeltme: öncelik sırası —
     * 1) son tarama ebeveyninin kardeşleri (hızlı yol),
     * 2) şarkının KENDİ klasörü (deterministik; lastBrowseParent arka plan
     *    sorgularıyla bozulsa bile doğru çalışır),
     * 3) tüm kütüphane (Şarkılar) — tek şarkılık kuyruk kurma:
     *    tek şarkı + "tümünü tekrarla" = aynı şarkıya başa sarma, hem ileri
     *    tuşunda hem parça sonunda (Auto'da bildirilen hata buydu),
     * 4) son çare tek şarkı.
     */
    fun resolveQueue(ctx: Context, mediaId: String): PlayRequest {
        if (mediaId.isEmpty()) return PlayRequest(emptyList(), 0)
        if (isBrowsableId(mediaId) || mediaId.startsWith("cobble:")) {
            return PlayRequest(resolvePlayable(ctx, mediaId), 0)
        }
        val siblings = children(ctx, lastBrowseParent).filter {
            it.mediaMetadata.isPlayable == true && it.mediaMetadata.isBrowsable != true
        }
        val idx = siblings.indexOfFirst { it.mediaId == mediaId }
        if (idx >= 0 && siblings.size > 1) {
            val items = siblings.mapIndexed { i, mi ->
                CobbleMedia.item(
                    ctx,
                    mi.mediaId,
                    mi.mediaMetadata.title?.toString(),
                    mi.mediaMetadata.artist?.toString(),
                    mi.mediaMetadata.albumTitle?.toString(),
                    artBytes = i == idx
                )
            }
            return PlayRequest(items, idx)
        }
        // 2) Deterministik yedek: şarkının kendi klasörü.
        val songs = LibraryStore.songs(ctx)
        val me = songs.firstOrNull { it.path == mediaId }
        if (me != null) {
            val folder = File(me.path).parent ?: "/"
            val sameFolder = songs
                .filter { (File(it.path).parent ?: "/") == folder }
                .sortedWith { a, b -> LibraryStore.compareTitle(a.title, b.title) }
            val i2 = sameFolder.indexOfFirst { it.path == mediaId }
            if (i2 >= 0 && sameFolder.size > 1) {
                val items = sameFolder.mapIndexed { i, s ->
                    CobbleMedia.item(
                        ctx,
                        s.path,
                        s.title,
                        s.artist.ifBlank { null },
                        s.album.ifBlank { null },
                        artBytes = i == i2
                    )
                }
                return PlayRequest(items, i2)
            }
            // 3) Klasör de tek şarkılıysa: tüm kütüphane (kesinlikle çoklu).
            val all = songs.sortedWith { a, b -> LibraryStore.compareTitle(a.title, b.title) }
            val i3 = all.indexOfFirst { it.path == mediaId }
            if (i3 >= 0 && all.size > 1) {
                val items = all.mapIndexed { i, s ->
                    CobbleMedia.item(
                        ctx,
                        s.path,
                        s.title,
                        s.artist.ifBlank { null },
                        s.album.ifBlank { null },
                        artBytes = i == i3
                    )
                }
                return PlayRequest(items, i3)
            }
        }
        // 4) Son çare: tek şarkı (kütüphane boşsa / tanınmayan yol).
        val s = LibraryStore.songByPath(ctx, mediaId)
        return PlayRequest(
            listOf(
                CobbleMedia.item(
                    ctx,
                    mediaId,
                    s?.title,
                    s?.artist?.ifBlank { null },
                    s?.album?.ifBlank { null },
                    artBytes = true
                )
            ),
            0
        )
    }

    /** Auto / sistem bir öğe seçince gerçek çalınabilir parçalara çevir. */
    fun resolvePlayable(ctx: Context, mediaId: String): List<MediaItem> {
        if (mediaId.isEmpty()) return emptyList()
        if (!isBrowsableId(mediaId) && !mediaId.startsWith("cobble:")) {
            val s = LibraryStore.songByPath(ctx, mediaId)
            return listOf(
                CobbleMedia.item(
                    ctx,
                    mediaId,
                    s?.title,
                    s?.artist?.ifBlank { null },
                    artBytes = true
                )
            )
        }
        val kids = children(ctx, mediaId)
        val songs = kids.filter { it.mediaMetadata.isPlayable == true && it.mediaMetadata.isBrowsable != true }
        if (songs.isNotEmpty()) {
            return songs.mapIndexed { i, mi ->
                CobbleMedia.item(
                    ctx,
                    mi.mediaId,
                    mi.mediaMetadata.title?.toString(),
                    mi.mediaMetadata.artist?.toString(),
                    artBytes = i == 0
                )
            }
        }
        // Klasörün altındaki çalınabilirler
        return kids.flatMap { child ->
            if (child.mediaMetadata.isBrowsable == true) resolvePlayable(ctx, child.mediaId)
            else listOf(
                CobbleMedia.item(
                    ctx,
                    child.mediaId,
                    child.mediaMetadata.title?.toString(),
                    child.mediaMetadata.artist?.toString(),
                    artBytes = false
                )
            )
        }
    }

    fun search(ctx: Context, query: String): List<MediaItem> {
        val q = query.trim().lowercase()
        if (q.isEmpty()) return children(ctx, SONGS).take(50)
        return LibraryStore.songs(ctx).filter {
            it.title.lowercase().contains(q) ||
                it.artist.lowercase().contains(q) ||
                it.album.lowercase().contains(q)
        }.take(80).map { songItem(ctx, it) }
    }

    private fun snapshotSongs(ctx: Context, songs: List<LibSong>, key: String): List<LibSong> {
        val paths = LibraryStore.smartSnapshot(ctx)[key] ?: return emptyList()
        if (paths.isEmpty()) return emptyList()
        val by = songs.associateBy { it.path }
        return paths.mapNotNull { by[it] }
    }

    private fun songsForPaths(ctx: Context, songs: List<LibSong>, paths: List<String>): List<MediaItem> {
        val byPath = songs.associateBy { it.path }
        return paths.mapNotNull { p ->
            val s = byPath[p] ?: LibSong(p, File(p).nameWithoutExtension, "", "")
            songItem(ctx, s)
        }
    }

    private fun songItem(ctx: Context, s: LibSong): MediaItem {
        return MediaItem.Builder()
            .setMediaId(s.path)
            .setUri(android.net.Uri.fromFile(File(s.path)))
            .setMediaMetadata(
                MediaMetadata.Builder()
                    .setTitle(s.title)
                    .setArtist(s.artist.ifBlank { "Bilinmeyen sanatçı" })
                    .setAlbumTitle(s.album.ifBlank { "Cobblestone" })
                    .setIsBrowsable(false)
                    .setIsPlayable(true)
                    .setMediaType(MediaMetadata.MEDIA_TYPE_MUSIC)
                    .setArtworkUri(CoverResolver.browseArtUri(ctx, s.path))
                    .build()
            )
            .build()
    }

    private fun folderItem(
        id: String,
        title: String,
        type: Int,
        ctx: Context,
        count: Int = -1,
        playable: Boolean = false,
        grid: Boolean = false
    ): MediaItem {
        val subtitle = if (count >= 0) "$count şarkı" else null
        val extras = Bundle().apply {
            putBoolean("android.media.browse.CONTENT_STYLE_SUPPORTED", true)
            putInt(
                "android.media.browse.CONTENT_STYLE_BROWSABLE_HINT",
                if (grid) 2 else 1
            )
            putInt("android.media.browse.CONTENT_STYLE_PLAYABLE_HINT", 1)
        }
        return MediaItem.Builder()
            .setMediaId(id)
            .setMediaMetadata(
                MediaMetadata.Builder()
                    .setTitle(title)
                    .setSubtitle(subtitle)
                    .setIsBrowsable(true)
                    .setIsPlayable(playable)
                    .setMediaType(type)
                    .setArtworkUri(CoverResolver.browseArtUri(ctx, null))
                    .setExtras(extras)
                    .build()
            )
            .build()
    }

    private fun labelOf(id: String): String = when (id) {
        SONGS -> "Şarkılar"
        ALBUMS -> "Albümler"
        ARTISTS -> "Sanatçılar"
        FOLDERS -> "Klasörler"
        PLAYLISTS -> "Listeler"
        FAVORITES -> "Favoriler"
        SMART -> "Akıllı listeler"
        SMART_MOST -> "En çok dinlenenler"
        SMART_LEAST -> "Az dinlenenler"
        SMART_NEVER -> "Hiç dinlenmeyenler"
        RECENT -> "Son çalınanlar"
        else -> id.substringAfterLast(':').substringAfterLast('/')
    }

    private fun recentSongs(ctx: Context): List<MediaItem> {
        try {
            val obj = LastQueueStore.load(ctx)
            val arr = obj?.optJSONArray("items")
            if (arr != null && arr.length() > 0) {
                val by = LibraryStore.songs(ctx).associateBy { it.path }
                val out = ArrayList<MediaItem>(arr.length())
                for (i in 0 until arr.length()) {
                    val o = arr.optJSONObject(i) ?: continue
                    val path = o.optString("path")
                    if (path.isEmpty()) continue
                    val s = by[path] ?: LibSong(
                        path,
                        o.optString("title").ifBlank { File(path).nameWithoutExtension },
                        o.optString("artist"),
                        ""
                    )
                    out.add(songItem(ctx, s))
                }
                if (out.isNotEmpty()) return out
            }
        } catch (_: Throwable) {
        }
        return snapshotSongs(ctx, LibraryStore.songs(ctx), "most").map { songItem(ctx, it) }
    }
}
