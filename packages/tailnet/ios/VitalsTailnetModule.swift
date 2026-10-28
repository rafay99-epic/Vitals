import ExpoModulesCore
import Tailnet

// gomobile exports Go errors as a trailing `NSError` out-parameter. Swift only turns that into `throws`
// for Objective-C methods, not these free functions, so each call checks the pointer itself.
/// Embedded Tailscale node (tsnet) that tunnels the app's Wi-Fi route to the Mac from anywhere.
public class VitalsTailnetModule: Module {
  /// The node's state folder in Application Support. Its keys belong to this phone, so it stays out of iCloud backups.
  private func stateDir() throws -> URL {
    let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    var dir = support.appendingPathComponent("tailnet", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try dir.setResourceValues(values)
    return dir
  }

  public func definition() -> ModuleDefinition {
    Name("VitalsTailnet")

    AsyncFunction("start") { (hostname: String) throws in
      let dir = try self.stateDir()
      var error: NSError?
      TailnetStart(dir.path, hostname, &error)
      if let error { throw error }
    }

    AsyncFunction("state") { () -> String in TailnetState() }

    AsyncFunction("login") { () throws in
      var error: NSError?
      TailnetLogin(&error)
      if let error { throw error }
    }

    // iOS netmon follows the routing socket itself; the event only makes it re-check now.
    AsyncFunction("networkChanged") { TailnetNetworkChanged("") }

    AsyncFunction("forward") { (target: String) throws -> Int in
      var port = 0
      var error: NSError?
      TailnetForward(target, &port, &error)
      if let error { throw error }
      return port
    }

    AsyncFunction("stop") { TailnetStop() }

    AsyncFunction("signOut") { () throws in
      let dir = try self.stateDir()
      var error: NSError?
      TailnetSignOut(dir.path, &error)
      if let error { throw error }
    }
  }
}
