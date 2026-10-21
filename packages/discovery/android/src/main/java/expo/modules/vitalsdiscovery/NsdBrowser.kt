package expo.modules.vitalsdiscovery

import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.os.Handler
import androidx.annotation.RequiresApi
import java.net.Inet4Address
import java.util.concurrent.Executor

/**
 * Browses one DNS-SD service type and resolves every instance it sees, emitting
 * `found` (again whenever address or TXT changes) and `lost`.
 *
 * All state is touched on the main thread only: NsdManager callbacks are posted there.
 * API 34+ watches each service with a ServiceInfoCallback (all addresses, live updates).
 * Older releases only allow one `resolveService` at a time, so resolves are queued.
 */
internal class NsdBrowser(
  private val nsd: NsdManager,
  private val main: Handler,
  private val type: String,
  private val emit: (String, Map<String, Any?>) -> Unit,
) {
  private val executor = Executor { main.post(it) }
  private val emitted = mutableMapOf<String, Map<String, Any?>>()
  private val watchers = mutableMapOf<String, () -> Unit>()
  private val pending = ArrayDeque<NsdServiceInfo>()
  private var resolving = false
  private var stopped = false

  private val discovery = object : NsdManager.DiscoveryListener {
    override fun onServiceFound(info: NsdServiceInfo) {
      main.post { found(info) }
    }

    override fun onServiceLost(info: NsdServiceInfo) {
      main.post { lost(info.serviceName) }
    }

    override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
      main.post { emit("failed", mapOf("reason" to "Discovery failed to start ($errorCode)")) }
    }

    override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) = Unit

    override fun onDiscoveryStarted(serviceType: String) = Unit

    override fun onDiscoveryStopped(serviceType: String) = Unit
  }

  fun start() = nsd.discoverServices(type, NsdManager.PROTOCOL_DNS_SD, discovery)

  /** NsdManager throws if the listener was never registered (e.g. start failed), hence runCatching. */
  fun stop() {
    stopped = true
    runCatching { nsd.stopServiceDiscovery(discovery) }
    watchers.values.forEach { it() }
    watchers.clear()
    pending.clear()
  }

  private fun found(info: NsdServiceInfo) {
    val name = info.serviceName
    if (stopped || name in watchers || pending.any { it.serviceName == name }) return
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) watch(info) else enqueue(info)
  }

  private fun lost(name: String) {
    if (stopped) return
    pending.removeAll { it.serviceName == name }
    watchers.remove(name)?.invoke()
    if (emitted.remove(name) != null) emit("lost", mapOf("name" to name))
  }

  @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
  private fun watch(info: NsdServiceInfo) {
    val name = info.serviceName
    val callback = object : NsdManager.ServiceInfoCallback {
      override fun onServiceUpdated(serviceInfo: NsdServiceInfo) = publish(serviceInfo)

      override fun onServiceInfoCallbackRegistrationFailed(errorCode: Int) {
        watchers.remove(name)
      }

      override fun onServiceLost() = Unit

      override fun onServiceInfoCallbackUnregistered() = Unit
    }
    watchers[name] = { runCatching { nsd.unregisterServiceInfoCallback(callback) } }
    nsd.registerServiceInfoCallback(info, executor, callback)
  }

  private fun enqueue(info: NsdServiceInfo) {
    pending.addLast(info)
    if (!resolving) resolveNext()
  }

  @Suppress("DEPRECATION")
  private fun resolveNext() {
    val info = pending.removeFirstOrNull()
    resolving = info != null
    if (stopped || info == null) return
    nsd.resolveService(
      info,
      object : NsdManager.ResolveListener {
        override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
          main.post {
            publish(serviceInfo)
            resolveNext()
          }
        }

        override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
          main.post(::resolveNext)
        }
      },
    )
  }

  private fun publish(info: NsdServiceInfo) {
    val host = address(info)
    if (stopped || host == null) return
    val mac = mapOf(
      "name" to info.serviceName,
      "host" to host,
      "port" to info.port,
      "txt" to info.attributes.mapValues { it.value?.decodeToString().orEmpty() },
    )
    if (emitted.put(info.serviceName, mac) != mac) emit("found", mac)
  }

  /** Prefers IPv4; falls back to whatever address is available. */
  @Suppress("DEPRECATION")
  private fun address(info: NsdServiceInfo): String? {
    val addresses = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) info.hostAddresses else listOfNotNull(info.host)
    return (addresses.firstOrNull { it is Inet4Address } ?: addresses.firstOrNull())?.hostAddress
  }
}
