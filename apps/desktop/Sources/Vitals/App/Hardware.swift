import Foundation
import AppKit
import Metal

enum Hardware {
    /// True only on Apple Silicon hardware. The packaged app is arm64-only,
    /// but keeping this runtime check makes unsupported hardware fail safely
    /// if a developer runs the executable from another build configuration.
    static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)
        return result == 0 && value == 1
    }

    /// True when running inside a virtual machine (QEMU/UTM, Parallels, VMware,
    /// VirtualBuddy, …). The kernel sets `kern.hv_vmm_present` to 1 for any
    /// guest under a hypervisor. Cached: the answer can't change during a run.
    static let isVirtualMachine: Bool = {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("kern.hv_vmm_present", &value, &size, nil, 0)
        return result == 0 && value == 1
    }()

    /// True only when a real, hardware-accelerated GPU is present. In a VM the
    /// system has either no Metal device or a paravirtual/software one, so
    /// SwiftUI renders in software. Cached.
    static let hasHardwareGPU: Bool = {
        guard let device = MTLCreateSystemDefaultDevice() else { return false }
        let name = device.name.lowercased()
        let softwareMarkers = ["paravirtual", "virtio", "software", "llvmpipe", "swiftshader"]
        return !softwareMarkers.contains { name.contains($0) }
    }()

    /// Whether Liquid Glass is safe to render. It must NOT render without a
    /// hardware GPU: macOS would composite its live backdrop blurs in software,
    /// and those offscreen captures balloon memory into the gigabytes (a VM hit
    /// 17.5 GB). Belt and suspenders — the VM flag and the GPU check each catch
    /// cases the other can miss (a paravirtual GPU that doesn't set the flag, a
    /// headless/no-Metal host that isn't technically a VM).
    static var supportsLiquidGlass: Bool { !isVirtualMachine && hasHardwareGPU }

    /// Shows an apology and exits when an unsupported machine runs a developer
    /// build directly. Release and Dev bundles are arm64-only.
    @MainActor
    static func showUnsupportedAndQuit() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Vitals requires an Apple Silicon Mac"
        alert.informativeText = """
        We're sorry — Vitals isn't supported on Intel-based Macs.

        It reads temperatures and controls fans through Apple Silicon (M-series) \
        hardware that Intel Macs don't have. Please run Vitals on an Apple Silicon Mac.
        """
        alert.addButton(withTitle: "Quit")

        app.activate(ignoringOtherApps: true)
        alert.runModal()
        exit(0)
    }
}
