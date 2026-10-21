package expo.modules.vitalsdiscovery

import android.Manifest
import android.net.nsd.NsdManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import expo.modules.interfaces.permissions.PermissionsResponseListener
import expo.modules.interfaces.permissions.PermissionsStatus
import expo.modules.kotlin.Promise
import expo.modules.kotlin.exception.Exceptions
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

class VitalsDiscoveryModule : Module() {
  private val main = Handler(Looper.getMainLooper())

  /** Main thread only. */
  private var browser: NsdBrowser? = null

  override fun definition() = ModuleDefinition {
    Name("VitalsDiscovery")

    Events("found", "lost", "failed")

    Function("start") {
      val nsd = appContext.reactContext?.getSystemService(NsdManager::class.java) ?: throw Exceptions.ReactContextLost()
      main.post {
        if (browser == null) browser = NsdBrowser(nsd, main, "_vitals._tcp", ::sendEvent).also { it.start() }
      }
    }

    Function("stop") { main.post(::stop) }

    OnDestroy { main.post(::stop) }

    /** Android 17 gates LAN access behind a runtime permission; older releases allow it implicitly. */
    AsyncFunction("requestLocalNetwork") { promise: Promise ->
      if (Build.VERSION.SDK_INT < Build.VERSION_CODES.CINNAMON_BUN) return@AsyncFunction promise.resolve("granted")
      val permissions = appContext.permissions ?: throw Exceptions.PermissionsModuleNotFound()
      val permission = Manifest.permission.ACCESS_LOCAL_NETWORK
      permissions.askForPermissions(
        PermissionsResponseListener { result ->
          promise.resolve(if (result[permission]?.status == PermissionsStatus.GRANTED) "granted" else "denied")
        },
        permission,
      )
    }
  }

  private fun stop() {
    browser?.stop()
    browser = null
  }
}
