package hu.balagedrone.balage_radio

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * A fejegység bekapcsolásakor elindítja az appot, ha a Beállításokban kérték
 * („Automatikus indítás a fejegység bekapcsolásakor”).
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val settings = prefs.getString("flutter.settings", null) ?: return
        if (!settings.replace(" ", "").contains("\"autoStartBoot\":true")) return
        val launch = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
        }
        try {
            context.startActivity(launch)
        } catch (_: Exception) {
        }
    }
}
