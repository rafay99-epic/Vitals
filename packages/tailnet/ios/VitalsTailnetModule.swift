import ExpoModulesCore
import Tailnet

// gomobile exports Go errors as a trailing `NSError` out-parameter. Swift only turns that into `throws`
// for Objective-C methods, not these free functions, so each call checks the pointer itself.
/// Embedded Tailscale node (tsnet) that tunnels the app's Wi-Fi route to the Mac from anywhere.
public class VitalsTailnetModule: Module {
  public func definition() -> ModuleDefinition {
    Name("VitalsTailnet")

    AsyncFunction("start") { (hostname: String) throws in
      let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      let dir = support.appendingPathComponent("tailnet", isDirectory: true)
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      var error: NSError?
      TailnetStart(dir.path, hostname, &error)
      if let error { throw error }
    }

    AsyncFunction("state") { () -> String in TailnetState() }

    AsyncFunction("forward") { (target: String) throws -> Int in
      var port = 0
      var error: NSError?
      TailnetForward(target, &port, &error)
      if let error { throw error }
      return port
    }

    AsyncFunction("stop") { TailnetStop() }
  }
}
