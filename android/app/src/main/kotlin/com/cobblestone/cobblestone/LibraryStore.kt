package com.cobblestone.cobblestone

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.Collator
import java.util.Locale

data class LibSong(
    val path: String,
    val title: String,
    val artist: String,
    val album: String,
    val addedMs: Long = 0L
)

data class LibPlaylist(
    val id: String,
    val name: String,
    val paths: List<String>
)

data class LibStats(
    val plays: Map<String, Int>,
    val lastMs: Map<String, Long>
)

/**
 * Flutter'ın filesDir altındaki JSON kütüphanesi.
 * Android Auto / widget / son-şarkı çal, uygulama kapalıyken de okur.
 */
object LibraryStore {

    private val tr: Collator = Collator.getInstance(Locale("tr", "TR")).apply {
        strength = Collator.PRIMARY
    }

    @Volatile private var songsCache: List<LibSong>? = null
    @Volatile private var songsStamp = -1L
    @Volatile private var playlistsCache: List<LibPlaylist>? = null
    @Volatile private var playlistsStamp = -1L

    fun invalidate() {
        songsCache = null
        playlistsCache = null
        songsStamp = -1L
        playlistsStamp = -1L
    }

    fun songs(ctx: Context): List<LibSong> {
        val stamp = fileStamp(ctx, "library_v1.json")
        val cached = songsCache
        if (cached != null && stamp == songsStamp) return cached
        val obj = readJson(ctx, "library_v1.json") ?: run {
            songsCache = emptyList()
            songsStamp = stamp
            return emptyList()
        }
        val arr = obj.optJSONArray("songs") ?: return emptyList()
        val out = ArrayList<LibSong>(arr.length())
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val path = o.optString("appPath")
            if (path.isEmpty()) continue
            val title = o.optString("title").ifBlank {
                File(path).nameWithoutExtension
            }
            out.add(
                LibSong(
                    path = path,
                    title = title,
                    artist = o.optString("artist"),
                    album = o.optString("album"),
                    addedMs = o.optLong("addedMs", 0L)
                )
            )
        }
        songsCache = out
        songsStamp = stamp
        return out
    }

    fun playlists(ctx: Context): List<LibPlaylist> {
        val stamp = fileStamp(ctx, "playlists_v1.json")
        val cached = playlistsCache
        if (cached != null && stamp == playlistsStamp) return cached
        val obj = readJson(ctx, "playlists_v1.json") ?: run {
            playlistsCache = emptyList()
            playlistsStamp = stamp
            return emptyList()
        }
        val arr = obj.optJSONArray("playlists") ?: return emptyList()
        val out = ArrayList<LibPlaylist>()
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val id = o.optString("id")
            if (id.isEmpty()) continue
            val pathsArr = o.optJSONArray("songPaths") ?: JSONArray()
            val paths = ArrayList<String>(pathsArr.length())
            for (j in 0 until pathsArr.length()) {
                val p = pathsArr.optString(j)
                if (p.isNotEmpty()) paths.add(p)
            }
            out.add(LibPlaylist(id, o.optString("name").ifBlank { id }, paths))
        }
        playlistsCache = out
        playlistsStamp = stamp
        return out
    }

    fun stats(ctx: Context): LibStats {
        val obj = readJson(ctx, "stats.json") ?: return LibStats(emptyMap(), emptyMap())
        val songs = obj.optJSONObject("songs") ?: return LibStats(emptyMap(), emptyMap())
        val plays = HashMap<String, Int>()
        val last = HashMap<String, Long>()
        val keys = songs.keys()
        while (keys.hasNext()) {
            val path = keys.next()
            val o = songs.optJSONObject(path) ?: continue
            plays[path] = o.optInt("plays", 0)
            last[path] = o.optLong("lastMs", 0L)
        }
        return LibStats(plays, last)
    }

    fun songByPath(ctx: Context, path: String): LibSong? =
        songs(ctx).firstOrNull { it.path == path }

    fun compareTitle(a: String, b: String): Int = tr.compare(a, b)

    fun groupedAlbums(list: List<LibSong>): Map<String, List<LibSong>> =
        list.groupBy { it.album.ifBlank { "Bilinmeyen albüm" } }

    fun groupedArtists(list: List<LibSong>): Map<String, List<LibSong>> =
        list.groupBy { it.artist.ifBlank { "Bilinmeyen sanatçı" } }

    fun groupedFolders(list: List<LibSong>): Map<String, List<LibSong>> {
        val seen = HashSet<String>()
        val out = LinkedHashMap<String, MutableList<LibSong>>()
        for (s in list) {
            val key = s.path.lowercase()
            if (!seen.add(key)) continue
            val folder = File(s.path).parent ?: "/"
            out.getOrPut(folder) { ArrayList() }.add(s)
        }
        return out
    }

    fun smartSnapshot(ctx: Context): Map<String, List<String>> {
        val obj = readJson(ctx, "smart_snapshot_v1.json") ?: return emptyMap()
        fun list(k: String): List<String> {
            val arr = obj.optJSONArray(k) ?: return emptyList()
            return (0 until arr.length()).mapNotNull { i ->
                arr.optString(i).takeIf { it.isNotEmpty() }
            }
        }
        return mapOf(
            "most" to list("most"),
            "least" to list("least"),
            "never" to list("never")
        )
    }

    private fun fileStamp(ctx: Context, name: String): Long {
        for (f in jsonCandidates(ctx, name)) {
            if (f.exists()) return f.lastModified() xor f.length()
        }
        return 0L
    }

    private fun jsonCandidates(ctx: Context, name: String): Array<File> = arrayOf(
        File(ctx.filesDir, name),
        File(ctx.getDir("flutter", Context.MODE_PRIVATE), name),
        File(ctx.filesDir.parentFile, "app_flutter/$name")
    )

    private fun readJson(ctx: Context, name: String): JSONObject? {
        val candidates = arrayOf(
            File(ctx.filesDir, name),
            File(ctx.getDir("flutter", Context.MODE_PRIVATE), name),
            File(ctx.filesDir.parentFile, "app_flutter/$name")
        )
        for (f in candidates) {
            if (f.exists() && f.length() > 2) {
                try {
                    return JSONObject(f.readText())
                } catch (_: Throwable) {
                }
            }
        }
        return null
    }
}
