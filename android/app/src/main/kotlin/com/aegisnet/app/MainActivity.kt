package com.aegisnet.app

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {

    companion object {
        private const val TAG = "AegisMainActivity"
        private const val CHANNEL = "com.aegisnet/vpn"
        private const val VPN_REQUEST_CODE = 0xAF1
        private const val NOTIFICATION_REQUEST_CODE = 0xAF2

        /// The consent dialog was shown and the user said no.
        private const val ERROR_CONSENT_DENIED = "consent_denied"

        /// The ROM could not show the consent dialog at all. Several MIUI builds
        /// strip or lock down com.android.vpndialogs, so startActivityForResult
        /// throws and no popup ever appears — the reported Xiaomi symptom.
        private const val ERROR_CONSENT_UNAVAILABLE = "consent_dialog_unavailable"

        /// VpnService.prepare() itself failed, which vendor VPN-management
        /// layers do instead of returning an intent.
        private const val ERROR_PREPARE_FAILED = "vpn_prepare_failed"

        /// The service never reported back. Better than leaving the Dart caller
        /// awaiting a reply that is not coming.
        private const val ERROR_START_TIMEOUT = "tunnel_start_timeout"

        /// establish() is quick; anything past this is a stuck vendor layer.
        private const val START_TIMEOUT_MS = 15_000L
    }

    /**
     * Reply to a "startVpn" call that is waiting on the system consent dialog
     * or on the tunnel actually coming up. Held so the Dart caller's await
     * resolves to whether the tunnel really started, instead of returning false
     * and never correcting itself.
     */
    private var pendingVpnResult: MethodChannel.Result? = null
    private var pendingBypassApps: ArrayList<String> = arrayListOf()

    private val mainHandler = Handler(Looper.getMainLooper())
    private var startTimeout: Runnable? = null

    /**
     * Answer the waiting Dart call exactly once. [error] non-null means the
     * tunnel is down and the UI has a reason to show; the old code could only
     * say "false", which is why the Xiaomi failure looked like nothing
     * happening at all.
     */
    private fun settleVpnResult(started: Boolean, error: String? = null) {
        startTimeout?.let { mainHandler.removeCallbacks(it) }
        startTimeout = null
        AegisVpnService.startListener = null

        val result = pendingVpnResult ?: return
        pendingVpnResult = null
        if (error != null) {
            result.error(error, "AegisNet tunnel did not start: $error", null)
        } else {
            result.success(started)
            if (started) requestNotificationPermission()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startVpn" -> {
                    val bypassAppsRaw = call.argument<List<String>>("bypassApps") ?: emptyList()
                    val bypassApps = ArrayList(bypassAppsRaw)
                    pendingBypassApps = bypassApps

                    val consent = try {
                        VpnService.prepare(this)
                    } catch (e: Exception) {
                        Log.e(TAG, "VpnService.prepare() failed", e)
                        result.error(ERROR_PREPARE_FAILED, e.message, null)
                        return@setMethodCallHandler
                    }

                    // Abandon any earlier request still waiting, so a stale
                    // consent prompt can never answer this one.
                    settleVpnResult(false)
                    pendingVpnResult = result

                    if (consent != null) {
                        try {
                            startActivityForResult(consent, VPN_REQUEST_CODE)
                        } catch (e: Exception) {
                            Log.e(TAG, "Could not show the VPN consent dialog", e)
                            settleVpnResult(false, ERROR_CONSENT_UNAVAILABLE)
                        }
                    } else {
                        // Consent is already on record — but that says nothing
                        // about whether the tunnel can be established, so wait
                        // for the service instead of assuming success.
                        startAegisVpnService(bypassApps)
                    }
                }
                "stopVpn" -> {
                    stopAegisVpnService()
                    result.success(true)
                }
                "isVpnPrepared" -> {
                    val intent = try {
                        VpnService.prepare(this)
                    } catch (e: Exception) {
                        Log.e(TAG, "VpnService.prepare() failed", e)
                        result.error(ERROR_PREPARE_FAILED, e.message, null)
                        return@setMethodCallHandler
                    }
                    result.success(intent == null)
                }
                // Everything the app can observe about why filtering may not be
                // working on this device. Vendor ROMs fail in ways the app
                // cannot fix, so at minimum it can report them.
                "getVpnDiagnostics" -> result.success(collectDiagnostics())
                "openPrivateDnsSettings" -> result.success(openPrivateDnsSettings())
                else -> result.notImplemented()
            }
        }
    }

    /// True when the ongoing tunnel notification can actually be shown.
    /// Notifications are opt-in from Android 13, and a fresh install starts out
    /// denied, so the foreground service runs with its notification invisible.
    private fun notificationsAllowed(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    /// Asked only once the tunnel is actually up: the user has just approved a
    /// VPN, so a prompt about seeing its status is in context. Deliberately not
    /// blocking — a denial costs visibility, not filtering, and the request must
    /// never collide with the system VPN consent dialog.
    private fun requestNotificationPermission() {
        if (notificationsAllowed()) return
        try {
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                NOTIFICATION_REQUEST_CODE,
            )
        } catch (e: Exception) {
            Log.w(TAG, "Could not request POST_NOTIFICATIONS", e)
        }
    }

    /// Private DNS lives under Network & internet on stock Android and
    /// somewhere else entirely on most vendor ROMs, so try the dedicated screen
    /// first and fall back to the wireless settings root.
    private fun openPrivateDnsSettings(): Boolean {
        val targets = listOf(
            "android.settings.PRIVATE_DNS_SETTINGS",
            Settings.ACTION_WIRELESS_SETTINGS,
        )
        for (action in targets) {
            try {
                startActivity(Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return true
            } catch (e: Exception) {
                Log.w(TAG, "Settings screen $action unavailable", e)
            }
        }
        return false
    }

    private fun collectDiagnostics(): Map<String, Any?> {
        val consentGranted = try {
            VpnService.prepare(this) == null
        } catch (e: Exception) {
            null
        }

        // Private DNS in "opportunistic"/"hostname" mode makes the resolver
        // speak DoT straight to the underlying network, bypassing the tunnel's
        // DNS server entirely — filtering silently does nothing. MIUI defaults
        // this to automatic.
        val privateDnsMode = try {
            Settings.Global.getString(contentResolver, "private_dns_mode")
        } catch (e: Exception) {
            null
        }

        return mapOf(
            "sdkInt" to Build.VERSION.SDK_INT,
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "consentGranted" to consentGranted,
            "tunnelUp" to AegisVpnService.isTunnelUp,
            "nativeEngineLoaded" to AegisVpnService.nativeAvailable,
            "notificationsAllowed" to notificationsAllowed(),
            "droppedUnderLoad" to AegisVpnService.droppedUnderLoad.get(),
            "privateDnsMode" to privateDnsMode,
            "lastError" to AegisVpnService.lastError,
        )
    }

    private fun startAegisVpnService(bypassApps: ArrayList<String> = arrayListOf()) {
        // The service reports what establish() actually did. Without this the
        // reply was success(true) the moment startService() returned, whether or
        // not a tunnel existed.
        AegisVpnService.startListener = { started, error ->
            mainHandler.post { settleVpnResult(started, if (started) null else error) }
        }

        startTimeout = Runnable { settleVpnResult(false, ERROR_START_TIMEOUT) }
            .also { mainHandler.postDelayed(it, START_TIMEOUT_MS) }

        val intent = Intent(this, AegisVpnService::class.java).apply {
            action = AegisVpnService.ACTION_START
            putStringArrayListExtra("bypassApps", bypassApps)
        }
        // The service goes foreground as its first act, so it must be started
        // as one on O+ — a plain startService() is killed on MIUI within
        // seconds of the user leaving the app.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
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

        if (resultCode == Activity.RESULT_OK) {
            // Consent granted; the tunnel still has to come up before the Dart
            // caller is told anything.
            startAegisVpnService(pendingBypassApps)
        } else {
            settleVpnResult(false, ERROR_CONSENT_DENIED)
        }
    }

    override fun onDestroy() {
        // Never leave the Dart side awaiting a reply that can no longer arrive.
        settleVpnResult(false)
        mainHandler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }
}
