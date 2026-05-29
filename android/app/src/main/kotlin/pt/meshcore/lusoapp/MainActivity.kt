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
                "stopRadioForeground" -> {
                    stopRadioForeground()
                    result?.success(null)
                }
                else -> result?.notImplemented()
            }
        }
    }

    /// FlutterActivity.onNewIntent does two things, in order:
    ///   1) Dispatches the intent to all activity-aware plugins (home_widget
    ///      reads the URI from intent.data here so its widgetClicked stream
    ///      can deliver it to Dart).
    ///   2) If intent.data is non-null, pushes that URI to the
    ///      "flutter/navigation" channel as a deep-link route — which makes
    ///      GoRouter receive the meshcore-widget://… URI and run our scheme
    ///      redirect, overwriting the navigation our Dart-side dispatcher
    ///      just performed.
    ///
    /// For meshcore-widget URIs we want (1) but NOT (2). So we dispatch to
    /// plugins manually and skip the navigation push that super would do.
    override fun onNewIntent(intent: Intent) {
        val engine = flutterEngine
        if (engine != null && intent.data?.scheme == "meshcore-widget") {
            engine.activityControlSurface.onNewIntent(intent)
            setIntent(intent)
            return
        }
        super.onNewIntent(intent)
        setIntent(intent)
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
}
