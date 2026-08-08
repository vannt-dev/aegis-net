package com.aegisnet.app

import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi

@RequiresApi(Build.VERSION_CODES.N)
class AegisTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        updateTileState()
    }

    override fun onClick() {
        super.onClick()
        val isTunnelUp = AegisVpnService.isTunnelUp
        if (isTunnelUp) {
            val intent = Intent(this, AegisVpnService::class.java).apply {
                action = AegisVpnService.ACTION_STOP
            }
            startService(intent)
        } else {
            val prepareIntent = VpnService.prepare(this)
            if (prepareIntent != null) {
                val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                if (launchIntent != null) {
                    startActivityAndCollapse(launchIntent)
                }
            } else {
                val intent = Intent(this, AegisVpnService::class.java).apply {
                    action = AegisVpnService.ACTION_START
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(intent)
                } else {
                    startService(intent)
                }
            }
        }
        updateTileState()
    }

    private fun updateTileState() {
        val tile = qsTile ?: return
        val isActive = AegisVpnService.isTunnelUp
        tile.state = if (isActive) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = if (isActive) "AegisNet Shield (ON)" else "AegisNet Shield (OFF)"
        tile.updateTile()
    }
}
