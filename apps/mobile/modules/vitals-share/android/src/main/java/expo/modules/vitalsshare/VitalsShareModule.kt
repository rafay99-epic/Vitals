package expo.modules.vitalsshare

import android.content.Intent
import android.os.Build
import android.os.Environment
import androidx.core.content.ContextCompat
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.ReactContext
import com.facebook.react.jstasks.HeadlessJsTaskConfig
import com.facebook.react.jstasks.HeadlessJsTaskContext
import expo.modules.kotlin.functions.Queues
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

class VitalsShareModule : Module() {
  private var task: Int? = null

  override fun definition() = ModuleDefinition {
    Name("VitalsShare")

    AsyncFunction("start") {
      val context = appContext.reactContext as? ReactContext ?: return@AsyncFunction false
      val started = runCatching { ContextCompat.startForegroundService(context, Intent(context, ShareService::class.java)) }.isSuccess
      if (started && task == null) {
        task = HeadlessJsTaskContext.getInstance(context).startTask(HeadlessJsTaskConfig(TASK, Arguments.createMap(), 0, true))
      }
      started
    }.runOnQueue(Queues.MAIN)

    AsyncFunction("stop") {
      task = null
      val context = appContext.reactContext ?: return@AsyncFunction Unit
      context.stopService(Intent(context, ShareService::class.java))
      Unit
    }.runOnQueue(Queues.MAIN)

    AsyncFunction("recent") { kind: String, offset: Int, limit: Int ->
      val context = appContext.reactContext ?: throw IllegalStateException("No context")
      Recent.page(context, kind, offset, limit)
    }

    AsyncFunction("thumbnail") { path: String, px: Int -> Recent.thumbnail(path, px) }

    Function("fullStorage") { if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) Environment.isExternalStorageManager() else null }

    AsyncFunction("toBack") { appContext.currentActivity?.moveTaskToBack(true) ?: false }.runOnQueue(Queues.MAIN)
  }

  private companion object {
    const val TASK = "VitalsShare"
  }
}
