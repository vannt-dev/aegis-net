package com.aegisnet.app

import android.content.Context

/**
 * Whether the optional PIN app lock is on.
 *
 * With it on, the app asks for the PIN before protection is turned off or
 * paused. The tile, the notification and the home-screen widget cannot ask
 * for a PIN, so they open the app instead of doing it themselves.
 */
object AppLock {
    /// The Dart side keeps its settings in this file, keys prefixed "flutter.",
    /// and stores a PIN hash only while the lock is on.
    fun isOn(context: Context): Boolean =
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .contains("flutter.app_lock_hash")
}
