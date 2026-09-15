package com.cobblestone.cobblestone

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.app.RecoverableSecurityException
import android.media.MediaScannerConnection
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionToken
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executor

/**
 * Flutter <-> Media3 köprüsü — v11.
 *
 * Oynatıcı komutları MethodChannel ("cobble/player"), durum yayını
 * EventChannel ("cobble/player/state") üstünden akar (v8 tabanı).
 *
 * Eklemeler:
 * • "cobble/eq" MethodChannel → gerçek ekolayzer (EqEngine) kontrolü
 * • "cobble/rhythm" EventChannel → nabız özetleri (sadece uygulama önde ve
 *   arayüz aboneyken yayınlanır; ekran kapalıyken pil dostu uyku)
 * • Kuyruk öğeleri artık kapak dosya yolu taşıyabilir ("cover"); varsa kart
 *   ve kilit ekranında şarkının kendi kapağı görünür.
 */
class MainActivity : FlutterActivity() {

    // Paket 14: Pazartesi raporu — soğuk açılışta bildirim eylemini bekletir.
    private var reportChannel: MethodChannel? = null
    private var pendingOpenReport = false

    // "Şununla aç → Cobblestone" ile gelen ses dosyası (soğuk açılışta bekletilir).
    private var pendingOpenSong: Map<String, String>? = null

    // "Uygulamadan ve telefondan sil": Android 10+ doğrudan silmeye izin
    // vermez; MediaStore "silme isteği" diyaloğuyla kullanıcı onayı alınır.
    private var pendingDeleteResult: MethodChannel.Result? = null
    private var pendingDeleteUri: Uri? = null
    private val deleteRequestCode = 4101
    private var pendingWriteResult: MethodChannel.Result? = null
    private var pendingWriteSrc: String? = null
    private var pendingWriteDest: String? = null
    private var pendingWriteTitle: String? = null
    private var pendingWriteArtist: String? = null
    private var pendingWriteAlbum: String? = null
    private val writeRequestCode = 4102

    private var lastSavedIndex = -99
    private var lastPosSaveAt = 0L

    private fun saveLastQueue(c: MediaController?) {
        if (c == null) return
        LastQueueStore.save(this, c)
    }

    // Bildirim kartındaki ★: native favori kümesi değişince Flutter'a yol listesi gider.
    private var nativeChannel: MethodChannel? = null
    private val favReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            try {
                val paths = intent.getStringArrayListExtra("paths")
                    ?: ArrayList(FavoritesStore.get(this@MainActivity))
                nativeChannel?.invokeMethod("favoritesChanged", paths)
            } catch (_: Throwable) {
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ReportReminder.scheduleNext(this)
        if (intent?.getBooleanExtra(ReportReminder.EXTRA_OPEN_REPORT, false) == true) {
            pendingOpenReport = true
            intent?.removeExtra(ReportReminder.EXTRA_OPEN_REPORT)
        }
        handleViewIntent(intent)
        handlePlayFromSearch(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getBooleanExtra(ReportReminder.EXTRA_OPEN_REPORT, false)) {
            intent.removeExtra(ReportReminder.EXTRA_OPEN_REPORT)
            val ch = reportChannel
            if (ch != null) ch.invokeMethod("openReport", null) else pendingOpenReport = true
        }
        handleViewIntent(intent)
        handlePlayFromSearch(intent)
    }

    /**
     * Samsung panel / "son şarkıyı çal" / MEDIA_PLAY_FROM_SEARCH:
     * Cobblestone müzik çalar olarak tanınır ve son kuyruk devam eder.
     */
    private fun handlePlayFromSearch(intent: Intent?) {
        val a = intent?.action ?: return
        if (a != "android.media.action.MEDIA_PLAY_FROM_SEARCH") return
        try {
            val i = Intent(this, PlaybackService::class.java)
                .setAction(PlaybackService.ACTION_TOGGLE)
            if (Build.VERSION.SDK_INT >= 26) startForegroundService(i) else startService(i)
        } catch (_: Throwable) {
        }
    }

    /**
     * "Şununla aç → Cobblestone" (ACTION_VIEW, audio MIME): dosyayı çözüp
     * Flutter'a iletir; motif uygulama kapatılmışsa soğuk açılışta "çekme"
     * (getPendingOpenSong) ile teslim edilir.
     */
    private fun queryDisplayName(uri: Uri): String? {
        return try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    val idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (idx >= 0) c.getString(idx) else null
                } else null
            }
        } catch (_: Throwable) {
            null
        }
    }

    /** content:// URI → gerçek dosya yolu. İzlenen Müzik klasöründeyse kopya yok. */
    private fun resolveAudioPath(uri: Uri, displayName: String?): String? {
        if (uri.scheme == "file") {
            val p = uri.path ?: return null
            return if (File(p).exists()) p else null
        }
        try {
            if (uri.authority == "com.android.externalstorage.documents") {
                val docId = DocumentsContract.getDocumentId(uri)
                val split = docId.split(":", limit = 2)
                if (split.size == 2) {
                    val vol = split[0]
                    val rel = split[1]
                    val cand = if (vol.equals("primary", true)) {
                        "/storage/emulated/0/$rel"
                    } else {
                        "/storage/$vol/$rel"
                    }
                    if (File(cand).exists()) return cand
                }
            }
        } catch (_: Throwable) {
        }
        try {
            contentResolver.query(
                uri,
                arrayOf(
                    MediaStore.MediaColumns.DATA,
                    MediaStore.MediaColumns.RELATIVE_PATH,
                    MediaStore.MediaColumns.DISPLAY_NAME
                ),
                null,
                null,
                null
            )?.use { c ->
                if (c.moveToFirst()) {
                    val dataIdx = c.getColumnIndex(MediaStore.MediaColumns.DATA)
                    if (dataIdx >= 0) {
                        val d = c.getString(dataIdx)
                        if (!d.isNullOrBlank() && File(d).exists()) return d
                    }
                    val relIdx = c.getColumnIndex(MediaStore.MediaColumns.RELATIVE_PATH)
                    val nameIdx = c.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
                    val rel = if (relIdx >= 0) c.getString(relIdx) else null
                    val name = if (nameIdx >= 0) c.getString(nameIdx) else displayName
                    if (!rel.isNullOrBlank() && !name.isNullOrBlank()) {
                        val cand = "/storage/emulated/0/${rel.trimEnd('/')}/$name"
                        if (File(cand).exists()) return cand
                    }
                }
            }
        } catch (_: Throwable) {
        }
        if (!displayName.isNullOrBlank()) {
            try {
                contentResolver.query(
                    MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                    arrayOf(MediaStore.Audio.Media.DATA),
                    "${MediaStore.Audio.Media.DISPLAY_NAME} = ?",
                    arrayOf(displayName),
                    null
                )?.use { c ->
                    val idx = c.getColumnIndex(MediaStore.Audio.Media.DATA)
                    while (c.moveToNext()) {
                        val d = if (idx >= 0) c.getString(idx) else null
                        if (!d.isNullOrBlank() && File(d).exists()) return d
                    }
                }
            } catch (_: Throwable) {
            }
        }
        return null
    }

    private fun handleViewIntent(intent: Intent?) {
        if (intent?.action != Intent.ACTION_VIEW) return
        val data = intent.data ?: return
        var type = intent.type ?: ""
        if (type.isEmpty()) {
            try {
                type = contentResolver.getType(data) ?: ""
            } catch (_: Throwable) {
            }
        }
        val looksAudio = type.startsWith("audio/") ||
            (data.lastPathSegment?.lowercase()?.let {
                it.endsWith(".mp3") || it.endsWith(".m4a") || it.endsWith(".flac") ||
                    it.endsWith(".wav") || it.endsWith(".ogg") || it.endsWith(".aac")
            } == true)
        if (!looksAudio && type.isNotEmpty() && !type.startsWith("audio/")) return
        val displayName = queryDisplayName(data)
        val real = resolveAudioPath(data, displayName)
        val file: File
        val name: String
        if (real != null && File(real).exists()) {
            file = File(real)
            name = displayName ?: file.name
        } else if (data.scheme == "content") {
            try {
                val dn = displayName ?: "İçe Aktarılan Şarkı"
                val safeName = dn.replace(Regex("[^A-Za-z0-9._-]"), "_")
                val out = File(cacheDir, "imported_${System.currentTimeMillis()}_$safeName")
                contentResolver.openInputStream(data)?.use { input ->
                    out.outputStream().use { o -> input.copyTo(o) }
                } ?: return
                name = dn
                file = out
            } catch (_: Throwable) {
                return
            }
        } else {
            val pth = data.path ?: return
            val f = File(pth)
            if (!f.exists()) return
            name = f.name
            file = f
        }
        val payload = mapOf("path" to file.absolutePath, "name" to name)
        val ch = nativeChannel
        if (ch != null) {
            try {
                ch.invokeMethod("openSongPath", payload)
            } catch (_: Throwable) {
                pendingOpenSong = payload
            }
        } else {
            pendingOpenSong = payload
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private val mainExecutor = Executor { command -> handler.post(command) }

    // v5.1.1: kuyruk JSON'u okuma/parse ve MediaItem üretimi (her öğede
    // File.exists çağrıları var) ana thread'de yapılmıyordu; 1000+ şarkıda
    // UI takılması yapıyordu. Artık bu tek iş parçacığında.
    private val io = java.util.concurrent.Executors.newSingleThreadExecutor()

    private var controller: MediaController? = null
    private var connecting = false
    private var events: EventChannel.EventSink? = null
    private var rhythmSink: EventChannel.EventSink? = null
    private val pendingConnects = ArrayList<MethodChannel.Result>()
    private var resumed = true

    private var lastPushedCount = -2

    private val ticker = object : Runnable {
        override fun run() {
            pushState()
            // v5.1.1: çalarken 400 ms (konum akışı + istatistik buna bağlı),
            // duraklatılmış/bosta 1.5 s — arka planda gereksiz tick bitti.
            val playing = try { controller?.isPlaying == true } catch (_: Throwable) { false }
            handler.postDelayed(this, if (playing) 400L else 1500L)
        }
    }

    private val rhythmTicker = object : Runnable {
        override fun run() {
            pushRhythm()
            handler.postDelayed(this, 90)
        }
    }

    private val saveQueueRunnable = Runnable {
        try {
            saveLastQueue(controller)
        } catch (_: Throwable) {
        }
    }

    private val playerListener = object : Player.Listener {
        override fun onEvents(player: Player, events: Player.Events) {
            val countChanged = try {
                player.mediaItemCount != lastPushedCount
            } catch (_: Throwable) {
                false
            }
            try {
                pushState(includeQueue = countChanged)
            } catch (_: Throwable) {
            }
            val idx = try { player.currentMediaItemIndex } catch (_: Throwable) { return }
            val now = System.currentTimeMillis()
            if (idx != lastSavedIndex || now - lastPosSaveAt > 4000L) {
                lastSavedIndex = idx
                lastPosSaveAt = now
                handler.removeCallbacks(saveQueueRunnable)
                handler.postDelayed(saveQueueRunnable, 500)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cobble/player").setMethodCallHandler { call, result ->
            when (call.method) {
                "connect" -> {
                    pendingConnects.add(result)
                    connectController()
                }

                "setQueue" -> {
                    val c = controller
                    if (c == null) {
                        result.error("no_controller", "Media3 kontrolü henüz bağlı değil", null)
                    } else {
                        val startIndex = call.argument<Number>("startIndex")?.toInt() ?: 0
                        val shuffle = call.argument<Boolean>("shuffle") ?: false
                        val repeat = call.argument<Number>("repeat")?.toInt() ?: Player.REPEAT_MODE_ALL
                        val filePath = call.argument<String>("file")
                        val itemsArg = call.argument<List<Map<String, Any?>>>("items")
                        // v5.1.1: dosya okuma + JSON parse + MediaItem üretimi
                        // (öğe başına birkaç File.exists) arka plan iş parçacığında.
                        // Yalnızca oynatıcı çağrıları ana thread'de kalır.
                        io.execute {
                            try {
                                NativeLog.log("setQueue:start")
                                val arr: org.json.JSONArray = if (!filePath.isNullOrBlank()) {
                                    val tok = org.json.JSONTokener(File(filePath).readText()).nextValue()
                                    when (tok) {
                                        is org.json.JSONArray -> tok
                                        is org.json.JSONObject -> tok.optJSONArray("items") ?: org.json.JSONArray()
                                        else -> org.json.JSONArray()
                                    }
                                } else {
                                    val items = itemsArg ?: emptyList()
                                    val a = org.json.JSONArray()
                                    for (m in items) {
                                        val o = org.json.JSONObject()
                                        o.put("path", m["path"] ?: "")
                                        o.put("title", m["title"] ?: "")
                                        o.put("artist", m["artist"] ?: "")
                                        a.put(o)
                                    }
                                    a
                                }
                                val n = arr.length()
                                if (n <= 0) {
                                    mainExecutor.execute {
                                        result.error("set_queue_failed", "empty", null)
                                    }
                                    return@execute
                                }
                                val si = startIndex.coerceIn(0, n - 1)
                                fun itemAt(i: Int): MediaItem {
                                    val o = arr.getJSONObject(i)
                                    return CobbleMedia.item(
                                        this@MainActivity,
                                        o.optString("path"),
                                        o.optString("title"),
                                        o.optString("artist").ifBlank { null },
                                        artBytes = false
                                    )
                                }
                                val nowItem = itemAt(si)
                                val before = ArrayList<MediaItem>()
                                for (i in 0 until si) before.add(itemAt(i))
                                val after = ArrayList<MediaItem>()
                                for (i in si + 1 until n) after.add(itemAt(i))
                                mainExecutor.execute {
                                    try {
                                        // Önce basılan parça — 5000 öğe beklenmeden çalsın.
                                        c.shuffleModeEnabled = shuffle
                                        c.repeatMode = repeat
                                        c.setMediaItems(listOf(nowItem), 0, 0L)
                                        c.prepare()
                                        c.play()
                                        NativeLog.log("setQueue:playing_now i=" + si)
                                        if (before.isNotEmpty()) c.addMediaItems(0, before)
                                        if (after.isNotEmpty()) c.addMediaItems(after)
                                        saveLastQueue(c)
                                        lastPushedCount = n
                                        result.success(true)
                                        NativeLog.log("setQueue:success n=" + n)
                                    } catch (t: Throwable) {
                                        result.error("set_queue_failed", t.message, null)
                                    }
                                }
                            } catch (t: Throwable) {
                                mainExecutor.execute {
                                    result.error("set_queue_failed", t.message, null)
                                }
                            }
                        }
                    }
                }

                "exportQueue" -> {
                    val c = controller
                    if (c == null || c.mediaItemCount <= 0) {
                        result.success(null)
                    } else {
                        try {
                            val arr = org.json.JSONArray()
                            for (i in 0 until c.mediaItemCount) {
                                val mi = c.getMediaItemAt(i)
                                arr.put(
                                    org.json.JSONObject()
                                        .put("path", mi.mediaId)
                                        .put("title", mi.mediaMetadata.title?.toString() ?: "")
                                )
                            }
                            val index = c.currentMediaItemIndex
                            val playing = c.isPlaying
                            val pwr = c.playWhenReady
                            // v5.1.1: dosya yazımı arka planda (her resume'da
                            // çağrılıyor; büyük kuyrukta ana thread'i yormasın).
                            io.execute {
                                try {
                                    val f = File(cacheDir, "cobble_export_queue.json")
                                    f.writeText(arr.toString())
                                    mainExecutor.execute {
                                        result.success(
                                            hashMapOf(
                                                "file" to f.absolutePath,
                                                "index" to index,
                                                "playing" to playing,
                                                "playWhenReady" to pwr
                                            )
                                        )
                                    }
                                } catch (t: Throwable) {
                                    mainExecutor.execute {
                                        result.error("export_failed", t.message, null)
                                    }
                                }
                            }
                        } catch (t: Throwable) {
                            result.error("export_failed", t.message, null)
                        }
                    }
                }

                "play" -> {
                    controller?.let {
                        if (it.playbackState == Player.STATE_IDLE) it.prepare()
                        it.play()
                    }
                    result.success(true)
                }

                "pause" -> {
                    controller?.pause()
                    saveLastQueue(controller)
                    result.success(true)
                }

                "close" -> {
                    try {
                        val c = controller
                        if (c != null) {
                            try { c.pause() } catch (_: Throwable) {}
                            try { c.playWhenReady = false } catch (_: Throwable) {}
                            try { c.stop() } catch (_: Throwable) {}
                            try { c.clearMediaItems() } catch (_: Throwable) {}
                            try {
                                c.sendCustomCommand(
                                    SessionCommand(PlaybackService.ACTION_CLOSE, Bundle.EMPTY),
                                    Bundle.EMPTY
                                )
                            } catch (_: Throwable) {}
                        }
                    } catch (_: Throwable) {
                    }
                    result.success(true)
                }

                "seekTo" -> {
                    val ms = call.argument<Number>("ms")?.toLong()
                    if (ms != null) controller?.seekTo(ms)
                    result.success(true)
                }

                "jumpToIndex" -> {
                    val c = controller
                    if (c == null) {
                        result.error("no_controller", "Media3 kontrolü henüz bağlı değil", null)
                    } else {
                        try {
                            val idx = call.argument<Number>("index")?.toInt() ?: -1
                            val n = try { c.mediaItemCount } catch (_: Throwable) { 0 }
                            if (idx >= 0 && idx < n) {
                                c.seekTo(idx, 0L)
                                if (c.playbackState == Player.STATE_IDLE) c.prepare()
                                c.play()
                            }
                            result.success(true)
                        } catch (t: Throwable) {
                            result.error("jump_failed", t.message, null)
                        }
                    }
                }

                "next" -> {
                    val c = controller
                    if (c != null) {
                        try {
                            val n = c.mediaItemCount
                            if (n > 0) {
                                val mode = c.repeatMode
                                c.repeatMode = Player.REPEAT_MODE_ALL
                                if (c.hasNextMediaItem()) {
                                    c.seekToNextMediaItem()
                                } else {
                                    c.seekTo(0, 0L)
                                }
                                c.repeatMode = mode
                                if (c.playbackState == Player.STATE_IDLE) c.prepare()
                                c.play()
                            }
                        } catch (_: Throwable) {
                        }
                    }
                    result.success(true)
                }

                "prev" -> {
                    // Tek basışta önceki parçaya geç (başa sarma yok).
                    controller?.seekToPreviousMediaItem()
                    result.success(true)
                }

                "setShuffle" -> {
                    controller?.shuffleModeEnabled = call.argument<Boolean>("shuffle") ?: false
                    result.success(true)
                }

                "setRepeat" -> {
                    controller?.repeatMode = call.argument<Number>("repeat")?.toInt() ?: Player.REPEAT_MODE_ALL
                    result.success(true)
                }

                "setSpeed" -> {
                    val c = controller
                    if (c != null) {
                        val speed = call.argument<Number>("speed")?.toFloat()
                        if (speed != null && speed > 0f) {
                            c.setPlaybackParameters(
                                androidx.media3.common.PlaybackParameters(speed)
                            )
                        }
                    }
                    result.success(true)
                }

                "addNext" -> {
                    val c = controller
                    val path = call.argument<String>("path")
                    if (c == null || path.isNullOrBlank()) {
                        result.error("no_controller", "Kuyruk yok", null)
                    } else {
                        try {
                            val item = CobbleMedia.item(
                                this,
                                path,
                                call.argument<String>("title"),
                                call.argument<String>("artist"),
                                artBytes = false
                            )
                            if (c.mediaItemCount <= 0) {
                                c.setMediaItems(listOf(item), 0, 0L)
                                c.prepare()
                                c.play()
                            } else {
                                val at = (c.currentMediaItemIndex + 1).coerceAtMost(c.mediaItemCount)
                                c.addMediaItem(at, item)
                            }
                            saveLastQueue(c)
                            result.success(true)
                        } catch (t: Throwable) {
                            result.error("add_next_failed", t.message, null)
                        }
                    }
                }

                "addToQueue" -> {
                    val c = controller
                    val path = call.argument<String>("path")
                    if (c == null || path.isNullOrBlank()) {
                        result.error("no_controller", "Kuyruk yok", null)
                    } else {
                        try {
                            val item = CobbleMedia.item(
                                this,
                                path,
                                call.argument<String>("title"),
                                call.argument<String>("artist"),
                                artBytes = false
                            )
                            if (c.mediaItemCount <= 0) {
                                c.setMediaItems(listOf(item), 0, 0L)
                                c.prepare()
                                c.play()
                            } else {
                                c.addMediaItem(item)
                            }
                            saveLastQueue(c)
                            result.success(true)
                        } catch (t: Throwable) {
                            result.error("add_queue_failed", t.message, null)
                        }
                    }
                }

                // Kapak geç çıkarıldıysa kuyruktaki ÖĞEYİ yerinde güncelle
                // (konum korunur); böylece bildirim ve kilit ekranı kapağı
                // şarkı değişince de doğru görünür.
                "updateArtwork" -> {
                    val c = controller
                    val path = call.argument<String>("path")
                    val cover = call.argument<String>("cover")
                    if (c != null && path != null && cover != null) {
                        try {
                            for (i in 0 until c.mediaItemCount) {
                                val mi = c.getMediaItemAt(i)
                                if (mi.mediaId != path) continue
                                if (mi.mediaMetadata.artworkData != null) break
                                val bytes = readCoverBytes(cover)
                                if (bytes == null) break
                                val newMeta = mi.mediaMetadata.buildUpon()
                                    .setArtworkData(
                                        bytes,
                                        MediaMetadata.PICTURE_TYPE_FRONT_COVER
                                    )
                                    .build()
                                c.replaceMediaItem(
                                    i,
                                    mi.buildUpon().setMediaMetadata(newMeta).build()
                                )
                                break
                            }
                        } catch (_: Throwable) {
                        }
                    }
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }

        // ── Gerçek ekolayzer köprüsü ──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cobble/eq").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "describe" -> result.success(EqEngine.describe())
                    "get" -> result.success(EqEngine.getState())
                    "apply" -> {
                        val levels = (call.argument<List<Any?>>("levels"))
                            ?.mapNotNull { (it as? Number)?.toInt() }
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        val bass = call.argument<Number>("bass")?.toInt() ?: 0
                        val virt = call.argument<Number>("virtualizer")?.toInt() ?: 0
                        EqEngine.applyAll(enabled, levels, bass, virt)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (t: Throwable) {
                result.error("eq_failed", t.message, null)
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "cobble/player/state").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    events = sink
                    connectController()
                    handler.removeCallbacks(ticker)
                    handler.post(ticker)
                    pushState()
                }

                override fun onCancel(arguments: Any?) {
                    events = null
                    handler.removeCallbacks(ticker)
                }
            }
        )

        // ── Nabız yayını: sadece arayüz aboneyken + uygulama öndeyken akar ──
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "cobble/rhythm").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    rhythmSink = sink
                    RhythmBus.sampling = true // ölçer uyandı: ses hattına bakıyor
                    handler.removeCallbacks(rhythmTicker)
                    handler.post(rhythmTicker)
                }

                override fun onCancel(arguments: Any?) {
                    rhythmSink = null
                    RhythmBus.sampling = false // ölçer uykuda: ses hattına sıfır yük
                    RhythmBus.level = 0f
                    RhythmBus.bass = 0f
                    handler.removeCallbacks(rhythmTicker)
                }
            }
        )

        nativeChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cobble/native")
        nativeChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                // "Uygulamadan ve telefondan sil": önce doğrudan sil, olmazsa
                // MediaStore isteğiyle kullanıcı onayı al.
                "deletePhoneFiles" -> {
                    // v5.1.3: çoklu silme — TÜM dosyalar için TEK sistem
                    // onay diyaloğu (Android 11+).
                    val raw = call.argument<List<*>>("paths") ?: emptyList<Any>()
                    val paths = raw.mapNotNull { it as? String }
                    if (paths.isEmpty()) {
                        result.success(false)
                    } else {
                        deletePhoneFiles(paths, result)
                    }
                }
                "deleteFromPhone" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.success(false)
                    } else {
                        deletePhoneFile(path, result)
                    }
                }

                // "Şununla aç" ile gelen dosya: uygulama daha yeni açıldıysa
                // Flutter tarafı başlangıçta çekip alır.
                "getPendingOpenSong" -> {
                    val p = pendingOpenSong
                    pendingOpenSong = null
                    result.success(p)
                }

                "getFavorites" -> {
                    if (!FavoritesStore.isSeeded(this)) {
                        result.success(null)
                    } else {
                        result.success(ArrayList(FavoritesStore.get(this)))
                    }
                }

                "syncFavorites" -> {
                    val raw = call.argument<List<*>>("paths") ?: emptyList<Any>()
                    val paths = raw.mapNotNull { it as? String }.toSet()
                    FavoritesStore.set(this, paths)
                    result.success(true)
                }

                "moveTaskToBack" -> {
                    moveTaskToBack(true)
                    result.success(true)
                }

                "shareFiles" -> {
                    // v5.1.3 coklu secim: birden cok sarkiyi tek paylasim
                    // sayfasiyle gonder (ACTION_SEND_MULTIPLE).
                    val paths = call.argument<List<String>>("paths").orEmpty()
                    if (paths.isEmpty()) {
                        result.error("no_path", "Dosya yolu yok", null)
                    } else {
                        // v5.1.3: dosya kopyalama ARKA PLANDA — ana iş
                        // parçacığı kilitlenirse döner gösterge de donar.
                        Thread {
                            try {
                                shareAudioFiles(paths)
                                mainExecutor.execute { result.success(true) }
                            } catch (t: Throwable) {
                                mainExecutor.execute {
                                    result.error("share_failed", t.message, null)
                                }
                            }
                        }.start()
                    }
                }

                "scanAudioFile" -> {
                    // v5.1.3: Dart doğrudan yazdıktan sonra MediaStore'u
                    // tazele (tara + başlık/sanatçı/albüm sütunları).
                    val scanPath = call.argument<String>("path")
                    if (scanPath.isNullOrBlank()) {
                        result.success(false)
                    } else {
                        Thread {
                            try {
                                scanAndTag(
                                    scanPath,
                                    call.argument<String>("title"),
                                    call.argument<String>("artist"),
                                    call.argument<String>("album")
                                )
                            } catch (_: Throwable) {
                            }
                            mainExecutor.execute { result.success(true) }
                        }.start()
                    }
                }

                "shareFile" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("no_path", "Dosya yolu yok", null)
                    } else {
                        try {
                            shareAudioFile(path)
                            result.success(true)
                        } catch (t: Throwable) {
                            result.error("share_failed", t.message, null)
                        }
                    }
                }

                "shareFilesAsZip" -> {
                    // v5.1.3: klasör/liste paylaşımı — şarkılar tek ZIP
                    // dosyası olarak gider (klasör gibi); adı, paylaşılan
                    // şeyin adıdır.
                    val name = call.argument<String>("name") ?: "Cobblestone"
                    val paths = call.argument<List<String>>("paths").orEmpty()
                    if (paths.isEmpty()) {
                        result.error("no_path", "Dosya yolu yok", null)
                    } else {
                        // v5.1.3: ZIP oluşturma ARKA PLANDA — arayüz ve
                        // "hazırlanıyor" döner göstergesi akmaya devam eder.
                        Thread {
                            try {
                                shareZip(name, paths)
                                mainExecutor.execute { result.success(true) }
                            } catch (t: Throwable) {
                                mainExecutor.execute {
                                    result.error("share_failed", t.message, null)
                                }
                            }
                        }.start()
                    }
                }
                "isAllFilesGranted" -> {
                    result.success(
                        Build.VERSION.SDK_INT < 30 ||
                            Environment.isExternalStorageManager()
                    )
                }
                "requestAllFilesAccess" -> {
                    // v5.1.3: "Tüm dosyalara erişim" — etiket yazma, klasör
                    // adlandırma ve uygulama içi klasör tarayıcı bunu kullanır.
                    if (Build.VERSION.SDK_INT >= 30 &&
                        !Environment.isExternalStorageManager()
                    ) {
                        var opened = false
                        // 1) Bu uygulamanın "tüm dosyalara erişim" sayfası.
                        try {
                            startActivity(
                                Intent(
                                    android.provider.Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                                    Uri.parse("package:$packageName")
                                )
                            )
                            opened = true
                        } catch (_: Throwable) {
                        }
                        // 2) Bazı Samsung'lar paket URI'li sayfayı açmıyor —
                        // genel "tüm dosyalara erişim" listesini dene.
                        if (!opened) {
                            try {
                                startActivity(
                                    Intent(
                                        android.provider.Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION
                                    )
                                )
                                opened = true
                            } catch (_: Throwable) {
                            }
                        }
                        // 3) Son çare: uygulama bilgisi sayfası.
                        if (!opened) {
                            try {
                                startActivity(
                                    Intent(
                                        android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                        Uri.parse("package:$packageName")
                                    )
                                )
                            } catch (_: Throwable) {
                            }
                        }
                    }
                    result.success(true)
                }
                "musicFolderSet" -> {
                    // v5.1.3: müzik İÇEREN klasörlerin tamamı (üstleriyle
                    // birlikte) — klasör seçici yalnız bunları listeler.
                    // MediaStore dizini kullanılır: hızlı ve güncel.
                    Thread {
                        val dirs = HashSet<String>()
                        try {
                            contentResolver.query(
                                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                                arrayOf(MediaStore.Audio.Media.DATA),
                                null, null, null
                            )?.use { c ->
                                val idx =
                                    c.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
                                while (c.moveToNext()) {
                                    val s = c.getString(idx)
                                    if (s == null) continue
                                    var d = File(s).parentFile
                                    while (d != null) {
                                        dirs.add(d.absolutePath)
                                        d = d.parentFile
                                    }
                                }
                            }
                        } catch (_: Throwable) {
                        }
                        val out = dirs.toList()
                        mainExecutor.execute { result.success(out) }
                    }.start()
                }
                "renameFolder" -> {
                    // v5.1.3: klasörü TELEFONDA yeniden adlandır (gerçek
                    // dosya sistemi işlemi). Paylaşılan depoda Android
                    // izin vermeyebilir → false döner, Dart tarafı söyler.
                    val old = call.argument<String>("old")
                    val nw = call.argument<String>("new")
                    if (old.isNullOrBlank() || nw.isNullOrBlank()) {
                        result.error("no_path", "Klasör yolu yok", null)
                    } else {
                        Thread {
                            val ok = try {
                                val f = File(old)
                                f.exists() && f.isDirectory && f.renameTo(File(nw))
                            } catch (_: Throwable) {
                                false
                            }
                            mainExecutor.execute { result.success(ok) }
                        }.start()
                    }
                }
                "startScanKeepAlive" -> {
                    LibraryScanService.start(this)
                    result.success(true)
                }

                // v5.1.1: Dart tarafı Android 9- için klasik depolama iznini
                // bilsin diye SDK sürümü (etiket yazma / telefondan silme).
                "sdkInt" -> {
                    result.success(Build.VERSION.SDK_INT)
                }

                "stopScanKeepAlive" -> {
                    LibraryScanService.stop(this)
                    result.success(true)
                }

                "listAudioInFolder" -> {
                    val folder = call.argument<String>("path")
                    if (folder.isNullOrBlank()) {
                        result.error("no_path", "Klasör yok", null)
                    } else {
                        Thread {
                            try {
                                val f = LibraryScanService.listToFile(this, folder)
                                mainExecutor.execute { result.success(f.absolutePath) }
                            } catch (t: Throwable) {
                                mainExecutor.execute {
                                    result.error("scan_failed", t.message, null)
                                }
                            }
                        }.start()
                    }
                }

                "writeAudioFile" -> {
                    val dest = call.argument<String>("dest")
                    val src = call.argument<String>("src")
                    if (dest.isNullOrBlank() || src.isNullOrBlank()) {
                        result.success(false)
                    } else {
                        writeAudioFile(
                            dest,
                            src,
                            call.argument<String>("title"),
                            call.argument<String>("artist"),
                            call.argument<String>("album"),
                            result
                        )
                    }
                }

                "setFallbackArt" -> {
                    val mode = call.argument<String>("mode") ?: "stone"
                    CoverResolver.setFallback(this, mode)
                    try {
                        PlaybackService.instance?.refreshArtworkNow()
                    } catch (_: Throwable) {
                    }
                    result.success(true)
                }

                "notifyLibraryChanged" -> {
                    try {
                        LibraryStore.invalidate()
                        PlaybackService.instance?.notifyLibrary()
                    } catch (_: Throwable) {
                    }
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }

        // Paket 14: Pazartesi raporu — soğuk açılış eyleminin teslim noktası.
        reportChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cobble/report")
        reportChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getLaunchAction" -> {
                    if (pendingOpenReport) {
                        pendingOpenReport = false
                        result.success("report")
                    } else result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }


    private fun shareAudioFiles(paths: List<String>) {
        val uris = ArrayList<android.net.Uri>()
        for (p in paths.take(50)) {
            val src = File(p)
            if (!src.exists() || !src.canRead()) continue
            val safe = src.name.replace(Regex("[^A-Za-z0-9._-]"), "_")
            val cache = File(cacheDir, "share_$safe")
            src.copyTo(cache, overwrite = true)
            uris.add(
                FileProvider.getUriForFile(
                    this,
                    "$packageName.fileprovider",
                    cache
                )
            )
        }
        if (uris.isEmpty()) {
            throw IllegalArgumentException("Dosya bulunamadı")
        }
        val send = Intent(Intent.ACTION_SEND_MULTIPLE).apply {
            type = "audio/*"
            putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        runOnUiThread {
            startActivity(
                Intent.createChooser(send, "Şarkıları paylaş").apply {
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
            )
        }
    }

    private fun shareZip(name: String, paths: List<String>) {
        val safe = name.replace(Regex("[^A-Za-z0-9çğıöşüÇĞİÖŞÜ ._-]"), "_")
            .take(60).trim().ifEmpty { "Cobblestone" }
        val dir = File(cacheDir, "zip_share")
        if (dir.exists()) dir.deleteRecursively()
        dir.mkdirs()
        val zip = File(dir, "$safe.zip")
        java.util.zip.ZipOutputStream(zip.outputStream().buffered()).use { zos ->
            val used = HashSet<String>()
            for (p in paths.take(200)) {
                val src = File(p)
                if (!src.exists() || !src.canRead()) continue
                var entry = src.name
                var i = 2
                while (!used.add(entry)) {
                    entry = "${src.nameWithoutExtension} ($i).${src.extension}"
                    i++
                }
                zos.putNextEntry(java.util.zip.ZipEntry(entry))
                src.inputStream().use { it.copyTo(zos) }
                zos.closeEntry()
            }
        }
        if (zip.length() < 64L) throw IllegalArgumentException("Dosya bulunamadı")
        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            zip
        )
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "application/zip"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        runOnUiThread {
            startActivity(
                Intent.createChooser(send, "Paylaş").apply {
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
            )
        }
    }

    private fun shareAudioFile(path: String) {
        val src = File(path)
        if (!src.exists() || !src.canRead()) {
            throw IllegalArgumentException("Dosya bulunamadı")
        }
        val safe = src.name.replace(Regex("[^A-Za-z0-9._-]"), "_")
        val cache = File(cacheDir, "share_$safe")
        src.copyTo(cache, overwrite = true)
        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            cache
        )
        val mime = when (src.extension.lowercase()) {
            "mp3" -> "audio/mpeg"
            "m4a", "aac" -> "audio/mp4"
            "flac" -> "audio/flac"
            "wav" -> "audio/wav"
            "ogg", "opus" -> "audio/ogg"
            else -> "audio/*"
        }
        val send = Intent(Intent.ACTION_SEND).apply {
            type = mime
            putExtra(Intent.EXTRA_STREAM, uri)
            clipData = android.content.ClipData.newRawUri("", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(
            Intent.createChooser(send, "Parçayı paylaş").apply {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        )
    }

    /**
     * Android 10+ paylaşımlı depolamada dosya silme: doğrudan File API
     * denenir; olmazsa MediaStore kaydı bulunup sistem "silme isteği"
     * diyaloğuyla kullanıcı onayı alınır. Sonuç MethodChannel'a döner.
     */
    private fun deletePhoneFiles(paths: List<String>, result: MethodChannel.Result) {
        Thread {
            val uris = ArrayList<android.net.Uri>()
            for (p in paths) {
                val u = try { queryAudioUri(p) } catch (_: Throwable) { null }
                if (u != null) uris.add(u)
            }
            if (uris.isEmpty()) {
                mainExecutor.execute { result.success(false) }
                return@Thread
            }
            if (Build.VERSION.SDK_INT >= 30) {
                // Tek istek, tek onay — parmak ağrımaz.
                val pi = try {
                    MediaStore.createDeleteRequest(contentResolver, uris)
                } catch (_: Throwable) {
                    null
                }
                if (pi == null) {
                    mainExecutor.execute { result.success(false) }
                    return@Thread
                }
                pendingDeleteResult = result
                mainExecutor.execute {
                    try {
                        startIntentSenderForResult(
                            pi.intentSender,
                            deleteRequestCode,
                            null,
                            0,
                            0,
                            0
                        )
                    } catch (_: Throwable) {
                        val r = pendingDeleteResult
                        pendingDeleteResult = null
                        r?.success(false)
                    }
                }
            } else {
                // Android 10-: tek tek (eski cihazlarda nadiren çoklu).
                var okCount = 0
                for (u in uris) {
                    try {
                        if (contentResolver.delete(u, null, null) > 0) okCount++
                    } catch (_: Throwable) {
                    }
                }
                mainExecutor.execute { result.success(okCount == uris.size) }
            }
        }.start()
    }

    private fun deletePhoneFile(path: String, result: MethodChannel.Result) {
        Thread {
            var fileGone = false
            try {
                val f = File(path)
                if (f.exists()) {
                    try {
                        fileGone = f.delete()
                    } catch (_: Throwable) {
                    }
                } else {
                    fileGone = true
                }
            } catch (_: Throwable) {
            }
            try {
                val uri = queryAudioUri(path)
                if (uri != null) {
                    if (Build.VERSION.SDK_INT >= 30) {
                        val pi = MediaStore.createDeleteRequest(contentResolver, listOf(uri))
                        pendingDeleteResult = result
                        mainExecutor.execute {
                            try {
                                startIntentSenderForResult(
                                    pi.intentSender,
                                    deleteRequestCode,
                                    null,
                                    0,
                                    0,
                                    0
                                )
                            } catch (_: Throwable) {
                                val r = pendingDeleteResult
                                pendingDeleteResult = null
                                r?.success(fileGone)
                            }
                        }
                        return@Thread
                    } else {
                        // v5.1.1: Android 10 (API 29) — createDeleteRequest
                        // yok; RecoverableSecurityException akışı kullanılır.
                        var deletedN = 0
                        try {
                            deletedN = contentResolver.delete(uri, null, null)
                        } catch (e: RecoverableSecurityException) {
                            pendingDeleteUri = uri
                            pendingDeleteResult = result
                            mainExecutor.execute {
                                try {
                                    startIntentSenderForResult(
                                        e.userAction.actionIntent.intentSender,
                                        deleteRequestCode,
                                        null,
                                        0,
                                        0,
                                        0
                                    )
                                } catch (_: Throwable) {
                                    pendingDeleteUri = null
                                    val r = pendingDeleteResult
                                    pendingDeleteResult = null
                                    r?.success(false)
                                }
                            }
                            return@Thread
                        } catch (_: Throwable) {
                            deletedN = 0
                        }
                        val ok = deletedN > 0 || fileGone
                        mainExecutor.execute { result.success(ok) }
                        return@Thread
                    }
                }
            } catch (_: Throwable) {
            }
            if (fileGone) {
                try {
                    MediaScannerConnection.scanFile(this, arrayOf(path), null, null)
                } catch (_: Throwable) {
                }
            }
            mainExecutor.execute { result.success(fileGone) }
        }.start()
    }

    /**
     * ID3 yazımı: asıl dosyayı asla Dart/File.copy ile ezme.
     * openOutputStream("w") dosyayı hemen boşaltır — yalnızca tam
     * etiketli tampon hazır ve (Android 10+) yazma izni alındıktan sonra.
     * Yazım yarıda kalırsa yedekten geri yüklenir.
     */
    private fun writeViaUri(uri: Uri, src: File): Boolean {
        if (!src.exists() || src.length() < 128L) return false
        val bak = File(cacheDir, "id3_bak_${System.currentTimeMillis()}.mp3")
        try {
            contentResolver.openInputStream(uri)?.use { inp ->
                bak.outputStream().use { inp.copyTo(it) }
            }
        } catch (_: Throwable) {
        }
        val expected = src.length()
        var wrote = false
        try {
            contentResolver.openOutputStream(uri, "w")?.use { os ->
                src.inputStream().buffered().use { it.copyTo(os) }
                os.flush()
            }
            wrote = true
        } catch (e: RecoverableSecurityException) {
            restoreBackup(uri, bak)
            try { bak.delete() } catch (_: Throwable) {}
            throw e
        } catch (_: Throwable) {
            wrote = false
        }
        if (!wrote) {
            restoreBackup(uri, bak)
            try { bak.delete() } catch (_: Throwable) {}
            return false
        }
        try { bak.delete() } catch (_: Throwable) {}
        return expected >= 128L
    }

    private fun restoreBackup(uri: Uri, bak: File) {
        if (!bak.exists() || bak.length() < 128L) return
        try {
            contentResolver.openOutputStream(uri, "w")?.use { os ->
                bak.inputStream().use { it.copyTo(os) }
                os.flush()
            }
        } catch (_: Throwable) {
        }
    }

    private fun writeAudioFile(
        dest: String,
        src: String,
        title: String?,
        artist: String?,
        album: String?,
        result: MethodChannel.Result
    ) {
        Thread {
            val srcF = File(src)
            val destF = File(dest)
            if (!srcF.exists() || srcF.length() < 128L) {
                mainExecutor.execute { result.success(false) }
                return@Thread
            }
            val appOwned = dest.startsWith(filesDir.absolutePath) ||
                dest.startsWith(cacheDir.absolutePath) ||
                // v5.1.3: "Tüm dosyalara erişim" verilmişse doğrudan yaz.
                (Build.VERSION.SDK_INT >= 30 &&
                    Environment.isExternalStorageManager())
            if (appOwned) {
                var ok = false
                try {
                    srcF.copyTo(destF, overwrite = true)
                    // v5.1.3: TAM eşitlik — kopya kaynakla birebir aynı
                    // olmalı. Eskiden %90 boyut tablosuydu; yeniden yazım
                    // dosyayı küçültüyorsa BAŞARILI yazım başarısız sanılıyordu.
                    ok = destF.length() == srcF.length()
                } catch (_: Throwable) {
                    ok = false
                }
                if (ok) {
                    scanAndTag(dest, title, artist, album)
                    mainExecutor.execute { result.success(true) }
                    return@Thread
                }
                // v5.1.3: doğrudan yazma başarısızsa vazgeçme — aşağıdaki
                // MediaStore yolunu da dene (izni açık olsa bile bazı
                // yollar FUSE üzerinden reddedilebiliyor).
            }
            // v5.1.3: MediaStore henüz bilmeyebilir — bir tara, tekrar sor.
            var uri = queryAudioUri(dest)
            if (uri == null) {
                try {
                    MediaScannerConnection.scanFile(this, arrayOf(dest), null, null)
                    Thread.sleep(500)
                    uri = queryAudioUri(dest)
                } catch (_: Throwable) {
                }
            }
            if (uri == null) {
                mainExecutor.execute { result.success(false) }
                return@Thread
            }
            // v5.1.3: "Tüm dosyalara erişim" VERİLMİŞSE kullanıcıya dosya
            // onay diyalogu gösterme — URI ile doğrudan yaz (yedekli).
            // createWriteRequest yalnız izin yoksa son çaredir.
            if (Build.VERSION.SDK_INT >= 30 && Environment.isExternalStorageManager()) {
                try {
                    if (writeViaUri(uri, srcF)) {
                        scanAndTag(dest, title, artist, album)
                        mainExecutor.execute { result.success(true) }
                        return@Thread
                    }
                } catch (_: Throwable) {
                }
            }
            if (Build.VERSION.SDK_INT >= 30) {
                try {
                    val pi = MediaStore.createWriteRequest(contentResolver, listOf(uri))
                    pendingWriteResult = result
                    pendingWriteSrc = src
                    pendingWriteDest = dest
                    pendingWriteTitle = title
                    pendingWriteArtist = artist
                    pendingWriteAlbum = album
                    mainExecutor.execute {
                        try {
                            startIntentSenderForResult(
                                pi.intentSender,
                                writeRequestCode,
                                null,
                                0,
                                0,
                                0
                            )
                        } catch (_: Throwable) {
                            val r = pendingWriteResult
                            pendingWriteResult = null
                            r?.success(false)
                        }
                    }
                    return@Thread
                } catch (_: Throwable) {
                }
            }
            var ok = false
            try {
                ok = writeViaUri(uri, srcF)
            } catch (e: RecoverableSecurityException) {
                if (Build.VERSION.SDK_INT >= 26) {
                    pendingWriteResult = result
                    pendingWriteSrc = src
                    pendingWriteDest = dest
                    pendingWriteTitle = title
                    pendingWriteArtist = artist
                    pendingWriteAlbum = album
                    mainExecutor.execute {
                        try {
                            startIntentSenderForResult(
                                e.userAction.actionIntent.intentSender,
                                writeRequestCode,
                                null,
                                0,
                                0,
                                0
                            )
                        } catch (_: Throwable) {
                            val r = pendingWriteResult
                            pendingWriteResult = null
                            r?.success(false)
                        }
                    }
                    return@Thread
                }
            } catch (_: Throwable) {
            }
            if (ok) scanAndTag(dest, title, artist, album)
            mainExecutor.execute { result.success(ok) }
        }.start()
    }

    private fun scanAndTag(dest: String, title: String?, artist: String?, album: String?) {
        try {
            MediaScannerConnection.scanFile(this, arrayOf(dest), null, null)
        } catch (_: Throwable) {
        }
        val uri = queryAudioUri(dest) ?: return
        if (title.isNullOrBlank() && artist.isNullOrBlank() && album.isNullOrBlank()) return
        try {
            val cv = ContentValues()
            if (!title.isNullOrBlank()) cv.put(MediaStore.Audio.Media.TITLE, title)
            if (!artist.isNullOrBlank()) cv.put(MediaStore.Audio.Media.ARTIST, artist)
            if (!album.isNullOrBlank()) cv.put(MediaStore.Audio.Media.ALBUM, album)
            if (cv.size() > 0) contentResolver.update(uri, cv, null, null)
        } catch (_: Throwable) {
        }
    }

    private fun finishPendingWrite(granted: Boolean) {
        val r = pendingWriteResult
        val src = pendingWriteSrc
        val dest = pendingWriteDest
        val title = pendingWriteTitle
        val artist = pendingWriteArtist
        val album = pendingWriteAlbum
        pendingWriteResult = null
        pendingWriteSrc = null
        pendingWriteDest = null
        pendingWriteTitle = null
        pendingWriteArtist = null
        pendingWriteAlbum = null
        if (!granted || r == null || src == null || dest == null) {
            r?.success(false)
            return
        }
        Thread {
            val srcF = File(src)
            val uri = queryAudioUri(dest)
            val ok = try {
                if (uri != null) writeViaUri(uri, srcF) else false
            } catch (_: Throwable) {
                false
            }
            if (ok) scanAndTag(dest, title, artist, album)
            mainExecutor.execute { r.success(ok) }
        }.start()
    }

    private fun queryAudioUri(path: String): Uri? {
        val candidates = linkedSetOf(path)
        if (path.startsWith("/sdcard/")) {
            candidates.add("/storage/emulated/0/" + path.removePrefix("/sdcard/"))
        }
        if (path.startsWith("/storage/emulated/0/")) {
            candidates.add("/sdcard/" + path.removePrefix("/storage/emulated/0/"))
        }
        for (cand in candidates) {
            try {
                contentResolver.query(
                    MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                    arrayOf(MediaStore.Audio.Media._ID),
                    "${MediaStore.Audio.Media.DATA} = ?",
                    arrayOf(cand),
                    null
                )?.use { c ->
                    if (c.moveToFirst()) {
                        return ContentUris.withAppendedId(
                            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                            c.getLong(0)
                        )
                    }
                }
            } catch (_: Throwable) {
            }
        }
        val name = File(path).name
        val parent = File(path).parentFile?.name ?: ""
        try {
            contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                arrayOf(
                    MediaStore.Audio.Media._ID,
                    MediaStore.Audio.Media.DATA,
                    MediaStore.Audio.Media.RELATIVE_PATH,
                    MediaStore.Audio.Media.DISPLAY_NAME
                ),
                "${MediaStore.Audio.Media.DISPLAY_NAME} = ?",
                arrayOf(name),
                null
            )?.use { c ->
                val idIdx = c.getColumnIndex(MediaStore.Audio.Media._ID)
                val dataIdx = c.getColumnIndex(MediaStore.Audio.Media.DATA)
                val relIdx = c.getColumnIndex(MediaStore.Audio.Media.RELATIVE_PATH)
                var fallback: Uri? = null
                var count = 0
                while (c.moveToNext()) {
                    count++
                    val id = c.getLong(idIdx)
                    val found = ContentUris.withAppendedId(
                        MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                        id
                    )
                    val data = if (dataIdx >= 0) c.getString(dataIdx) else null
                    val rel = if (relIdx >= 0) c.getString(relIdx) else null
                    val dataHit = data != null && (
                        candidates.contains(data) ||
                            (data.endsWith(name) && (parent.isEmpty() || data.contains(parent)))
                    )
                    val relHit = rel != null && path.contains(rel.trimEnd('/'))
                    if (dataHit || relHit) return found
                    fallback = found
                }
                if (count == 1) return fallback
            }
        } catch (_: Throwable) {
        }
        return null
    }

    /** Media3 MediaController ile servise bağlanır; bağlanınca EQ motorunu
     * oyuncunun ses kanalına takar. */
    private fun connectController() {
        if (controller != null) {
            flushConnects(true)
            pushState(includeQueue = true)
            return
        }
        if (connecting) return
        connecting = true
        val token = SessionToken(this, ComponentName(this, PlaybackService::class.java))
        val future = MediaController.Builder(this, token).buildAsync()
        future.addListener({
            try {
                val c = future.get()
                controller = c
                c.addListener(playerListener)
                flushConnects(true)
            } catch (t: Throwable) {
                controller = null
                flushConnects(false)
            }
            connecting = false
            pushState(includeQueue = true)
        }, mainExecutor)
    }

    private fun flushConnects(ok: Boolean) {
        val list = pendingConnects.toList()
        pendingConnects.clear()
        for (r in list) {
            try {
                r.success(ok)
            } catch (_: Throwable) {
            }
        }
    }

    private fun pushRhythm() {
        val sink = rhythmSink ?: return
        if (!resumed) return // ekran/uygulama arkada: pil dostu uyku
        val map = HashMap<String, Any?>()
        map["level"] = RhythmBus.level.toDouble()
        map["bass"] = RhythmBus.bass.toDouble()
        map["playing"] = RhythmBus.playing
        try {
            sink.success(map)
        } catch (_: Throwable) {
        }
    }

    private fun pushState(includeQueue: Boolean = false) {
        val sink = events ?: return
        val c = controller
        val map = HashMap<String, Any?>()
        map["connected"] = c != null
        map["isPlaying"] = c?.isPlaying ?: false
        map["playWhenReady"] = c?.playWhenReady ?: false
        map["playbackState"] = c?.playbackState ?: Player.STATE_IDLE
        map["error"] = c?.playerError?.message
        map["currentIndex"] = c?.currentMediaItemIndex ?: -1
        map["currentPath"] = c?.currentMediaItem?.mediaId
        map["currentTitle"] = c?.currentMediaItem?.mediaMetadata?.title?.toString()
        map["itemCount"] = try { c?.mediaItemCount ?: 0 } catch (_: Throwable) { 0 }
        map["positionMs"] = c?.currentPosition?.coerceAtLeast(0L) ?: 0L
        map["durationMs"] = (c?.duration ?: 0L).let { if (it > 0) it else 0L }
        map["shuffle"] = c?.shuffleModeEnabled ?: false
        map["repeat"] = c?.repeatMode ?: Player.REPEAT_MODE_ALL

        // DUZELTME: bu blok artik try-catch korumali (dosyanin her yerinde
        // zaten boyle). Hizli ardisik setMediaItems() cagrilarinda (spam
        // tiklama) controller'in zaman cizelgesi gecis halindeyken
        // mediaItemCount / getMediaItemAt() bir an icin tutarsiz olabiliyor;
        // korumasiz dongu bunu yakalayinca ana is parciginda yakalanmamis
        // istisna olusuyordu = sessiz cokme.
        val count = try { c?.mediaItemCount ?: 0 } catch (_: Throwable) { 0 }
        val sendQueue = includeQueue || count != lastPushedCount
        lastPushedCount = count
        if (sendQueue && count in 1..250) {
            val queue = ArrayList<HashMap<String, String>>()
            try {
                if (c != null) {
                    for (i in 0 until c.mediaItemCount) {
                        val mi = c.getMediaItemAt(i)
                        val item = HashMap<String, String>()
                        item["path"] = mi.mediaId
                        item["title"] = mi.mediaMetadata.title?.toString() ?: ""
                        queue.add(item)
                    }
                }
            } catch (_: Throwable) {
            }
            map["queue"] = queue
        }

        try {
            sink.success(map)
        } catch (_: Throwable) {
        }
    }

    private fun readCoverBytes(path: String): ByteArray? {
        return try {
            val f = File(path)
            if (!f.exists() || f.length() > 2 * 1024 * 1024) return null
            f.readBytes()
        } catch (_: Throwable) {
            null
        }
    }

    override fun onStart() {
        super.onStart()
        try {
            val filter = IntentFilter(PlaybackService.ACTION_FAVORITES_CHANGED)
            if (Build.VERSION.SDK_INT >= 33) {
                registerReceiver(favReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("DEPRECATION")
                registerReceiver(favReceiver, filter)
            }
        } catch (_: Throwable) {
        }
    }

    override fun onStop() {
        try {
            unregisterReceiver(favReceiver)
        } catch (_: Throwable) {
        }
        super.onStop()
    }

    override fun onResume() {
        super.onResume()
        resumed = true
    }

    override fun onPause() {
        resumed = false
        super.onPause()
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == deleteRequestCode) {
            val r = pendingDeleteResult
            val uri = pendingDeleteUri
            pendingDeleteResult = null
            pendingDeleteUri = null
            if (resultCode == Activity.RESULT_OK && r != null) {
                if (uri != null) {
                    // API 29 RSE akışı: izin verildi, silmeyi tekrar dene.
                    Thread {
                        var ok = false
                        try {
                            ok = contentResolver.delete(uri, null, null) > 0
                        } catch (_: Throwable) {
                        }
                        mainExecutor.execute { r.success(ok) }
                    }.start()
                } else {
                    // createDeleteRequest (API 30+): sistem zaten sildi.
                    r.success(true)
                }
            } else {
                r?.success(false)
            }
        } else if (requestCode == writeRequestCode) {
            finishPendingWrite(resultCode == Activity.RESULT_OK)
        }
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        try { io.shutdownNow() } catch (_: Throwable) {}
        try {
            LibraryScanService.stop(this)
        } catch (_: Throwable) {
        }
        controller?.removeListener(playerListener)
        controller?.release()
        controller = null
        super.onDestroy()
    }
}

