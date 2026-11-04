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
        val on = MainActivity.autoStartEnabled(context)
        MainActivity.note(context, "bekapcsolás (${intent.action?.substringAfterLast('.')})" + if (on) "" else " – automatikus indítás kikapcsolva")
        if (!on) return
        val launch = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
        }
        try {
            context.startActivity(launch)
        } catch (e: Exception) {
            MainActivity.note(context, "bekapcsolás – indítás sikertelen: ${e.message}")
        }
    }
}
