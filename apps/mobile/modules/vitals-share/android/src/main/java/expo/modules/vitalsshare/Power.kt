package expo.modules.vitalsshare

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings

/**
 * Keeps this phone answering other devices with its screen off. Android's battery limits freeze the
 * link service anyway, so Vitals asks once to be left unrestricted, and holds the CPU awake for a
 * short while after each request so a browsing session or send isn't cut off between requests.
 */
object Power {
  private const val TAG = "vitals:serve"
  private var lock: PowerManager.WakeLock? = null

  fun unrestricted(context: Context): Boolean =
    context.getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(context.packageName)

  /** Android's own "let Vitals always run in the background" prompt; its settings list if that won't open. */
  @SuppressLint("BatteryLife")
  fun ask(context: Context): Boolean {
    val own = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:${context.packageName}"))
    val list = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
    return listOf(own, list).any { intent ->
      if (context !is Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      runCatching { context.startActivity(intent) }.isSuccess
    }
  }

  /** Holds the CPU for `ms` from now; a later call restarts the clock. It always lets go on its own. */
  @Synchronized
  fun stayAwake(context: Context, ms: Long) {
    val held = lock ?: context.getSystemService(PowerManager::class.java).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, TAG).also {
      it.setReferenceCounted(false)
      lock = it
    }
    held.acquire(ms)
  }
}
