package site.massawallet.app

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews

/**
 * Homescreen balance widget.
 *
 * Data is written by the Dart layer (WalletProvider.refreshBalances /
 * background sync) into `FlutterSharedPreferences` under the key
 * `flutter.massa_widget` — a JSON blob with balance / rolls / address /
 * network / updatedAt / hideBalances. This provider only reads and renders.
 */
class MassaWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, buildViews(context))
        }
    }

    override fun onEnabled(context: Context) {
        // Nothing to subscribe to — data is pushed from Dart.
    }

    companion object {
        /** Force-updates every placed widget (called via MethodChannel). */
        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                android.content.ComponentName(context, MassaWidgetProvider::class.java),
            )
            for (id in ids) {
                manager.updateAppWidget(id, buildViews(context))
            }
        }

        private fun buildViews(context: Context): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget_balance)
            try {
                val prefs = context.getSharedPreferences(
                    "FlutterSharedPreferences",
                    Context.MODE_PRIVATE,
                )
                val raw = prefs.getString("flutter.massa_widget", null) ?: return views
                val json = org.json.JSONObject(raw)
                val hide = json.optBoolean("hideBalances", false)
                val balance = if (hide) "\u2022\u2022\u2022\u2022\u2022" else json.optString("balance", "—")
                views.setTextViewText(R.id.widget_balance, balance)
                views.setTextViewText(R.id.widget_rolls, "${json.optString("rolls", "0")} rolls")
                val addr = json.optString("address", "")
                views.setTextViewText(
                    R.id.widget_address,
                    if (addr.length > 16) "${addr.substring(0, 10)}…${addr.substring(addr.length - 4)}" else addr,
                )
                views.setTextViewText(R.id.widget_network, json.optString("network", "Massa"))
            } catch (_: Exception) {
                // Malformed payload — keep placeholder values.
            }
            return views
        }
    }
}
