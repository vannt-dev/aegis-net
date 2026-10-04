package com.aegisnet.app

/**
 * Public resolvers apps use to go around the system DNS. With the
 * "stop apps from bypassing the filter" switch on, each address is routed
 * into the tunnel: plain DNS to it is filtered like any other query, and
 * everything else (DoT, DoH, DoQ) is refused so the app falls back.
 */
object KnownResolvers {
    val ADDRESSES: List<String> = listOf(
        // Google
        "8.8.8.8", "8.8.4.4", "2001:4860:4860::8888", "2001:4860:4860::8844",
        // Cloudflare
        "1.1.1.1", "1.0.0.1", "2606:4700:4700::1111", "2606:4700:4700::1001",
        // Quad9
        "9.9.9.9", "149.112.112.112", "2620:fe::fe", "2620:fe::9",
        // OpenDNS
        "208.67.222.222", "208.67.220.220", "2620:119:35::35", "2620:119:53::53",
        // AdGuard
        "94.140.14.14", "94.140.15.15", "2a10:50c0::ad1:ff", "2a10:50c0::ad2:ff",
        // CleanBrowsing
        "185.228.168.9", "185.228.169.9",
    )

    /** A host route: the whole address and nothing around it. */
    fun prefixLength(address: String): Int = if (address.contains(':')) 128 else 32
}
