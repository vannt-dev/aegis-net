package com.aegisnet.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.util.Log
import android.widget.RemoteViews
import java.text.DateFormat
import java.text.NumberFormat
import java.util.Date
import java.util.TimeZone

/**
 * The home-screen widget: protection on or off, and how many lookups were
 * blocked today. Tapping it does what tapping the Quick Settings tile does.
 *
 * The widget is drawn again whenever the tunnel changes state (see
 * [AegisVpnService.publishState]) and when the app hands it a new count.
 */
class AegisWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        AegisWidget.draw(context, manager, ids)
    }
}

object AegisWidget {
    private const val TAG = "AegisWidget"
    private const val PREFS_NAME = "aegis_widget"
    private const val KEY_DAY = "blocked_day"
    private const val KEY_BLOCKED = "blocked_count"
    private const val DAY_MS = 24 * 60 * 60_000L

    /// What the widget says, and what a tap on it does.
    enum class Status { PROTECTED, PAUSED, OFF }
    enum class Tap { STOP, RESUME, START, OPEN_APP }

    data class Look(val status: Status, val tap: Tap)

    /// The same choices the tile makes. Turning protection off needs the app
    /// lock's PIN and turning it on may need the system's VPN consent; the
    /// widget can ask for neither, so it opens the app for those. Ending a
    /// pause only makes protection stronger, so it never needs the PIN.
    fun look(
        tunnelUp: Boolean,
        pausedUntilMs: Long,
        nowMs: Long,
        consentNeeded: Boolean,
        appLockOn: Boolean,
    ): Look = when {
        tunnelUp && PauseWindow.isActive(pausedUntilMs, nowMs) -> Look(Status.PAUSED, Tap.RESUME)
        tunnelUp -> Look(Status.PROTECTED, if (appLockOn) Tap.OPEN_APP else Tap.STOP)
        else -> Look(Status.OFF, if (consentNeeded) Tap.OPEN_APP else Tap.START)
    }

    /// Local calendar day of [nowMs], counted from 1970-01-01, the way the
    /// app counts the days of its history.
    fun localDay(nowMs: Long, utcOffsetMs: Long): Long = Math.floorDiv(nowMs + utcOffsetMs, DAY_MS)

    /// Today's blocked count, or null when the app last counted on another
    /// day: a number from yesterday would read as today's.
    fun blockedToday(savedDay: Long, savedCount: Long, today: Long): Long? =
        if (savedDay == today && savedCount >= 0) savedCount else null

    /// Keep the count the app worked out for [day] and draw the widget again.
    fun saveBlocked(context: Context, day: Long, blocked: Long) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putLong(KEY_DAY, day)
            .putLong(KEY_BLOCKED, blocked)
            .apply()
        refresh(context)
    }

    /// Draw every placed widget again. Does nothing when none is placed.
    fun refresh(context: Context) {
        try {
            val manager = AppWidgetManager.getInstance(context) ?: return
            val ids = manager.getAppWidgetIds(ComponentName(context, AegisWidgetProvider::class.java))
            if (ids.isNotEmpty()) draw(context, manager, ids)
        } catch (e: Exception) {
            // The widget is a convenience; it must never take the tunnel down.
            Log.w(TAG, "Could not draw the widget", e)
        }
    }

    fun draw(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val now = System.currentTimeMillis()
        val consentNeeded = try {
            VpnService.prepare(context) != null
        } catch (e: Exception) {
            // Some vendor ROMs throw here; the app knows how to explain that.
            true
        }
        val look = look(
            tunnelUp = AegisVpnService.isTunnelUp,
            pausedUntilMs = AegisVpnService.pausedUntilMs,
            nowMs = now,
            consentNeeded = consentNeeded,
            appLockOn = AppLock.isOn(context),
        )

        val views = RemoteViews(context.packageName, R.layout.aegis_widget)
        val (statusText, color) = when (look.status) {
            Status.PROTECTED -> "Protected" to 0xFF10B981.toInt()
            Status.PAUSED -> {
                val end = DateFormat.getTimeInstance(DateFormat.SHORT)
                    .format(Date(AegisVpnService.pausedUntilMs))
                "Paused until $end" to 0xFFFFD740.toInt()
            }
            Status.OFF -> "Protection off" to 0xFF90A4AE.toInt()
        }
        views.setTextViewText(R.id.widget_status, statusText)
        views.setTextColor(R.id.widget_status, color)
        views.setInt(R.id.widget_icon, "setColorFilter", color)
        views.setTextViewText(R.id.widget_blocked, blockedLine(context, now))
        views.setTextViewText(
            R.id.widget_action,
            when (look.tap) {
                Tap.STOP -> "Tap to turn off"
                Tap.RESUME -> "Tap to resume"
                Tap.START -> "Tap to turn on"
                Tap.OPEN_APP -> "Tap to open the app"
            },
        )
        tapIntent(context, look.tap)?.let { views.setOnClickPendingIntent(R.id.widget_root, it) }
        manager.updateAppWidget(ids, views)
    }

    private fun blockedLine(context: Context, now: Long): String {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val today = localDay(now, TimeZone.getDefault().getOffset(now).toLong())
        val count = blockedToday(prefs.getLong(KEY_DAY, -1L), prefs.getLong(KEY_BLOCKED, -1L), today)
        return if (count == null) {
            "Blocked today: open the app to count"
        } else {
            "Blocked today: ${NumberFormat.getIntegerInstance().format(count)}"
        }
    }

    private fun tapIntent(context: Context, tap: Tap): PendingIntent? {
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        fun service(action: String) = Intent(context, AegisVpnService::class.java)
            .setAction(action)
            .putExtra(AegisVpnService.EXTRA_FROM_SHORTCUT, true)
        return when (tap) {
            // The service is in the foreground while the tunnel is up, so a
            // plain start reaches it.
            Tap.STOP -> PendingIntent.getService(context, 1, service(AegisVpnService.ACTION_STOP), flags)
            Tap.RESUME -> PendingIntent.getService(context, 2, service(AegisVpnService.ACTION_RESUME), flags)
            // A widget tap is one of the moments Android lets an app start a
            // foreground service from the background.
            Tap.START -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                PendingIntent.getForegroundService(context, 3, service(AegisVpnService.ACTION_START), flags)
            } else {
                PendingIntent.getService(context, 3, service(AegisVpnService.ACTION_START), flags)
            }
            Tap.OPEN_APP -> context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                ?.let { PendingIntent.getActivity(context, 4, it, flags) }
        }
    }
}
