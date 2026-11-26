package com.aegisnet.app

import android.content.Context

/**
 * Which networks protection applies on.
 *
 * Off by default: protection applies on every network. The user can limit it
 * to Wi-Fi or to mobile data, and can name Wi-Fi networks where it does not
 * apply. On a network left out the tunnel stays up without filtering, the
 * way it does during a pause, so it filters again by itself on the next
 * network that is in.
 *
 * The Dart side keeps the settings; see [load].
 */
object NetworkRule {
    const val MODE_ALL = "all"
    const val MODE_WIFI = "wifi"
    const val MODE_MOBILE = "mobile"

    enum class Transport { WIFI, CELLULAR, OTHER, NONE }

    /// What Android reports when a Wi-Fi name may not be read: without
    /// location access, or with location turned off.
    private const val UNKNOWN_SSID = "<unknown ssid>"

    data class Settings(
        val mode: String,
        val exceptionsOn: Boolean,
        val exceptions: Set<String>,
    ) {
        /// True when the rule can leave any network out, which is when the
        /// service has to watch the network at all.
        val active: Boolean
            get() = mode == MODE_WIFI || mode == MODE_MOBILE ||
                (exceptionsOn && exceptions.isNotEmpty())
    }

    val OFF = Settings(MODE_ALL, false, emptySet())

    /// The Dart side keeps its settings in this file, keys prefixed "flutter.".
    private const val FLUTTER_PREFS = "FlutterSharedPreferences"
    private const val KEY_MODE = "flutter.network_rule_mode"
    private const val KEY_EXCEPTIONS_ON = "flutter.network_ssid_exceptions_on"
    private const val KEY_EXCEPTIONS = "flutter.network_ssid_exceptions"

    fun load(context: Context): Settings = try {
        val prefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
        Settings(
            mode = prefs.getString(KEY_MODE, MODE_ALL) ?: MODE_ALL,
            exceptionsOn = prefs.getBoolean(KEY_EXCEPTIONS_ON, false),
            exceptions = parseExceptions(prefs.getString(KEY_EXCEPTIONS, null)),
        )
    } catch (e: Exception) {
        // A value of the wrong type must not cost protection.
        OFF
    }

    /// The Wi-Fi names, kept one per line.
    fun parseExceptions(stored: String?): Set<String> =
        stored.orEmpty().split('\n').filter { it.isNotBlank() }.toSet()

    /// A Wi-Fi name as Android reports it, without the quotes it puts around
    /// a readable name, or null when it could not be read.
    fun normalizeSsid(raw: String?): String? {
        if (raw == null) return null
        var ssid = raw
        if (ssid.length >= 2 && ssid.startsWith("\"") && ssid.endsWith("\"")) {
            ssid = ssid.substring(1, ssid.length - 1)
        }
        if (ssid.isBlank() || ssid == UNKNOWN_SSID) return null
        return ssid
    }

    /// Whether to filter on the network the device is using now.
    ///
    /// [ssid] is null when the Wi-Fi name could not be read; the choice then
    /// falls back to Wi-Fi versus mobile data. With no network at all nothing
    /// changes ([current]), so a short drop does not rebuild the tunnel.
    /// Any other network (Ethernet, for one) is filtered: when in doubt, the
    /// rule errs on the side of protection.
    fun shouldFilter(
        settings: Settings,
        transport: Transport,
        ssid: String?,
        current: Boolean,
    ): Boolean = when (transport) {
        Transport.NONE -> current
        Transport.CELLULAR -> settings.mode != MODE_WIFI
        Transport.WIFI -> when {
            settings.mode == MODE_MOBILE -> false
            settings.exceptionsOn && ssid != null && ssid in settings.exceptions -> false
            else -> true
        }
        Transport.OTHER -> true
    }
}
