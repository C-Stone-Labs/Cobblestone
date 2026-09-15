package com.cobblestone.cobblestone

import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.FileDataSource
import androidx.media3.datasource.TransferListener
import java.io.File
import java.io.RandomAccessFile
import java.util.concurrent.ConcurrentHashMap

/**
 * MP3 başındaki ID3 etiketini okumadan atlar (FileDataSource final → sarmalayıcı).
 * JPEG 0xFFE0 karesini MPEG sanma: senkron taraması YOK, yalnız ID3 boyutu.
 */
@OptIn(UnstableApi::class)
class SkipId3DataSource : DataSource {

    private val inner = FileDataSource()

    override fun addTransferListener(transferListener: TransferListener) {
        inner.addTransferListener(transferListener)
    }

    override fun open(dataSpec: DataSpec): Long {
        try {
            inner.close()
        } catch (_: Throwable) {
        }
        var spec = dataSpec
        val path = dataSpec.uri.path
        val scheme = dataSpec.uri.scheme
        if (!path.isNullOrEmpty() && (scheme == null || scheme == "file")) {
            val skip = id3ByteLength(File(path))
            if (skip > 0) {
                spec = dataSpec.buildUpon().setPosition(dataSpec.position + skip).build()
            }
        }
        return inner.open(spec)
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int =
        inner.read(buffer, offset, length)

    override fun getUri(): Uri? = inner.getUri()

    override fun close() {
        inner.close()
    }

    class Factory : DataSource.Factory {
        override fun createDataSource(): DataSource = SkipId3DataSource()
    }

    companion object {
        private val cache = ConcurrentHashMap<String, Long>()

        fun id3ByteLength(file: File): Long {
            val key = try {
                file.canonicalPath + ":" + file.length() + ":" + file.lastModified()
            } catch (_: Throwable) {
                file.absolutePath
            }
            cache[key]?.let { return it }
            val skip = compute(file)
            cache[key] = skip
            return skip
        }

        private fun compute(file: File): Long {
            try {
                RandomAccessFile(file, "r").use { raf ->
                    val len = raf.length()
                    if (len < 10) return 0
                    var pos = 0L
                    val h = ByteArray(10)
                    while (pos + 10 < len) {
                        raf.seek(pos)
                        raf.readFully(h)
                        if (h[0] != 0x49.toByte() ||
                            h[1] != 0x44.toByte() ||
                            h[2] != 0x33.toByte()
                        ) {
                            break
                        }
                        val size =
                            ((h[6].toInt() and 0x7F) shl 21) or
                                ((h[7].toInt() and 0x7F) shl 14) or
                                ((h[8].toInt() and 0x7F) shl 7) or
                                (h[9].toInt() and 0x7F)
                        var total = 10L + size
                        if ((h[5].toInt() and 0x10) != 0) total += 10
                        if (total <= 0 || pos + total >= len) break
                        pos += total
                    }
                    return pos
                }
            } catch (_: Throwable) {
                return 0
            }
        }
    }
}
