package dev.nbriq.wear.watchface

import android.content.Context
import android.os.BatteryManager
import android.support.wearable.complications.ComplicationData
import android.support.wearable.complications.ComplicationManager
import android.support.wearable.complications.ComplicationProviderService
import android.support.wearable.complications.ComplicationText

/**
 * Complicación propia: publica el nivel de batería del reloj como valor con rango y como texto.
 *
 * Se usa como proveedor por defecto del hueco de la esfera, así que funciona sin configurar
 * nada, y además queda disponible para cualquier otra esfera del sistema.
 */
class BatteryComplicationProvider : ComplicationProviderService() {

    override fun onComplicationUpdate(
        complicationId: Int,
        dataType: Int,
        complicationManager: ComplicationManager
    ) {
        val percent = readBatteryPercent(this)

        val data = when (dataType) {
            ComplicationData.TYPE_RANGED_VALUE -> ComplicationData.Builder(
                ComplicationData.TYPE_RANGED_VALUE
            )
                .setValue(percent.toFloat())
                .setMinValue(0f)
                .setMaxValue(100f)
                .setShortTitle(ComplicationText.plainText(getString(R.string.complication_short_title)))
                .setShortText(ComplicationText.plainText("$percent%"))
                .build()

            ComplicationData.TYPE_SHORT_TEXT -> ComplicationData.Builder(
                ComplicationData.TYPE_SHORT_TEXT
            )
                .setShortText(ComplicationText.plainText("$percent%"))
                .setShortTitle(ComplicationText.plainText(getString(R.string.complication_short_title)))
                .build()

            else -> null
        }

        if (data != null) {
            complicationManager.updateComplicationData(complicationId, data)
        } else {
            complicationManager.noUpdateRequired(complicationId)
        }
    }

    private fun readBatteryPercent(context: Context): Int {
        val batteryManager =
            context.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
        val fromManager = batteryManager?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1
        if (fromManager in 0..100) return fromManager

        // Fallback por broadcast fijo (algunos firmwares no exponen la propiedad).
        val intent = context.registerReceiver(
            null,
            android.content.IntentFilter(android.content.Intent.ACTION_BATTERY_CHANGED)
        )
        val level = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        return if (level >= 0 && scale > 0) (level * 100f / scale).toInt() else 0
    }
}
