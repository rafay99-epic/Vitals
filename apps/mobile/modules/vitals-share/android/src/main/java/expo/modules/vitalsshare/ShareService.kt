package expo.modules.vitalsshare

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

class ShareService : Service() {
  override fun onBind(intent: Intent?): IBinder? = null

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      startForeground(NOTIFICATION, notification(this), ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
    } else {
      startForeground(NOTIFICATION, notification(this))
    }
    return START_NOT_STICKY
  }

  override fun onTimeout(startId: Int) = finish()

  override fun onTimeout(startId: Int, fgsType: Int) = finish()

  private fun finish() {
    stopForeground(STOP_FOREGROUND_REMOVE)
    stopSelf()
  }

  private companion object {
    const val CHANNEL = "vitals-share"
    const val NOTIFICATION = 4107

    fun notification(context: Context): Notification {
      val manager = context.getSystemService(NotificationManager::class.java)
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && manager.getNotificationChannel(CHANNEL) == null) {
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "Sharing this phone", NotificationManager.IMPORTANCE_LOW))
      }
      val icon = context.resources.getIdentifier("notification_icon", "drawable", context.packageName).takeIf { it != 0 } ?: android.R.drawable.stat_sys_upload_done
      val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
      return NotificationCompat.Builder(context, CHANNEL)
        .setSmallIcon(icon)
        .setContentTitle("Sharing this phone's files")
        .setContentText("Your Mac can browse and get files. Turn it off in Settings › This phone.")
        .setOngoing(true)
        .setSilent(true)
        .setCategory(NotificationCompat.CATEGORY_SERVICE)
        .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
        .apply { if (launch != null) setContentIntent(PendingIntent.getActivity(context, 0, launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)) }
        .build()
    }
  }
}
