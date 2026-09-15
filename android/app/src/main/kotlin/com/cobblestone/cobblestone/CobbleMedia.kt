package com.cobblestone.cobblestone

import android.content.Context
import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.util.UnstableApi
import java.io.File

/**
 * Kuyruk öğesi. Kapak baytı her şarkıya basılmaz (Binder).
 * Çalan öğenin kapağı CoverResolver ile (gerçek APIC / kullanıcı / yedek).
 */
object CobbleMedia {

    fun artUri(ctx: Context): Uri = CoverResolver.artUri(ctx)

    fun jpegBytes(ctx: Context, path: String? = null): ByteArray? =
        CoverResolver.jpegFor(ctx, path)

    @OptIn(UnstableApi::class)
    fun item(
        ctx: Context,
        path: String,
        title: String?,
        artist: String? = null,
        album: String? = null,
        artBytes: Boolean = false
    ): MediaItem {
        val f = File(path)
        val t = title?.takeIf { it.isNotBlank() } ?: f.nameWithoutExtension
        return MediaItem.Builder()
            .setMediaId(path)
            .setUri(Uri.fromFile(f))
            .setMediaMetadata(
                MediaMetadata.Builder()
                    .setTitle(t)
                    .setArtist(artist?.takeIf { it.isNotBlank() } ?: "Bilinmeyen sanatçı")
                    .setAlbumTitle(album?.takeIf { it.isNotBlank() } ?: "Cobblestone")
                    .setIsPlayable(true)
                    .setIsBrowsable(false)
                    .setMediaType(MediaMetadata.MEDIA_TYPE_MUSIC)
                    .apply {
                        // Kuyruk öğelerinde APIC tarama yok (ana iş parçığı kilitlenmesin).
                        if (artBytes) {
                            setArtworkUri(CoverResolver.artUri(ctx, path))
                            val b = CoverResolver.jpegFor(ctx, path)
                            if (b != null && b.size in 33..400_000) {
                                setArtworkData(b, MediaMetadata.PICTURE_TYPE_FRONT_COVER)
                            }
                        } else {
                            setArtworkUri(CoverResolver.browseArtUri(ctx, path))
                        }
                    }
                    .build()
            )
            .build()
    }
}
