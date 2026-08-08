package com.aegisnet.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.FileInputStream
import java.io.FileOutputStream
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

        private const val CHANNEL_ID = "aegis_vpn_status"
        private const val NOTIFICATION_ID = 0xA3

        /// ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE (API 34). Spelled as
        /// a literal so the module still compiles against an older compileSdk.
        private const val FGS_TYPE_SPECIAL_USE = 1 shl 30

        // Virtual DNS servers the OS sends queries to; only these addresses are
        // routed into the TUN.
        private const val TUN_DNS_SERVER = "10.0.0.3"
        private const val TUN_DNS_SERVER_V6 = "fd00:aegis::3"

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

    /// Filters a raw IPv4 packet read from the TUN interface. Returns a DNS
    /// reply packet to write back, or an empty array when there is nothing to
    /// inject (non-DNS traffic or an allowed query).
    private external fun nativeProcessPacket(packet: ByteArray): ByteArray

    private var vpnInterface: ParcelFileDescriptor? = null
    private var vpnThread: Thread? = null
    @Volatile private var isRunning = false

    /// Filtering runs here instead of on the reader thread. Sized for the work:
    /// blocked and cached answers return in microseconds and never occupy a
    /// worker for long, so this only has to cover concurrent cache misses, each
    /// bounded by the engine's 2.5s DoH timeout.
    private var workers: ThreadPoolExecutor? = null
    private val tunWriteLock = Any()

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                // Go foreground BEFORE building the tunnel. Android 12 kills a
                // service that has not posted its notification within 5s of
                // startForegroundService(), and MIUI reaps plain background
                // services within seconds of the user leaving the app — which
                // is why the tunnel kept dying on Xiaomi devices.
                enterForeground()
                startVpn(intent.getStringArrayListExtra("bypassApps") ?: arrayListOf())
            }
            ACTION_STOP -> stopVpn()
        }
        return START_STICKY
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

    private fun startVpn(bypassApps: ArrayList<String>) {
        if (isRunning) {
            publishStartResult(true, null)
            return
        }
        try {
            // DNS-only tunnel: advertise a private DNS server and route ONLY
            // its address into the TUN. Every other packet (including the Rust
            // engine's own upstream DoH lookups for allowed queries) stays on
            // the real network, so nothing loops and non-DNS traffic is
            // untouched. This also removes the need to protect() upstream
            // sockets.
            val builder = Builder()
                .setSession("AegisNet Shield")
                .addAddress("10.0.0.2", 24)
                .addDnsServer(TUN_DNS_SERVER)
                .addRoute(TUN_DNS_SERVER, 32)
                // Register IPv6 TUN & DNS Route to prevent IPv6 DNS leaks (especially on MIUI / Android 14)
                .addAddress("fd00:aegis::2", 128)
                .addDnsServer(TUN_DNS_SERVER_V6)
                .addRoute(TUN_DNS_SERVER_V6, 128)
                // Intercept common hardcoded public DNS addresses to prevent app DNS bypasses
                .addRoute("8.8.8.8", 32)
                .addRoute("8.8.4.4", 32)
                .addRoute("1.1.1.1", 32)
                .addRoute("1.0.0.1", 32)
                .addRoute("9.9.9.9", 32)
                .addRoute("2001:4860:4860::8888", 128)
                .addRoute("2001:4860:4860::8844", 128)
                .addRoute("2606:4700:4700::1111", 128)
                .addRoute("2606:4700:4700::1001", 128)

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
        leaveForeground()
        stopSelf()
    }

    private fun stopVpn() {
        isRunning = false
        markTunnelDown()
        try {
            // Drop in-flight work before the fd goes away, so workers are not
            // left writing to a closed descriptor.
            workers?.shutdownNow()
            workers = null
            vpnInterface?.close()
            vpnInterface = null
            vpnThread?.interrupt()
            vpnThread = null
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

        while (isRunning) {
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
                if (!isRunning) break
                Log.e(TAG, "Error reading from the TUN interface", e)
            }
        }
    }

    private fun filterAndReply(packet: ByteArray, outputStream: FileOutputStream) {
        try {
            val reply = nativeProcessPacket(packet)

            // An empty reply means the packet was not a parseable IPv4/UDP DNS
            // query. Only TUN_DNS_SERVER/32 is routed into this interface, so
            // that is a malformed or non-IPv4 datagram aimed at our virtual
            // resolver, and dropping it is correct.
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
        stopVpn()
        super.onDestroy()
    }
}
