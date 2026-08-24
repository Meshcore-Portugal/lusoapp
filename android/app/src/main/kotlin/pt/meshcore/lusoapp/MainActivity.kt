package pt.meshcore.lusoapp

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val radioServiceChannel = "pt.meshcore.lusoapp/radio_service"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            radioServiceChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startRadioForeground" -> {
                    val radioName = call.argument<String>("radioName") ?: "Radio"
                    startRadioForeground(radioName)
                    result?.success(null)
                }
                "updateRadioForeground" -> {
                    val radioName = call.argument<String>("radioName")
                    val noiseFloor = call.argument<Int>("noiseFloor")
                    val lastRssi = call.argument<Int>("lastRssi")
                    val lastSnrDb = call.argument<Double>("lastSnrDb")
                    val reconnecting = call.argument<Boolean>("reconnecting")
                    val attempt = call.argument<Int>("attempt")
                    updateRadioForeground(
                        radioName, noiseFloor, lastRssi, lastSnrDb, reconnecting, attempt
                    )
                    result?.success(null)
                }
                "stopRadioForeground" -> {
                    stopRadioForeground()
                    result?.success(null)
                }
                "isIgnoringBatteryOptimizations" -> {
                    result?.success(isIgnoringBatteryOptimizations())
                }
                "openBatteryOptimizationSettings" -> {
                    result?.success(openBatteryOptimizationSettings())
                }
                else -> result?.notImplemented()
            }
        }
    }

    private fun startRadioForeground(radioName: String) {
        val intent = Intent(this, RadioForegroundService::class.java).apply {
            action = RadioForegroundService.ACTION_START
            putExtra(RadioForegroundService.EXTRA_RADIO_NAME, radioName)
        }
        // Android 12+ throws ForegroundServiceStartNotAllowedException when the
        // process is in the background. Connecting is a foreground action so this
        // should not happen, but a crash here would be far worse than a missing
        // notification.
        try {
            startForegroundService(intent)
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "startForegroundService failed: ${e.message}", e)
        }
    }

    private fun stopRadioForeground() {
        val intent = Intent(this, RadioForegroundService::class.java).apply {
            action = RadioForegroundService.ACTION_STOP
        }
        try {
            startService(intent)
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "stopRadioForeground failed: ${e.message}", e)
        }
    }

    private fun updateRadioForeground(
        radioName: String?,
        noiseFloor: Int?,
        lastRssi: Int?,
        lastSnrDb: Double?,
        reconnecting: Boolean?,
        attempt: Int?
    ) {
        val intent = Intent(this, RadioForegroundService::class.java).apply {
            action = RadioForegroundService.ACTION_UPDATE
            radioName?.let { putExtra(RadioForegroundService.EXTRA_RADIO_NAME, it) }
            noiseFloor?.let { putExtra(RadioForegroundService.EXTRA_NOISE_FLOOR, it) }
            lastRssi?.let { putExtra(RadioForegroundService.EXTRA_LAST_RSSI, it) }
            lastSnrDb?.let { putExtra(RadioForegroundService.EXTRA_LAST_SNR_DB, it) }
            reconnecting?.let { putExtra(RadioForegroundService.EXTRA_RECONNECTING, it) }
            attempt?.let { putExtra(RadioForegroundService.EXTRA_ATTEMPT, it) }
        }
        // startService() on an already-foreground service is permitted from the
        // background; if the service died anyway, swallow rather than crash.
        try {
            startService(intent)
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "updateRadioForeground failed: ${e.message}", e)
        }
    }

    /**
     * Whether the user has exempted the app from Doze / App Standby battery
     * optimisation. A foreground service is not enough on its own for several
     * OEM skins (Xiaomi, Huawei, Samsung, OnePlus), which kill BLE links anyway
     * unless the app is unrestricted.
     */
    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        return try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            pm.isIgnoringBatteryOptimizations(packageName)
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "battery optimisation check failed: ${e.message}", e)
            false
        }
    }

    /**
     * Open the system battery-optimisation screen so the user can mark the app as
     * unrestricted.
     *
     * We deliberately use ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS (the system
     * list) rather than ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS (the one-tap
     * dialog): the latter needs the REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
     * permission, which Google Play restricts to a short list of app categories
     * that companion-device apps are not part of.
     *
     * Falls back to the app's own settings page if the OEM has no such screen.
     */
    private fun openBatteryOptimizationSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        try {
            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            return true
        } catch (e: Exception) {
            android.util.Log.w("MainActivity", "battery optimisation settings unavailable: ${e.message}")
        }
        return try {
            startActivity(
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.fromParts("package", packageName, null)
                )
            )
            true
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "app details settings failed: ${e.message}", e)
            false
        }
    }
}
