package com.cobblestone.cobblestone

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

/**
 * Favori yollarının tek kaynağı.
 *
 * Flutter `setStringList` (JSON önekli dizi / DataStore) ile Kotlin'in
 * `FlutterSharedPreferences` okuması uyumsuzdu; bildirimdeki ★ bu yüzden
 * hiçbir şey yazmıyordu. Bu depo düz bir StringSet — uygulama kapalıyken
 * de yıldız çalışır. Flutter açılınca kümeyi okuyup çalma listesine yazar.
 */
object FavoritesStore {
    private const val PREFS = "cobble_favorites_v1"
    const val KEY_PATHS = "paths"
    private const val KEY_SEEDED = "seeded"

    // shared_preferences 2.x StringList önekleri (bir kerelik göç).
    private const val JSON_LIST_PREFIX = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGxpc3Qu!!"
    private const val LIST_PREFIX = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGxpc3Qu"
    private const val FLUTTER_PREFS = "FlutterSharedPreferences"
    private const val PLAYLISTS_KEY = "flutter.saved_playlists_v1"
    private const val FAVORITES_ID = "__favorites__"

    private fun prefs(ctx: Context): SharedPreferences =
        ctx.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun isSeeded(ctx: Context): Boolean = prefs(ctx).getBoolean(KEY_SEEDED, false)

    fun get(ctx: Context): Set<String> =
        prefs(ctx).getStringSet(KEY_PATHS, emptySet())?.toSet() ?: emptySet()

    fun set(ctx: Context, paths: Set<String>) {
        prefs(ctx).edit()
            .putStringSet(KEY_PATHS, HashSet(paths))
            .putBoolean(KEY_SEEDED, true)
            .apply()
    }

    /** @return yeni durum: true = artık favori */
    fun toggle(ctx: Context, path: String): Boolean {
        ensureSeeded(ctx)
        val next = get(ctx).toMutableSet()
        val nowFav = if (!next.add(path)) {
            next.remove(path)
            false
        } else {
            true
        }
        set(ctx, next)
        return nowFav
    }

    fun contains(ctx: Context, path: String?): Boolean =
        !path.isNullOrEmpty() && get(ctx).contains(path)

    fun registerListener(
        ctx: Context,
        listener: SharedPreferences.OnSharedPreferenceChangeListener
    ) {
        prefs(ctx).registerOnSharedPreferenceChangeListener(listener)
    }

    fun unregisterListener(
        ctx: Context,
        listener: SharedPreferences.OnSharedPreferenceChangeListener
    ) {
        prefs(ctx).unregisterOnSharedPreferenceChangeListener(listener)
    }

    /**
     * İlk yazmadan önce Flutter prefs'ten (varsa) favorileri alır.
     * DataStore kullanılıyorsa dosya boş kalır; o durumda Flutter
     * `syncFavorites` ile doldurur.
     */
    private fun ensureSeeded(ctx: Context) {
        if (isSeeded(ctx)) return
        val migrated = readFlutterFavoritePaths(ctx) ?: return
        set(ctx, migrated)
    }

    /** Favoriler listesi bulunduysa yollar (boş küme dahil); yoksa null. */
    private fun readFlutterFavoritePaths(ctx: Context): Set<String>? {
        return try {
            val rawPref = ctx.applicationContext
                .getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
                .getString(PLAYLISTS_KEY, null) ?: return null
            var raw = rawPref
            if (raw.startsWith(JSON_LIST_PREFIX)) {
                raw = raw.substring(JSON_LIST_PREFIX.length)
            } else if (raw.startsWith(LIST_PREFIX)) {
                val rest = raw.substring(LIST_PREFIX.length)
                if (!rest.startsWith("[")) return null
                raw = rest
            }
            val arr = JSONArray(raw)
            for (i in 0 until arr.length()) {
                val obj = playlistObjectAt(arr, i) ?: continue
                if (obj.optString("id") == FAVORITES_ID) {
                    val paths = obj.optJSONArray("songPaths") ?: return emptySet()
                    val out = HashSet<String>()
                    for (j in 0 until paths.length()) {
                        val p = paths.optString(j)
                        if (p.isNotEmpty()) out.add(p)
                    }
                    return out
                }
            }
            null
        } catch (_: Throwable) {
            null
        }
    }

    private fun playlistObjectAt(arr: JSONArray, i: Int): JSONObject? {
        arr.optJSONObject(i)?.let { return it }
        val s = arr.optString(i)
        if (s.startsWith("{")) {
            return try {
                JSONObject(s)
            } catch (_: Throwable) {
                null
            }
        }
        return null
    }
}
