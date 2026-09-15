package com.cobblestone.cobblestone

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.provider.MediaStore
import androidx.core.app.NotificationCompat
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Klasör taraması sırasında süreci canlı tutar (dataSync ön plan servisi).
 * Medya çalma servisine dokunmaz — Play politikası için ayrı tip.
 */
class LibraryScanService : Service() {

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopKeepAlive()
            return START_NOT_STICKY
        }
        startKeepAlive()
        return START_NOT_STICKY
    }

    private fun startKeepAlive() {
        ensureChannel()
        val launch = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        val pi = PendingIntent.getActivity(
            this,
            0,
            launch,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val notif = NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_cobble)
            .setContentTitle("Cobblestone")
            .setContentText("Klasör taranıyor…")
            .setContentIntent(pi)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
        // startForegroundService sonrası 5 sn içinde startForeground şart.
        if (Build.VERSION.SDK_INT >= 34) {
            try {
                startForeground(
                    NOTIF_ID,
                    notif,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                )
            } catch (t: Throwable) {
                NativeLog.log("scanFgTypedFailed=" + (t.message ?: ""))
                startForeground(NOTIF_ID, notif)
            }
        } else {
            startForeground(NOTIF_ID, notif)
        }
        try {
            if (wakeLock == null) {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = pm.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "cobblestone:scan"
                ).also {
                    it.setReferenceCounted(false)
                    it.acquire(30 * 60 * 1000L)
                }
            }
        } catch (t: Throwable) {
            NativeLog.log("scanWakeFailed=" + (t.message ?: ""))
        }
    }

    private fun stopKeepAlive() {
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
        } catch (_: Throwable) {
        }
        wakeLock = null
        try {
            if (Build.VERSION.SDK_INT >= 24) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Throwable) {
        }
        stopSelf()
    }

    override fun onDestroy() {
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
        } catch (_: Throwable) {
        }
        wakeLock = null
        super.onDestroy()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = getSystemService(NotificationManager::class.java) ?: return
        val ch = NotificationChannel(
            CHANNEL,
            "Klasör tarama",
            NotificationManager.IMPORTANCE_LOW
        )
        ch.setShowBadge(false)
        ch.setSound(null, null)
        nm.createNotificationChannel(ch)
    }

    companion object {
        const val ACTION_START = "cobble.scan.start"
        const val ACTION_STOP = "cobble.scan.stop"
        private const val NOTIF_ID = 42
        private const val CHANNEL = "cobble.scan"

        private val AUDIO_EXT = setOf(
            "mp3", "m4a", "aac", "flac", "wav", "ogg", "opus", "wma", "amr"
        )

        fun start(ctx: Context) {
            val i = Intent(ctx, LibraryScanService::class.java).setAction(ACTION_START)
            try {
                if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i)
                else ctx.startService(i)
            } catch (t: Throwable) {
                NativeLog.log("scanStartFailed=" + (t.message ?: ""))
            }
        }

        fun stop(ctx: Context) {
            try {
                ctx.startService(
                    Intent(ctx, LibraryScanService::class.java).setAction(ACTION_STOP)
                )
            } catch (_: Throwable) {
            }
        }

        /**
         * MediaStore (hızlı, indekslenmiş) + gerekirse disk gezintisi.
         * Binder limiti olmasın diye sonucu cache JSON dosyasına yazar.
         */
        fun listToFile(ctx: Context, folderPath: String): File {
            val items = LinkedHashMap<String, Long>()
            val folder = try {
                File(folderPath).canonicalFile
            } catch (_: Throwable) {
                File(folderPath)
            }
            val prefixes = linkedSetOf(folder.absolutePath)
            try {
                val abs = folder.absoluteFile
                if (abs.absolutePath != folder.absolutePath) prefixes.add(abs.absolutePath)
            } catch (_: Throwable) {
            }

            try {
                queryMediaStore(ctx, prefixes, items)
            } catch (t: Throwable) {
                NativeLog.log("scanMediaStoreFailed=" + (t.message ?: ""))
            }
            // İndekslenmemiş kopyalar (USB, az önce atılmış dosya) kaçmasın.
            try {
                walkDisk(folder, items)
            } catch (t: Throwable) {
                NativeLog.log("scanWalkFailed=" + (t.message ?: ""))
            }

            val arr = JSONArray()
            for ((path, size) in items) {
                arr.put(
                    JSONObject()
                        .put("path", path)
                        .put("size", size)
                )
            }
            val out = File(ctx.cacheDir, "scan_list.json")
            out.writeText(arr.toString())
            NativeLog.log("scanListed=" + items.size)
            return out
        }

        private fun queryMediaStore(
            ctx: Context,
            prefixes: Set<String>,
            items: MutableMap<String, Long>
        ) {
            val uri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            val cols = arrayOf(
                MediaStore.Audio.Media.DATA,
                MediaStore.Audio.Media.SIZE
            )
            ctx.contentResolver.query(uri, cols, null, null, null)?.use { c ->
                val iPath = c.getColumnIndex(MediaStore.Audio.Media.DATA)
                val iSize = c.getColumnIndex(MediaStore.Audio.Media.SIZE)
                if (iPath < 0) return
                while (c.moveToNext()) {
                    val path = c.getString(iPath) ?: continue
                    if (!underAny(path, prefixes)) continue
                    val size = if (iSize >= 0) c.getLong(iSize) else 0L
                    items[path] = size
                }
            }
        }

        private fun underAny(path: String, prefixes: Set<String>): Boolean {
            for (p in prefixes) {
                if (path == p || path.startsWith("$p/")) return true
            }
            return false
        }

        private fun walkDisk(root: File, items: MutableMap<String, Long>) {
            if (!root.exists()) return
            val stack = ArrayDeque<File>()
            stack.add(root)
            var n = 0
            while (stack.isNotEmpty()) {
                val dir = stack.removeLast()
                val kids = dir.listFiles() ?: continue
                for (f in kids) {
                    n++
                    if (f.isDirectory) {
                        if (!f.isHidden && f.name != "." && f.name != "..") {
                            stack.add(f)
                        }
                    } else if (isAudioName(f.name)) {
                        val path = f.absolutePath
                        if (!items.containsKey(path)) {
                            items[path] = try {
                                f.length()
                            } catch (_: Throwable) {
                                0L
                            }
                        }
                    }
                }
            }
        }

        private fun isAudioName(name: String): Boolean {
            val dot = name.lastIndexOf('.')
            if (dot < 0 || dot == name.length - 1) return false
            return AUDIO_EXT.contains(name.substring(dot + 1).lowercase())
        }
    }
}
