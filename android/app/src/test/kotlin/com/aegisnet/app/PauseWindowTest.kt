package com.aegisnet.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PauseWindowTest {
    private val now = 1_700_000_000_000L

    @Test
    fun activeUntilItsEnd() {
        assertTrue(PauseWindow.isActive(now + 5 * 60_000L, now))
        assertFalse(PauseWindow.isActive(now, now))
        assertFalse(PauseWindow.isActive(now - 1, now))
    }

    @Test
    fun noPauseIsNotActive() {
        assertFalse(PauseWindow.isActive(0L, now))
    }

    @Test
    fun endTooFarAwayIsIgnored() {
        assertTrue(PauseWindow.isActive(now + PauseWindow.LONGEST_MS, now))
        assertFalse(PauseWindow.isActive(now + PauseWindow.LONGEST_MS + 1, now))
    }

    @Test
    fun looksAgainAtTheEndOrWithinTheCheckInterval() {
        assertEquals(3_000L, PauseWindow.nextCheckMs(now + 3_000L, now))
        assertEquals(PauseWindow.CHECK_EVERY_MS, PauseWindow.nextCheckMs(now + 60 * 60_000L, now))
        assertEquals(0L, PauseWindow.nextCheckMs(now - 1, now))
    }
}
