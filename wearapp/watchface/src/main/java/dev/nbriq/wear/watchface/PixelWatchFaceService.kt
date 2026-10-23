package dev.nbriq.wear.watchface

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.os.BatteryManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.support.wearable.complications.ComplicationData
import android.support.wearable.complications.ComplicationHelperActivity
import android.support.wearable.complications.rendering.ComplicationDrawable
import android.support.wearable.watchface.CanvasWatchFaceService
import android.support.wearable.watchface.WatchFaceService
import android.support.wearable.watchface.WatchFaceStyle
import android.text.format.DateFormat
import android.view.Gravity
import android.view.SurfaceHolder
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import kotlin.math.min
import kotlin.math.roundToInt

private const val COMPLICATION_ID = 100

private const val COLOR_BG_CENTER = 0xFF17191F.toInt()
private const val COLOR_BG_MID = 0xFF0B0C10.toInt()
private const val COLOR_BG_EDGE = 0xFF000000.toInt()
private const val COLOR_RING = 0xFF252A33.toInt()
private const val COLOR_ACCENT = 0xFF8AB4F8.toInt()
private const val COLOR_ACCENT_CHARGING = 0xFF6EE7A8.toInt()
private const val COLOR_ACCENT_LOW = 0xFFF28B82.toInt()
private const val COLOR_TEXT_DIM = 0xFFA8AFBA.toInt()
private const val COLOR_ARC_AMBIENT = 0xFF9AA0A6.toInt()
private const val COLOR_TEXT_AMBIENT = 0xFFE8EAED.toInt()
private const val COLOR_TEXT_DIM_AMBIENT = 0xFF8A8F98.toInt()
private const val COLOR_CHIP_BG = 0xFF1F2229.toInt()

/** Radio del anillo respecto al lado menor de pantalla (deja sitio al icono de notificación). */
private const val RADIUS_FACTOR = 0.42f

/**
 * Esfera estilo Pixel Watch para el NBRiq (shasta, Wear OS 2.0 / API 25, 400x400 px).
 *
 * Layout: hora grande centrada, fecha en mayúsculas debajo, anillo perimetral con el nivel de
 * batería y un chip inferior con complicación (por defecto la batería, tocable para cambiarla).
 */
class PixelWatchFaceService : CanvasWatchFaceService() {

    override fun onCreateEngine(): Engine = PixelEngine()

    inner class PixelEngine : CanvasWatchFaceService.Engine() {

        private val handler = Handler(Looper.getMainLooper())
        private val calendar: Calendar = Calendar.getInstance()

        private var timeFormat = SimpleDateFormat("HH:mm", Locale.getDefault())
        private var dateFormat = SimpleDateFormat("EEE d MMM", Locale.getDefault())

        private var isAmbient = false
        private var lowBitAmbient = false
        private var burnInProtection = false
        private var visible = false

        private var batteryPercent = -1
        private var charging = false

        private var surfaceWidth = 0
        private var surfaceHeight = 0
        private var centerX = 0f
        private var centerY = 0f
        private var faceSize = 0f

        private val backgroundPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            color = COLOR_RING
        }
        private val arcPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            color = COLOR_ACCENT
        }
        private val timePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textAlign = Paint.Align.CENTER
            typeface = Typeface.create("sans-serif-light", Typeface.NORMAL)
            color = Color.WHITE
        }
        private val datePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textAlign = Paint.Align.CENTER
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            letterSpacing = 0.16f
            color = COLOR_TEXT_DIM
        }

        private val arcBounds = RectF()
        private val chipBounds = Rect()
        private var backgroundGradient: Shader? = null

        private var lastComplicationData: ComplicationData? = null

        private val complicationDrawable = ComplicationDrawable(this@PixelWatchFaceService)

        private var timeZoneRegistered = false

        private val batteryReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val level = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
                val scale = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
                if (level >= 0 && scale > 0) {
                    batteryPercent = (level * 100f / scale).roundToInt()
                }
                val status = intent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
                charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                    status == BatteryManager.BATTERY_STATUS_FULL
                invalidate()
            }
        }

        private val timeZoneReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                calendar.timeZone = TimeZone.getDefault()
                updateFormats()
                invalidate()
            }
        }

        /** Se reprograma al borde exacto del minuto: barato para una batería de 300 mAh. */
        private val tickRunnable = object : Runnable {
            override fun run() {
                invalidate()
                scheduleTick()
            }
        }

        override fun onCreate(holder: SurfaceHolder) {
            super.onCreate(holder)

            setWatchFaceStyle(
                WatchFaceStyle.Builder(this@PixelWatchFaceService)
                    .setAcceptsTapEvents(true)
                    .setShowSystemUiTime(false)
                    .setHideHotwordIndicator(true)
                    .setStatusBarGravity(Gravity.TOP or Gravity.CENTER_HORIZONTAL)
                    .setCardPeekMode(WatchFaceStyle.PEEK_MODE_SHORT)
                    .setAmbientPeekMode(WatchFaceStyle.AMBIENT_PEEK_MODE_HIDDEN)
                    .setBackgroundVisibility(WatchFaceStyle.BACKGROUND_VISIBILITY_INTERRUPTIVE)
                    .build()
            )

            // Hueco propio + proveedor por defecto (batería) para que el chip muestre algo
            // útil desde el primer segundo, sin configurar nada a mano.
            setActiveComplications(COMPLICATION_ID)
            setDefaultComplicationProvider(
                COMPLICATION_ID,
                ComponentName(this@PixelWatchFaceService, BatteryComplicationProvider::class.java),
                ComplicationData.TYPE_SHORT_TEXT
            )
            setTouchEventsEnabled(true)

            updateFormats()
            configureComplicationDrawable()
            this@PixelWatchFaceService.registerReceiver(
                batteryReceiver,
                IntentFilter(Intent.ACTION_BATTERY_CHANGED)
            )
            refreshBattery()
        }

        override fun onDestroy() {
            handler.removeCallbacksAndMessages(null)
            unregisterTimeZone()
            try {
                this@PixelWatchFaceService.unregisterReceiver(batteryReceiver)
            } catch (ignored: IllegalArgumentException) {
                // ya estaba desregistrado
            }
            super.onDestroy()
        }

        override fun onVisibilityChanged(visible: Boolean) {
            super.onVisibilityChanged(visible)
            this.visible = visible
            if (visible) {
                calendar.timeZone = TimeZone.getDefault()
                updateFormats()
                registerTimeZone()
                refreshBattery()
                invalidate()
                scheduleTick()
            } else {
                unregisterTimeZone()
                handler.removeCallbacks(tickRunnable)
            }
        }

        private fun scheduleTick() {
            handler.removeCallbacks(tickRunnable)
            if (!visible) return
            val now = System.currentTimeMillis()
            handler.postDelayed(tickRunnable, 60_000L - now % 60_000L + 40L)
        }

        private fun refreshBattery() {
            val intent = this@PixelWatchFaceService
                .registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            if (intent != null) batteryReceiver.onReceive(this@PixelWatchFaceService, intent)
        }

        private fun registerTimeZone() {
            if (timeZoneRegistered) return
            this@PixelWatchFaceService.registerReceiver(
                timeZoneReceiver,
                IntentFilter(Intent.ACTION_TIMEZONE_CHANGED)
            )
            timeZoneRegistered = true
        }

        private fun unregisterTimeZone() {
            if (!timeZoneRegistered) return
            try {
                this@PixelWatchFaceService.unregisterReceiver(timeZoneReceiver)
            } catch (ignored: IllegalArgumentException) {
                // ya estaba desregistrado
            }
            timeZoneRegistered = false
        }

        override fun onSurfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
            super.onSurfaceChanged(holder, format, width, height)
            surfaceWidth = width
            surfaceHeight = height
            updateLayout()
        }

        override fun onAmbientModeChanged(inAmbientMode: Boolean) {
            super.onAmbientModeChanged(inAmbientMode)
            isAmbient = inAmbientMode
            complicationDrawable.setInAmbientMode(inAmbientMode)
            if (lowBitAmbient) {
                val antiAlias = !inAmbientMode
                timePaint.isAntiAlias = antiAlias
                datePaint.isAntiAlias = antiAlias
                trackPaint.isAntiAlias = antiAlias
                arcPaint.isAntiAlias = antiAlias
                backgroundPaint.isAntiAlias = antiAlias
            }
            invalidate()
        }

        override fun onPropertiesChanged(properties: Bundle) {
            super.onPropertiesChanged(properties)
            lowBitAmbient = properties.getBoolean(WatchFaceService.PROPERTY_LOW_BIT_AMBIENT, false)
            burnInProtection =
                properties.getBoolean(WatchFaceService.PROPERTY_BURN_IN_PROTECTION, false)
            complicationDrawable.setLowBitAmbient(lowBitAmbient)
            complicationDrawable.setBurnInProtection(burnInProtection)
            invalidate()
        }

        override fun onTimeTick() {
            super.onTimeTick()
            invalidate()
        }

        private fun updateFormats() {
            val locale = Locale.getDefault()
            val is24h = DateFormat.is24HourFormat(this@PixelWatchFaceService)
            timeFormat = SimpleDateFormat(if (is24h) "HH:mm" else "h:mm", locale)
            timeFormat.timeZone = calendar.timeZone
            dateFormat = SimpleDateFormat("EEE d MMM", locale)
            dateFormat.timeZone = calendar.timeZone
        }

        private fun configureComplicationDrawable() {
            val medium = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            val regular = Typeface.create("sans-serif", Typeface.NORMAL)
            with(complicationDrawable) {
                setContext(this@PixelWatchFaceService)
                setTextTypefaceActive(medium)
                setTextTypefaceAmbient(regular)
                setTitleTypefaceActive(regular)
                setTitleTypefaceAmbient(regular)
                setTextColorActive(Color.WHITE)
                setTextColorAmbient(COLOR_TEXT_AMBIENT)
                setTitleColorActive(COLOR_TEXT_DIM)
                setTitleColorAmbient(COLOR_TEXT_DIM_AMBIENT)
                setIconColorActive(COLOR_ACCENT)
                setIconColorAmbient(COLOR_ARC_AMBIENT)
                setBackgroundColorActive(COLOR_CHIP_BG)
                setBackgroundColorAmbient(Color.BLACK)
                setBorderStyleActive(ComplicationDrawable.BORDER_STYLE_NONE)
                setBorderStyleAmbient(ComplicationDrawable.BORDER_STYLE_NONE)
                setBorderWidthActive(0)
                setBorderWidthAmbient(0)
                setRangedValuePrimaryColorActive(COLOR_ACCENT)
                setRangedValuePrimaryColorAmbient(COLOR_ARC_AMBIENT)
                setRangedValueSecondaryColorActive(COLOR_RING)
                setRangedValueSecondaryColorAmbient(Color.DKGRAY)
                setHighlightColorActive(COLOR_CHIP_BG)
                setNoDataText("—")
            }
        }

        private fun updateLayout() {
            if (surfaceWidth <= 0 || surfaceHeight <= 0) return
            faceSize = min(surfaceWidth, surfaceHeight).toFloat()
            centerX = surfaceWidth / 2f
            centerY = surfaceHeight / 2f

            val ringRadius = faceSize * RADIUS_FACTOR
            val ringStroke = faceSize * 0.014f
            arcBounds.set(
                centerX - ringRadius,
                centerY - ringRadius,
                centerX + ringRadius,
                centerY + ringRadius
            )
            trackPaint.strokeWidth = ringStroke
            arcPaint.strokeWidth = ringStroke * 1.35f

            timePaint.textSize = faceSize * 0.245f
            datePaint.textSize = faceSize * 0.052f

            val chipWidth = faceSize * 0.46f
            val chipHeight = faceSize * 0.145f
            val chipTop = centerY + faceSize * 0.205f
            chipBounds.set(
                (centerX - chipWidth / 2f).toInt(),
                chipTop.toInt(),
                (centerX + chipWidth / 2f).toInt(),
                (chipTop + chipHeight).toInt()
            )
            with(complicationDrawable) {
                setBounds(chipBounds)
                setTextSizeActive((faceSize * 0.052f).toInt())
                setTextSizeAmbient((faceSize * 0.052f).toInt())
                setTitleSizeActive((faceSize * 0.036f).toInt())
                setTitleSizeAmbient((faceSize * 0.036f).toInt())
                setBorderRadiusActive((chipHeight / 2f).toInt())
                setBorderRadiusAmbient((chipHeight / 2f).toInt())
            }

            backgroundGradient = RadialGradient(
                centerX,
                centerY - faceSize * 0.10f,
                faceSize * 0.75f,
                intArrayOf(COLOR_BG_CENTER, COLOR_BG_MID, COLOR_BG_EDGE),
                floatArrayOf(0f, 0.55f, 1f),
                Shader.TileMode.CLAMP
            )
            invalidate()
        }

        override fun onDraw(canvas: Canvas, bounds: Rect) {
            val now = System.currentTimeMillis()
            calendar.timeInMillis = now
            complicationDrawable.setCurrentTimeMillis(now)

            val timeText = timeFormat.format(calendar.time)
            val dateText = dateFormat.format(calendar.time).uppercase(Locale.getDefault())

            drawBackground(canvas)

            // En pantallas con protección anti burn-in desplazamos 1-2 px por minuto.
            val burnInStep = if (isAmbient && burnInProtection) {
                ((now / 60_000L) % 3L).toFloat() - 1f
            } else {
                0f
            }
            canvas.save()
            canvas.translate(burnInStep * 2f, burnInStep)
            drawRing(canvas)
            drawTime(canvas, timeText, dateText)
            drawComplication(canvas, now)
            canvas.restore()
        }

        private fun drawBackground(canvas: Canvas) {
            if (isAmbient) {
                canvas.drawColor(Color.BLACK)
                return
            }
            backgroundPaint.shader = backgroundGradient
            canvas.drawRect(
                0f,
                0f,
                surfaceWidth.toFloat(),
                surfaceHeight.toFloat(),
                backgroundPaint
            )
        }

        private fun drawRing(canvas: Canvas) {
            trackPaint.color = if (isAmbient) 0xFF141518.toInt() else COLOR_RING
            canvas.drawArc(arcBounds, 0f, 359.5f, false, trackPaint)

            val percent = batteryPercent
            if (percent <= 0) return
            arcPaint.color = when {
                isAmbient -> COLOR_ARC_AMBIENT
                charging -> COLOR_ACCENT_CHARGING
                percent <= 15 -> COLOR_ACCENT_LOW
                else -> COLOR_ACCENT
            }
            canvas.drawArc(arcBounds, -90f, 360f * (percent / 100f), false, arcPaint)
        }

        private fun drawTime(canvas: Canvas, timeText: String, dateText: String) {
            timePaint.color = if (isAmbient) COLOR_TEXT_AMBIENT else Color.WHITE
            canvas.drawText(timeText, centerX, centerY + faceSize * 0.031f, timePaint)

            datePaint.color = if (isAmbient) COLOR_TEXT_DIM_AMBIENT else COLOR_TEXT_DIM
            canvas.drawText(dateText, centerX, centerY + faceSize * 0.145f, datePaint)
        }

        private fun drawComplication(canvas: Canvas, now: Long) {
            if (lastComplicationData == null) return
            complicationDrawable.draw(canvas, now)
        }

        override fun onComplicationDataUpdate(complicationId: Int, data: ComplicationData) {
            if (complicationId != COMPLICATION_ID) return
            lastComplicationData = data
            complicationDrawable.setComplicationData(data)
            invalidate()
        }

        override fun onTapCommand(tapType: Int, x: Int, y: Int, eventTime: Long) {
            if (tapType == WatchFaceService.TAP_TYPE_TOUCH) {
                setChipHighlighted(chipBounds.contains(x, y))
            } else if (tapType == WatchFaceService.TAP_TYPE_TOUCH_CANCEL) {
                setChipHighlighted(false)
            } else if (tapType == WatchFaceService.TAP_TYPE_TAP) {
                setChipHighlighted(false)
                if (chipBounds.contains(x, y)) onComplicationTapped()
            }
        }

        private fun setChipHighlighted(highlighted: Boolean) {
            complicationDrawable.setIsHighlighted(highlighted)
            invalidate()
        }

        private fun onComplicationTapped() {
            val tapAction = lastComplicationData?.tapAction
            if (tapAction != null) {
                try {
                    tapAction.send()
                    return
                } catch (ignored: Exception) {
                    // PendingIntent caducado: caemos al selector
                }
            }
            openComplicationChooser()
        }

        private fun openComplicationChooser() {
            val intent = ComplicationHelperActivity.createProviderChooserHelperIntent(
                this@PixelWatchFaceService,
                ComponentName(this@PixelWatchFaceService, PixelWatchFaceService::class.java),
                COMPLICATION_ID,
                ComplicationData.TYPE_RANGED_VALUE,
                ComplicationData.TYPE_SHORT_TEXT,
                ComplicationData.TYPE_ICON,
                ComplicationData.TYPE_SMALL_IMAGE,
                ComplicationData.TYPE_LARGE_IMAGE
            )
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                this@PixelWatchFaceService.startActivity(intent)
            } catch (ignored: Exception) {
                // el reloj no tiene selector de complicaciones (no debería pasar en Wear 2.0)
            }
        }
    }
}
