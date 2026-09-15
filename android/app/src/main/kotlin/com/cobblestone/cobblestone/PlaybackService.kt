package com.cobblestone.cobblestone

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.ForwardingPlayer
import androidx.media3.common.Player
import androidx.media3.common.PlaybackException
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.extractor.mp3.Mp3Extractor
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.common.audio.SonicAudioProcessor
import androidx.media3.exoplayer.audio.TeeAudioProcessor
import androidx.media3.session.CommandButton
import androidx.media3.session.DefaultMediaNotificationProvider
import androidx.media3.session.LibraryResult
import androidx.media3.session.MediaLibraryService
import androidx.media3.session.MediaLibraryService.LibraryParams
import androidx.media3.session.MediaLibraryService.MediaLibrarySession
import androidx.media3.session.MediaSession
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionResult
import com.google.common.collect.ImmutableList
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import java.util.concurrent.Executors

private enum class NotificationButtonKind { FAV, PREV, PLAY, NEXT, CLOSE }

/**
 * Cobblestone yerli çalma servisi — MediaLibraryService (Android Auto +
 * bildirim + Samsung "son şarkıyı çal").
 */
class PlaybackService : MediaLibraryService() {

    private var mediaSession: MediaLibrarySession? = null
    private var exoPlayer: ExoPlayer? = null
    private val handler = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    // v5.1.1: art arda çalma hataları sayacı. Kuyruğun tamamı çalınamıyorsa
    // (SD kart çekildi / dosyalar taşındı) seekToNextMediaItem sonsuz
    // döngüye girip CPU + bildirim churn'i yaratıyordu. 5. hatada dur.
    private var consecutivePlayerErrors = 0
    @Volatile private var artSeq = 0L
    @Volatile private var applyingArt = false
    private val attachEqRunnable = Runnable {
        try {
            val id = exoPlayer?.audioSessionId ?: 0
            if (id > 0) EqEngine.attach(id)
        } catch (_: Throwable) {
        }
    }

    /** Sonraki: son parçada başa. Tekrarla-bir açıkken bile atla (Samsung). */
    @OptIn(UnstableApi::class)
    private class WrapQueuePlayer(private val exo: ExoPlayer) : ForwardingPlayer(exo) {
        override fun seekToNext() = wrapNext()
        override fun seekToNextMediaItem() = wrapNext()

        // v5.1.3: ileri oku HER ZAMAN göster — Media3, kuyruğun sonunda
        // komutu "kullanılamaz" sayıp düğmeyi gizliyor; yıldız ve çarpı
        // kayıp yer değiştirmiş gibi görünüyordu. Sonda basılırsa
        // wrapNext() kuyruğun başına sarar.
        override fun isCommandAvailable(command: Int): Boolean {
            if ((command == Player.COMMAND_SEEK_TO_NEXT ||
                 command == Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM) &&
                exo.mediaItemCount > 0
            ) {
                return true
            }
            return super.isCommandAvailable(command)
        }

        override fun getAvailableCommands(): Player.Commands {
            val base = super.getAvailableCommands()
            return if (exo.mediaItemCount > 0) {
                base.buildUpon()
                    .add(Player.COMMAND_SEEK_TO_NEXT)
                    .add(Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM)
                    .build()
            } else {
                base
            }
        }

        private fun wrapNext() {
            val n = exo.mediaItemCount
            if (n <= 0) return
            val mode = exo.repeatMode
            try {
                exo.repeatMode = Player.REPEAT_MODE_ALL
                if (exo.hasNextMediaItem()) {
                    exo.seekToNextMediaItem()
                } else {
                    exo.seekTo(0, 0L)
                }
                if (exo.playbackState == Player.STATE_IDLE) exo.prepare()
                exo.play()
            } catch (_: Throwable) {
            } finally {
                try {
                    exo.repeatMode = mode
                } catch (_: Throwable) {
                }
            }
        }
    }

    companion object {
        const val ACTION_CLOSE = "cobble.close"
        const val ACTION_FAVORITE = "cobble.favorite"
        const val ACTION_PLAY_FILE = "cobble.play_file"
        const val ACTION_TOGGLE = "cobble.toggle"
        const val EXTRA_PATH = "path"
        const val EXTRA_TITLE = "title"
        const val ACTION_FAVORITES_CHANGED = "com.cobblestone.cobblestone.FAVORITES_CHANGED"
        const val LAST_QUEUE_KEY = "flutter.last_queue_v1"

        @Volatile
        var instance: PlaybackService? = null
    }

    private val favPrefsListener =
        SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
            if (key == FavoritesStore.KEY_PATHS) {
                refreshLayout()
                try {
                    triggerNotificationUpdate()
                } catch (_: Throwable) {
                }
                try {
                    notifyLibrary()
                } catch (_: Throwable) {
                }
            }
        }

    @OptIn(UnstableApi::class)
    private fun buildPlayer(): ExoPlayer {
        val extractors = DefaultExtractorsFactory()
            .setMp3ExtractorFlags(
                Mp3Extractor.FLAG_DISABLE_ID3_METADATA or
                    Mp3Extractor.FLAG_ENABLE_CONSTANT_BITRATE_SEEKING
            )
        val builder = ExoPlayer.Builder(this)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(C.USAGE_MEDIA)
                    .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                    .build(),
                /* handleAudioFocus= */ true
            )
            .setHandleAudioBecomingNoisy(true)
            .setWakeMode(C.WAKE_MODE_LOCAL)
            // Auto / direksiyon: 3 sn'den sonra önceki = başa sar (Media3 varsayılanı).
            .setMaxSeekToPreviousPositionMs(3_000L)
            .setMediaSourceFactory(
                DefaultMediaSourceFactory(SkipId3DataSource.Factory(), extractors)
            )
            .setLoadControl(
                DefaultLoadControl.Builder()
                    .setBufferDurationsMs(2_500, 12_000, 80, 200)
                    .build()
            )
        val player = try {
            val renderers = object : DefaultRenderersFactory(this) {
                override fun buildAudioSink(
                    context: Context,
                    enableFloatOutput: Boolean,
                    enableAudioTrackPlaybackParams: Boolean
                ): AudioSink? {
                    return DefaultAudioSink.Builder(context)
                        .setAudioProcessors(
                            arrayOf(
                                EqEngine.processor,
                                SonicAudioProcessor(),
                                TeeAudioProcessor(MeterSink())
                            )
                        )
                        .build()
                }
            }
            builder.setRenderersFactory(renderers).build()
        } catch (t: Throwable) {
            builder.build()
        }
        try {
            player.repeatMode = Player.REPEAT_MODE_ALL
        } catch (_: Throwable) {
        }
        return player
    }

    @OptIn(UnstableApi::class)
    override fun onCreate() {
        super.onCreate()
        instance = this
        NativeLog.appContext = applicationContext
        NativeLog.log("service:onCreate")
        try {
            setShowNotificationForIdlePlayer(SHOW_NOTIFICATION_FOR_IDLE_PLAYER_NEVER)
        } catch (_: Throwable) {
        }
        try {
            FavoritesStore.registerListener(this, favPrefsListener)
        } catch (_: Throwable) {
        }
        val exo = buildPlayer()
        exoPlayer = exo
        val player: Player = WrapQueuePlayer(exo)
        try {
            EqEngine.attach(exo.audioSessionId)
        } catch (_: Throwable) {
        }
        player.addListener(object : Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                NativeLog.log("isPlaying=" + isPlaying)
                RhythmBus.playing = isPlaying
                try {
                    getSharedPreferences("cobble_native", Context.MODE_PRIVATE)
                        .edit().putBoolean("playing", isPlaying).apply()
                } catch (_: Throwable) {
                }
                if (!isPlaying) {
                    RhythmBus.level = 0f
                    RhythmBus.bass = 0f
                    try {
                        LastQueueStore.save(this@PlaybackService, player)
                    } catch (_: Throwable) {
                    }
                }
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                NativeLog.log("playbackState=" + playbackState)
                if (playbackState == Player.STATE_READY) {
                    consecutivePlayerErrors = 0
                    handler.removeCallbacks(attachEqRunnable)
                    handler.postDelayed(attachEqRunnable, 280)
                    refreshCurrentArtwork(player)
                }
            }

            override fun onMediaItemTransition(
                mediaItem: MediaItem?,
                reason: Int
            ) {
                consecutivePlayerErrors = 0
                if (applyingArt) return
                refreshLayout()
                refreshCurrentArtwork(player)
            }

            override fun onPlayerError(error: PlaybackException) {
                consecutivePlayerErrors++
                NativeLog.log(
                    "playerError=$consecutivePlayerErrors " +
                        error.errorCodeName + ":" + (error.message ?: "")
                )
                if (consecutivePlayerErrors >= 5) {
                    // Kuyruğun tamamı çalınamıyor: daha fazla atlama yapma.
                    NativeLog.log("playerErrorTooMany:pausing")
                    try {
                        player.pause()
                    } catch (_: Throwable) {
                    }
                    return
                }
                try {
                    player.seekToNextMediaItem()
                } catch (t: Throwable) {
                    NativeLog.log("playerErrorRecoveryFailed=" + (t.message ?: ""))
                }
            }
        })

        val launch = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                Intent.FLAG_ACTIVITY_NEW_TASK
            putExtra("cobble_from_player", true)
        }
        val sessionActivity = PendingIntent.getActivity(
            this,
            0,
            launch,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val callback = CobbleLibraryCallback()
        val session = MediaLibrarySession.Builder(this, player, callback)
            .setId("cobble.library")
            .setSessionActivity(sessionActivity)
            .build()

        session.setCustomLayout(buildLayout(player.currentMediaItem?.mediaId))
        mediaSession = session

        val notif = CobbleNotificationProvider(this)
        try {
            notif.setSmallIcon(R.drawable.ic_stat_cobble)
        } catch (_: Throwable) {
        }
        setMediaNotificationProvider(notif)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_TOGGLE -> togglePlayback()
            ACTION_PLAY_FILE -> {
                val path = intent.getStringExtra(EXTRA_PATH)
                if (!path.isNullOrBlank()) playFileNow(path, intent.getStringExtra(EXTRA_TITLE))
            }
            Intent.ACTION_MEDIA_BUTTON -> {
                val p = mediaSession?.player
                if (p != null && p.mediaItemCount <= 0) restoreLastQueueIfAny(p)
            }
        }
        return super.onStartCommand(intent, flags, startId)
    }

    @OptIn(UnstableApi::class)
    private inner class CobbleLibraryCallback : MediaLibrarySession.Callback {

        @OptIn(UnstableApi::class)
        override fun onConnect(
            session: MediaSession,
            controller: MediaSession.ControllerInfo
        ): MediaSession.ConnectionResult {
            val commands = MediaSession.ConnectionResult.DEFAULT_SESSION_AND_LIBRARY_COMMANDS
                .buildUpon()
                .add(SessionCommand(ACTION_FAVORITE, Bundle.EMPTY))
                .add(SessionCommand(ACTION_CLOSE, Bundle.EMPTY))
                .build()
            return MediaSession.ConnectionResult.AcceptedResultBuilder(session)
                .setAvailableSessionCommands(commands)
                .build()
        }

        override fun onCustomCommand(
            session: MediaSession,
            controller: MediaSession.ControllerInfo,
            customCommand: SessionCommand,
            args: Bundle
        ): ListenableFuture<SessionResult> {
            if (customCommand.customAction == ACTION_CLOSE) {
                closeEverything(session.player)
            } else if (customCommand.customAction == ACTION_FAVORITE) {
                toggleFavoriteForCurrent(session.player)
            }
            return Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
        }

        override fun onPlayerCommandRequest(
            session: MediaSession,
            controller: MediaSession.ControllerInfo,
            playerCommand: Int
        ): Int {
            // COMMAND_STOP Auto/Bluetooth'tan da gelir — kuyruğu öldürme.
            if (playerCommand == Player.COMMAND_PLAY_PAUSE ||
                playerCommand == Player.COMMAND_PREPARE ||
                playerCommand == Player.COMMAND_SEEK_TO_NEXT ||
                playerCommand == Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM ||
                playerCommand == Player.COMMAND_SEEK_TO_PREVIOUS ||
                playerCommand == Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM
            ) {
                val p = session.player
                if (p.mediaItemCount <= 0) restoreLastQueueIfAny(p)
            }
            return SessionResult.RESULT_SUCCESS
        }

        override fun onPlaybackResumption(
            session: MediaSession,
            controller: MediaSession.ControllerInfo
        ): ListenableFuture<MediaSession.MediaItemsWithStartPosition> {
            return try {
                val loaded = loadLastQueueItems()
                if (loaded != null) {
                    Futures.immediateFuture(loaded)
                } else {
                    val songs = BrowseTree.resolvePlayable(this@PlaybackService, BrowseTree.SONGS)
                    Futures.immediateFuture(
                        MediaSession.MediaItemsWithStartPosition(songs, 0, 0L)
                    )
                }
            } catch (t: Throwable) {
                NativeLog.log("resumptionFailed=" + (t.message ?: ""))
                Futures.immediateFuture(
                    MediaSession.MediaItemsWithStartPosition(emptyList(), 0, 0L)
                )
            }
        }

        override fun onAddMediaItems(
            session: MediaSession,
            controller: MediaSession.ControllerInfo,
            mediaItems: MutableList<MediaItem>
        ): ListenableFuture<MutableList<MediaItem>> {
            val search = mediaItems.firstOrNull()?.requestMetadata?.searchQuery
            if (!search.isNullOrBlank()) {
                return Futures.immediateFuture(ArrayList(searchToItems(search)))
            }
            val fromApp = controller.packageName == packageName
            val out = ArrayList<MediaItem>()
            for (mi in mediaItems) {
                val id = mi.mediaId
                if (id.isNullOrEmpty()) continue
                if (fromApp && !BrowseTree.isBrowsableId(id)) {
                    out.add(mi)
                } else {
                    out.addAll(BrowseTree.resolvePlayable(this@PlaybackService, id))
                }
            }
            return Futures.immediateFuture(out)
        }

        override fun onSetMediaItems(
            session: MediaSession,
            controller: MediaSession.ControllerInfo,
            mediaItems: MutableList<MediaItem>,
            startIndex: Int,
            startPositionMs: Long
        ): ListenableFuture<MediaSession.MediaItemsWithStartPosition> {
            val search = mediaItems.firstOrNull()?.requestMetadata?.searchQuery
            if (!search.isNullOrBlank()) {
                val items = searchToItems(search)
                return Futures.immediateFuture(
                    MediaSession.MediaItemsWithStartPosition(items, 0, 0L)
                )
            }
            val fromApp = controller.packageName == packageName
            // Auto tek şarkı gönderince albüm/liste kuyruğunu doldur.
            // Uygulama kendi kuyruğunu zaten gönderiyor — şişirme (çift kuyruk + çökme).
            if (!fromApp && mediaItems.size == 1) {
                val id = mediaItems[0].mediaId
                if (!id.isNullOrEmpty()) {
                    val req = BrowseTree.resolveQueue(this@PlaybackService, id)
                    val idx = if (req.items.isEmpty()) 0
                    else req.index.coerceIn(0, req.items.size - 1)
                    return Futures.immediateFuture(
                        MediaSession.MediaItemsWithStartPosition(
                            req.items,
                            idx,
                            startPositionMs.coerceAtLeast(0L)
                        )
                    )
                }
            }
            val out = ArrayList<MediaItem>()
            for (mi in mediaItems) {
                val id = mi.mediaId
                if (id.isNullOrEmpty()) continue
                if (fromApp && !BrowseTree.isBrowsableId(id)) {
                    out.add(mi)
                } else {
                    out.addAll(BrowseTree.resolvePlayable(this@PlaybackService, id))
                }
            }
            val idx = if (out.isEmpty()) 0 else startIndex.coerceIn(0, out.size - 1)
            return Futures.immediateFuture(
                MediaSession.MediaItemsWithStartPosition(out, idx, startPositionMs)
            )
        }

        private fun searchToItems(query: String): List<MediaItem> {
            val hits = BrowseTree.search(this@PlaybackService, query)
            if (hits.isEmpty()) {
                return BrowseTree.resolvePlayable(this@PlaybackService, BrowseTree.SONGS)
            }
            return hits.mapIndexed { i, mi ->
                CobbleMedia.item(
                    this@PlaybackService,
                    mi.mediaId,
                    mi.mediaMetadata.title?.toString(),
                    mi.mediaMetadata.artist?.toString(),
                    mi.mediaMetadata.albumTitle?.toString(),
                    artBytes = i == 0
                )
            }
        }

        override fun onGetLibraryRoot(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            params: LibraryParams?
        ): ListenableFuture<LibraryResult<MediaItem>> {
            val extras = Bundle().apply {
                putBoolean("android.media.browse.SEARCH_SUPPORTED", true)
                putBoolean("android.media.browse.CONTENT_STYLE_SUPPORTED", true)
                putInt("android.media.browse.CONTENT_STYLE_BROWSABLE_HINT", 2)
                putInt("android.media.browse.CONTENT_STYLE_PLAYABLE_HINT", 1)
            }
            val outParams = LibraryParams.Builder()
                .setExtras(extras)
                .setRecent(params?.isRecent == true)
                .build()
            val item = if (params?.isRecent == true) {
                BrowseTree.item(this@PlaybackService, BrowseTree.RECENT)
                    ?: BrowseTree.rootItem(this@PlaybackService)
            } else {
                BrowseTree.rootItem(this@PlaybackService)
            }
            return Futures.immediateFuture(LibraryResult.ofItem(item, outParams))
        }

        override fun onGetChildren(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            parentId: String,
            page: Int,
            pageSize: Int,
            params: LibraryParams?
        ): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> {
            var all = BrowseTree.children(this@PlaybackService, parentId)
            if (parentId == BrowseTree.ROOT) {
                val limit = params?.extras?.getInt(
                    "android.media.browse.extra.ROOT_CHILDREN_LIMIT",
                    0
                ) ?: 0
                if (limit > 0 && all.size > limit) {
                    all = all.take(limit)
                }
            }
            val from = (page * pageSize).coerceAtLeast(0)
            val slice = if (from >= all.size) emptyList()
            else all.subList(from, minOf(all.size, from + pageSize.coerceAtLeast(1)))
            return Futures.immediateFuture(
                LibraryResult.ofItemList(ImmutableList.copyOf(slice), params)
            )
        }

        override fun onGetItem(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            mediaId: String
        ): ListenableFuture<LibraryResult<MediaItem>> {
            val item = BrowseTree.item(this@PlaybackService, mediaId)
                ?: return Futures.immediateFuture(
                    LibraryResult.ofError(LibraryResult.RESULT_ERROR_BAD_VALUE)
                )
            return Futures.immediateFuture(LibraryResult.ofItem(item, null))
        }

        override fun onSearch(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            query: String,
            params: LibraryParams?
        ): ListenableFuture<LibraryResult<Void>> {
            val n = BrowseTree.search(this@PlaybackService, query).size
            session.notifySearchResultChanged(browser, query, n, params)
            return Futures.immediateFuture(LibraryResult.ofVoid(params))
        }

        override fun onGetSearchResult(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            query: String,
            page: Int,
            pageSize: Int,
            params: LibraryParams?
        ): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> {
            val all = BrowseTree.search(this@PlaybackService, query)
            val from = (page * pageSize).coerceAtLeast(0)
            val slice = if (from >= all.size) emptyList()
            else all.subList(from, minOf(all.size, from + pageSize.coerceAtLeast(1)))
            return Futures.immediateFuture(
                LibraryResult.ofItemList(ImmutableList.copyOf(slice), params)
            )
        }
    }

    private fun playFileNow(path: String, title: String?) {
        val p = mediaSession?.player ?: return
        try {
            val item = CobbleMedia.item(this, path, title, artBytes = true)
            p.setMediaItems(listOf(item), 0, 0L)
            p.prepare()
            p.play()
            LastQueueStore.save(this, p)
            NativeLog.log("playFileNow=" + path)
        } catch (t: Throwable) {
            NativeLog.log("playFileNowFailed=" + (t.message ?: ""))
        }
    }

    private fun togglePlayback() {
        val p = mediaSession?.player ?: return
        try {
            if (p.mediaItemCount <= 0) restoreLastQueueIfAny(p)
            if (p.mediaItemCount <= 0) {
                val songs = BrowseTree.resolvePlayable(this, BrowseTree.SONGS)
                if (songs.isEmpty()) return
                p.setMediaItems(songs, 0, 0L)
                p.prepare()
                p.play()
                LastQueueStore.save(this, p)
                return
            }
            if (p.isPlaying) {
                p.pause()
            } else {
                if (p.playbackState == Player.STATE_IDLE) p.prepare()
                p.play()
            }
        } catch (t: Throwable) {
            NativeLog.log("toggleFailed=" + (t.message ?: ""))
        }
    }

    fun refreshArtworkNow() {
        val p = mediaSession?.player ?: return
        refreshCurrentArtwork(p)
    }

    private fun refreshCurrentArtwork(player: Player) {
        val idx = player.currentMediaItemIndex
        val mi = try {
            if (idx < 0 || idx >= player.mediaItemCount) return
            player.getMediaItemAt(idx)
        } catch (_: Throwable) {
            return
        }
        val path = mi.mediaId ?: return
        val existing = mi.mediaMetadata.artworkData
        if (existing != null && existing.size > 32) return
        val seq = ++artSeq
        io.execute {
            try {
                if (seq != artSeq) return@execute
                val bytes = CoverResolver.jpegFor(this, path) ?: return@execute
                if (bytes.size < 33 || bytes.size > 400_000) return@execute
                if (seq != artSeq) return@execute
                handler.post {
                    if (seq != artSeq) return@post
                    try {
                        val cur = player.currentMediaItem ?: return@post
                        if (cur.mediaId != path) return@post
                        val already = cur.mediaMetadata.artworkData
                        if (already != null && already.size > 32) return@post
                        val newMeta = cur.mediaMetadata.buildUpon()
                            .setArtworkUri(CoverResolver.artUri(this, path))
                            .setArtworkData(bytes, MediaMetadata.PICTURE_TYPE_FRONT_COVER)
                            .build()
                        val i = player.currentMediaItemIndex
                        if (i < 0) return@post
                        applyingArt = true
                        try {
                            player.replaceMediaItem(
                                i,
                                cur.buildUpon().setMediaMetadata(newMeta).build()
                            )
                        } finally {
                            applyingArt = false
                        }
                    } catch (_: Throwable) {
                        applyingArt = false
                    }
                }
            } catch (_: Throwable) {
            }
        }
    }

    @OptIn(UnstableApi::class)
    private inner class CobbleNotificationProvider(
        context: Context
    ) : DefaultMediaNotificationProvider(context) {

        override fun getMediaButtons(
            session: MediaSession,
            playerCommands: Player.Commands,
            mediaButtonPreferences: ImmutableList<CommandButton>,
            showPauseButton: Boolean
        ): ImmutableList<CommandButton> {
            val kinds = ArrayList<NotificationButtonKind>()
            kinds.add(NotificationButtonKind.FAV)
            val hasPrev = playerCommands.containsAny(
                Player.COMMAND_SEEK_TO_PREVIOUS,
                Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM
            )
            val hasNext = playerCommands.containsAny(
                Player.COMMAND_SEEK_TO_NEXT,
                Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM
            )
            if (hasPrev) kinds.add(NotificationButtonKind.PREV)
            kinds.add(NotificationButtonKind.PLAY)
            if (hasNext) kinds.add(NotificationButtonKind.NEXT)
            kinds.add(NotificationButtonKind.CLOSE)

            val compact = ArrayList<Int>()
            for (i in kinds.indices) {
                if (kinds[i] == NotificationButtonKind.PREV ||
                    kinds[i] == NotificationButtonKind.PLAY ||
                    kinds[i] == NotificationButtonKind.NEXT
                ) {
                    compact.add(i)
                    if (compact.size == 3) break
                }
            }

            val currentPath = session.player.currentMediaItem?.mediaId
            val fav = isFavorite(currentPath)
            val buttons = ArrayList<CommandButton>()
            for (i in kinds.indices) {
                val extras = Bundle().apply {
                    val ci = compact.indexOf(i)
                    if (ci >= 0) {
                        putInt(DefaultMediaNotificationProvider.COMMAND_KEY_COMPACT_VIEW_INDEX, ci)
                    }
                }
                buttons.add(
                    when (kinds[i]) {
                        NotificationButtonKind.FAV -> CommandButton.Builder()
                            .setSessionCommand(SessionCommand(ACTION_FAVORITE, Bundle.EMPTY))
                            .setDisplayName(
                                if (fav) "Favorilerden Çıkar" else "Favorilere Ekle"
                            )
                            .setIconResId(if (fav) R.drawable.ic_star_filled else R.drawable.ic_star)
                            .setExtras(extras)
                            .build()

                        NotificationButtonKind.PREV -> prevButton(extras)
                        NotificationButtonKind.PLAY -> playPauseButton(showPauseButton, extras)
                        NotificationButtonKind.NEXT -> nextButton(extras)
                        NotificationButtonKind.CLOSE -> closeButton(extras)
                    }
                )
            }
            return ImmutableList.copyOf(buttons)
        }
    }

    private fun prevButton(extras: Bundle): CommandButton = CommandButton.Builder()
        .setDisplayName("Önceki")
        .setIconResId(R.drawable.ic_prev)
        .setPlayerCommand(Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM)
        .setExtras(extras)
        .build()

    private fun playPauseButton(showPause: Boolean, extras: Bundle): CommandButton =
        CommandButton.Builder()
            .setDisplayName(if (showPause) "Duraklat" else "Çal")
            .setIconResId(if (showPause) R.drawable.ic_pause else R.drawable.ic_play)
            .setPlayerCommand(Player.COMMAND_PLAY_PAUSE)
            .setExtras(extras)
            .build()

    private fun nextButton(extras: Bundle): CommandButton = CommandButton.Builder()
        .setDisplayName("Sonraki")
        .setIconResId(R.drawable.ic_next)
        .setPlayerCommand(Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM)
        .setExtras(extras)
        .build()

    private fun closeButton(extras: Bundle): CommandButton = CommandButton.Builder()
        .setSessionCommand(SessionCommand(ACTION_CLOSE, Bundle.EMPTY))
        .setDisplayName("Kapat")
        .setIconResId(R.drawable.ic_close)
        .setExtras(extras)
        .build()

    private fun loadLastQueueItems(): MediaSession.MediaItemsWithStartPosition? {
        val obj = LastQueueStore.load(this) ?: return null
        val arr = obj.optJSONArray("items") ?: return null
        val items = ArrayList<MediaItem>()
        val indexWanted = obj.optInt("index", 0)
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val path = o.optString("path")
            if (path.isEmpty()) continue
            items.add(
                CobbleMedia.item(
                    this,
                    path,
                    o.optString("title"),
                    o.optString("artist").ifBlank { null },
                    artBytes = i == indexWanted
                )
            )
        }
        if (items.isEmpty()) return null
        val index = indexWanted.coerceIn(0, items.size - 1)
        val positionMs = obj.optLong("positionMs", 0L).coerceAtLeast(0L)
        return MediaSession.MediaItemsWithStartPosition(items, index, positionMs)
    }

    private fun restoreLastQueueIfAny(player: Player) {
        try {
            if (player.mediaItemCount > 0) return
            val loaded = loadLastQueueItems() ?: return
            player.setMediaItems(loaded.mediaItems, loaded.startIndex, loaded.startPositionMs)
            player.prepare()
            NativeLog.log("lastQueueRestored=" + loaded.mediaItems.size)
        } catch (t: Throwable) {
            NativeLog.log("lastQueueRestoreFailed=" + (t.message ?: ""))
        }
    }

    private fun buildLayout(currentPath: String?): List<CommandButton> {
        // Play/prev/next Auto ve bildirimde zaten var. Özel düzen: ★ + çarpı (kapat).
        val fav = isFavorite(currentPath)
        val favoriteButton = CommandButton.Builder()
            .setSessionCommand(SessionCommand(ACTION_FAVORITE, Bundle.EMPTY))
            .setDisplayName(if (fav) "Favorilerden Çıkar" else "Favorilere Ekle")
            .setIconResId(if (fav) R.drawable.ic_star_filled else R.drawable.ic_star)
            .build()
        val close = CommandButton.Builder()
            .setSessionCommand(SessionCommand(ACTION_CLOSE, Bundle.EMPTY))
            .setDisplayName("Kapat")
            .setIconResId(R.drawable.ic_close)
            .build()
        return listOf(favoriteButton, close)
    }

    private fun refreshLayout() {
        val session = mediaSession ?: return
        try {
            val path = session.player.currentMediaItem?.mediaId
            session.setCustomLayout(buildLayout(path))
        } catch (_: Throwable) {
        }
    }

    private fun toggleFavoriteForCurrent(player: Player) {
        try {
            val path = player.currentMediaItem?.mediaId ?: return
            val nowFav = FavoritesStore.toggle(this, path)
            NativeLog.log("favoriteToggled=" + path + " now=" + nowFav)
        } catch (t: Throwable) {
            NativeLog.log("favoriteToggleFailed=" + (t.message ?: ""))
        }
        refreshLayout()
        try {
            triggerNotificationUpdate()
        } catch (_: Throwable) {
        }
        try {
            val paths = ArrayList(FavoritesStore.get(this))
            sendBroadcast(
                Intent(ACTION_FAVORITES_CHANGED)
                    .setPackage(packageName)
                    .putStringArrayListExtra("paths", paths)
            )
        } catch (_: Throwable) {
        }
    }

    private fun isFavorite(path: String?): Boolean = FavoritesStore.contains(this, path)

    private fun closeEverything(player: Player) {
        RhythmBus.playing = false
        RhythmBus.level = 0f
        RhythmBus.bass = 0f
        player.stop()
        player.clearMediaItems()
        try {
            getSharedPreferences("cobble_native", Context.MODE_PRIVATE)
                .edit().putBoolean("playing", false).apply()
        } catch (_: Throwable) {
        }
        stopSelf()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        val p = mediaSession?.player
        if (p == null || p.mediaItemCount <= 0) {
            super.onTaskRemoved(rootIntent)
            stopSelf()
            return
        }
        try {
            LastQueueStore.save(this, p)
        } catch (_: Throwable) {
        }
        // Duraklatılmış kuyruk kalsın: canlı bildirim AIMP gibi durur.
        // Kapatma yalnızca bildirim X / kaydırma / mini X.
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaLibrarySession? =
        mediaSession

    fun notifyLibrary() {
        try {
            LibraryStore.invalidate()
        } catch (_: Throwable) {
        }
        try {
            mediaSession?.notifyChildrenChanged(BrowseTree.ROOT, Int.MAX_VALUE, null)
            mediaSession?.notifyChildrenChanged(BrowseTree.SONGS, Int.MAX_VALUE, null)
            mediaSession?.notifyChildrenChanged(BrowseTree.ALBUMS, Int.MAX_VALUE, null)
            mediaSession?.notifyChildrenChanged(BrowseTree.ARTISTS, Int.MAX_VALUE, null)
            mediaSession?.notifyChildrenChanged(BrowseTree.FOLDERS, Int.MAX_VALUE, null)
            mediaSession?.notifyChildrenChanged(BrowseTree.PLAYLISTS, Int.MAX_VALUE, null)
            mediaSession?.notifyChildrenChanged(BrowseTree.FAVORITES, Int.MAX_VALUE, null)
            mediaSession?.notifyChildrenChanged(BrowseTree.SMART, Int.MAX_VALUE, null)
            mediaSession?.notifyChildrenChanged(BrowseTree.RECENT, Int.MAX_VALUE, null)
        } catch (_: Throwable) {
        }
    }

    override fun onDestroy() {
        artSeq++
        applyingArt = false
        try {
            FavoritesStore.unregisterListener(this, favPrefsListener)
        } catch (_: Throwable) {
        }
        if (instance === this) instance = null
        exoPlayer = null
        handler.removeCallbacksAndMessages(null)
        RhythmBus.playing = false
        mediaSession?.let { session ->
            session.player.release()
            session.release()
            mediaSession = null
        }
        EqEngine.release()
        try { io.shutdownNow() } catch (_: Throwable) {}
        super.onDestroy()
    }
}
