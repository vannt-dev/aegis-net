package com.aegisnet.app

/**
 * When a pause of protection is over.
 *
 * The tunnel holds the pause, not the app: Android closes a backgrounded app
 * freely, and a pause kept there never ended. Times are wall-clock
 * milliseconds so a pause survives the service being restarted.
 */
object PauseWindow {
    /// Longest wait between two looks at the clock. A Handler delay stops
    /// counting while the device sleeps, so one long delay would end the pause
    /// late by however long the phone slept; a short one only by this much.
    const val CHECK_EVERY_MS = 15_000L

    /// The app offers pauses of at most an hour. An end further away than this
    /// comes from a clock set back after pausing, and must not keep
    /// protection off for that long.
    const val LONGEST_MS = 24 * 60 * 60_000L

    /// True while a pause ending at [untilMs] is still running at [nowMs].
    fun isActive(untilMs: Long, nowMs: Long): Boolean =
        untilMs > nowMs && untilMs - nowMs <= LONGEST_MS

    /// The pause the notification's button starts.
    const val NOTIFICATION_PAUSE_MS = 5 * 60_000L

    /// The longest pause the app offers, and so the longest a pause given as
    /// a length (rather than an end) may run.
    const val LONGEST_OFFERED_MS = 60 * 60_000L

    /// When a pause of [durationMs] started at [nowMs] ends, or 0 for a
    /// length that is not a pause the app offers. The end is worked out when
    /// the tap arrives: one fixed when the notification was posted would
    /// already be in the past by the time someone taps it.
    fun endAfter(durationMs: Long, nowMs: Long): Long =
        if (durationMs in 1..LONGEST_OFFERED_MS) nowMs + durationMs else 0L

    /// How long to wait before looking again.
    fun nextCheckMs(untilMs: Long, nowMs: Long): Long =
        (untilMs - nowMs).coerceIn(0L, CHECK_EVERY_MS)
}
