package com.aegisnet.app

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.aegisnet/vpn"
        private const val VPN_REQUEST_CODE = 0xAF1
    }

    /**
     * Reply to a "startVpn" call that is waiting on the system consent dialog.
     * Held so the Dart caller's await resolves to whether the tunnel actually
     * started, instead of returning false and never correcting itself.
     */
    private var pendingVpnResult: MethodChannel.Result? = null

    private fun settleVpnResult(started: Boolean) {
        pendingVpnResult?.success(started)
        pendingVpnResult = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startVpn" -> {
                    val intent = VpnService.prepare(this)
                    if (intent != null) {
                        // Consent required: hold the reply until onActivityResult.
                        // Abandon any earlier request still waiting, so a stale
                        // consent prompt can never answer this one.
                        settleVpnResult(false)
                        pendingVpnResult = result
                        startActivityForResult(intent, VPN_REQUEST_CODE)
                    } else {
                        startAegisVpnService()
                        result.success(true)
                    }
                }
                "stopVpn" -> {
                    stopAegisVpnService()
                    result.success(true)
                }
                "isVpnPrepared" -> {
                    val intent = VpnService.prepare(this)
                    result.success(intent == null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startAegisVpnService() {
        val intent = Intent(this, AegisVpnService::class.java).apply {
            action = AegisVpnService.ACTION_START
        }
        startService(intent)
    }

    private fun stopAegisVpnService() {
        val intent = Intent(this, AegisVpnService::class.java).apply {
            action = AegisVpnService.ACTION_STOP
        }
        startService(intent)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != VPN_REQUEST_CODE) return

        val granted = resultCode == Activity.RESULT_OK
        if (granted) {
            startAegisVpnService()
        }
        settleVpnResult(granted)
    }

    override fun onDestroy() {
        // Never leave the Dart side awaiting a reply that can no longer arrive.
        settleVpnResult(false)
        super.onDestroy()
    }
}
