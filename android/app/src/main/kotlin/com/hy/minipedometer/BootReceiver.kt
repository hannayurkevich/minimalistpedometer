package com.hy.minipedometer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Restarts step counting after a reboot or an app update. (Starting a
 * foreground service from these broadcasts is explicitly permitted.)
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> {
                SampleStore.init(context)
                StepCounterService.start(context)
            }
        }
    }
}
