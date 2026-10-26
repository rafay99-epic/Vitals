package expo.modules.vitalsshare

import android.content.Intent
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
  }

  private companion object {
    const val TASK = "VitalsShare"
  }
}
