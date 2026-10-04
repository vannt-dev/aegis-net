package com.aegisnet.app

import java.net.InetAddress

/** Who sent a UDP datagram read from the tunnel, and where to. */
data class Endpoints(
    val source: InetAddress,
    val sourcePort: Int,
    val destination: InetAddress,
    val destinationPort: Int,
)

/**
 * Reads the addresses and ports of an IPv4 or IPv6 UDP datagram, which is
 * what `getConnectionOwnerUid` needs to name the app behind a DNS query.
 * Anything else — another protocol, a truncated header, IPv6 extension
 * headers in front of UDP — gives null, and the query is counted as unknown.
 */
object PacketEndpoints {
    private const val UDP = 17

    fun parse(packet: ByteArray): Endpoints? {
        if (packet.isEmpty()) return null
        return when ((packet[0].toInt() shr 4) and 0x0f) {
            4 -> parseIpv4(packet)
            6 -> parseIpv6(packet)
            else -> null
        }
    }

    private fun parseIpv4(p: ByteArray): Endpoints? {
        if (p.size < 20) return null
        val headerLength = (p[0].toInt() and 0x0f) * 4
        if (headerLength < 20 || (p[9].toInt() and 0xff) != UDP) return null
        if (p.size < headerLength + 8) return null
        return Endpoints(
            InetAddress.getByAddress(p.copyOfRange(12, 16)),
            port(p, headerLength),
            InetAddress.getByAddress(p.copyOfRange(16, 20)),
            port(p, headerLength + 2),
        )
    }

    private fun parseIpv6(p: ByteArray): Endpoints? {
        if (p.size < 48 || (p[6].toInt() and 0xff) != UDP) return null
        return Endpoints(
            InetAddress.getByAddress(p.copyOfRange(8, 24)),
            port(p, 40),
            InetAddress.getByAddress(p.copyOfRange(24, 40)),
            port(p, 42),
        )
    }

    private fun port(p: ByteArray, at: Int): Int =
        ((p[at].toInt() and 0xff) shl 8) or (p[at + 1].toInt() and 0xff)
}
