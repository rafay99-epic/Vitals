package expo.modules.vitalstailnet

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.service.quicksettings.TileService

class DropTileService : TileService() {
  @SuppressLint("StartActivityAndCollapseDeprecated")
  override fun onClick() {
    @Suppress("DEPRECATION")
    val scheme = packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA).metaData?.getString("dev.vitals.drop.SCHEME")
    val intent = (if (scheme != null) Intent(Intent.ACTION_VIEW, Uri.parse("$scheme://clipboard/send")).setPackage(packageName) else packageManager.getLaunchIntentForPackage(packageName) ?: return)
      .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
      startActivityAndCollapse(PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
    } else {
      @Suppress("DEPRECATION")
      startActivityAndCollapse(intent)
    }
  }
}
