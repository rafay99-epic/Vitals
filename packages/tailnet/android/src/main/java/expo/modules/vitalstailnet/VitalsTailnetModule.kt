package expo.modules.vitalstailnet

import dev.vitals.tailnet.Tailnet
import expo.modules.kotlin.exception.Exceptions
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import java.io.File

/** Embedded Tailscale node (tsnet) that tunnels the app's Wi-Fi route to the Mac from anywhere. */
class VitalsTailnetModule : Module() {
  override fun definition() = ModuleDefinition {
    Name("VitalsTailnet")

    AsyncFunction("start") { hostname: String ->
      val context = appContext.reactContext ?: throw Exceptions.ReactContextLost()
      val dir = File(context.filesDir, "tailnet").apply { mkdirs() }
      Tailnet.start(dir.absolutePath, hostname)
    }

    AsyncFunction("state") { Tailnet.state() }

    AsyncFunction("forward") { target: String -> Tailnet.forward(target).toInt() }

    AsyncFunction("stop") { Tailnet.stop() }
  }
}
