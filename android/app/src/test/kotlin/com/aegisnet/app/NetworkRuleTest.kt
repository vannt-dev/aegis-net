package com.aegisnet.app

import com.aegisnet.app.NetworkRule.Transport
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NetworkRuleTest {
    private fun rule(
        mode: String = NetworkRule.MODE_ALL,
        exceptionsOn: Boolean = false,
        vararg exceptions: String,
    ) = NetworkRule.Settings(mode, exceptionsOn, exceptions.toSet())

    private fun filters(
        settings: NetworkRule.Settings,
        transport: Transport,
        ssid: String? = null,
        current: Boolean = true,
    ) = NetworkRule.shouldFilter(settings, transport, ssid, current)

    @Test
    fun offByDefaultFiltersEverywhere() {
        assertFalse(NetworkRule.OFF.active)
        for (transport in listOf(Transport.WIFI, Transport.CELLULAR, Transport.OTHER)) {
            assertTrue(filters(NetworkRule.OFF, transport, "Home"))
        }
    }

    @Test
    fun wifiOnlyLeavesMobileDataOut() {
        val settings = rule(NetworkRule.MODE_WIFI)
        assertTrue(settings.active)
        assertTrue(filters(settings, Transport.WIFI))
        assertFalse(filters(settings, Transport.CELLULAR))
    }

    @Test
    fun mobileOnlyLeavesWifiOut() {
        val settings = rule(NetworkRule.MODE_MOBILE)
        assertTrue(settings.active)
        assertFalse(filters(settings, Transport.WIFI))
        assertTrue(filters(settings, Transport.CELLULAR))
    }

    @Test
    fun otherNetworksAreAlwaysFiltered() {
        assertTrue(filters(rule(NetworkRule.MODE_WIFI), Transport.OTHER))
        assertTrue(filters(rule(NetworkRule.MODE_MOBILE), Transport.OTHER))
    }

    @Test
    fun noNetworkKeepsWhatTheTunnelDoes() {
        val settings = rule(NetworkRule.MODE_MOBILE)
        assertTrue(filters(settings, Transport.NONE, current = true))
        assertFalse(filters(settings, Transport.NONE, current = false))
    }

    @Test
    fun aListedWifiNetworkIsLeftOut() {
        val settings = rule(NetworkRule.MODE_ALL, true, "Home", "Office")
        assertTrue(settings.active)
        assertFalse(filters(settings, Transport.WIFI, "Home"))
        assertFalse(filters(settings, Transport.WIFI, "Office"))
        assertTrue(filters(settings, Transport.WIFI, "Cafe"))
        assertTrue(filters(settings, Transport.CELLULAR))
    }

    @Test
    fun wifiNamesMatchExactly() {
        val settings = rule(NetworkRule.MODE_ALL, true, "Home")
        assertTrue(filters(settings, Transport.WIFI, "home"))
        assertTrue(filters(settings, Transport.WIFI, "Home "))
    }

    @Test
    fun anUnreadableNameFallsBackToWifiVersusMobile() {
        assertTrue(filters(rule(NetworkRule.MODE_ALL, true, "Home"), Transport.WIFI, null))
        assertTrue(filters(rule(NetworkRule.MODE_WIFI, true, "Home"), Transport.WIFI, null))
        assertFalse(filters(rule(NetworkRule.MODE_MOBILE, true, "Home"), Transport.WIFI, null))
    }

    @Test
    fun listedNetworksCountOnlyWhileTheListIsOn() {
        val settings = rule(NetworkRule.MODE_ALL, false, "Home")
        assertFalse(settings.active)
        assertTrue(filters(settings, Transport.WIFI, "Home"))
    }

    @Test
    fun anEmptyListLeavesNothingOut() {
        assertFalse(rule(NetworkRule.MODE_ALL, true).active)
    }

    @Test
    fun anUnknownModeFiltersEverywhere() {
        val settings = rule("something-newer")
        assertFalse(settings.active)
        assertTrue(filters(settings, Transport.WIFI))
        assertTrue(filters(settings, Transport.CELLULAR))
    }

    @Test
    fun namesAreReadWithoutTheirQuotes() {
        assertEquals("Home", NetworkRule.normalizeSsid("\"Home\""))
        assertEquals("Home", NetworkRule.normalizeSsid("Home"))
        assertEquals("\"", NetworkRule.normalizeSsid("\""))
        assertNull(NetworkRule.normalizeSsid("<unknown ssid>"))
        assertNull(NetworkRule.normalizeSsid("\"<unknown ssid>\""))
        assertNull(NetworkRule.normalizeSsid(""))
        assertNull(NetworkRule.normalizeSsid("\"\""))
        assertNull(NetworkRule.normalizeSsid(null))
    }

    @Test
    fun theStoredListIsOneNamePerLine() {
        assertEquals(setOf("Home", "My Office"), NetworkRule.parseExceptions("Home\nMy Office\n"))
        assertEquals(emptySet<String>(), NetworkRule.parseExceptions(null))
        assertEquals(emptySet<String>(), NetworkRule.parseExceptions(""))
    }
}
