package com.taskman.taskman

import android.app.ActivityManager
import android.content.Intent
import android.content.IntentFilter
import android.net.TrafficStats
import android.net.Uri
import android.os.BatteryManager
import android.os.Environment
import android.os.StatFs
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(e: FlutterEngine) {
        super.configureFlutterEngine(e)
        MethodChannel(e.dartExecutor.binaryMessenger, "taskman/stats").setMethodCallHandler { call, res ->
            when (call.method) {
                "stats" -> res.success(stats())
                "apps" -> res.success(apps())
                "openSettings" -> {
                    val i = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.parse("package:" + call.argument<String>("pkg")))
                    i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(i)
                    res.success(null)
                }
                else -> res.notImplemented()
            }
        }
    }

    private fun stats(): Map<String, Any> {
        val mi = ActivityManager.MemoryInfo()
        (getSystemService(ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(mi)
        val sf = StatFs(Environment.getDataDirectory().path)
        val b = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val lvl = b?.getIntExtra(BatteryManager.EXTRA_LEVEL, 0) ?: 0
        val scale = b?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
        return mapOf(
            "ramTotal" to mi.totalMem, "ramFree" to mi.availMem,
            "diskTotal" to sf.totalBytes, "diskFree" to sf.availableBytes,
            "battery" to lvl * 100 / scale,
            "batteryTemp" to (b?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0) ?: 0) / 10.0,
            "charging" to ((b?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0) != 0),
            "cpu" to cpuLoad(),
            "rx" to TrafficStats.getTotalRxBytes(), "tx" to TrafficStats.getTotalTxBytes()
        )
    }

    // Android blocks /proc/stat for apps, so CPU % is estimated from current vs max core clock.
    private fun cpuLoad(): Int {
        var sum = 0.0
        var n = 0
        for (i in 0 until Runtime.getRuntime().availableProcessors()) {
            try {
                val d = "/sys/devices/system/cpu/cpu$i/cpufreq/"
                val cur = File(d + "scaling_cur_freq").readText().trim().toDouble()
                val max = File(d + "cpuinfo_max_freq").readText().trim().toDouble()
                sum += cur / max
                n++
            } catch (_: Exception) {}
        }
        return if (n == 0) -1 else (sum / n * 100).toInt()
    }

    private fun apps(): List<Map<String, String>> {
        val pm = packageManager
        return pm.getInstalledApplications(0)
            .filter { pm.getLaunchIntentForPackage(it.packageName) != null }
            .map { mapOf("name" to pm.getApplicationLabel(it).toString(), "pkg" to it.packageName) }
            .sortedBy { it["name"]!!.lowercase() }
    }
}
