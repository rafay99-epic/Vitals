package expo.modules.vitalstailnet

import android.content.Context
import android.content.Intent
import dev.vitals.tailnet.Tailnet
import expo.modules.kotlin.exception.Exceptions
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

class VitalsDropModule : Module() {
  private val context: Context
    get() = appContext.reactContext ?: throw Exceptions.ReactContextLost()

  override fun definition() = ModuleDefinition {
    Name("VitalsDrop")

    Events("transfer")

    Constant("canInstallApps") { DropCenter.canInstallApps(context) }

    OnCreate { DropCenter.emit = { sendEvent("transfer", it) } }

    OnDestroy { DropCenter.emit = null }

    AsyncFunction("upload") { json: String -> DropCenter.upload(context, json) }

    AsyncFunction("download") { json: String -> DropCenter.download(context, json) }

    AsyncFunction("cancel") { job: String -> Tailnet.dropCancel(job) }

    AsyncFunction("installApk") { uri: String ->
      view(Intent(Intent.ACTION_VIEW).setDataAndType(DropCenter.viewable(context, uri), "application/vnd.android.package-archive"))
    }

    AsyncFunction("openFile") { uri: String, mime: String? ->
      val target = DropCenter.viewable(context, uri)
      val type = mime ?: context.contentResolver.getType(target) ?: "*/*"
      view(Intent.createChooser(Intent(Intent.ACTION_VIEW).setDataAndType(target, type).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION), null))
    }
  }

  private fun view(intent: Intent) {
    intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    val activity = appContext.currentActivity
    if (activity != null) activity.startActivity(intent) else context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
  }
}
