package com.cobblestone.cobblestone

import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin

/**
 * Yazılımsal 10 bantlı tepe EQ. Cihazın 5 bantlı sistem Equalizer'ına
 * bağlı değil — her telefonda aynı 10 kaydırıcı.
 */
@OptIn(UnstableApi::class)
class BiquadEqProcessor : BaseAudioProcessor() {

    companion object {
        val FREQS = intArrayOf(31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000)
        const val BANDS = 10
    }

    @Volatile var enabled: Boolean = false
    private val gainsDb = FloatArray(BANDS)
    @Volatile private var dirty = true
    private var sampleRate = 44100
    private var channels = 2
    private var filters: Array<Array<Biquad>> = emptyArray()

    @Synchronized
    fun setGainsMilliBel(levels: List<Int>?) {
        for (i in 0 until BANDS) {
            val mb = levels?.getOrNull(i) ?: 0
            gainsDb[i] = mb / 100f // millibel → dB
        }
        dirty = true
    }

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        if (inputAudioFormat.encoding != C.ENCODING_PCM_16BIT) {
            return AudioProcessor.AudioFormat.NOT_SET
        }
        sampleRate = inputAudioFormat.sampleRate
        channels = inputAudioFormat.channelCount
        rebuild()
        return inputAudioFormat
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val remaining = inputBuffer.remaining()
        if (remaining <= 0) return
        val bypass = !enabled || allFlat()
        if (bypass) {
            val out = replaceOutputBuffer(remaining)
            out.put(inputBuffer)
            out.flip()
            return
        }
        if (dirty) rebuild()
        val out = replaceOutputBuffer(remaining)
        val ch = channels.coerceAtLeast(1)
        while (inputBuffer.remaining() >= 2 * ch) {
            for (c in 0 until ch) {
                val sample = inputBuffer.short
                var x = sample / 32768.0
                val bank = filters.getOrNull(c)
                if (bank != null) {
                    for (b in bank) x = b.process(x)
                }
                val y = (x * 32768.0).coerceIn(-32768.0, 32767.0).toInt().toShort()
                out.putShort(y)
            }
        }
        out.flip()
    }

    override fun onFlush() {
        for (ch in filters) for (b in ch) b.reset()
    }

    override fun onReset() {
        filters = emptyArray()
        dirty = true
    }

    @Synchronized
    private fun allFlat(): Boolean {
        for (g in gainsDb) if (abs(g) >= 0.15f) return false
        return true
    }

    @Synchronized
    private fun rebuild() {
        val ch = channels.coerceAtLeast(1)
        if (filters.size != ch || filters.firstOrNull()?.size != BANDS) {
            filters = Array(ch) { Array(BANDS) { Biquad() } }
        }
        for (c in 0 until ch) {
            for (b in 0 until BANDS) {
                filters[c][b].peaking(sampleRate, FREQS[b].toDouble(), gainsDb[b].toDouble(), 1.0)
            }
        }
        dirty = false
    }

    private class Biquad {
        var b0 = 1.0
        var b1 = 0.0
        var b2 = 0.0
        var a1 = 0.0
        var a2 = 0.0
        var z1 = 0.0
        var z2 = 0.0

        fun reset() {
            z1 = 0.0
            z2 = 0.0
        }

        fun process(x: Double): Double {
            val y = b0 * x + z1
            z1 = b1 * x - a1 * y + z2
            z2 = b2 * x - a2 * y
            return y
        }

        fun peaking(fs: Int, f: Double, db: Double, q: Double) {
            reset()
            if (abs(db) < 0.08) {
                b0 = 1.0; b1 = 0.0; b2 = 0.0; a1 = 0.0; a2 = 0.0
                return
            }
            val nyquist = fs * 0.48
            val freq = f.coerceIn(20.0, nyquist)
            val A = 10.0.pow(db / 40.0)
            val w0 = 2.0 * PI * freq / fs
            val alpha = sin(w0) / (2.0 * q)
            val cosw = cos(w0)
            val b0n = 1 + alpha * A
            val b1n = -2 * cosw
            val b2n = 1 - alpha * A
            val a0n = 1 + alpha / A
            val a1n = -2 * cosw
            val a2n = 1 - alpha / A
            b0 = b0n / a0n
            b1 = b1n / a0n
            b2 = b2n / a0n
            a1 = a1n / a0n
            a2 = a2n / a0n
        }
    }
}
