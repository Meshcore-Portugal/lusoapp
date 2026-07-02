package pt.meshcore.lusoapp

import android.content.Intent
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
                    updateRadioForeground(radioName, noiseFloor, lastRssi, lastSnrDb)
                    result?.success(null)
                }
                "stopRadioForeground" -> {
                    stopRadioForeground()
                    result?.success(null)
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
        startForegroundService(intent)
    }

    private fun stopRadioForeground() {
        val intent = Intent(this, RadioForegroundService::class.java).apply {
            action = RadioForegroundService.ACTION_STOP
        }
        startService(intent)
    }

    private fun updateRadioForeground(
        radioName: String?,
        noiseFloor: Int?,
        lastRssi: Int?,
        lastSnrDb: Double?
    ) {
        val intent = Intent(this, RadioForegroundService::class.java).apply {
            action = RadioForegroundService.ACTION_UPDATE
            radioName?.let { putExtra(RadioForegroundService.EXTRA_RADIO_NAME, it) }
            noiseFloor?.let { putExtra(RadioForegroundService.EXTRA_NOISE_FLOOR, it) }
            lastRssi?.let { putExtra(RadioForegroundService.EXTRA_LAST_RSSI, it) }
            lastSnrDb?.let { putExtra(RadioForegroundService.EXTRA_LAST_SNR_DB, it) }
        }
        startService(intent)
    }
}
