package com.hy.minipedometer

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges the Dart `AndroidStepTracker` to the native step counter.
 * Channel names must match lib/src/tracking/step_tracker.dart.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val METHOD_CHANNEL = "com.hy.minipedometer/steps"
        private const val LIVE_CHANNEL = "com.hy.minipedometer/steps/live"
        private const val PERMISSION_REQUEST = 4201
        private const val PREFS = "minipedometer_permissions"
        private const val KEY_ASKED = "askedActivityRecognition"
    }

    private var pendingPermission: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        SampleStore.init(this)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(status())
                "requestAccess" -> requestAccess(result)
                "openSettings" -> {
                    startActivity(
                        Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.fromParts("package", packageName, null),
                        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                    result.success(null)
                }
                "startTracking" -> {
                    StepCounterService.start(this)
                    result.success(null)
                }
                "flush" -> {
                    StepCounterService.flush()
                    result.success(null)
                }
                "readSamples" -> result.success(SampleStore.read())
                "installId" -> result.success(SampleStore.installId())
                "ackSamples" -> {
                    val upTo = call.argument<Number>("upTo")?.toLong()
                    if (upTo != null) SampleStore.ack(upTo)
                    result.success(null)
                }
                "walkingTime" -> {
                    val day = call.argument<String>("day")
                    if (day == null) {
                        result.error("bad_args", "day is required", null)
                    } else {
                        result.success(
                            SampleStore.walkingTime(day, StepCounterService.isRunning),
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, LIVE_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            private var listener: (() -> Unit)? = null

            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                val l: () -> Unit = { events.success(null) }
                listener = l
                SampleStore.addListener(l)
                StepCounterService.setLive(true)
            }

            override fun onCancel(arguments: Any?) {
                listener?.let { SampleStore.removeListener(it) }
                listener = null
                StepCounterService.setLive(false)
            }
        })
    }

    private fun status(): String {
        if (!StepCounterService.hasSensor(this)) return "unsupported"
        if (StepCounterService.hasPermission(this)) return "authorized"
        val asked = getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_ASKED, false)
        return when {
            !asked -> "notDetermined"
            shouldShowRequestPermissionRationale(Manifest.permission.ACTIVITY_RECOGNITION) -> "denied"
            else -> "permanentlyDenied"
        }
    }

    private fun requestAccess(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || StepCounterService.hasPermission(this) ||
            !StepCounterService.hasSensor(this)
        ) {
            result.success(status())
            return
        }
        if (pendingPermission != null) {
            result.error("busy", "A permission request is already in progress", null)
            return
        }
        pendingPermission = result
        getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(KEY_ASKED, true).apply()
        requestPermissions(arrayOf(Manifest.permission.ACTIVITY_RECOGNITION), PERMISSION_REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PERMISSION_REQUEST) return
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (granted) StepCounterService.start(this)
        pendingPermission?.success(status())
        pendingPermission = null
    }
}
