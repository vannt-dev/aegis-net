package com.aegisnet.app

import android.content.Intent
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.FileInputStream
import java.io.FileOutputStream

class AegisVpnService : VpnService(), Runnable {

    companion object {
        const val ACTION_START = "com.aegisnet.app.START"
        const val ACTION_STOP = "com.aegisnet.app.STOP"
        private const val TAG = "AegisVpnService"

        /// True when libaegis_core.so (the Rust DNS engine) is present. Built
        /// per-ABI via cargo-ndk; absent in UI-only builds. Loading must never
        /// crash the service, mirroring the graceful fallback on the Dart side.
        @Volatile
        var nativeAvailable: Boolean = false
            private set

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
        val action = intent?.action
        if (action == ACTION_START) {
            val bypassApps = intent.getStringArrayListExtra("bypassApps") ?: arrayListOf()
            startVpn(bypassApps)
        } else if (action == ACTION_STOP) {
            stopVpn()
        }
        return START_STICKY
    }

    private fun startVpn(bypassApps: ArrayList<String>) {
        if (isRunning) return
        try {
            val builder = Builder()
                .setSession("AegisNet Shield")
                .addAddress("10.0.0.1", 32)
                .addDnsServer("1.1.1.1")
                .addRoute("0.0.0.0", 0)

            // Add disallowed apps for Split Tunneling
            for (pkg in bypassApps) {
                try {
                    builder.addDisallowedApplication(pkg)
                    Log.i(TAG, "Added bypass application: $pkg")
                } catch (e: Exception) {
                    Log.w(TAG, "Package $pkg not installed on device", e)
                }
            }

            vpnInterface = builder.establish()
            isRunning = true

            vpnThread = Thread(this, "AegisVpnThread")
            vpnThread?.start()
            Log.i(TAG, "Aegis Local VPN Started Successfully with Split Tunneling")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start Aegis VPN", e)
        }
    }

    private fun stopVpn() {
        isRunning = false
        try {
            vpnInterface?.close()
            vpnInterface = null
            vpnThread?.interrupt()
            vpnThread = null
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
                    // A synthesized DNS reply (blocked / SafeSearch / cached) —
                    // write it straight back to the client.
                    outputStream.write(reply)
                }

                // NOTE: packets without a synthesized reply — allowed cache-miss
                // DNS queries and all non-DNS traffic — are currently dropped.
                // Forwarding them to the real network requires a socket excluded
                // from the tunnel via VpnService.protect(); tracked as follow-up.
            } catch (e: Exception) {
                if (!isRunning) break
                Log.e(TAG, "Error handling TUN packet", e)
            }
        }
    }

    override fun onDestroy() {
        stopVpn()
        super.onDestroy()
    }
}
