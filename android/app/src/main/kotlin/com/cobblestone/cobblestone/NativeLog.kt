package com.cobblestone.cobblestone

import android.content.Context
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Cihazda gelistirici secenekleri olmadan tani icin: adimlari ayni
 *  hata_gunlugu.txt dosyasina yazar (Ayarlar -> Hata Gunlugu ekrani okur). */
object NativeLog {
    @Volatile var appContext: Context? = null

    @Synchronized
    fun log(tag: String) {
        try {
            val ctx = appContext ?: return
            if ((ctx.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) == 0) return
            val dir = File(ctx.filesDir, "app_flutter")
            if (!dir.exists()) dir.mkdirs()
            val f = File(dir, "hata_gunlugu.txt")
            val ts = SimpleDateFormat("HH:mm:ss.SSS", Locale.US).format(Date())
            f.appendText("[native $ts] $tag\n")
        } catch (_: Throwable) {
        }
    }
}

