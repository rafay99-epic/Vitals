import Foundation
import AppKit
import CoreServices
import IOKit.pwr_mgt

@MainActor
final class PowerControl {
    struct KeepAwake: Equatable, Sendable {
        var active = false
        var display = false
        var until: Date?
        var whileProcess: ProcessRef?
    }

    private(set) var keepAwake = KeepAwake()
    var onKeepAwakeChange: ((KeepAwake) -> Void)?

    private var systemAssertion: IOPMAssertionID = 0
    private var displayAssertion: IOPMAssertionID = 0
    private var expiry: Timer?
    private var processWatch: DispatchSourceProcess?

    func startKeepAwake(until: Date?, display: Bool, whileProcess: ProcessRef?) -> String? {
        stopKeepAwake(notify: false)
        if let whileProcess, ProcessSampler.startTimeMs(of: whileProcess.pid) != whileProcess.startTimeMs {
            return "That process already exited"
        }
        guard let system = assertion("PreventUserIdleSystemSleep") else { return "macOS refused the keep-awake assertion" }
        systemAssertion = system
        if display, let displayID = assertion("PreventUserIdleDisplaySleep") { displayAssertion = displayID }
        keepAwake = KeepAwake(active: true, display: display, until: until, whileProcess: whileProcess)
        if let until {
            let timer = Timer(fire: until, interval: 0, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.stopKeepAwake(notify: true) }
            }
            RunLoop.main.add(timer, forMode: .common)
            expiry = timer
        }
        if let whileProcess {
            let source = DispatchSource.makeProcessSource(identifier: whileProcess.pid, eventMask: .exit, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.stopKeepAwake(notify: true) }
            }
            source.resume()
            processWatch = source
        }
        onKeepAwakeChange?(keepAwake)
        return nil
    }

    func stopKeepAwake(notify: Bool = true) {
        let wasActive = keepAwake.active
        if systemAssertion != 0 { IOPMAssertionRelease(systemAssertion) }
        if displayAssertion != 0 { IOPMAssertionRelease(displayAssertion) }
        systemAssertion = 0
        displayAssertion = 0
        expiry?.invalidate()
        expiry = nil
        processWatch?.cancel()
        processWatch = nil
        keepAwake = KeepAwake()
        if notify && wasActive { onKeepAwakeChange?(keepAwake) }
    }

    private func assertion(_ type: String) -> IOPMAssertionID? {
        var id: IOPMAssertionID = 0
        let status = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Vitals Remote keep awake" as CFString,
            &id
        )
        return status == kIOReturnSuccess ? id : nil
    }
}

enum SystemPower {
    enum Event {
        case sleep, restart, shutDown, logOut

        var code: AEEventID {
            switch self {
            case .sleep: return AEEventID(kAESleep)
            case .restart: return AEEventID(kAERestart)
            case .shutDown: return AEEventID(kAEShutDown)
            case .logOut: return AEEventID(kAEReallyLogOut)
            }
        }
    }

    static func send(_ event: Event) -> String? {
        var psn = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: UInt32(kSystemProcess))
        var target = AEAddressDesc()
        var status = OSStatus(AECreateDesc(DescType(typeProcessSerialNumber), &psn, MemoryLayout<ProcessSerialNumber>.size, &target))
        guard status == noErr else { return "Apple event target failed (\(status))" }
        defer { AEDisposeDesc(&target) }
        var appleEvent = AppleEvent()
        status = OSStatus(AECreateAppleEvent(
            AEEventClass(kCoreEventClass),
            event.code,
            &target,
            AEReturnID(kAutoGenerateReturnID),
            AETransactionID(kAnyTransactionID),
            &appleEvent
        ))
        guard status == noErr else { return "Apple event failed (\(status))" }
        defer { AEDisposeDesc(&appleEvent) }
        var reply = AppleEvent()
        defer { AEDisposeDesc(&reply) }
        status = AESendMessage(&appleEvent, &reply, AESendMode(kAENormalPriority), kAEDefaultTimeout)
        return status == noErr ? nil : "loginwindow refused (\(status))"
    }

    static func displaySleep() -> String? {
        run("/usr/bin/pmset", ["displaysleepnow"])
    }

    static func lock() -> String? {
        typealias LockFunction = @convention(c) () -> Void
        let path = "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login"
        if let handle = dlopen(path, RTLD_LAZY), let symbol = dlsym(handle, "SACLockScreenImmediate") {
            unsafeBitCast(symbol, to: LockFunction.self)()
            return nil
        }
        return displaySleep()
    }

    static func run(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? nil : "\(executable) exited \(process.terminationStatus)"
        } catch {
            return error.localizedDescription
        }
    }
}
