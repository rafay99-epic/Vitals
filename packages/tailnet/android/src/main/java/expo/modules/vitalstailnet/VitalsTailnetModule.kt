package expo.modules.vitalstailnet

import android.content.Context
import android.net.ConnectivityManager
import dev.vitals.tailnet.Tailnet
import expo.modules.kotlin.exception.Exceptions
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import java.io.File

/** Embedded Tailscale node (tsnet) that tunnels the app's Wi-Fi route to the Mac from anywhere. */
class VitalsTailnetModule : Module() {
  private val context: Context
    get() = appContext.reactContext ?: throw Exceptions.ReactContextLost()

  private fun stateDir() = File(context.filesDir, "tailnet")

  /** The default network's interface (wlan0, rmnet_data0, ...), or "" when offline. */
  private fun defaultInterface(): String {
    val connectivity = context.getSystemService(ConnectivityManager::class.java) ?: return ""
    return connectivity.getLinkProperties(connectivity.activeNetwork)?.interfaceName ?: ""
  }

  override fun definition() = ModuleDefinition {
    Name("VitalsTailnet")

    AsyncFunction("start") { hostname: String ->
      val dir = stateDir().apply { mkdirs() }
      Tailnet.start(dir.absolutePath, hostname)
      Tailnet.networkChanged(defaultInterface())
    }

    AsyncFunction("state") { Tailnet.state() }

    AsyncFunction("login") { Tailnet.login() }

    AsyncFunction("networkChanged") { Tailnet.networkChanged(defaultInterface()) }

    AsyncFunction("forward") { target: String -> Tailnet.forward(target).toInt() }

    AsyncFunction("stop") { Tailnet.stop() }

    AsyncFunction("signOut") { Tailnet.signOut(stateDir().absolutePath) }
  }
}
