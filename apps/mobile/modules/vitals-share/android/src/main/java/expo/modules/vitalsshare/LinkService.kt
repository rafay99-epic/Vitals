package expo.modules.vitalsshare

import android.app.ForegroundServiceStartNotAllowedException
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Keeps the phone's link to the Mac alive while Vitals is closed: a connectedDevice foreground
 * service with one quiet ongoing notification. JS sets its text (`update`) as the connection
 * changes. Disconnect, or Android stopping it, calls `onStopped` so JS never thinks it still runs.
 */
class LinkService : Service() {
  override fun onBind(intent: Intent?): IBinder? = null

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    if (intent?.action == DISCONNECT) {
      finish()
      return START_NOT_STICKY
    }
    val failure = runCatching {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        startForeground(NOTIFICATION, notification(this), ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
      } else {
        startForeground(NOTIFICATION, notification(this))
      }
    }.exceptionOrNull()
    if (failure == null) {
      running = true
      return START_NOT_STICKY
    }
    // Android 12+ refuses a start from the background: say so and stay down.
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || failure !is ForegroundServiceStartNotAllowedException) throw failure
    stopSelf()
    onStopped?.invoke()
    return START_NOT_STICKY
  }

  override fun onTimeout(startId: Int) = finish()

  override fun onTimeout(startId: Int, fgsType: Int) = finish()

  override fun onDestroy() {
    if (running) {
      running = false
      onStopped?.invoke()
    }
    super.onDestroy()
  }

  private fun finish() {
    stopForeground(STOP_FOREGROUND_REMOVE)
    stopSelf()
  }

  companion object {
    private const val CHANNEL = "vitals-link"
    private const val NOTIFICATION = 4107
    private const val DISCONNECT = "expo.modules.vitalsshare.DISCONNECT"

    @Volatile private var title = "Vitals"
    @Volatile private var text = "Connecting to your Mac"

    @Volatile var running = false
      private set

    /** Set by the module: tells JS the service ended, whoever ended it. */
    @Volatile var onStopped: (() -> Unit)? = null

    /** New notification text. Shown at once while the service runs, and used when it next starts. */
    fun update(context: Context, nextTitle: String, nextText: String) {
      if (nextTitle == title && nextText == text) return
      title = nextTitle
      text = nextText
      if (running) context.getSystemService(NotificationManager::class.java).notify(NOTIFICATION, notification(context))
    }

    private fun notification(context: Context): Notification {
      val manager = context.getSystemService(NotificationManager::class.java)
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && manager.getNotificationChannel(CHANNEL) == null) {
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "Connection to your Mac", NotificationManager.IMPORTANCE_LOW))
      }
      val icon = context.resources.getIdentifier("notification_icon", "drawable", context.packageName).takeIf { it != 0 } ?: android.R.drawable.stat_sys_upload_done
      val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
      val disconnect = PendingIntent.getService(context, 1, Intent(context, LinkService::class.java).setAction(DISCONNECT), PendingIntent.FLAG_IMMUTABLE)
      return NotificationCompat.Builder(context, CHANNEL)
        .setSmallIcon(icon)
        .setContentTitle(title)
        .setContentText(text)
        .setOngoing(true)
        .setSilent(true)
        .setOnlyAlertOnce(true)
        .setShowWhen(false)
        .setCategory(NotificationCompat.CATEGORY_SERVICE)
        .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
        .addAction(0, "Disconnect", disconnect)
        .apply { if (launch != null) setContentIntent(PendingIntent.getActivity(context, 0, launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)) }
        .build()
    }
  }
}
