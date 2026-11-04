package com.aegisnet.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Fills the engine when the tunnel comes up without the app's screen.
 *
 * The engine keeps its rules in memory, and only the Dart side knows the
 * user's saved settings and the lists kept from the last sync. A tunnel
 * started by Always-on VPN at boot, by the Quick Settings tile with the app
 * closed, or by the system restarting the service used to filter with the
 * built-in seed rules alone until the app was opened.
 *
 * This runs the Dart start-up (`restoreWithoutUi` in main.dart) in a Flutter
 * engine with no screen, and destroys that engine once Dart reports back.
 */
object HeadlessRestore {
    private const val TAG = "AegisHeadless"
    private const val ENTRYPOINT = "restoreWithoutUi"
    private const val DONE_CHANNEL = "com.aegisnet/headless"
    private const val VPN_CHANNEL = "com.aegisnet/vpn"

    /// Generous: a first start downloads every list. Past this the engine is
    /// destroyed anyway so it cannot hold memory for the life of the tunnel.
    private const val GIVE_UP_MS = 5 * 60_000L

    /// True while MainActivity's engine is alive. Its Dart side has already
    /// filled the engine and keeps it up to date, so nothing is restored then.
    @Volatile
    var uiEngineAlive = false

    private var engine: FlutterEngine? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val giveUp = Runnable {
        Log.w(TAG, "Restore did not report back; shutting it down")
        shutDown()
    }

    /// Restore unless the app's screen is up or a restore is already running.
    fun startIfNoUi(context: Context) {
        val app = context.applicationContext
        mainHandler.post {
            if (uiEngineAlive || engine != null) return@post
            try {
                start(app)
            } catch (e: Exception) {
                Log.e(TAG, "Could not restore the engine without the app", e)
                shutDown()
            }
        }
    }

    private fun start(app: Context) {
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(app)
        loader.ensureInitializationComplete(app, null)

        val headless = FlutterEngine(app)
        engine = headless
        val messenger = headless.dartExecutor.binaryMessenger

        // The part of MainActivity's channel the start-up needs. The rest
        // (consent, diagnostics, history) answers "not implemented", which the
        // Dart side already treats as "unknown".
        MethodChannel(messenger, VPN_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getFilesDir" -> result.success(app.filesDir.absolutePath)
                "resolvePackageUids" -> {
                    val packages = call.argument<List<String>>("packages") ?: emptyList()
                    result.success(resolvePackageUids(app, packages))
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(messenger, DONE_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "done") {
                result.success(null)
                // Not from inside the engine's own callback.
                mainHandler.post { shutDown() }
            } else {
                result.notImplemented()
            }
        }

        mainHandler.postDelayed(giveUp, GIVE_UP_MS)
        Log.i(TAG, "Restoring saved settings and lists without the app")
        headless.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(loader.findAppBundlePath(), ENTRYPOINT),
        )
    }

    private fun shutDown() {
        mainHandler.removeCallbacks(giveUp)
        val headless = engine ?: return
        engine = null
        headless.destroy()
        Log.i(TAG, "Restore finished")
    }
}

/// The UID behind each package. Packages that are not installed are left out
/// rather than reported.
fun resolvePackageUids(context: Context, packages: List<String>): Map<String, Int> {
    val uids = HashMap<String, Int>()
    for (name in packages) {
        try {
            uids[name] = context.packageManager.getApplicationInfo(name, 0).uid
        } catch (e: Exception) {
            // Uninstalled, or hidden from this app by package visibility.
        }
    }
    return uids
}
