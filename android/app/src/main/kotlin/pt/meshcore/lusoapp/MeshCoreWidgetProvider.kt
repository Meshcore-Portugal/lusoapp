package pt.meshcore.lusoapp

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.util.Log
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

class MeshCoreWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (widgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, widgetId)
        }
    }

    companion object {
        fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            widgetId: Int,
        ) {
            // home_widget stores data in SharedPreferences under "HomeWidgetPreferences"
            // Use HomeWidgetPlugin.getData() so the key stays in sync with the library.
            val prefs = HomeWidgetPlugin.getData(context)

            val radioName   = prefs.getString("radio_name",   "—")     ?: "—"
            val connected   = prefs.getBoolean("connected",   false)
            val batteryPct  = (prefs.all["battery_pct"]  as? Number)?.toInt() ?: 0
            val contacts    = (prefs.all["contact_count"] as? Number)?.toInt() ?: 0
            val channels    = (prefs.all["channel_count"] as? Number)?.toInt() ?: 0
            val lastUpdated = prefs.getString("last_updated", "--:--") ?: "--:--"

            Log.d("MCWidget", "update: radio=$radioName connected=$connected " +
                    "bat=$batteryPct% contacts=$contacts channels=$channels ts=$lastUpdated")

            val views = RemoteViews(context.packageName, R.layout.widget_meshcore)

            views.setTextViewText(R.id.widget_radio_name, radioName)

            if (connected) {
                views.setTextViewText(R.id.widget_status, "● ONLINE")
                views.setTextColor(R.id.widget_status, Color.parseColor("#00E676"))
            } else {
                views.setTextViewText(R.id.widget_status, "● OFFLINE")
                views.setTextColor(R.id.widget_status, Color.parseColor("#FF5252"))
            }

            views.setTextViewText(R.id.widget_battery,  "Bat: $batteryPct%")
            views.setTextViewText(R.id.widget_contacts, "$contacts contacts")
            views.setTextViewText(R.id.widget_channels, "$channels ch")
            views.setTextViewText(R.id.widget_updated,  lastUpdated)

            // Tap anywhere on widget → open app
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                context, 0, launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
