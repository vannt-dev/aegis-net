package com.aegisnet.app

import android.content.Intent
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer

class AegisVpnService : VpnService(), Runnable {

    companion object {
        const val ACTION_START = "com.aegisnet.app.START"
        const val ACTION_STOP = "com.aegisnet.app.STOP"
        private const val TAG = "AegisVpnService"
    }

    private var vpnInterface: ParcelFileDescriptor? = null
    private var vpnThread: Thread? = null
    @Volatile private var isRunning = false

    override fn onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == ACTION_START) {
            startVpn()
        } else if (action == ACTION_STOP) {
            stopVpn()
        }
        return START_STICKY
    }

    private fun startVpn() {
        if (isRunning) return
        try {
            val builder = Builder()
                .setSession("AegisNet Shield")
                .addAddress("10.0.0.1", 32)
                .addDnsServer("1.1.1.1")
                .addRoute("0.0.0.0", 0)

            vpnInterface = builder.establish()
            isRunning = true

            vpnThread = Thread(this, "AegisVpnThread")
            vpnThread?.start()
            Log.i(TAG, "Aegis Local VPN Started Successfully")
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
        val buffer = ByteBuffer.allocate(32767)

        while (isRunning) {
            try {
                val length = inputStream.read(buffer.array())
                if (length > 0) {
                    // Packet received from OS TUN interface.
                    // Pass to Rust Core engine via FFI handle_dns_packet
                    buffer.limit(length)
                    buffer.rewind()
                    
                    // Note: Here Rust handle_dns_packet processes DNS payload
                    // and outputStream.write(...) sends response back to OS
                    buffer.clear()
                }
            } catch (e: Exception) {
                if (!isRunning) break
                Log.e(TAG, "Error reading from TUN interface", e)
            }
        }
    }

    override fun onDestroy() {
        stopVpn()
        super.onDestroy()
    }
}
