import ExpoModulesCore
import Tailnet

/// Embedded Tailscale node (tsnet) that tunnels the app's Wi-Fi route to the Mac from anywhere.
public class VitalsTailnetModule: Module {
  public func definition() -> ModuleDefinition {
    Name("VitalsTailnet")

    AsyncFunction("start") { (hostname: String) throws in
      let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      let dir = support.appendingPathComponent("tailnet", isDirectory: true)
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      try TailnetStart(dir.path, hostname)
    }

    AsyncFunction("state") { () -> String in TailnetState() }

    AsyncFunction("forward") { (target: String) throws -> Int in
      var port = 0
      try TailnetForward(target, &port)
      return port
    }

    AsyncFunction("stop") { TailnetStop() }
  }
}
