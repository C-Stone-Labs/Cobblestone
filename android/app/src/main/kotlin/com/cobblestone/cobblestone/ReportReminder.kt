package com.cobblestone.cobblestone

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import java.util.Calendar

/**
 * Paket 14 — Pazartesi raporu bildirimi.
 *
 * Her Pazartesi 09:00 civarında tek bildirim: "Raporun hazır". Kasıtlı
 * olarak KESİN alarm değil (setAndAllowWhileIdle): izin istemez, sistem
 * uykusunda birkaç dakika kayabilir — haftalık rapor için ideal ve pil
 * dostu. Alarm üç yerde tazelenir: uygulama her açıldığında (MainActivity),
 * bildirim ateşlendiğinde (bir sonraki haftaya kurulur), telefon yeniden
 * başladığında (ReportBootReceiver).
 */
object ReportReminder {
    const val EXTRA_OPEN_REPORT = "com.cobblestone.OPEN_REPORT"
    private const val REQ_ALARM = 4141
    private const val CHANNEL_ID = "haftalik_rapor"
    private const val NOTIF_ID = 4202

    /** Şu andan sonraki ilk Pazartesi 09:00 (yerel saat). */
    private fun nextMondayNine(): Long {
        val c = Calendar.getInstance()
        c.set(Calendar.SECOND, 0)
        c.set(Calendar.MILLISECOND, 0)
        c.set(Calendar.MINUTE, 0)
        c.set(Calendar.HOUR_OF_DAY, 9)
        while (c.get(Calendar.DAY_OF_WEEK) != Calendar.MONDAY ||
            c.timeInMillis <= System.currentTimeMillis()
        ) {
            c.add(Calendar.DAY_OF_YEAR, 1)
        }
        return c.timeInMillis
    }

    private fun alarmIntent(context: Context): PendingIntent {
        val i = Intent(context, ReportAlarmReceiver::class.java)
        return PendingIntent.getBroadcast(
            context, REQ_ALARM, i,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    /** Sonraki Pazartesi 09:00 için (yeniden) kurar; tekrarlı çağrı güvenli. */
    fun scheduleNext(context: Context) {
        try {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, nextMondayNine(), alarmIntent(context))
        } catch (_: Throwable) {
        }
    }

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val ch = NotificationChannel(CHANNEL_ID, "Haftalık Rapor", NotificationManager.IMPORTANCE_DEFAULT)
            ch.description = "Pazartesi günleri haftalık dinleme raporu"
            nm.createNotificationChannel(ch)
        } catch (_: Throwable) {
        }
    }

    fun showNow(context: Context) {
        try {
            ensureChannel(context)
            val open = Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                .putExtra(EXTRA_OPEN_REPORT, true)
            val pi = PendingIntent.getActivity(
                context, 0, open,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val builder = if (Build.VERSION.SDK_INT >= 26)
                Notification.Builder(context, CHANNEL_ID)
            else
                @Suppress("DEPRECATION") Notification.Builder(context)
            val prefs = context.getSharedPreferences("cobble_native", Context.MODE_PRIVATE)
            val shown = prefs.getInt("report_notif_shown", 0)
            val first = shown <= 0
            prefs.edit().putInt("report_notif_shown", shown + 1).apply()
            val title = if (first) "İlk raporunuz hazır" else "Raporunuz yenilendi"
            val text = if (first)
                "Geçen Pazartesi–Pazar dökümü hazır. Dokununca açılır."
            else
                "Geçen haftanın raporu kilitlendi. Dokununca açılır."
            val n = builder
                .setSmallIcon(R.drawable.ic_stat_cobble)
                .setContentTitle(title)
                .setContentText(text)
                .setAutoCancel(true)
                .setContentIntent(pi)
                .build()
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(NOTIF_ID, n)
        } catch (_: Throwable) {
        }
    }
}

/** Alarm vakti geldiğinde bildirimi basar ve görevi devreder: bir SONRAKİ
 *  Pazartesi için alarmı hemen yeniden kurar. */
class ReportAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        ReportReminder.showNow(context)
        ReportReminder.scheduleNext(context)
    }
}

/** Telefon yeniden başladığında alarm kaybolur; burada tazeleyiz. */
class ReportBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            ReportReminder.scheduleNext(context)
        }
    }
}

