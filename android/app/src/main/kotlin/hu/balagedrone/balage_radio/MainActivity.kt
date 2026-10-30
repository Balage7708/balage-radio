package hu.balagedrone.balage_radio

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.media.audiofx.Visualizer
import android.net.Uri
import android.os.Build
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Az audio_service miatt (háttérlejátszás, értesítés, zárolt képernyő) ebből kell származnia.
// A "balage/meter" csatorna a LED-jelzőnek adja a lejátszott hang szintjét (Visualizer).
class MainActivity : AudioServiceActivity() {
    private var viz: Visualizer? = null
    private var askedPermission = false
    private val m = Visualizer.MeasurementPeakRms()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "balage/system").setMethodCallHandler { call, result ->
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
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "balage/meter").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> result.success(startMeter())
                "stop" -> {
                    stopMeter()
                    result.success(null)
                }
                "read" -> {
                    val v = viz
                    if (v == null) {
                        result.success(null)
                    } else {
                        try {
                            v.getMeasurementPeakRms(m)
                            result.success(listOf(m.mPeak, m.mRms))
                        } catch (e: Exception) {
                            result.success(null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startMeter(): String {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            if (!askedPermission) {
                askedPermission = true
                requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 77)
            }
            return "Engedély szükséges (Mikrofon)"
        }
        if (viz != null) return "ok"
        return try {
            val v = Visualizer(0)
            v.measurementMode = Visualizer.MEASUREMENT_MODE_PEAK_RMS
            v.enabled = true
            viz = v
            "ok"
        } catch (e: Exception) {
            "Visualizer hiba: ${e.message}"
        }
    }

    private fun stopMeter() {
        try {
            viz?.release()
        } catch (_: Exception) {
        }
        viz = null
    }

    override fun onDestroy() {
        stopMeter()
        super.onDestroy()
    }
}
