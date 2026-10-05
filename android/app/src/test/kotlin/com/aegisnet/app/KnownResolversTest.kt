package com.aegisnet.app

import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InetAddress
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class KnownResolversTest {
    // getByName on a literal never touches DNS; a typo would throw here.
    private val parsed = KnownResolvers.ADDRESSES.map { InetAddress.getByName(it) }

    @Test
    fun everyEntryIsAnAddressLiteral() {
        KnownResolvers.ADDRESSES.forEach { assertTrue(it, it.all { c -> c.isLetterOrDigit() || c == '.' || c == ':' }) }
    }

    @Test
    fun noDuplicates() {
        assertEquals(parsed.size, parsed.toSet().size)
    }

    @Test
    fun bothFamiliesAreCovered() {
        assertTrue(parsed.any { it is Inet4Address })
        assertTrue(parsed.any { it is Inet6Address })
    }

    @Test
    fun prefixIsAHostRoute() {
        assertEquals(32, KnownResolvers.prefixLength("8.8.8.8"))
        assertEquals(128, KnownResolvers.prefixLength("2001:4860:4860::8888"))
    }
}
