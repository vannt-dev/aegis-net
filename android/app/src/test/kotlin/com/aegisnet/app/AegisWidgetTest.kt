package com.aegisnet.app

import com.aegisnet.app.AegisWidget.Look
import com.aegisnet.app.AegisWidget.Status
import com.aegisnet.app.AegisWidget.Tap
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AegisWidgetTest {
    private val now = 1_700_000_000_000L

    private fun look(
        tunnelUp: Boolean,
        pausedUntilMs: Long = 0L,
        consentNeeded: Boolean = false,
        appLockOn: Boolean = false,
    ) = AegisWidget.look(tunnelUp, pausedUntilMs, now, consentNeeded, appLockOn)

    @Test
    fun protectedTurnsOffUnlessTheAppLockIsOn() {
        assertEquals(Look(Status.PROTECTED, Tap.STOP), look(tunnelUp = true))
        assertEquals(Look(Status.PROTECTED, Tap.OPEN_APP), look(tunnelUp = true, appLockOn = true))
    }

    @Test
    fun pausedResumesEvenWithTheAppLockOn() {
        val until = now + 5 * 60_000L
        assertEquals(Look(Status.PAUSED, Tap.RESUME), look(tunnelUp = true, pausedUntilMs = until))
        assertEquals(
            Look(Status.PAUSED, Tap.RESUME),
            look(tunnelUp = true, pausedUntilMs = until, appLockOn = true),
        )
    }

    @Test
    fun aPauseThatIsOverShowsProtected() {
        assertEquals(Look(Status.PROTECTED, Tap.STOP), look(tunnelUp = true, pausedUntilMs = now))
    }

    @Test
    fun offTurnsOnOrOpensTheAppForConsent() {
        assertEquals(Look(Status.OFF, Tap.START), look(tunnelUp = false))
        assertEquals(Look(Status.OFF, Tap.OPEN_APP), look(tunnelUp = false, consentNeeded = true))
        // A pause left behind by a tunnel that is gone is not a pause.
        assertEquals(Look(Status.OFF, Tap.START), look(tunnelUp = false, pausedUntilMs = now + 60_000L))
    }

    @Test
    fun localDayFollowsTheOffset() {
        val dayMs = 24 * 60 * 60_000L
        // 2023-11-14 22:13:20 UTC is already the 15th at UTC+7.
        assertEquals(now / dayMs, AegisWidget.localDay(now, 0L))
        assertEquals(now / dayMs + 1, AegisWidget.localDay(now, 7 * 60 * 60_000L))
        assertEquals(-1L, AegisWidget.localDay(-1L, 0L))
    }

    @Test
    fun aCountFromAnotherDayIsNotShown() {
        assertEquals(42L, AegisWidget.blockedToday(savedDay = 19_000L, savedCount = 42L, today = 19_000L))
        assertNull(AegisWidget.blockedToday(savedDay = 18_999L, savedCount = 42L, today = 19_000L))
        assertNull(AegisWidget.blockedToday(savedDay = 19_000L, savedCount = -1L, today = 19_000L))
    }
}
