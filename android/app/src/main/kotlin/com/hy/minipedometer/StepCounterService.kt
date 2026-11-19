package com.hy.minipedometer

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import android.provider.Settings

/**
 * Low-power foreground service listening to the hardware step counter.
 *
 * Why a foreground service: since Android 9, apps in the background receive
 * no sensor events at all. The hardware keeps counting regardless, but
 * without readings over time the app cannot tell which day steps belong to.
 *
 * Battery: the step counter is a dedicated low-power sensor. While the app
 * is not visible the listener uses hardware batching (readings are buffered
 * in the sensor hub and delivered every few minutes, each with its own
 * timestamp). While the app is visible, readings are delivered immediately.
 */
class StepCounterService : Service(), SensorEventListener {

    companion object {
        private const val CHANNEL_ID = "step_counting"
        private const val NOTIFICATION_ID = 7000
        private const val BATCH_LATENCY_US = 5 * 60 * 1_000_000 // 5 minutes

        @Volatile private var instance: StepCounterService? = null
        @Volatile private var liveRequested = false

        val isRunning: Boolean get() = instance != null

        fun hasSensor(context: Context): Boolean {
            val sm = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
            return sm.getDefaultSensor(Sensor.TYPE_STEP_COUNTER) != null
        }

        fun hasPermission(context: Context): Boolean =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
                context.checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) ==
                PackageManager.PERMISSION_GRANTED

        fun canRun(context: Context) = hasSensor(context) && hasPermission(context)

        /** Starts the service if possible. Safe to call repeatedly. */
        fun start(context: Context) {
            if (!canRun(context)) return
            try {
                context.startForegroundService(Intent(context, StepCounterService::class.java))
            } catch (e: Exception) {
                // e.g. ForegroundServiceStartNotAllowedException when called
                // from the background; it will be started on next app open.
            }
        }

        /** Immediate delivery while the UI is visible; batching otherwise. */
        fun setLive(live: Boolean) {
            liveRequested = live
            instance?.registerSensor()
        }

        /** Asks the sensor hub to deliver buffered readings now. */
        fun flush() {
            instance?.let { s -> s.sensor?.let { s.sensorManager.flush(s) } }
        }

        fun bootCount(context: Context): Int =
            Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT, -1)
    }

    private lateinit var sensorManager: SensorManager
    private var sensor: Sensor? = null
    private var bootCount = -1

    private val shutdownReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            SampleStore.markShutdown(
                bootCount, SystemClock.elapsedRealtime(), System.currentTimeMillis(),
            )
        }
    }

    override fun onCreate() {
        super.onCreate()
        SampleStore.init(this)
        if (!canRun(this) || !startInForeground()) {
            stopSelf()
            return
        }
        instance = this
        bootCount = bootCount(this)
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        // Prefer the wake-up variant: it can wake the CPU to deliver a full
        // batch instead of dropping readings when the buffer fills up.
        sensor = sensorManager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER, true)
            ?: sensorManager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        // Observation may have been interrupted before now (process killed,
        // force-stop, reboot): readings from here on are a new session.
        SampleStore.beginSession(sensor?.isWakeUpSensor == true)
        registerSensor()

        val filter = IntentFilter(Intent.ACTION_SHUTDOWN)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(shutdownReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(shutdownReceiver, filter)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (instance == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        if (instance === this) {
            sensorManager.unregisterListener(this)
            try { unregisterReceiver(shutdownReceiver) } catch (_: Exception) {}
            SampleStore.persistNow(sync = false)
            instance = null
        }
        super.onDestroy()
    }

    private fun registerSensor() {
        val s = sensor ?: return
        sensorManager.unregisterListener(this)
        val latency = if (liveRequested) 0 else BATCH_LATENCY_US
        sensorManager.registerListener(this, s, SensorManager.SENSOR_DELAY_NORMAL, latency)
    }

    override fun onSensorChanged(event: SensorEvent) {
        if (event.sensor.type != Sensor.TYPE_STEP_COUNTER) return
        val steps = event.values[0].toLong()
        val nowElapsed = SystemClock.elapsedRealtime()
        // event.timestamp uses the elapsedRealtimeNanos time base; batched
        // readings therefore keep the time they were actually counted.
        var elapsed = event.timestamp / 1_000_000
        if (elapsed <= 0 || elapsed > nowElapsed) elapsed = nowElapsed
        val wall = System.currentTimeMillis() - (nowElapsed - elapsed)
        SampleStore.record(bootCount, elapsed, wall, steps)
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    private fun startInForeground(): Boolean {
        val nm = getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(CHANNEL_ID) == null) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Step counting", NotificationManager.IMPORTANCE_MIN,
            ).apply {
                description = "Shown while steps are being counted"
                setShowBadge(false)
                enableVibration(false)
                setSound(null, null)
            }
            nm.createNotificationChannel(channel)
        }
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification = Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_steps)
            .setContentTitle("Counting steps")
            .setColor(0xFF241C18.toInt())
            .setOngoing(true)
            .setShowWhen(false)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setContentIntent(open)
            .apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_DEFERRED)
                }
            }
            .build()
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            true
        } catch (e: Exception) {
            false
        }
    }
}
