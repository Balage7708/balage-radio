package hu.balagedrone.balage_radio

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.audiofx.Visualizer
import android.net.Uri
import android.os.Build
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.sqrt

// Az audio_service miatt (háttérlejátszás, értesítés, zárolt képernyő) ebből kell származnia.
// "balage/meter": a LED-jelzőnek adja a lejátszott hang szintjét. A lejátszómotor (mpv) saját
// hang-munkamenet azonosítót kap, a Visualizer erre figyel – ez régebbi Androidon (fejegység) is működik.
// "balage/system": összeomlás-napló, automatikus indítás, ébredés.
class MainActivity : AudioServiceActivity() {
    private var viz: Visualizer? = null
    private var vizSession = -1
    private var askedPermission = false
    private val m = Visualizer.MeasurementPeakRms()
    private var wave = ByteArray(1024)
    private var systemChannel: MethodChannel? = null

    companion object {
        private var audioSession = 0
        private var wakeRegistered = false
        var activeChannel: MethodChannel? = null

        fun autoStartEnabled(ctx: Context): Boolean {
            val s = ctx.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getString("flutter.settings", null) ?: return false
            return s.replace(" ", "").contains("\"autoStartBoot\":true")
        }

        fun note(ctx: Context, what: String) {
            val p = ctx.getSharedPreferences("balage_native", Context.MODE_PRIVATE)
            val t = java.text.SimpleDateFormat("yyyy.MM.dd HH:mm:ss", java.util.Locale.US).format(java.util.Date())
            p.edit().putString("lastEvent", "$t – $what").apply()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val sys = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "balage/system")
        systemChannel = sys
        activeChannel = sys
        sys.setMethodCallHandler { call, result ->
            when (call.method) {
                "previousCrash" -> {
                    // Az előző futás összeomlásának nyomai a rendszernaplóból (csak a saját app sorai láthatók).
                    Thread {
                        val out = StringBuilder()
                        try {
                            val p = Runtime.getRuntime().exec(arrayOf("logcat", "-d", "-v", "time", "-t", "3000"))
                            val lines = p.inputStream.bufferedReader().readLines()
                            val idx = lines.indexOfLast {
                                it.contains("Fatal signal") || it.contains("FATAL EXCEPTION") || it.contains("Abort message")
                            }
                            if (idx >= 0) {
                                val from = maxOf(0, idx - 25)
                                val to = minOf(lines.size, idx + 40)
                                for (i in from until to) {
                                    val l = lines[i]
                                    if (l.contains(" E/") || l.contains(" F/") || l.contains(" W/") || i == idx) out.append(l).append('\n')
                                }
                            }
                        } catch (e: Exception) {
                            out.append("logcat hiba: ").append(e.message)
                        }
                        runOnUiThread { result.success(out.toString()) }
                    }.start()
                }
                "requestOverlay" -> {
                    if (Build.VERSION.SDK_INT >= 23 && !Settings.canDrawOverlays(this)) {
                        try {
                            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
                        } catch (_: Exception) {
                        }
                    }
                    result.success(null)
                }
                "lastEvent" -> {
                    result.success(getSharedPreferences("balage_native", Context.MODE_PRIVATE).getString("lastEvent", ""))
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "balage/meter").setMethodCallHandler { call, result ->
            when (call.method) {
                "session" -> {
                    if (audioSession == 0) {
                        try {
                            audioSession = (getSystemService(Context.AUDIO_SERVICE) as AudioManager).generateAudioSessionId()
                        } catch (_: Exception) {
                        }
                    }
                    result.success(audioSession)
                }
                "start" -> result.success(startMeter(call.argument<Int>("session") ?: 0))
                "stop" -> {
                    stopMeter()
                    result.success(null)
                }
                "read" -> result.success(readMeter())
                else -> result.notImplemented()
            }
        }
        registerWake()
    }

    /** Ha a fejegység alvásból ébred (az app közben futva maradt), szóljon újra a rádió. */
    private fun registerWake() {
        if (wakeRegistered) return
        wakeRegistered = true
        val f = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        applicationContext.registerReceiver(object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                if (!autoStartEnabled(ctx)) return
                note(ctx, "ébredés (${intent.action?.substringAfterLast('.')})")
                try {
                    ctx.startActivity(Intent(ctx, MainActivity::class.java).addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT))
                } catch (_: Exception) {
                }
                try {
                    activeChannel?.invokeMethod("wake", null)
                } catch (_: Exception) {
                }
            }
        }, f)
    }

    private fun startMeter(session: Int): String {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            if (!askedPermission) {
                askedPermission = true
                requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 77)
            }
            return "Engedély szükséges (Mikrofon)"
        }
        if (viz != null && vizSession == session) return "ok (munkamenet $session)"
        stopMeter()
        for (s in listOf(session, 0).distinct()) {
            try {
                val v = Visualizer(s)
                try {
                    v.captureSize = Visualizer.getCaptureSizeRange()[1]
                } catch (_: Exception) {
                }
                try {
                    v.measurementMode = Visualizer.MEASUREMENT_MODE_PEAK_RMS
                } catch (_: Exception) {
                }
                v.enabled = true
                wave = ByteArray(v.captureSize)
                viz = v
                vizSession = s
                return "ok (munkamenet $s)"
            } catch (_: Exception) {
            }
        }
        return "Visualizer nem indítható"
    }

    /** [csúcs mB, rms mB, hullámforma-csúcs mB, hullámforma-rms mB] */
    private fun readMeter(): List<Int>? {
        val v = viz ?: return null
        var pk = -9600
        var rms = -9600
        try {
            v.getMeasurementPeakRms(m)
            pk = m.mPeak
            rms = m.mRms
        } catch (_: Exception) {
        }
        var wpk = -9600
        var wrms = -9600
        try {
            if (v.getWaveForm(wave) == Visualizer.SUCCESS) {
                var mx = 0
                var sum = 0.0
                for (b in wave) {
                    val x = (b.toInt() and 0xff) - 128
                    val a = abs(x)
                    if (a > mx) mx = a
                    sum += (x * x).toDouble()
                }
                if (mx > 0) wpk = (2000 * log10(mx / 128.0)).toInt()
                val r = sqrt(sum / wave.size) / 128.0
                if (r > 0) wrms = (2000 * log10(r)).toInt()
            }
        } catch (_: Exception) {
        }
        return listOf(pk, rms, max(wpk, -9600), max(wrms, -9600))
    }

    private fun stopMeter() {
        try {
            viz?.release()
        } catch (_: Exception) {
        }
        viz = null
        vizSession = -1
    }

    override fun onDestroy() {
        stopMeter()
        if (activeChannel == systemChannel) activeChannel = null
        super.onDestroy()
    }
}
