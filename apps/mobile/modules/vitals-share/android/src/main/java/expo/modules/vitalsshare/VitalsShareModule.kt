package expo.modules.vitalsshare

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
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

    Events(LINK_STOPPED)

    // The link service may stop on its own (Disconnect in the notification, Android); JS hears it here.
    OnCreate {
      LinkService.onStopped = {
        task = null
        sendEvent(LINK_STOPPED)
      }
    }

    OnDestroy { LinkService.onStopped = null }

    /** Starts the link service and a headless task that keeps JS running while the app is closed. */
    AsyncFunction("start") {
      val context = appContext.reactContext as? ReactContext ?: return@AsyncFunction false
      val started = runCatching { ContextCompat.startForegroundService(context, Intent(context, LinkService::class.java)) }.isSuccess
      if (started && task == null) {
        task = HeadlessJsTaskContext.getInstance(context).startTask(HeadlessJsTaskConfig(TASK, Arguments.createMap(), 0, true))
      }
      started
    }.runOnQueue(Queues.MAIN)

    AsyncFunction("stop") {
      task = null
      val context = appContext.reactContext ?: return@AsyncFunction Unit
      context.stopService(Intent(context, LinkService::class.java))
      Unit
    }.runOnQueue(Queues.MAIN)

    /** The notification's title and line, e.g. the Mac's name and "Connected over Wi-Fi". */
    Function("update") { title: String, text: String ->
      val context = appContext.reactContext ?: return@Function Unit
      LinkService.update(context, title, text)
    }

    AsyncFunction("recent") { kind: String, offset: Int, limit: Int ->
      val context = appContext.reactContext ?: throw IllegalStateException("No context")
      Recent.page(context, kind, offset, limit)
    }

    AsyncFunction("thumbnail") { path: String, px: Int -> Recent.thumbnail(path, px) }

    Function("fullStorage") { if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) Environment.isExternalStorageManager() else null }

    /** Opens Vitals' own All files access switch, or the list of apps where a phone has no such page. */
    AsyncFunction("openFullStorage") {
      val context = appContext.currentActivity ?: appContext.reactContext ?: return@AsyncFunction false
      if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return@AsyncFunction false
      val own = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, Uri.parse("package:${context.packageName}"))
      val any = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
      listOf(own, any).any { intent ->
        if (context !is Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { context.startActivity(intent) }.isSuccess
      }
    }.runOnQueue(Queues.MAIN)

    AsyncFunction("list") { path: String -> Files.list(path) }

    AsyncFunction("readChunk") { path: String, offset: Double, length: Int -> Files.readChunk(path, offset, length) }

    AsyncFunction("pdfPages") { path: String -> Pdf.pages(path) }

    AsyncFunction("pdfPage") { path: String, index: Int, width: Int ->
      val context = appContext.reactContext ?: throw IllegalStateException("No context")
      Pdf.page(context, path, index, width)
    }

    AsyncFunction("pdfClose") { Pdf.close() }

    AsyncFunction("toBack") { appContext.currentActivity?.moveTaskToBack(true) ?: false }.runOnQueue(Queues.MAIN)
  }

  private companion object {
    const val TASK = "VitalsShare"
    const val LINK_STOPPED = "onLinkStopped"
  }
}
