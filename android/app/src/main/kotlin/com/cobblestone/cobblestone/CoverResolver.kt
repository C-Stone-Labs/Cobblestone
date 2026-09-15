package com.cobblestone.cobblestone

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.drawable.BitmapDrawable
import android.net.Uri
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.RandomAccessFile
import java.util.concurrent.ConcurrentHashMap

/**
 * Bildirim / Auto / widget kapağı.
 * Öncelik: kullanıcı kapağı → ID3 APIC (önbellek) → ayardaki yedek (taş / nota).
 */
object CoverResolver {

    private val mem = ConcurrentHashMap<String, ByteArray>()
    private var stoneJpeg: ByteArray? = null
    private var noteJpeg: ByteArray? = null

    private val autoPackages = arrayOf(
        "com.google.android.projection.gearhead",
        "com.google.android.gms",
        "com.google.android.gms.car",
        "com.android.car",
        "com.google.android.apps.automotive.templates.host"
    )

    fun artUri(ctx: Context, path: String? = null): Uri {
        try {
            val jpeg = jpegFor(ctx, path)
            if (jpeg != null && jpeg.size > 32) {
                val key = if (path.isNullOrEmpty()) {
                    if (fallbackIsNote(ctx)) "fb_note" else "fb_stone"
                } else {
                    Integer.toHexString(stableSeedHash(path))
                }
                val dir = File(ctx.cacheDir, "notif_art")
                dir.mkdirs()
                val f = File(dir, "$key.jpg")
                if (!f.exists() || f.length() != jpeg.size.toLong()) {
                    f.writeBytes(jpeg)
                }
                return fileProviderUri(ctx, f)
            }
        } catch (_: Throwable) {
        }
        return fallbackResourceUri(ctx)
    }

    /**
     * Auto tarama listesi: APIC çıkarma yok (zaman aşımı olmasın).
     * Yalnızca önbellekteki kapak veya yedek kaynak URI.
     */
    fun browseArtUri(ctx: Context, path: String? = null): Uri {
        if (!path.isNullOrEmpty()) {
            try {
                val user = userCoverFile(ctx, path)
                if (user != null && user.exists() && user.length() > 32) {
                    return fileProviderUri(ctx, user)
                }
            } catch (_: Throwable) {
            }
            try {
                val cached = id3CacheFile(ctx, path)
                if (cached.exists() && cached.length() > 32) {
                    return fileProviderUri(ctx, cached)
                }
            } catch (_: Throwable) {
            }
        }
        return fallbackResourceUri(ctx)
    }

    private fun fallbackResourceUri(ctx: Context): Uri {
        val res = if (fallbackIsNote(ctx)) R.drawable.ic_music_note
        else R.drawable.notif_placeholder
        return Uri.parse("android.resource://${ctx.packageName}/$res")
    }

    private fun fileProviderUri(ctx: Context, file: File): Uri {
        val uri = FileProvider.getUriForFile(
            ctx,
            "${ctx.packageName}.fileprovider",
            file
        )
        grantAutoRead(ctx, uri)
        return uri
    }

    private fun grantAutoRead(ctx: Context, uri: Uri) {
        val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION
        for (pkg in autoPackages) {
            try {
                ctx.grantUriPermission(pkg, uri, flags)
            } catch (_: Throwable) {
            }
        }
    }

    fun fallbackIsNote(ctx: Context): Boolean =
        ctx.getSharedPreferences("cobble_native", Context.MODE_PRIVATE)
            .getString("fallback_art", "stone") == "note"

    fun setFallback(ctx: Context, mode: String) {
        val v = if (mode == "note") "note" else "stone"
        ctx.getSharedPreferences("cobble_native", Context.MODE_PRIVATE)
            .edit().putString("fallback_art", v).apply()
        mem.clear()
    }

    fun fallbackJpeg(ctx: Context): ByteArray? {
        return if (fallbackIsNote(ctx)) noteJpeg(ctx) else stoneJpeg(ctx)
    }

    fun jpegFor(ctx: Context, path: String?): ByteArray? {
        if (path.isNullOrEmpty()) return fallbackJpeg(ctx)
        mem[path]?.let { return it }
        try {
            val user = userCoverFile(ctx, path)
            if (user != null && user.exists() && user.length() > 32) {
                val b = compressFile(user) ?: user.readBytes()
                mem[path] = b
                return b
            }
        } catch (_: Throwable) {
        }
        try {
            val cached = id3CacheFile(ctx, path)
            if (cached.exists() && cached.length() > 32) {
                val b = cached.readBytes()
                mem[path] = b
                return b
            }
            val extracted = extractApic(File(path)) ?: extractMp4Cover(File(path))
            if (extracted != null && extracted.size > 32) {
                val jpeg = toJpeg(extracted) ?: extracted
                try {
                    cached.parentFile?.mkdirs()
                    cached.writeBytes(jpeg)
                } catch (_: Throwable) {
                }
                mem[path] = jpeg
                return jpeg
            }
        } catch (_: Throwable) {
        }
        return fallbackJpeg(ctx)
    }

    fun hasRealCover(ctx: Context, path: String?): Boolean {
        if (path.isNullOrEmpty()) return false
        try {
            val user = userCoverFile(ctx, path)
            if (user != null && user.exists() && user.length() > 32) return true
        } catch (_: Throwable) {
        }
        try {
            val cached = id3CacheFile(ctx, path)
            if (cached.exists() && cached.length() > 32) return true
            val extracted = extractApic(File(path)) ?: extractMp4Cover(File(path))
            if (extracted != null && extracted.size > 32) {
                try {
                    cached.parentFile?.mkdirs()
                    cached.writeBytes(toJpeg(extracted) ?: extracted)
                } catch (_: Throwable) {
                }
                return true
            }
        } catch (_: Throwable) {
        }
        return false
    }

    fun forget(path: String) {
        mem.remove(path)
    }

    // v5.1.3: Dart (path_provider) kapakları app_flutter/covers altında
    // tutuyor; Kotlin ise files/covers'a yazıyordu — iki taraf birbirinin
    // önbelleğini görmüyor, kapaklar iki kez çıkarılıyordu. Artık öncelikli
    // dizin Dart ile aynı; eskiler yalnız okuma için yedek.
    private fun coversDirs(ctx: Context): Array<File> {
        val appFlutter = File(ctx.filesDir.parentFile, "app_flutter/covers")
        val legacy1 = File(ctx.filesDir, "covers")
        val legacy2 = File(ctx.getDir("flutter", Context.MODE_PRIVATE), "covers")
        return arrayOf(appFlutter, legacy1, legacy2)
    }

    private fun userCoverFile(ctx: Context, path: String): File? {
        val hash = stableSeedHash(path).toString(16)
        val name = "user_${hash}_${path.length}.png"
        for (d in coversDirs(ctx)) {
            val f = File(d, name)
            if (f.exists()) return f
        }
        val primary = coversDirs(ctx).first()
        return File(primary, name)
    }

    private fun id3CacheFile(ctx: Context, path: String): File {
        val hash = stableSeedHash(path).toString(16)
        val name = "id3_${hash}_${path.length}.jpg"
        val dirs = coversDirs(ctx)
        for (d in dirs) {
            val f = File(d, name)
            if (f.exists()) return f
        }
        return File(dirs.first(), name)
    }

    private fun stableSeedHash(s: String): Int {
        var hash = 5381
        for (c in s) {
            hash = ((hash * 33) + c.code) and 0x7FFFFFFF
        }
        return hash
    }

    private fun stoneJpeg(ctx: Context): ByteArray? {
        stoneJpeg?.let { return it }
        stoneJpeg = drawableJpeg(ctx, R.drawable.notif_placeholder)
        return stoneJpeg
    }

    private fun noteJpeg(ctx: Context): ByteArray? {
        noteJpeg?.let { return it }
        noteJpeg = drawNoteJpeg()
            ?: drawableJpeg(ctx, R.drawable.ic_music_note, darkBg = true)
        return noteJpeg
    }

    /** Bildirimde okunaklı turuncu nota — 24dp vektör büyütülmez. */
    private fun drawNoteJpeg(): ByteArray? {
        return try {
            val size = 512
            val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val c = Canvas(bmp)
            c.drawColor(0xFF121212.toInt())
            val card = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = 0xFF1C1C1C.toInt()
            }
            val pad = 36f
            c.drawRoundRect(
                RectF(pad, pad, size - pad, size - pad),
                56f,
                56f,
                card
            )
            val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = 0x44E67A35
                style = Paint.Style.STROKE
                strokeWidth = 8f
            }
            c.drawRoundRect(
                RectF(pad, pad, size - pad, size - pad),
                56f,
                56f,
                ring
            )
            val orange = 0xFFE67A35.toInt()
            val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = orange
                style = Paint.Style.FILL
            }
            c.save()
            c.rotate(-20f, 214f, 348f)
            c.drawOval(RectF(128f, 292f, 300f, 404f), fill)
            c.restore()
            val stem = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = orange
                style = Paint.Style.STROKE
                strokeWidth = 30f
                strokeCap = Paint.Cap.ROUND
            }
            c.drawLine(284f, 338f, 284f, 118f, stem)
            val flag = Path()
            flag.moveTo(284f, 118f)
            flag.cubicTo(410f, 132f, 458f, 220f, 368f, 276f)
            flag.cubicTo(418f, 210f, 372f, 156f, 284f, 168f)
            flag.close()
            c.drawPath(flag, fill)
            val stream = ByteArrayOutputStream()
            bmp.compress(Bitmap.CompressFormat.JPEG, 90, stream)
            stream.toByteArray()
        } catch (_: Throwable) {
            null
        }
    }

    private fun drawableJpeg(ctx: Context, res: Int, darkBg: Boolean = false): ByteArray? {
        return try {
            val d = ContextCompat.getDrawable(ctx, res) ?: return null
            val bmp = if (d is BitmapDrawable && d.bitmap != null) {
                d.bitmap
            } else {
                val w = (d.intrinsicWidth.takeIf { it > 0 } ?: 256)
                val h = (d.intrinsicHeight.takeIf { it > 0 } ?: 256)
                val size = 256
                val out = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
                val c = Canvas(out)
                if (darkBg) c.drawColor(0xFF121212.toInt())
                val pad = if (darkBg) size / 5 else 0
                d.setBounds(pad, pad, size - pad, size - pad)
                d.draw(c)
                out
            }
            val stream = ByteArrayOutputStream()
            bmp.compress(Bitmap.CompressFormat.JPEG, 85, stream)
            stream.toByteArray()
        } catch (_: Throwable) {
            null
        }
    }

    private fun compressFile(f: File): ByteArray? {
        return try {
            val bmp = BitmapFactory.decodeFile(f.absolutePath) ?: return null
            val stream = ByteArrayOutputStream()
            val scaled = if (bmp.width > 512 || bmp.height > 512) {
                val s = 512f / maxOf(bmp.width, bmp.height)
                Bitmap.createScaledBitmap(
                    bmp,
                    (bmp.width * s).toInt().coerceAtLeast(1),
                    (bmp.height * s).toInt().coerceAtLeast(1),
                    true
                )
            } else bmp
            scaled.compress(Bitmap.CompressFormat.JPEG, 82, stream)
            stream.toByteArray()
        } catch (_: Throwable) {
            null
        }
    }

    private fun toJpeg(bytes: ByteArray): ByteArray? {
        return try {
            val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return bytes
            val stream = ByteArrayOutputStream()
            val scaled = if (bmp.width > 512 || bmp.height > 512) {
                val s = 512f / maxOf(bmp.width, bmp.height)
                Bitmap.createScaledBitmap(
                    bmp,
                    (bmp.width * s).toInt().coerceAtLeast(1),
                    (bmp.height * s).toInt().coerceAtLeast(1),
                    true
                )
            } else bmp
            scaled.compress(Bitmap.CompressFormat.JPEG, 82, stream)
            stream.toByteArray()
        } catch (_: Throwable) {
            bytes
        }
    }

    /** MP3 ID3v2 APIC karesini okur. v5.1.3: ID3v2.2 "PIC" de desteklenir. */
    fun extractApic(file: File): ByteArray? {
        if (!file.exists() || file.length() < 20) return null
        try {
            RandomAccessFile(file, "r").use { raf ->
                val h = ByteArray(10)
                raf.readFully(h)
                if (h[0] != 0x49.toByte() || h[1] != 0x44.toByte() || h[2] != 0x33.toByte()) {
                    return null
                }
                val ver = h[3].toInt() and 0xFF
                val tagSize = syncSafe(h, 6)
                val toRead = tagSize.coerceAtMost(8 * 1024 * 1024)
                val tag = ByteArray(toRead)
                raf.readFully(tag)
                var off = 0
                val v22 = ver == 2
                // Genişletilmiş başlık yalnız v2.3+ (v2.2'de bu bit sıkıştırma).
                if (!v22 && (h[5].toInt() and 0x40) != 0 && off + 4 <= tag.size) {
                    val ext = if (ver >= 4) syncSafe(tag, off) else u32(tag, off)
                    if (ext > 4) off += ext
                }
                if (v22) {
                    // ID3v2.2: 6 bayt kare başlığı — 3 harf ID + 3 bayt boyut.
                    while (off + 6 <= tag.size) {
                        if (tag[off] == 0.toByte()) break
                        val id = String(tag, off, 3, Charsets.ISO_8859_1)
                        val size = ((tag[off + 3].toInt() and 0xFF) shl 16) or
                            ((tag[off + 4].toInt() and 0xFF) shl 8) or
                            (tag[off + 5].toInt() and 0xFF)
                        if (size <= 0 || off + 6 + size > tag.size) break
                        if (id == "PIC") {
                            return picImage(tag.copyOfRange(off + 6, off + 6 + size))
                        }
                        off += 6 + size
                    }
                    return null
                }
                while (off + 10 <= tag.size) {
                    if (tag[off] == 0.toByte()) break
                    val id = String(tag, off, 4, Charsets.ISO_8859_1)
                    val size = if (ver >= 4) syncSafe(tag, off + 4) else u32(tag, off + 4)
                    if (size <= 0 || off + 10 + size > tag.size) break
                    if (id == "APIC") {
                        return apicImage(tag.copyOfRange(off + 10, off + 10 + size))
                    }
                    off += 10 + size
                }
            }
        } catch (_: Throwable) {
        }
        return null
    }

    /** ID3v2.2 PIC gövdesi: kodlama(1) + biçim(3) + tür(1) + açıklama + veri. */
    private fun picImage(f: ByteArray): ByteArray? {
        if (f.size < 6) return null
        val enc = f[0].toInt() and 0xFF
        var i = 5
        if (enc == 1 || enc == 2) {
            while (i + 1 < f.size && !(f[i] == 0.toByte() && f[i + 1] == 0.toByte())) i++
            i += 2
        } else {
            while (i < f.size && f[i] != 0.toByte()) i++
            i++
        }
        if (i >= f.size) return null
        for (s in i until minOf(f.size - 1, i + 24)) {
            val a = f[s].toInt() and 0xFF
            val b = f[s + 1].toInt() and 0xFF
            if (a == 0xFF && b == 0xD8) return f.copyOfRange(s, f.size)
            if (a == 0x89 && b == 0x50) return f.copyOfRange(s, f.size)
        }
        return f.copyOfRange(i, f.size)
    }

    // ── v5.1.3: MP4/M4A (iTunes stili) kapak desteği ──

    private fun mp4Atom(b: ByteArray, name: String, skip: Int = 0): ByteArray? {
        var off = skip
        while (off + 8 <= b.size) {
            val size = u32(b, off).toLong() and 0xFFFFFFFFL
            if (size < 8 || off + size > b.size) return null
            val t = String(b, off + 4, 4, Charsets.ISO_8859_1)
            if (t == name) return b.copyOfRange(off + 8, off + size.toInt())
            off += size.toInt()
        }
        return null
    }

    /** MP4/M4A: moov > udta > meta > ilst > covr > data yolunu izler. */
    fun extractMp4Cover(file: File): ByteArray? {
        if (!file.exists() || file.length() < 12) return null
        try {
            RandomAccessFile(file, "r").use { raf ->
                val len = raf.length()
                var pos = 0L
                while (pos + 8 <= len) {
                    raf.seek(pos)
                    val hdr = ByteArray(8)
                    raf.readFully(hdr)
                    var size = u32(hdr, 0).toLong() and 0xFFFFFFFFL
                    var headLen = 8L
                    if (size == 1L) {
                        val ext = ByteArray(8)
                        raf.readFully(ext)
                        size = ((u32(ext, 0).toLong() and 0xFFFFFFFFL) shl 32) or
                            (u32(ext, 4).toLong() and 0xFFFFFFFFL)
                        headLen = 16L
                    } else if (size == 0L) {
                        size = len - pos
                    }
                    if (size < headLen) return null
                    val type = String(hdr, 4, 4, Charsets.ISO_8859_1)
                    if (type == "moov") {
                        val want = minOf(size - headLen, 8L * 1024 * 1024).toInt()
                        val moov = ByteArray(want)
                        raf.readFully(moov)
                        // v5.1.3 düzeltme: meta'nın 4 bayt öneki gövdesinde;
                        // önce udta>meta bulunur, önek atlanıp ilst aranır.
                        var meta: ByteArray? = mp4Atom(moov, "meta")
                        val udta = mp4Atom(moov, "udta")
                        if (udta != null) {
                            val m = mp4Atom(udta, "meta")
                            if (m != null) meta = m
                        }
                        val m = meta ?: return null
                        if (m.size <= 12) return null
                        val ilst = mp4Atom(m.copyOfRange(4, m.size), "ilst") ?: return null
                        val covr = mp4Atom(ilst, "covr") ?: return null
                        val data = mp4Atom(covr, "data") ?: return null
                        if (data.size <= 8) return null
                        return data.copyOfRange(8, data.size)
                    }
                    pos += size
                }
            }
        } catch (_: Throwable) {
        }
        return null
    }

    private fun apicImage(f: ByteArray): ByteArray? {
        if (f.isEmpty()) return null
        val enc = f[0].toInt() and 0xFF
        var i = 1
        while (i < f.size && f[i] != 0.toByte()) i++
        i++ // mime end
        if (i >= f.size) return null
        i++ // picture type
        if (enc == 1 || enc == 2) {
            while (i + 1 < f.size && !(f[i] == 0.toByte() && f[i + 1] == 0.toByte())) i++
            i += 2
        } else {
            while (i < f.size && f[i] != 0.toByte()) i++
            i++
        }
        if (i >= f.size) return null
        for (s in i until minOf(f.size - 1, i + 24)) {
            val a = f[s].toInt() and 0xFF
            val b = f[s + 1].toInt() and 0xFF
            if (a == 0xFF && b == 0xD8) return f.copyOfRange(s, f.size)
            if (a == 0x89 && b == 0x50) return f.copyOfRange(s, f.size)
        }
        return f.copyOfRange(i, f.size)
    }

    private fun syncSafe(x: ByteArray, off: Int): Int =
        ((x[off].toInt() and 0x7F) shl 21) or
            ((x[off + 1].toInt() and 0x7F) shl 14) or
            ((x[off + 2].toInt() and 0x7F) shl 7) or
            (x[off + 3].toInt() and 0x7F)

    private fun u32(x: ByteArray, off: Int): Int =
        ((x[off].toInt() and 0xFF) shl 24) or
            ((x[off + 1].toInt() and 0xFF) shl 16) or
            ((x[off + 2].toInt() and 0xFF) shl 8) or
            (x[off + 3].toInt() and 0xFF)
}
