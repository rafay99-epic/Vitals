package expo.modules.vitalsupdate

import android.app.Activity
import com.google.android.play.core.appupdate.AppUpdateInfo
import com.google.android.play.core.appupdate.AppUpdateManager
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.InstallStateUpdatedListener
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.InstallErrorCode
import com.google.android.play.core.install.model.InstallStatus
import com.google.android.play.core.install.model.UpdateAvailability
import expo.modules.kotlin.Promise
import expo.modules.kotlin.exception.Exceptions
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

/**
 * Google Play in-app updates. A flexible update downloads while the app runs and waits:
 * Play installs it only when JS calls `complete`, so the user picks the moment.
 */
class VitalsUpdateModule : Module() {
  private val manager: AppUpdateManager by lazy {
    AppUpdateManagerFactory.create(appContext.reactContext ?: throw Exceptions.ReactContextLost())
  }

  private var sentPercent = -1

  // Progress goes out once per whole percent, so a download never floods the bridge.
  private val listener = InstallStateUpdatedListener { state ->
    when (state.installStatus()) {
      InstallStatus.DOWNLOADING -> {
        val total = state.totalBytesToDownload()
        val percent = if (total > 0) (state.bytesDownloaded() * 100 / total).toInt() else 0
        if (percent != sentPercent) {
          sentPercent = percent
          sendEvent(PROGRESS, mapOf("progress" to percent / 100.0))
        }
      }
      InstallStatus.DOWNLOADED -> sendEvent(DOWNLOADED)
      InstallStatus.FAILED -> {
        // Low battery or storage; Play gives no finer reason.
        val blocked = state.installErrorCode() == InstallErrorCode.ERROR_INSTALL_NOT_ALLOWED
        sendEvent(STOPPED, mapOf("reason" to if (blocked) "blocked" else "download"))
      }
      InstallStatus.CANCELED -> sendEvent(STOPPED, mapOf("reason" to "cancelled"))
      else -> Unit
    }
    if (state.installStatus() != InstallStatus.DOWNLOADING) sentPercent = -1
  }

  override fun definition() = ModuleDefinition {
    Name("VitalsUpdate")

    Events(PROGRESS, DOWNLOADED, STOPPED)

    OnCreate { manager.registerListener(listener) }
    OnDestroy { manager.unregisterListener(listener) }

    // Null when Play can't answer, e.g. the app wasn't installed from Play.
    AsyncFunction("check") { promise: Promise ->
      manager.appUpdateInfo
        .addOnSuccessListener { info -> promise.resolve(facts(info)) }
        .addOnFailureListener { promise.resolve(null) }
    }

    AsyncFunction("start") { immediate: Boolean, promise: Promise ->
      val activity = appContext.currentActivity ?: return@AsyncFunction promise.resolve(null)
      val type = if (immediate) AppUpdateType.IMMEDIATE else AppUpdateType.FLEXIBLE
      manager.appUpdateInfo
        .addOnSuccessListener { info ->
          if (!startable(info) || !info.isUpdateTypeAllowed(type)) {
            promise.resolve(null)
            return@addOnSuccessListener
          }
          manager.startUpdateFlow(info, activity, AppUpdateOptions.defaultOptions(type))
            .addOnSuccessListener { code -> promise.resolve(outcome(code)) }
            .addOnFailureListener { promise.resolve("failed") }
        }
        .addOnFailureListener { promise.resolve(null) }
    }

    Function("complete") { manager.completeUpdate() }
  }

  private fun startable(info: AppUpdateInfo) =
    info.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE ||
      info.updateAvailability() == UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS

  private fun facts(info: AppUpdateInfo) = mapOf(
    "available" to startable(info),
    "version" to info.availableVersionCode(),
    "immediate" to info.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE),
    "flexible" to info.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE),
    "download" to when (info.installStatus()) {
      InstallStatus.DOWNLOADED -> "downloaded"
      InstallStatus.PENDING, InstallStatus.DOWNLOADING, InstallStatus.INSTALLING -> "downloading"
      else -> "idle"
    }
  )

  private fun outcome(code: Int) = when (code) {
    Activity.RESULT_OK -> "accepted"
    Activity.RESULT_CANCELED -> "cancelled"
    else -> "failed"
  }

  companion object {
    private const val PROGRESS = "onProgress"
    private const val DOWNLOADED = "onDownloaded"
    private const val STOPPED = "onStopped"
  }
}
