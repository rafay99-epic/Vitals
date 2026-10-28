import ExpoModulesCore
import Network

private let serviceType = "_vitals._tcp"
private let policyDenied = NWError.dns(DNSServiceErrorType(kDNSServiceErr_PolicyDenied))

private struct Found: Equatable {
  let host: String
  let port: UInt16
  let txt: [String: String]
}

private struct Mac {
  var txt: [String: String] = [:]
  var connection: NWConnection?
  var emitted: Found?
}

/// Browses `_vitals._tcp` with NWBrowser. Each result is resolved by connecting to the service
/// endpoint and reading the path's remote address (NetService is deprecated and NWBrowser exposes
/// no resolver). IPv4 is tried first, then any family. All state lives on `queue`.
public final class VitalsDiscoveryModule: Module {
  private let queue = DispatchQueue(label: "vitals.discovery")
  private var browser: NWBrowser?
  private var macs: [String: Mac] = [:]

  public func definition() -> ModuleDefinition {
    Name("VitalsDiscovery")

    Events("found", "lost", "failed")

    Function("start") { self.queue.async { self.start() } }

    Function("stop") { self.queue.async { self.stop() } }

    OnDestroy { self.queue.async { self.stop() } }

    AsyncFunction("requestLocalNetwork") { (promise: Promise) in
      self.queue.async { self.probe(promise) }
    }
  }

  private func start() {
    guard browser == nil else { return }
    let browser = NWBrowser(for: .bonjourWithTXTRecord(type: serviceType, domain: nil), using: NWParameters())
    browser.stateUpdateHandler = { [weak self] state in self?.browserChanged(state) }
    browser.browseResultsChangedHandler = { [weak self] _, changes in changes.forEach { self?.apply($0) } }
    browser.start(queue: queue)
    self.browser = browser
  }

  private func stop() {
    browser?.cancel()
    browser = nil
    macs.values.forEach { $0.connection?.cancel() }
    macs.removeAll()
  }

  /// Policy denial is reported as `.waiting`, and browsing resumes on its own if the user later allows access.
  private func browserChanged(_ state: NWBrowser.State) {
    switch state {
    case .failed(let error):
      stop()
      sendEvent("failed", ["reason": "\(error)"])
    case .waiting(policyDenied):
      sendEvent("failed", ["reason": "Local network access denied"])
    default:
      break
    }
  }

  private func apply(_ change: NWBrowser.Result.Change) {
    switch change {
    case .added(let result), .changed(_, let result, _):
      update(result)
    case .removed(let result):
      remove(result)
    default:
      break
    }
  }

  private func update(_ result: NWBrowser.Result) {
    guard case let .service(name, _, _, _) = result.endpoint else { return }
    macs[name]?.connection?.cancel()
    macs[name, default: Mac()].txt = txt(result.metadata)
    resolve(name, result.endpoint, family: .v4)
  }

  private func remove(_ result: NWBrowser.Result) {
    guard case let .service(name, _, _, _) = result.endpoint, let mac = macs.removeValue(forKey: name) else { return }
    mac.connection?.cancel()
    if mac.emitted != nil { sendEvent("lost", ["name": name]) }
  }

  private func resolve(_ name: String, _ endpoint: NWEndpoint, family: NWProtocolIP.Options.Version) {
    let parameters = NWParameters.tcp
    (parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)?.version = family
    let connection = NWConnection(to: endpoint, using: parameters)
    connection.stateUpdateHandler = { [weak self, weak connection] state in
      guard let self, let connection, self.macs[name]?.connection === connection else { return }
      switch state {
      case .ready:
        let remote = connection.currentPath?.remoteEndpoint
        connection.cancel()
        self.macs[name]?.connection = nil
        self.resolved(name, remote)
      case .waiting, .failed:
        connection.cancel()
        self.macs[name]?.connection = nil
        if family == .v4 { self.resolve(name, endpoint, family: .any) }
      default:
        break
      }
    }
    macs[name]?.connection = connection
    connection.start(queue: queue)
  }

  private func resolved(_ name: String, _ endpoint: NWEndpoint?) {
    guard case let .hostPort(host, port)? = endpoint, let address = address(host), let mac = macs[name] else { return }
    let found = Found(host: address, port: port.rawValue, txt: mac.txt)
    guard found != mac.emitted else { return }
    macs[name]?.emitted = found
    sendEvent("found", ["name": name, "host": found.host, "port": Int(found.port), "txt": found.txt])
  }

  /// iOS has no API to read local network access. Browsing triggers the prompt; denial shows up as
  /// `.waiting(PolicyDenied)`, which may also appear while the prompt is up, so the verdict is
  /// "granted" on any result, otherwise the last state seen after a short window.
  private func probe(_ promise: Promise) {
    let probe = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: NWParameters())
    var denied = false
    var settled = false
    let settle = { (granted: Bool) in
      guard !settled else { return }
      settled = true
      probe.stateUpdateHandler = nil
      probe.browseResultsChangedHandler = nil
      probe.cancel()
      promise.resolve(granted ? "granted" : "denied")
    }
    probe.stateUpdateHandler = { state in denied = state == .waiting(policyDenied) }
    probe.browseResultsChangedHandler = { results, _ in
      if !results.isEmpty { settle(true) }
    }
    probe.start(queue: queue)
    queue.asyncAfter(deadline: .now() + 2) { settle(!denied) }
  }
}

private func txt(_ metadata: NWBrowser.Result.Metadata) -> [String: String] {
  switch metadata {
  case .bonjour(let record): record.dictionary
  default: [:]
  }
}

private func address(_ host: NWEndpoint.Host) -> String? {
  switch host {
  case .ipv4(let ip): ip.rawValue.map(String.init).joined(separator: ".")
  case .ipv6(let ip): "\(ip)"
  case .name(let name, _): name
  @unknown default: nil
  }
}
