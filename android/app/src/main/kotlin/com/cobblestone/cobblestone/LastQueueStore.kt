package com.cobblestone.cobblestone

import android.content.Context
import androidx.media3.common.Player
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** Son kuyruk: SharedPreferences 1 MB tavanına takılmasın diye dosya. */
object LastQueueStore {
    private const val FILE = "last_queue_v1.json"
    private const val LEGACY_PREFS = "FlutterSharedPreferences"
    private const val LEGACY_KEY = "flutter.last_queue_v1"

    fun file(ctx: Context): File = File(ctx.filesDir, FILE)

    fun save(ctx: Context, c: Player) {
        try {
            if (c.mediaItemCount <= 0) {
                // v5.1.3: boş kuyruk son kaydı SİLMEZ — mini oynatıcı
                // kapatıldıktan sonra bile "son çalınanlar" korunur.
                return
            }
            val items = JSONArray()
            for (i in 0 until c.mediaItemCount) {
                val mi = c.getMediaItemAt(i)
                items.put(
                    JSONObject()
                        .put("path", mi.mediaId)
                        .put("title", mi.mediaMetadata.title?.toString() ?: "")
                        .put("artist", mi.mediaMetadata.artist?.toString() ?: "")
                )
            }
            val obj = JSONObject()
            obj.put("items", items)
            obj.put("index", c.currentMediaItemIndex)
            obj.put("positionMs", c.currentPosition.coerceAtLeast(0L))
            val tmp = File(ctx.filesDir, "$FILE.tmp")
            tmp.writeText(obj.toString())
            if (!tmp.renameTo(file(ctx))) {
                tmp.copyTo(file(ctx), overwrite = true)
                tmp.delete()
            }
        } catch (_: Throwable) {
        }
    }

    fun load(ctx: Context): JSONObject? {
        val f = file(ctx)
        if (f.exists() && f.length() > 2) {
            try {
                return JSONObject(f.readText())
            } catch (_: Throwable) {
            }
        }
        return try {
            val raw = ctx.getSharedPreferences(LEGACY_PREFS, Context.MODE_PRIVATE)
                .getString(LEGACY_KEY, null)
            if (raw.isNullOrBlank()) null else JSONObject(raw)
        } catch (_: Throwable) {
            null
        }
    }

    fun delete(ctx: Context) {
        try {
            file(ctx).delete()
        } catch (_: Throwable) {
        }
        try {
            ctx.getSharedPreferences(LEGACY_PREFS, Context.MODE_PRIVATE)
                .edit()
                .remove(LEGACY_KEY)
                .apply()
        } catch (_: Throwable) {
        }
    }

    fun hasQueue(ctx: Context): Boolean {
        val f = file(ctx)
        if (f.exists() && f.length() > 2) return true
        return try {
            !ctx.getSharedPreferences(LEGACY_PREFS, Context.MODE_PRIVATE)
                .getString(LEGACY_KEY, null).isNullOrBlank()
        } catch (_: Throwable) {
            false
        }
    }
}
