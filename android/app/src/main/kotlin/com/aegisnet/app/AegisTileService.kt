package com.aegisnet.app

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log
import androidx.annotation.RequiresApi

@RequiresApi(Build.VERSION_CODES.N)
class AegisTileService : TileService() {

    companion object {
        private const val TAG = "AegisTile"

        /// Ask the platform to re-bind the tile so it re-reads tunnel state.
        ///
        /// Without this the tile only refreshes when the user opens the shade,
        /// so it keeps claiming "ON" after the tunnel goes down — which on
        /// MIUI happens routinely, because its Security app revokes VPN
        /// consent behind the framework's back.
        fun requestTileRefresh(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
            try {
                requestListeningState(
                    context,
                    ComponentName(context, AegisTileService::class.java),
                )
            } catch (e: Exception) {
                // Not fatal: the tile is a convenience, and some vendor ROMs
                // reject this for apps they consider backgrounded.
                Log.w(TAG, "Could not request a tile refresh", e)
            }
        }
    }

    override fun onStartListening() {
        super.onStartListening()
        updateTileState()
    }

    override fun onClick() {
        super.onClick()

        if (AegisVpnService.isTunnelUp) {
            sendToService(AegisVpnService.ACTION_STOP, foreground = false)
        } else {
            // Consent has to be granted from an Activity, which a tile cannot
            // show; bounce to the app and let it ask.
            val prepareIntent = try {
                VpnService.prepare(this)
            } catch (e: Exception) {
                // Several MIUI builds throw here instead of returning an
                // intent, the same way they do in MainActivity.
                Log.e(TAG, "VpnService.prepare() failed", e)
                openApp()
                return
            }

            if (prepareIntent != null) {
                openApp()
            } else {
                sendToService(AegisVpnService.ACTION_START, foreground = true)
            }
        }

        // The tile reflects `isTunnelUp`, which only becomes true once
        // establish() returns — after this method has already finished. The
        // service calls back through requestTileRefresh() when it knows; this
        // is only to show the intermediate state.
        updateTileState()
    }

    /// Hand a command to the tunnel service.
    ///
    /// Android 12 refuses to start a foreground service from the background
    /// unless the app qualifies for one of the platform's exemptions, and a
    /// Quick Settings click is not on that list. That makes
    /// `ForegroundServiceStartNotAllowedException` a routine outcome of
    /// tapping the tile with the app closed — and it is a RuntimeException, so
    /// leaving it uncaught takes the tile down instead of the toggle simply
    /// not working. Fall back to opening the app, which puts the user in a
    /// foreground context where the start is allowed.
    private fun sendToService(action: String, foreground: Boolean) {
        val intent = Intent(this, AegisVpnService::class.java).apply {
            this.action = action
        }

        try {
            if (foreground && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (e: IllegalStateException) {
            // ForegroundServiceStartNotAllowedException extends this on API 31+.
            Log.w(TAG, "Background start refused for $action; opening the app", e)
            openApp()
        } catch (e: SecurityException) {
            Log.e(TAG, "Not allowed to start the tunnel service", e)
        }
    }

    /// Bring the app to the front and collapse the shade.
    ///
    /// `startActivityAndCollapse(Intent)` is not merely deprecated on API 34+:
    /// it throws UnsupportedOperationException for apps targeting that level,
    /// so the Intent overload would crash the tile on Android 14 and newer.
    /// The PendingIntent overload only exists from 34, hence both paths.
    @Suppress("DEPRECATION")
    private fun openApp() {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        } ?: run {
            Log.w(TAG, "No launch intent for $packageName; cannot ask for VPN consent")
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pending = PendingIntent.getActivity(
                this,
                0,
                launchIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            startActivityAndCollapse(pending)
        } else {
            startActivityAndCollapse(launchIntent)
        }
    }

    private fun updateTileState() {
        val tile = qsTile ?: return
        val isActive = AegisVpnService.isTunnelUp
        tile.state = if (isActive) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = if (isActive) "AegisNet Shield (ON)" else "AegisNet Shield (OFF)"
        tile.updateTile()
    }
}
