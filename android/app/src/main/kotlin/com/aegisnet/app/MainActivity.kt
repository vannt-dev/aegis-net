package com.aegisnet.app

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.Uri
import android.net.VpnService
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
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
        private const val PICK_FILE_REQUEST_CODE = 0xAF3
        private const val LOCATION_REQUEST_CODE = 0xAF4

        /// Largest blocklist file the import reads. The biggest lists offered
        /// in the app are a few megabytes; a file past this is not a list.
        private const val MAX_IMPORT_BYTES = 32L * 1024 * 1024

        /// Why a picked file could not be imported. The picker being closed
        /// without a choice is not an error; it answers null.
        private const val ERROR_FILE_TOO_LARGE = "file_too_large"
        private const val ERROR_FILE_UNREADABLE = "file_unreadable"
        private const val ERROR_PICKER_UNAVAILABLE = "picker_unavailable"

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
    private var pendingIntercept = true

    private val mainHandler = Handler(Looper.getMainLooper())
    private var startTimeout: Runnable? = null

    /// Reply to a "pickBlocklistFile" call waiting on the system file picker.
    private var pendingPickResult: MethodChannel.Result? = null

    /// Reply to a "requestLocationAccess" call waiting on the system prompt.
    private var pendingLocationResult: MethodChannel.Result? = null

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
        // From here this screen's Dart side fills the engine itself.
        HeadlessRestore.uiEngineAlive = true

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        // A pause or a toggle from the notification or the widget happens
        // behind this screen's back; tell its Dart side what the tunnel did.
        AegisVpnService.stateListener = {
            mainHandler.post {
                try {
                    channel.invokeMethod("tunnelStateChanged", collectDiagnostics())
                } catch (e: Exception) {
                    Log.w(TAG, "Could not report the tunnel state", e)
                }
            }
        }
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startVpn" -> {
                    val bypassAppsRaw = call.argument<List<String>>("bypassApps") ?: emptyList()
                    val bypassApps = ArrayList(bypassAppsRaw)
                    pendingBypassApps = bypassApps
                    val intercept = call.argument<Boolean>("interceptHardcodedDns") ?: true
                    pendingIntercept = intercept

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
                        startAegisVpnService(bypassApps, intercept)
                    }
                }
                "stopVpn" -> {
                    stopAegisVpnService()
                    result.success(true)
                }
                // The running tunnel holds a pause and ends it by itself, so
                // it ends on time even when the app has been closed. False
                // when no tunnel is up; Dart then falls back to stopping it.
                "pauseVpn" -> {
                    val until = call.argument<Number>("until")?.toLong() ?: 0L
                    if (!AegisVpnService.isTunnelUp) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    result.success(sendToService(Intent(this, AegisVpnService::class.java).apply {
                        action = AegisVpnService.ACTION_PAUSE
                        putExtra(AegisVpnService.EXTRA_PAUSED_UNTIL, until)
                    }))
                }
                "resumeVpn" -> {
                    if (!AegisVpnService.isTunnelUp) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val bypassApps = ArrayList(call.argument<List<String>>("bypassApps") ?: emptyList())
                    val intercept = call.argument<Boolean>("interceptHardcodedDns") ?: true
                    result.success(sendToService(Intent(this, AegisVpnService::class.java).apply {
                        action = AegisVpnService.ACTION_RESUME
                        putStringArrayListExtra("bypassApps", bypassApps)
                        putExtra(AegisVpnService.EXTRA_INTERCEPT, intercept)
                    }))
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
                // The engine keeps the per-day history there; the screen opens
                // it too, so the history shows while the tunnel is off.
                // Downloaded filter lists are kept under it between runs.
                // Today's blocked count for the home-screen widget, which has
                // no other way to know it.
                "updateWidget" -> {
                    val day = call.argument<Number>("day")?.toLong()
                    val blocked = call.argument<Number>("blocked")?.toLong()
                    if (day != null && blocked != null) AegisWidget.saveBlocked(this, day, blocked)
                    result.success(day != null && blocked != null)
                }
                // Something the notification and the widget show changed in
                // the app (the app lock); post them again.
                "refreshNativeUi" -> {
                    if (AegisVpnService.isTunnelUp) {
                        sendToService(
                            Intent(this, AegisVpnService::class.java)
                                .setAction(AegisVpnService.ACTION_REFRESH),
                        )
                    } else {
                        AegisWidget.refresh(this)
                    }
                    result.success(true)
                }
                // The networks protection applies on were changed; the running
                // tunnel looks at the network again.
                "applyNetworkRule" -> {
                    if (AegisVpnService.isTunnelUp) {
                        sendToService(
                            Intent(this, AegisVpnService::class.java)
                                .setAction(AegisVpnService.ACTION_NETWORK_RULE),
                        )
                    }
                    result.success(true)
                }
                // Wi-Fi names can only be read with location access. Asked
                // for only when the user turns on the Wi-Fi network list.
                "getLocationAccess" -> result.success(locationAccess())
                "requestLocationAccess" ->
                    requestLocationAccess(call.argument<Boolean>("background") ?: false, result)
                "currentWifiSsid" -> result.success(currentWifiSsid())
                "pickBlocklistFile" -> pickBlocklistFile(result)
                "getFilesDir" -> result.success(filesDir.absolutePath)
                "getHistoryPath" -> result.success(
                    AegisVpnService.historyFile(this).absolutePath,
                )
                // Names for the UIDs in the per-app statistics. Never fails as a
                // whole: a UID that cannot be named comes back with nulls.
                "resolveApps" -> {
                    val uids = call.argument<List<Int>>("uids") ?: emptyList()
                    result.success(uids.map { resolveApp(it) })
                }
                // The UID behind each package the user has blocked. A UID is
                // only stable while the app stays installed, so the list is
                // kept by package name and looked up again at every start.
                "resolvePackageUids" -> {
                    val packages = call.argument<List<String>>("packages") ?: emptyList()
                    result.success(resolvePackageUids(this, packages))
                }
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

    private fun declared(permission: String): Boolean = try {
        @Suppress("DEPRECATION")
        packageManager.getPackageInfo(packageName, PackageManager.GET_PERMISSIONS)
            .requestedPermissions?.contains(permission) == true
    } catch (e: Exception) {
        false
    }

    private fun granted(permission: String): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    /// What the app may do with location, which is what reading the name of
    /// the Wi-Fi network takes. "background" is the "Allow all the time"
    /// choice, which Android 10+ needs before a closed app may read it.
    private fun locationAccess(): Map<String, Any?> {
        val fine = granted(Manifest.permission.ACCESS_FINE_LOCATION)
        val background = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            granted(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
        } else {
            fine
        }
        // A build without "all the time" in its manifest cannot ask for it;
        // the screen then does not offer it.
        val backgroundAvailable = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
            declared(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
        val locationOn = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                getSystemService(LocationManager::class.java)?.isLocationEnabled
            } else {
                @Suppress("DEPRECATION")
                Settings.Secure.getInt(contentResolver, Settings.Secure.LOCATION_MODE) !=
                    Settings.Secure.LOCATION_MODE_OFF
            }
        } catch (e: Exception) {
            null
        }
        return mapOf(
            "sdkInt" to Build.VERSION.SDK_INT,
            "fine" to fine,
            "background" to background,
            "backgroundAvailable" to backgroundAvailable,
            "locationOn" to locationOn,
        )
    }

    /// Ask for location access: first while the app is in use, then, on
    /// Android 10+ and only when [background] is set, all the time (Android
    /// 11+ shows the app's permission page for that). Answers with
    /// [locationAccess] once the user has chosen.
    private fun requestLocationAccess(background: Boolean, result: MethodChannel.Result) {
        pendingLocationResult?.success(locationAccess())
        pendingLocationResult = null
        val permissions = if (background && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
        } else {
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION,
            )
        }
        if (permissions.all { granted(it) } || Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.success(locationAccess())
            return
        }
        pendingLocationResult = result
        try {
            requestPermissions(permissions, LOCATION_REQUEST_CODE)
        } catch (e: Exception) {
            Log.w(TAG, "Could not request location access", e)
            pendingLocationResult = null
            result.success(locationAccess())
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != LOCATION_REQUEST_CODE) return
        val result = pendingLocationResult ?: return
        pendingLocationResult = null
        result.success(locationAccess())
        // A tunnel already watching the network may read the name now.
        if (AegisVpnService.isTunnelUp) {
            sendToService(
                Intent(this, AegisVpnService::class.java)
                    .setAction(AegisVpnService.ACTION_NETWORK_RULE),
            )
        }
    }

    /// The name of the Wi-Fi network in use, or null when there is none or
    /// it cannot be read (no location access, or location turned off).
    private fun currentWifiSsid(): String? = try {
        @Suppress("DEPRECATION")
        val ssid = applicationContext.getSystemService(WifiManager::class.java)?.connectionInfo?.ssid
        NetworkRule.normalizeSsid(ssid)
    } catch (e: Exception) {
        null
    }

    /// With the Wi-Fi network list on, the tunnel reads the network's name
    /// while the app is open: without "Allow all the time" Android hides it
    /// from the app in the background, and one read lasts the connection.
    override fun onResume() {
        super.onResume()
        try {
            val rule = NetworkRule.load(this)
            if (AegisVpnService.isTunnelUp && rule.active && rule.exceptionsOn) {
                sendToService(
                    Intent(this, AegisVpnService::class.java)
                        .setAction(AegisVpnService.ACTION_NETWORK_RULE),
                )
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not hand the tunnel the network", e)
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

    private fun resolveApp(uid: Int): Map<String, Any?> {
        val unknown = mapOf(
            "uid" to uid,
            "package" to null,
            "label" to null,
            "isSystem" to false,
            "sharedCount" to 0,
        )
        if (uid < 0) return unknown
        return try {
            val packages = packageManager.getPackagesForUid(uid)
            if (packages.isNullOrEmpty()) return unknown
            val info = packageManager.getApplicationInfo(packages[0], 0)
            mapOf(
                "uid" to uid,
                "package" to packages[0],
                "label" to packageManager.getApplicationLabel(info).toString(),
                "isSystem" to ((info.flags and ApplicationInfo.FLAG_SYSTEM) != 0),
                "sharedCount" to packages.size - 1,
            )
        } catch (e: Exception) {
            unknown
        }
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
            "pausedUntil" to AegisVpnService.pausedUntilMs,
            "networkIdle" to AegisVpnService.networkIdle,
            "nativeEngineLoaded" to AegisVpnService.nativeAvailable,
            "notificationsAllowed" to notificationsAllowed(),
            "droppedUnderLoad" to AegisVpnService.droppedUnderLoad.get(),
            "privateDnsMode" to privateDnsMode,
            "lastError" to AegisVpnService.lastError,
        )
    }

    private fun startAegisVpnService(
        bypassApps: ArrayList<String> = arrayListOf(),
        intercept: Boolean = true,
    ) {
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
            putExtra(AegisVpnService.EXTRA_INTERCEPT, intercept)
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

    /// For a service that is already running in the foreground.
    private fun sendToService(intent: Intent): Boolean = try {
        startService(intent)
        true
    } catch (e: Exception) {
        Log.e(TAG, "Could not reach the tunnel service", e)
        false
    }

    private fun stopAegisVpnService() {
        val intent = Intent(this, AegisVpnService::class.java).apply {
            action = AegisVpnService.ACTION_STOP
        }
        startService(intent)
    }

    /// Let the user choose a blocklist file with the system picker. Any type
    /// is offered: a hosts file usually has no extension, and the Dart side
    /// checks what is inside instead.
    private fun pickBlocklistFile(result: MethodChannel.Result) {
        pendingPickResult?.success(null)
        pendingPickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType("*/*")
        try {
            startActivityForResult(intent, PICK_FILE_REQUEST_CODE)
        } catch (e: Exception) {
            Log.e(TAG, "No file picker on this device", e)
            pendingPickResult = null
            result.error(ERROR_PICKER_UNAVAILABLE, e.message, null)
        }
    }

    /// Read the picked file off the main thread and answer the waiting call
    /// with its name and text.
    private fun readPickedFile(uri: Uri) {
        val result = pendingPickResult ?: return
        pendingPickResult = null
        Thread {
            val reply: Pair<Map<String, Any?>?, String?> = try {
                val name = displayName(uri)
                val size = fileSize(uri)
                if (size != null && size > MAX_IMPORT_BYTES) {
                    null to ERROR_FILE_TOO_LARGE
                } else {
                    val bytes = contentResolver.openInputStream(uri)?.use { input ->
                        // The size a provider reports can be missing or wrong;
                        // never read past the cap whatever it said.
                        input.readNBytesCompat(MAX_IMPORT_BYTES + 1)
                    }
                    when {
                        bytes == null -> null to ERROR_FILE_UNREADABLE
                        bytes.size > MAX_IMPORT_BYTES -> null to ERROR_FILE_TOO_LARGE
                        else -> mapOf("name" to name, "text" to String(bytes, Charsets.UTF_8)) to null
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Could not read the picked file", e)
                null to ERROR_FILE_UNREADABLE
            }
            mainHandler.post {
                val (value, error) = reply
                if (error != null) result.error(error, null, null) else result.success(value)
            }
        }.start()
    }

    private fun displayName(uri: Uri): String? = try {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { if (it.moveToFirst()) it.getString(0) else null }
    } catch (e: Exception) {
        null
    }

    private fun fileSize(uri: Uri): Long? = try {
        contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use {
            if (it.moveToFirst() && !it.isNull(0)) it.getLong(0) else null
        }
    } catch (e: Exception) {
        null
    }

    /// InputStream.readNBytes is API 33; this reads at most [limit] bytes on
    /// every version.
    private fun java.io.InputStream.readNBytesCompat(limit: Long): ByteArray {
        val out = java.io.ByteArrayOutputStream()
        val buffer = ByteArray(64 * 1024)
        var total = 0L
        while (total < limit) {
            val read = read(buffer, 0, minOf(buffer.size.toLong(), limit - total).toInt())
            if (read < 0) break
            out.write(buffer, 0, read)
            total += read
        }
        return out.toByteArray()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PICK_FILE_REQUEST_CODE) {
            val uri = data?.data
            if (resultCode == Activity.RESULT_OK && uri != null) {
                readPickedFile(uri)
            } else {
                pendingPickResult?.success(null)
                pendingPickResult = null
            }
            return
        }
        if (requestCode != VPN_REQUEST_CODE) return

        if (resultCode == Activity.RESULT_OK) {
            // Consent granted; the tunnel still has to come up before the Dart
            // caller is told anything.
            startAegisVpnService(pendingBypassApps, pendingIntercept)
        } else {
            settleVpnResult(false, ERROR_CONSENT_DENIED)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        HeadlessRestore.uiEngineAlive = false
        AegisVpnService.stateListener = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        // Never leave the Dart side awaiting a reply that can no longer arrive.
        settleVpnResult(false)
        pendingPickResult?.success(null)
        pendingPickResult = null
        pendingLocationResult?.success(locationAccess())
        pendingLocationResult = null
        mainHandler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }
}
