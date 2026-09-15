package com.cobblestone.cobblestone

import android.media.audiofx.BassBoost
import android.media.audiofx.Virtualizer

/**
 * 10 bant yazılımsal EQ + sistem BassBoost + Virtualizer.
 * Bantlar cihazdan bağımsız (31 Hz … 16 kHz).
 */
object EqEngine {

    val processor = BiquadEqProcessor()

    private var bass: BassBoost? = null
    private var virt: Virtualizer? = null
    private var sessionId: Int = 0
    private var lastEnabled = false
    private var lastLevels: List<Int>? = null
    private var lastBass = 0
    private var lastVirt = 0

    @Synchronized
    fun attach(audioSessionId: Int): Boolean {
        if (audioSessionId <= 0) return false
        if (audioSessionId == sessionId && (bass != null || virt != null)) return true
        val oldBass = bass
        val oldVirt = virt
        bass = null
        virt = null
        sessionId = audioSessionId
        return try {
            bass = try {
                BassBoost(0, audioSessionId).apply { enabled = false }
            } catch (_: Throwable) {
                null
            }
            virt = try {
                Virtualizer(0, audioSessionId).apply { enabled = false }
            } catch (_: Throwable) {
                null
            }
            applyAll(lastEnabled, lastLevels, lastBass, lastVirt)
            try { oldBass?.release() } catch (_: Throwable) {}
            try { oldVirt?.release() } catch (_: Throwable) {}
            true
        } catch (_: Throwable) {
            bass = oldBass
            virt = oldVirt
            false
        }
    }

    @Synchronized
    fun describe(): Map<String, Any?> {
        return mapOf(
            "supported" to true,
            "bandCount" to BiquadEqProcessor.BANDS,
            "minLevel" to -1500,
            "maxLevel" to 1500,
            "freqs" to BiquadEqProcessor.FREQS.toList(),
            "bassSupported" to true,
            "virtualizerSupported" to true,
        )
    }

    @Synchronized
    fun getState(): Map<String, Any?> {
        return mapOf(
            "supported" to true,
            "enabled" to processor.enabled,
            "bass" to (bass?.let { if (it.enabled) it.roundedStrength.toInt() else 0 } ?: 0),
            "virtualizer" to (virt?.let { if (it.enabled) it.roundedStrength.toInt() else 0 } ?: 0),
        )
    }

    @Synchronized
    fun applyAll(
        enabled: Boolean,
        levels: List<Int>?,
        bassStrength: Int,
        virtStrength: Int
    ) {
        try {
            processor.setGainsMilliBel(levels)
            processor.enabled = enabled
            bass?.let {
                try {
                    it.setStrength(bassStrength.coerceIn(0, 1000).toShort())
                    it.enabled = bassStrength > 0 && enabled
                } catch (_: Throwable) {
                }
            }
            virt?.let {
                try {
                    it.setStrength(virtStrength.coerceIn(0, 1000).toShort())
                    it.enabled = virtStrength > 0 && enabled
                } catch (_: Throwable) {
                }
            }
        } catch (_: Throwable) {
        }
    }

    @Synchronized
    fun release() {
        releaseFx()
        processor.enabled = false
    }

    private fun releaseFx() {
        try { bass?.release() } catch (_: Throwable) {}
        try { virt?.release() } catch (_: Throwable) {}
        bass = null
        virt = null
        sessionId = 0
    }
}
