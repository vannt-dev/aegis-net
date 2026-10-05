package com.aegisnet.app

import java.net.InetAddress
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PacketEndpointsTest {
    private fun ipv4Udp(): ByteArray {
        val p = ByteArray(28 + 4)
        p[0] = 0x45
        p[9] = 17
        byteArrayOf(10, 0, 0, 2).copyInto(p, 12)
        byteArrayOf(10, 0, 0, 1).copyInto(p, 16)
        p[20] = 0x9c.toByte(); p[21] = 0x40 // 40000
        p[22] = 0; p[23] = 53
        return p
    }

    private fun ipv6Udp(): ByteArray {
        val p = ByteArray(48 + 4)
        p[0] = 0x60
        p[6] = 17
        p[8] = 0xfd.toByte(); p[23] = 2 // fd00::2
        p[24] = 0xfd.toByte(); p[39] = 1 // fd00::1
        p[40] = 0x9c.toByte(); p[41] = 0x41 // 40001
        p[42] = 0; p[43] = 53
        return p
    }

    @Test
    fun readsIpv4UdpEndpoints() {
        val e = PacketEndpoints.parse(ipv4Udp())!!
        assertEquals(InetAddress.getByName("10.0.0.2"), e.source)
        assertEquals(40000, e.sourcePort)
        assertEquals(InetAddress.getByName("10.0.0.1"), e.destination)
        assertEquals(53, e.destinationPort)
    }

    @Test
    fun readsIpv4WithOptions() {
        val base = ipv4Udp()
        val p = ByteArray(base.size + 4)
        base.copyInto(p, 0, 0, 20)
        base.copyInto(p, 24, 20)
        p[0] = 0x46 // IHL 6 words
        val e = PacketEndpoints.parse(p)!!
        assertEquals(40000, e.sourcePort)
        assertEquals(53, e.destinationPort)
    }

    @Test
    fun readsIpv6UdpEndpoints() {
        val e = PacketEndpoints.parse(ipv6Udp())!!
        assertEquals(InetAddress.getByName("fd00::2"), e.source)
        assertEquals(40001, e.sourcePort)
        assertEquals(InetAddress.getByName("fd00::1"), e.destination)
        assertEquals(53, e.destinationPort)
    }

    @Test
    fun rejectsTcp() {
        val p = ipv4Udp()
        p[9] = 6
        assertNull(PacketEndpoints.parse(p))
    }

    @Test
    fun rejectsIpv6ExtensionHeaders() {
        val p = ipv6Udp()
        p[6] = 0 // hop-by-hop options first
        assertNull(PacketEndpoints.parse(p))
    }

    @Test
    fun rejectsTruncatedPackets() {
        assertNull(PacketEndpoints.parse(ByteArray(0)))
        assertNull(PacketEndpoints.parse(ipv4Udp().copyOf(25)))
        assertNull(PacketEndpoints.parse(ipv6Udp().copyOf(45)))
    }
}
