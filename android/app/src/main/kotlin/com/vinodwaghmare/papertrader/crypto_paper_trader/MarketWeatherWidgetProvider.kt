package com.vinodwaghmare.papertrader.crypto_paper_trader

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Renders `public_market_weather/current` (synced into HomeWidget's
 * SharedPreferences by market_weather_sync_task.dart, on a WorkManager
 * timer aligned with computeMarketWeather.ts's 4-hour schedule — see that
 * file for why this provider never fetches anything itself). Tapping the
 * widget deep-links into the chart screen via the `cryptopapertrader://
 * chart` URI, handled on the Dart side in market_weather_sync_task.dart's
 * deep-link wiring.
 */
class MarketWeatherWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.market_weather_widget)

            val tier = widgetData.getString("weather_tier", null) ?: "Unknown"
            val iconKey = widgetData.getString("weather_icon_key", null)
            val updatedLabel = widgetData.getString("weather_updated_label", null) ?: ""

            views.setTextViewText(R.id.weather_tier_label, tier)
            views.setTextViewText(R.id.weather_updated_label, updatedLabel)
            views.setImageViewResource(R.id.weather_icon, iconResFor(context, iconKey))

            val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("cryptopapertrader://chart"),
            )
            views.setOnClickPendingIntent(R.id.weather_widget_root, pendingIntent)

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    /** [iconKey] is one of computeMarketWeather.ts's `weather_*` values;
     * this app's drawables use the conventional `ic_` prefix, so the two
     * don't share a name directly. Falls back to the Calm icon for a
     * missing/unrecognized key (e.g. before the first sync has run). */
    private fun iconResFor(context: Context, iconKey: String?): Int {
        if (iconKey == null) return R.drawable.ic_weather_calm
        val resId = context.resources.getIdentifier("ic_$iconKey", "drawable", context.packageName)
        return if (resId != 0) resId else R.drawable.ic_weather_calm
    }
}
