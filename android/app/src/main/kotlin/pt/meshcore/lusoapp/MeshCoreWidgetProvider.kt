package pt.meshcore.lusoapp

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.graphics.Color
import android.net.Uri
import android.util.Log
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
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
        // Deep-link URIs handled by Flutter side via HomeWidget.widgetClicked.
        private const val URI_OPEN     = "meshcore-widget://open"
        private const val URI_ADVERT   = "meshcore-widget://action/advert"
        private const val URI_SOS      = "meshcore-widget://action/sos"
        private const val URI_CHATS    = "meshcore-widget://nav/channels"
        private const val URI_MAP      = "meshcore-widget://nav/map"
        private const val URI_CONNECT  = "meshcore-widget://nav/connect"

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
            val gpsSharing  = prefs.getBoolean("gps_sharing", false)
            val batteryPct  = (prefs.all["battery_pct"]  as? Number)?.toInt() ?: 0
            val contacts    = (prefs.all["contact_count"] as? Number)?.toInt() ?: 0
            val channels    = (prefs.all["channel_count"] as? Number)?.toInt() ?: 0
            val lastUpdated = prefs.getString("last_updated", "--:--") ?: "--:--"

            Log.d("MCWidget", "update: radio=$radioName connected=$connected gps=$gpsSharing " +
                    "bat=$batteryPct% contacts=$contacts channels=$channels ts=$lastUpdated")

            val views = RemoteViews(context.packageName, R.layout.widget_meshcore)

            views.setTextViewText(R.id.widget_radio_name, radioName)

            // GPS-sharing badge — visible only when the user opted in.
            if (gpsSharing) {
                views.setViewVisibility(R.id.widget_gps_badge, android.view.View.VISIBLE)
                views.setTextViewText(R.id.widget_gps_badge, "📍")
            } else {
                views.setViewVisibility(R.id.widget_gps_badge, android.view.View.GONE)
            }

            if (connected) {
                views.setTextViewText(R.id.widget_status, "● ONLINE")
                views.setTextColor(R.id.widget_status, Color.parseColor("#00E676"))
            } else {
                views.setTextViewText(R.id.widget_status, "● OFFLINE")
                views.setTextColor(R.id.widget_status, Color.parseColor("#FF5252"))
            }

            views.setTextViewText(R.id.widget_battery,  "Bat: $batteryPct%")
            views.setTextViewText(R.id.widget_contacts, "$contacts contactos")
            views.setTextViewText(R.id.widget_channels, "$channels canais")
            views.setTextViewText(R.id.widget_updated,  lastUpdated)

            // Connect button reflects the live transport state.
            if (connected) {
                views.setTextViewText(R.id.widget_btn_connect, "🔌  Ligado")
                views.setTextColor(
                    R.id.widget_btn_connect,
                    Color.parseColor("#FF88FFAA"),
                )
                views.setInt(
                    R.id.widget_btn_connect,
                    "setBackgroundResource",
                    R.drawable.widget_button_connect_on_bg,
                )
            } else {
                views.setTextViewText(R.id.widget_btn_connect, "🔌  Ligar")
                views.setTextColor(
                    R.id.widget_btn_connect,
                    Color.parseColor("#FFFF8888"),
                )
                views.setInt(
                    R.id.widget_btn_connect,
                    "setBackgroundResource",
                    R.drawable.widget_button_connect_off_bg,
                )
            }

            // Header (radio name + status) → just open the app.
            views.setOnClickPendingIntent(
                R.id.widget_header,
                HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse(URI_OPEN),
                ),
            )

            // Quick-action buttons — each carries a unique URI handled in Dart.
            views.setOnClickPendingIntent(
                R.id.widget_btn_sos,
                HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse(URI_SOS),
                ),
            )
            views.setOnClickPendingIntent(
                R.id.widget_btn_advert,
                HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse(URI_ADVERT),
                ),
            )
            views.setOnClickPendingIntent(
                R.id.widget_btn_chats,
                HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse(URI_CHATS),
                ),
            )
            views.setOnClickPendingIntent(
                R.id.widget_btn_map,
                HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse(URI_MAP),
                ),
            )
            views.setOnClickPendingIntent(
                R.id.widget_btn_connect,
                HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse(URI_CONNECT),
                ),
            )

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
