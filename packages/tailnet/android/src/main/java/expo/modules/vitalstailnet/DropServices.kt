package expo.modules.vitalstailnet

import android.app.Service
import android.app.job.JobParameters
import android.app.job.JobService
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

class DropJobService : JobService() {
  override fun onStartJob(params: JobParameters): Boolean = DropCenter.attach(this, params)

  override fun onStopJob(params: JobParameters): Boolean = DropCenter.detach(this)
}

class DropService : Service() {
  override fun onBind(intent: Intent?): IBinder? = null

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    val notification = DropCenter.notification(this)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      startForeground(DropCenter.notificationId(), notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
    } else {
      startForeground(DropCenter.notificationId(), notification)
    }
    if (!DropCenter.attach(this)) finish()
    return START_NOT_STICKY
  }

  override fun onTimeout(startId: Int) = finish()

  override fun onTimeout(startId: Int, fgsType: Int) = finish()

  override fun onDestroy() {
    DropCenter.detach(this)
    super.onDestroy()
  }

  fun finish() {
    stopForeground(STOP_FOREGROUND_REMOVE)
    stopSelf()
  }
}
