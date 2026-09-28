import Foundation
import IOKit.hidsystem
import PrivateSensors

/// Reads the named temperature sensors that Apple Silicon exposes through
/// the HID event system (CPU cores, GPU, NAND, battery, ...).
final class HIDSensors {
    struct Reading {
        let name: String
        let celsius: Double
    }

    private let client: IOHIDEventSystemClient?

    init() {
        guard let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault) else {
            // The whole temperature subsystem is unavailable — explains an empty
            // Temperatures section in a support report. One-time at startup.
            Log.noticeOnce(.sensors, key: "hid-client-create", "couldn't create the HID event-system client — no temperature sensors will be read")
            self.client = nil
            return
        }
        let match: [String: Int] = [
            "PrimaryUsagePage": Int(VITALS_HID_USAGE_PAGE_APPLE_VENDOR),
            "PrimaryUsage": Int(VITALS_HID_USAGE_TEMPERATURE_SENSOR),
        ]
        IOHIDEventSystemClientSetMatching(client, match as CFDictionary)
        self.client = client
    }

    /// The temperature services and their names never change at runtime, and
    /// copying them costs an IPC round-trip per sensor, so they're cached and
    /// only re-listed every few minutes (or when the list comes back empty).
    private var sensors: [(service: IOHIDServiceClient, name: String)] = []
    private var listedAt = Date.distantPast
    private static let relistInterval: TimeInterval = 300

    func readAll() -> [Reading] {
        if sensors.isEmpty || Date().timeIntervalSince(listedAt) >= Self.relistInterval { relist() }
        let temperatureField = Int32(VITALS_HID_EVENT_TEMPERATURE << 16)
        return sensors.compactMap { sensor in
            guard let event = IOHIDServiceClientCopyEvent(sensor.service, Int64(VITALS_HID_EVENT_TEMPERATURE), 0, 0)
            else { return nil }
            let value = IOHIDEventGetFloatValue(event, temperatureField)
            // Discard sensors that report nonsense (unpowered or reserved slots).
            guard value > 0, value < 128 else { return nil }
            return Reading(name: sensor.name, celsius: value)
        }
    }

    private func relist() {
        listedAt = Date()
        guard let client,
              let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient]
        else { sensors = []; return }
        sensors = services.compactMap { service in
            guard IOHIDServiceClientConformsTo(
                service,
                UInt32(VITALS_HID_USAGE_PAGE_APPLE_VENDOR),
                UInt32(VITALS_HID_USAGE_TEMPERATURE_SENSOR)
            ) != 0,
                let name = IOHIDServiceClientCopyProperty(service, "Product" as CFString) as? String
            else { return nil }
            return (service, name)
        }
    }
}
