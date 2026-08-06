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

        // Virtual DNS server the OS sends queries to; only this address is
        // routed into the TUN.
        private const val TUN_DNS_SERVER = "10.0.0.3"

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
            .setSmallIcon(R.mipmap.ic_launcher)
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

    override fun run() {
        val pfd = vpnInterface ?: return
        val inputStream = FileInputStream(pfd.fileDescriptor)
        val outputStream = FileOutputStream(pfd.fileDescriptor)
        val buffer = ByteArray(32767)

        while (isRunning) {
            try {
                val length = inputStream.read(buffer)
                if (length <= 0) continue

                // Hand the raw IPv4 packet to the Rust engine (when present).
                val reply =
                    if (nativeAvailable) nativeProcessPacket(buffer.copyOf(length))
                    else ByteArray(0)

                if (reply.isNotEmpty()) {
                    // Every DNS query gets an answer here: blocked (NXDOMAIN),
                    // SafeSearch-rewritten, cached, resolved upstream by the
                    // engine's own DoH client, or SERVFAIL when that upstream is
                    // unreachable. No VpnService.protect() is needed — the DoH
                    // socket is not routed into the TUN, only TUN_DNS_SERVER is.
                    outputStream.write(reply)
                }

                // An empty reply means the packet was not a parseable IPv4/UDP
                // DNS query. Only TUN_DNS_SERVER/32 is routed into this
                // interface, so that is a malformed or non-IPv4 datagram aimed
                // at our virtual resolver, and dropping it is correct.
            } catch (e: Exception) {
                if (!isRunning) break
                Log.e(TAG, "Error handling TUN packet", e)
            }
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
