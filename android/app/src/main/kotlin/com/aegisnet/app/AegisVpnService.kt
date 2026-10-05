package com.aegisnet.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.database.ContentObserver
import android.net.ConnectivityManager
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.Process
import android.provider.Settings
import android.system.OsConstants
import android.util.Log
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.InetSocketAddress
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

class AegisVpnService : VpnService(), Runnable {

    companion object {
        const val ACTION_START = "com.aegisnet.app.START"
        const val ACTION_STOP = "com.aegisnet.app.STOP"
        private const val TAG = "AegisVpnService"
        const val UNKNOWN_UID = -1

        private const val CHANNEL_ID = "aegis_vpn_status"
        private const val NOTIFICATION_ID = 0xA3

        private const val PREFS_NAME = "aegis_vpn_service"
        private const val KEY_BYPASS_APPS = "bypass_apps"
        private const val KEY_INTERCEPT = "intercept_hardcoded_dns"
        const val EXTRA_INTERCEPT = "interceptHardcodedDns"

        /// ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE (API 34). Spelled as
        /// a literal so the module still compiles against an older compileSdk.
        private const val FGS_TYPE_SPECIAL_USE = 1 shl 30

        // Virtual DNS servers the OS sends queries to; only these addresses are
        // routed into the TUN.
        //
        // The v6 address is a ULA and has to be a valid IPv6 literal: every
        // group is hexadecimal, so a mnemonic like "aegis" does not parse and
        // Builder.addAddress throws before the tunnel is ever established.
        private const val TUN_DNS_SERVER = "10.0.0.3"
        private const val TUN_DNS_SERVER_V6 = "fd00:aeed::3"
        private const val TUN_ADDRESS_V6 = "fd00:aeed::2"

        /// Concurrent upstream lookups allowed before queries start queueing.
        private const val WORKER_THREADS = 8

        /// Queries waiting for a free worker. Deep enough to absorb the burst an
        /// app launch produces, shallow enough that a dead upstream is noticed
        /// rather than silently buffering for minutes.
        private const val WORKER_QUEUE_DEPTH = 256

        /// Queries dropped because every worker was busy and the queue was full.
        /// Surfaced through diagnostics: a growing number means the upstream is
        /// too slow for the load, which is invisible from the UI otherwise.
        val droppedUnderLoad = AtomicLong(0)

        // Reasons handed back to Dart. Kept as stable codes so the UI can give
        // vendor-specific advice instead of a generic "failed".
        const val ERROR_ESTABLISH_NULL = "tunnel_not_established"
        const val ERROR_ESTABLISH_DENIED = "tunnel_permission_denied"

        /// True when libaegis_core.so (the Rust DNS engine) is present. Built
        /// per-ABI via cargo-ndk; absent in UI-only builds. Loading must never
        /// crash the service, mirroring the graceful fallback on the Dart side.
        @Volatile
        var nativeAvailable: Boolean = false
            private set

        /// True only while a TUN interface is actually established. The old code
        /// reported success the moment startService() was called, so a tunnel
        /// the system silently refused still showed as "protected".
        @Volatile
        var isTunnelUp: Boolean = false
            private set

        /// Why the last start attempt failed, or null after a successful one.
        @Volatile
        var lastError: String? = null
            private set

        /// Set by MainActivity for the duration of one start attempt. Invoked
        /// with the outcome of `establish()` — the thing the caller actually
        /// wants to know.
        @Volatile
        var startListener: ((Boolean, String?) -> Unit)? = null

        fun publishStartResult(started: Boolean, error: String?) {
            isTunnelUp = started
            lastError = error
            val listener = startListener
            startListener = null
            listener?.invoke(started, error)
        }

        fun markTunnelDown(error: String? = null) {
            isTunnelUp = false
            if (error != null) lastError = error
        }

        init {
            nativeAvailable = try {
                System.loadLibrary("aegis_core")
                true
            } catch (e: UnsatisfiedLinkError) {
                Log.w(TAG, "libaegis_core.so not bundled; DNS filtering disabled", e)
                false
            }
        }
    }

    /// Filters a raw packet read from the TUN interface. Returns a DNS reply
    /// packet to write back, or an empty array when there is nothing to
    /// inject. `uid` is the app that sent the query, or -1 when unknown; it
    /// only feeds the per-app statistics.
    private external fun nativeProcessPacket(packet: ByteArray, uid: Int): ByteArray

    private val connectivity by lazy { getSystemService(ConnectivityManager::class.java) }

    @Volatile private var vpnInterface: ParcelFileDescriptor? = null
    private var vpnThread: Thread? = null
    @Volatile private var isRunning = false

    /// What the running tunnel was built for; see [privateDnsObserver].
    private var builtForStrictPrivateDns = false

    /// The tunnel is built differently under strict Private DNS, and the mode
    /// can change while it is up. Left alone, switching to a fixed provider
    /// cut DNS off for the whole device until protection was toggled, and
    /// switching back left the tunnel filtering nothing.
    private val privateDnsObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
        override fun onChange(selfChange: Boolean) {
            if (!isRunning || strictPrivateDns() == builtForStrictPrivateDns) return
            Log.i(TAG, "Private DNS mode changed; rebuilding the tunnel")
            closeTunnel()
            startVpn(loadBypassApps(), loadIntercept())
        }
    }

    override fun onCreate() {
        super.onCreate()
        try {
            contentResolver.registerContentObserver(
                Settings.Global.getUriFor("private_dns_mode"), false, privateDnsObserver,
            )
        } catch (e: Exception) {
            Log.w(TAG, "Cannot watch the Private DNS mode", e)
        }
    }

    /// Filtering runs here instead of on the reader thread. Sized for the work:
    /// blocked and cached answers return in microseconds and never occupy a
    /// worker for long, so this only has to cover concurrent cache misses, each
    /// bounded by the engine's 2.5s DoH timeout.
    private var workers: ThreadPoolExecutor? = null
    private val tunWriteLock = Any()

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // START_STICKY redelivers a NULL intent after the system restarts a
        // killed service, which on MIUI is a routine event rather than an edge
        // case. Falling through the `when` left the process alive with no
        // notification and no tunnel: a zombie that reports "protected" to
        // nobody and, on Android 12, risks being killed again for never
        // calling startForeground() after a startForegroundService() start.
        //
        // Rebuild the tunnel instead, using the bypass list the last start
        // used, since the intent that carried it is gone.
        if (intent == null) {
            Log.i(TAG, "Restarted by the system; rebuilding the tunnel")
            enterForeground()
            startVpn(loadBypassApps(), loadIntercept())
            return START_STICKY
        }

        when (intent.action) {
            ACTION_START -> {
                // Go foreground BEFORE building the tunnel. Android 12 kills a
                // service that has not posted its notification within 5s of
                // startForegroundService(), and MIUI reaps plain background
                // services within seconds of the user leaving the app — which
                // is why the tunnel kept dying on Xiaomi devices.
                enterForeground()
                val bypassApps = intent.getStringArrayListExtra("bypassApps") ?: arrayListOf()
                saveBypassApps(bypassApps)
                val intercept = intent.getBooleanExtra(EXTRA_INTERCEPT, true)
                saveIntercept(intercept)
                startVpn(bypassApps, intercept)
            }
            ACTION_STOP -> stopVpn()
            else -> Log.w(TAG, "Ignoring unknown action ${intent.action}")
        }
        return START_STICKY
    }

    /// Split-tunnel exclusions, remembered across a restart.
    ///
    /// A static would be lost with the process, and MIUI kills the process, not
    /// just the service — the sticky restart would then rebuild the tunnel with
    /// no exclusions at all and quietly route the user's banking and messaging
    /// apps through it.
    private fun saveBypassApps(apps: List<String>) {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putStringSet(KEY_BYPASS_APPS, apps.toSet())
            .apply()
    }

    private fun loadBypassApps(): ArrayList<String> {
        val saved = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getStringSet(KEY_BYPASS_APPS, emptySet())
            .orEmpty()
        return ArrayList(saved)
    }

    /// The bypass-interception switch, kept for the same reason as the
    /// exclusions: a sticky restart must rebuild the same tunnel.
    private fun saveIntercept(enabled: Boolean) {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_INTERCEPT, enabled)
            .apply()
    }

    private fun loadIntercept(): Boolean =
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).getBoolean(KEY_INTERCEPT, true)

    /// Private DNS set to a fixed provider ("hostname" mode).
    private fun strictPrivateDns(): Boolean = try {
        Settings.Global.getString(contentResolver, "private_dns_mode") == "hostname"
    } catch (e: Exception) {
        false
    }

    private fun enterForeground() {
        val manager = getSystemService(NotificationManager::class.java)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "AegisNet Shield",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Shows while DNS filtering is active"
                setShowBadge(false)
            }
            manager?.createNotificationChannel(channel)
        }

        // FLAG_IMMUTABLE is mandatory from API 31 (Android 12) — omitting it
        // throws IllegalArgumentException on exactly the devices reported here.
        var pendingFlags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            pendingFlags = pendingFlags or PendingIntent.FLAG_IMMUTABLE
        }
        val contentIntent = packageManager.getLaunchIntentForPackage(packageName)?.let {
            PendingIntent.getActivity(this, 0, it, pendingFlags)
        }

        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            // Pre-O there are no channels, so IMPORTANCE_LOW has nothing to
            // apply to and the notification would post at default prominence.
            // PRIORITY_LOW is its equivalent: a quiet, always-present status
            // notification rather than something demanding attention.
            @Suppress("DEPRECATION")
            Notification.Builder(this).setPriority(Notification.PRIORITY_LOW)
        }

        // Android 12+ defers a foreground-service notification for up to 10s by
        // default. For a VPN the notification IS the confirmation that traffic
        // is being filtered, so it has to appear the moment the tunnel does.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }

        val notification = builder
            .setContentTitle("AegisNet Shield")
            .setContentText("DNS filtering is active")
            // Must be a white silhouette with real transparency: Android keeps
            // only the alpha channel and tints it. A colour launcher icon comes
            // out as one solid blob.
            .setSmallIcon(R.drawable.ic_stat_aegis)
            .setOngoing(true)
            .also { b -> contentIntent?.let { b.setContentIntent(it) } }
            .build()

        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIFICATION_ID, notification, FGS_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun leaveForeground() {
        @Suppress("DEPRECATION")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            stopForeground(true)
        }
    }

    private fun startVpn(bypassApps: ArrayList<String>, interceptResolvers: Boolean) {
        if (isRunning) {
            publishStartResult(true, null)
            return
        }
        try {
            // DNS-only tunnel: advertise a private DNS server on both families
            // and route ONLY those two addresses into the TUN. Every other
            // packet (including the Rust engine's own upstream DoH lookups for
            // allowed queries) stays on the real network, so nothing loops and
            // non-DNS traffic is untouched. This also removes the need to
            // protect() upstream sockets.
            //
            // With the bypass switch on, public resolver addresses are routed
            // here too (KnownResolvers). A route captures every port, so the
            // engine answers what it cannot filter — TCP with a reset, other
            // UDP with port-unreachable — and apps fall back to the system
            // resolver. This used to swallow the engine's own DoH upstream
            // (https://1.1.1.1/dns-query) and break DNS; since the app excludes
            // itself from the VPN (addDisallowedApplication below), its own
            // sockets never enter the tunnel.
            val builder = Builder()
                .setSession("AegisNet Shield")
                .addAddress("10.0.0.2", 24)
                .addRoute(TUN_DNS_SERVER, 32)
                // The v6 half closes the IPv6 DNS leak that MIUI / Android 14
                // open by handing apps an IPv6 resolver alongside the v4 one.
                .addAddress(TUN_ADDRESS_V6, 128)
                .addRoute(TUN_DNS_SERVER_V6, 128)

            // Strict Private DNS ("hostname" mode) cannot be filtered: Android
            // speaks DoT to its provider for every lookup, on this network
            // too, and a tunnel that forwards nothing cannot carry that. With
            // our DNS server advertised the device was left with no DNS at
            // all. Without one, lookups stay on the real network — unfiltered,
            // which the dashboard warns about. The resolver routes stay out
            // as well: the provider is usually one of those addresses.
            val strictPrivateDns = strictPrivateDns()
            builtForStrictPrivateDns = strictPrivateDns
            if (!strictPrivateDns) {
                builder.addDnsServer(TUN_DNS_SERVER)
                builder.addDnsServer(TUN_DNS_SERVER_V6)
            } else {
                Log.w(TAG, "Strict Private DNS is on; the tunnel will not filter")
            }
            if (interceptResolvers && !strictPrivateDns) {
                for (address in KnownResolvers.ADDRESSES) {
                    try {
                        builder.addRoute(address, KnownResolvers.prefixLength(address))
                    } catch (e: IllegalArgumentException) {
                        // One bad route must not cost the whole tunnel.
                        Log.w(TAG, "Skipping resolver route $address", e)
                    }
                }
            }

            // Keep this app out of its own tunnel. The engine's upstream socket
            // is not routed in here, but looking up its host name is: inside
            // the VPN this process's resolver is TUN_DNS_SERVER, i.e. the
            // engine itself, which needs that same upstream to answer. With a
            // host-name upstream (https://dns.google/dns-query, tls://dns.google)
            // every lookup waited on itself until it timed out, and DNS went
            // down for the whole device. Excluded, the lookup goes to the
            // network's own resolver; the TUN fd is unaffected.
            builder.addDisallowedApplication(packageName)

            // Add disallowed apps for Split Tunneling
            for (pkg in bypassApps) {
                try {
                    builder.addDisallowedApplication(pkg)
                    Log.i(TAG, "Added bypass application: $pkg")
                } catch (e: Exception) {
                    Log.w(TAG, "Package $pkg not installed on device", e)
                }
            }

            // establish() returns null — it does NOT throw — when the platform
            // refuses the tunnel, which is what MIUI's Security app does when it
            // revokes VPN consent behind the framework's back. The previous code
            // treated that as success and left the UI claiming protection.
            val tun = builder.establish()
            if (tun == null) {
                failStart(ERROR_ESTABLISH_NULL)
                return
            }

            vpnInterface = tun
            isRunning = true
            workers = ThreadPoolExecutor(
                WORKER_THREADS,
                WORKER_THREADS,
                0L,
                TimeUnit.MILLISECONDS,
                ArrayBlockingQueue(WORKER_QUEUE_DEPTH),
            )
            vpnThread = Thread(this, "AegisVpnThread").also { it.start() }
            publishStartResult(true, null)
            AegisTileService.requestTileRefresh(this)
            Log.i(TAG, "Aegis Local VPN Started Successfully with Split Tunneling")
        } catch (e: SecurityException) {
            // Consent was never granted, or another app holds the VPN slot.
            Log.e(TAG, "Denied while establishing the tunnel", e)
            failStart(ERROR_ESTABLISH_DENIED)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start Aegis VPN", e)
            failStart(e.javaClass.simpleName + (e.message?.let { ": $it" } ?: ""))
        }
    }

    /// A tunnel that never came up must not leave a foreground notification
    /// claiming otherwise, and Dart has to hear about it.
    private fun failStart(reason: String) {
        isRunning = false
        publishStartResult(false, reason)
        AegisTileService.requestTileRefresh(this)
        leaveForeground()
        stopSelf()
    }

    /// Takes the tunnel down and leaves the service itself running.
    private fun closeTunnel() {
        isRunning = false
        // Drop in-flight work before the fd goes away, so workers are not
        // left writing to a closed descriptor.
        workers?.shutdownNow()
        workers = null
        vpnInterface?.close()
        vpnInterface = null
        vpnThread?.interrupt()
        vpnThread = null
    }

    private fun stopVpn() {
        isRunning = false
        markTunnelDown()
        AegisTileService.requestTileRefresh(this)
        try {
            closeTunnel()
            leaveForeground()
            stopSelf()
            Log.i(TAG, "Aegis Local VPN Stopped")
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping VPN", e)
        }
    }

    /// Reads the TUN and hands each packet to the worker pool.
    ///
    /// The read stays on this one thread — a single fd wants a single reader —
    /// but filtering does not. `nativeProcessPacket` blocks for the whole
    /// upstream DoH round trip on a cache miss, so doing it here made every
    /// other DNS query on the device queue behind that one lookup.
    override fun run() {
        val pfd = vpnInterface ?: return
        val inputStream = FileInputStream(pfd.fileDescriptor)
        val outputStream = FileOutputStream(pfd.fileDescriptor)
        val buffer = ByteArray(32767)

        // Tied to its own descriptor: after a rebuild isRunning is true again,
        // and this thread must not go on reading a tunnel that is gone.
        while (isRunning && vpnInterface === pfd) {
            try {
                val length = inputStream.read(buffer)
                if (length <= 0) continue
                if (!nativeAvailable) continue

                // buffer is reused by the next read, so the worker gets a copy.
                val packet = buffer.copyOf(length)
                try {
                    workers?.execute { filterAndReply(packet, outputStream) }
                } catch (e: RejectedExecutionException) {
                    // Every worker is busy and the queue is full: the upstream
                    // is struggling. Dropping is what a resolver under load does
                    // anyway, and the client will retry — but count it, because
                    // it is invisible otherwise.
                    droppedUnderLoad.incrementAndGet()
                }
            } catch (e: Exception) {
                if (!isRunning || vpnInterface !== pfd) break
                Log.e(TAG, "Error reading from the TUN interface", e)
            }
        }
    }

    /// The app whose DNS query this is, for the per-app statistics. Android
    /// 10+ lets the active VPN ask who owns a connection; the system resolver
    /// tags its query sockets with the requesting app, so this names the app,
    /// not the resolver. Anything that goes wrong only costs the attribution.
    private fun ownerUid(packet: ByteArray): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return UNKNOWN_UID
        val endpoints = PacketEndpoints.parse(packet) ?: return UNKNOWN_UID
        return try {
            val uid = connectivity?.getConnectionOwnerUid(
                OsConstants.IPPROTO_UDP,
                InetSocketAddress(endpoints.source, endpoints.sourcePort),
                InetSocketAddress(endpoints.destination, endpoints.destinationPort),
            ) ?: Process.INVALID_UID
            if (uid == Process.INVALID_UID) UNKNOWN_UID else uid
        } catch (e: Exception) {
            UNKNOWN_UID
        }
    }

    private fun filterAndReply(packet: ByteArray, outputStream: FileOutputStream) {
        try {
            val reply = nativeProcessPacket(packet, ownerUid(packet))

            // An empty reply means the packet was not a parseable IPv4/IPv6 UDP
            // DNS query. Only TUN_DNS_SERVER and TUN_DNS_SERVER_V6 are routed
            // into this interface, so that is a malformed datagram aimed at our
            // virtual resolver, and dropping it is correct.
            if (reply.isEmpty()) return

            // Every DNS query gets an answer here: blocked (NXDOMAIN),
            // SafeSearch-rewritten, cached, resolved upstream by the engine's
            // own DoH client, or SERVFAIL when that upstream is unreachable. No
            // VpnService.protect() is needed — the DoH socket is not routed into
            // the TUN, only TUN_DNS_SERVER is.
            //
            // Workers finish out of order, so writes are serialised: two threads
            // writing the same stream can interleave into a torn packet.
            synchronized(tunWriteLock) {
                outputStream.write(reply)
            }
        } catch (e: Exception) {
            if (isRunning) Log.e(TAG, "Error handling TUN packet", e)
        }
    }

    /// The system tears the tunnel down without going through stopVpn() when
    /// the user revokes consent from Settings — MIUI does this routinely. Dart
    /// must not keep showing "protected" afterwards.
    override fun onRevoke() {
        Log.w(TAG, "VPN consent revoked by the system")
        markTunnelDown(ERROR_ESTABLISH_DENIED)
        stopVpn()
        super.onRevoke()
    }

    override fun onDestroy() {
        contentResolver.unregisterContentObserver(privateDnsObserver)
        stopVpn()
        super.onDestroy()
    }
}
