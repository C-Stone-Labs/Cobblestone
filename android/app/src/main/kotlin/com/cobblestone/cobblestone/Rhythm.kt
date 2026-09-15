package com.cobblestone.cobblestone

import java.nio.ByteBuffer
import androidx.media3.common.C
import androidx.media3.exoplayer.audio.TeeAudioProcessor

/**
 * Nabız veri otobüsü. Servis ile MainActivity aynı süreçte yaşar;
 * ölçüm halkası (MeterSink) yazıyor, MainActivity okuyup Dart'a akıtıyor.
 * İzin gerektirmez: ses zaten bizim oyuncumuzun içinden geçiyor.
 *
 * v4.0.2 — AKICILIK DÜZENİ: ölçer artık yalnızca nabız ekranı AÇIKKEN
 * çalışır (sampling). Kapalıyken ses hattına yük SIFIRDAN da az: halka
 * ilk baytta geri döner, kopya/hesap yapmaz.
 */
object RhythmBus {
    @Volatile var level: Float = 0f      // toplam yoğunluk 0..1
    @Volatile var bass: Float = 0f       // bas ağırlığı 0..1
    @Volatile var playing: Boolean = false
    @Volatile var sampling: Boolean = false // MainActivity nabız aboneliğine bağlar
}

/**
 * ExoPlayer ses zincirine "tee" halkasıyla eklenen ölçüm tüketicisi.
 * Ham PCM örneklerinden RMS enerji ve tek kutuplu alçak geçiren süzgeçle
 * bas ağırlığını hesaplar; ~50 ms'de bir özet yayınlar. Ses yolunu asla
 * değiştirmez (salt okunur kopya tüketir).
 *
 * v4.0.2: tampon her pakette yeniden AYRILMAZ; tek karalama belleği
 * büyüyerek yeniden kullanılır (GC baskısı bitti).
 */
class MeterSink : TeeAudioProcessor.AudioBufferSink {

    private var encoding: Int = C.ENCODING_PCM_16BIT
    private var framesAccum = 0
    private var energy = 0.0
    private var bassEnergy = 0.0
    private var lp = 0.0          // alçak geçiren süzgeç çıkışı (bas yaklaşığı)
    private var lastPublishMs = 0L
    private var scratch = ByteArray(0)

    override fun flush(sampleRateHz: Int, channelCount: Int, encoding: Int) {
        this.encoding = encoding
        framesAccum = 0
        energy = 0.0
        bassEnergy = 0.0
        lp = 0.0
    }

    override fun handleBuffer(buffer: ByteBuffer) {
        if (!RhythmBus.sampling) return // kimse dinlemiyor: sıfır maliyet
        if (encoding != C.ENCODING_PCM_16BIT) return // alışılmadık biçim: sessizce geç
        val remaining = buffer.remaining()
        if (remaining < 4) return
        if (scratch.size < remaining) scratch = ByteArray(remaining)
        val bytes = scratch
        buffer.get(bytes, 0, remaining)
        var i = 0
        while (i + 1 < remaining) {
            val sample = (bytes[i + 1].toInt() shl 8) or (bytes[i].toInt() and 0xFF)
            val signed = if (sample >= 32768) sample - 65536 else sample
            val x = signed / 32768.0
            energy += x * x
            lp += 0.08 * (x - lp)
            bassEnergy += lp * lp
            framesAccum++
            i += 2
        }
        val now = System.currentTimeMillis()
        if (now - lastPublishMs >= 50 && framesAccum > 512) {
            lastPublishMs = now
            RhythmBus.level = (Math.sqrt(energy / framesAccum) * 3.2)
                .toFloat().coerceIn(0f, 1f)
            RhythmBus.bass = (Math.sqrt(bassEnergy / framesAccum) * 4.0)
                .toFloat().coerceIn(0f, 1f)
            energy = 0.0
            bassEnergy = 0.0
            framesAccum = 0
        }
    }
}

