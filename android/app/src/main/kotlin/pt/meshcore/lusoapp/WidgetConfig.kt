package pt.meshcore.lusoapp

import android.content.Context
import androidx.core.content.edit

/// Per-widget customization: which action keys (in display order), which of
/// those show their text label on the widget, and the accent color applied
/// to highlight roles.
data class WidgetConfig(
    val buttons: List<String>,
    val labels: Set<String>,
    val accent: Int,
) {
    companion object {
        const val PREFS = "HomeWidgetPreferences"
        const val DEFAULT_ACCENT = 0xFFFF6B00.toInt()

        val DEFAULT_BUTTONS = listOf("sos", "advert", "chats", "map", "connect")

        // SOS and connect labels carry state ("SOS"/"LIGADO"), so they were
        // shown in the original design. Mirror that as the default for new
        // widgets — users can toggle other labels on per their preference.
        val DEFAULT_LABELS = setOf("sos", "connect")

        val ALL_BUTTONS = listOf(
            "sos", "advert", "connect", "chats", "map", "plan333", "telemetry",
        )

        const val MIN_BUTTONS = 3
        const val MAX_BUTTONS = 5

        fun keyButtons(widgetId: Int) = "widget_${widgetId}_buttons"
        fun keyLabels(widgetId: Int)  = "widget_${widgetId}_labels"
        fun keyAccent(widgetId: Int)  = "widget_${widgetId}_accent"

        fun load(context: Context, widgetId: Int): WidgetConfig {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val raw = prefs.getString(keyButtons(widgetId), null)
            val buttons = raw
                ?.split(',')
                ?.map { it.trim() }
                ?.filter { it.isNotEmpty() && it in ALL_BUTTONS }
                ?.takeIf { it.size in MIN_BUTTONS..MAX_BUTTONS }
                ?: DEFAULT_BUTTONS

            // Labels: missing key ⇒ default (sos/connect). Empty string ⇒
            // user explicitly hid every label.
            val labels = prefs.getString(keyLabels(widgetId), null)?.let { rawLabels ->
                rawLabels.split(',')
                    .map { it.trim() }
                    .filter { it.isNotEmpty() && it in ALL_BUTTONS }
                    .toSet()
            } ?: DEFAULT_LABELS

            val accent = when (val v = prefs.all[keyAccent(widgetId)]) {
                is Int  -> v
                is Long -> v.toInt()
                else    -> DEFAULT_ACCENT
            }
            return WidgetConfig(buttons, labels, accent)
        }

        fun save(context: Context, widgetId: Int, config: WidgetConfig) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit {
                putString(keyButtons(widgetId), config.buttons.joinToString(","))
                putString(keyLabels(widgetId),  config.labels.joinToString(","))
                putInt(keyAccent(widgetId), config.accent)
            }
        }

        fun clear(context: Context, widgetId: Int) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit {
                remove(keyButtons(widgetId))
                remove(keyLabels(widgetId))
                remove(keyAccent(widgetId))
            }
        }
    }
}
