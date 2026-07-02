package pt.meshcore.lusoapp

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import java.util.Locale
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/**
 * Foreground service to maintain a persistent notification while connected to a radio.
 * 
 * This prevents Android from applying Doze mode restrictions, allowing the app to:
 * - Maintain BLE connection stability
 * - Retry auto-reconnect in background
 * - Continue background work without aggressive throttling
 * 
 * Requires FOREGROUND_SERVICE permission and a high-importance notification.
 */
class RadioForegroundService : Service() {
    
    companion object {
        const val NOTIFICATION_CHANNEL_ID = "meshcore_radio_connected"
        const val NOTIFICATION_ID = 9999
        const val ACTION_START = "pt.meshcore.lusoapp.ACTION_START_RADIO_SERVICE"
        const val ACTION_UPDATE = "pt.meshcore.lusoapp.ACTION_UPDATE_RADIO_SERVICE"
        const val ACTION_STOP = "pt.meshcore.lusoapp.ACTION_STOP_RADIO_SERVICE"
        const val EXTRA_RADIO_NAME = "radio_name"
        const val EXTRA_NOISE_FLOOR = "noise_floor"
        const val EXTRA_LAST_RSSI = "last_rssi"
        const val EXTRA_LAST_SNR_DB = "last_snr_db"
    }

    private var currentRadioName: String = "Radio"
    private var currentNoiseFloor: Int? = null
    private var currentLastRssi: Int? = null
    private var currentLastSnrDb: Double? = null
    private var startedForeground = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startRadioNotification(intent)
            ACTION_UPDATE -> updateRadioNotification(intent)
            ACTION_STOP -> stopRadioNotification()
        }
        // Do not restart the service automatically after process death.
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // User removed app task from recents -> remove persistent notification.
        stopRadioNotification()
        super.onTaskRemoved(rootIntent)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                getString(R.string.radio_notification_channel_name),
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = getString(R.string.radio_notification_channel_description)
                enableVibration(false)
            }
            
            val notificationManager: NotificationManager =
                getSystemService(Service.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun startRadioNotification(intent: Intent) {
        currentRadioName = intent.getStringExtra(EXTRA_RADIO_NAME) ?: currentRadioName
        if (intent.hasExtra(EXTRA_NOISE_FLOOR)) {
            currentNoiseFloor = intent.getIntExtra(EXTRA_NOISE_FLOOR, 0)
        }
        if (intent.hasExtra(EXTRA_LAST_RSSI)) {
            currentLastRssi = intent.getIntExtra(EXTRA_LAST_RSSI, 0)
        }
        if (intent.hasExtra(EXTRA_LAST_SNR_DB)) {
            currentLastSnrDb = intent.getDoubleExtra(EXTRA_LAST_SNR_DB, 0.0)
        }

        // Create the notification channel before building the notification
        createNotificationChannel()

        val baseText = getString(R.string.radio_notification_text)
        val statsParts = mutableListOf<String>()
        currentNoiseFloor?.let { statsParts.add("NF ${it} dBm") }
        currentLastRssi?.let { statsParts.add("RSSI ${it} dBm") }
        currentLastSnrDb?.let {
            val snrText = String.format(Locale.US, "%.1f", it)
            statsParts.add("SNR ${snrText} dB")
        }
        val contentText = if (statsParts.isEmpty()) {
            baseText
        } else {
            "$baseText • ${statsParts.joinToString(" • ")}"
        }

        val notificationBuilder = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle(getString(R.string.radio_notification_title, currentRadioName))
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)

        // Create intent to return to app when notification is tapped
        val appIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }

        val pendingIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.getActivity(
                this,
                0,
                appIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        } else {
            @Suppress("UnspecifiedImmutableFlag")
            PendingIntent.getActivity(this, 0, appIntent, PendingIntent.FLAG_UPDATE_CURRENT)
        }
        notificationBuilder.setContentIntent(pendingIntent)

        val notification = notificationBuilder.build()

        // Start foreground service
        try {
            if (!startedForeground) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    ServiceCompat.startForeground(
                        this,
                        NOTIFICATION_ID,
                        notification,
                        android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
                    )
                } else {
                    startForeground(NOTIFICATION_ID, notification)
                }
                startedForeground = true
            } else {
                val nm = getSystemService(Service.NOTIFICATION_SERVICE) as NotificationManager
                nm.notify(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            // Log the error for debugging
            android.util.Log.e("RadioForegroundService", "Failed to start foreground: ${e.message}", e)
        }
    }

    private fun updateRadioNotification(intent: Intent) {
        if (intent.hasExtra(EXTRA_RADIO_NAME)) {
            currentRadioName = intent.getStringExtra(EXTRA_RADIO_NAME) ?: currentRadioName
        }
        if (intent.hasExtra(EXTRA_NOISE_FLOOR)) {
            currentNoiseFloor = intent.getIntExtra(EXTRA_NOISE_FLOOR, 0)
        }
        if (intent.hasExtra(EXTRA_LAST_RSSI)) {
            currentLastRssi = intent.getIntExtra(EXTRA_LAST_RSSI, 0)
        }
        if (intent.hasExtra(EXTRA_LAST_SNR_DB)) {
            currentLastSnrDb = intent.getDoubleExtra(EXTRA_LAST_SNR_DB, 0.0)
        }
        // Reuse start path which updates notification when already started.
        startRadioNotification(Intent().apply {
            putExtra(EXTRA_RADIO_NAME, currentRadioName)
            currentNoiseFloor?.let { putExtra(EXTRA_NOISE_FLOOR, it) }
            currentLastRssi?.let { putExtra(EXTRA_LAST_RSSI, it) }
            currentLastSnrDb?.let { putExtra(EXTRA_LAST_SNR_DB, it) }
        })
    }

    private fun stopRadioNotification() {
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        startedForeground = false
        stopSelf()
    }
}
