import Testing
@testable import Vitals

/// `VitalsModel.classify` turns raw HID sensor names into the labeled,
/// categorized sensors the whole UI is built on.
@MainActor
struct ClassificationTests {
    private func classify(_ names: [String]) -> [VitalsModel.Sensor] {
        VitalsModel.classify(names.map { HIDSensors.Reading(name: $0, celsius: 40) })
    }

    @Test func dieSensorsMapToBankLabels() {
        let sensors = classify(["PMU tdie1", "PMU2 tdie3"])
        #expect(sensors[0].label == "A1")
        #expect(sensors[0].kind == .cpu)
        #expect(sensors[1].label == "B3")
        #expect(sensors[1].kind == .cpu)
    }

    @Test func performanceAndEfficiencyClusters() {
        let sensors = classify(["pACC MTR Temp Sensor4", "eACC MTR Temp Sensor1"])
        #expect(sensors[0].label == "P4")
        #expect(sensors[1].label == "E1")
        #expect(sensors.allSatisfy { $0.kind == .cpu })
    }

    @Test func kindsAreDetectedFromNames() {
        let sensors = classify(["NAND CH0 temp", "gas gauge battery", "GPU MTR Temp Sensor1", "PMU tcal"])
        #expect(sensors[0].kind == .storage)
        #expect(sensors[0].label == "SSD")
        #expect(sensors[1].kind == .battery)
        #expect(sensors[1].label == "Battery")
        #expect(sensors[2].kind == .gpu)
        #expect(sensors[2].label == "GPU 1")
        #expect(sensors[3].kind == .other)
    }

    @Test func duplicateLabelsAreDisambiguated() {
        let sensors = classify(["NAND CH0 temp", "NAND CH0 temp"])
        #expect(sensors[0].label == "SSD")
        #expect(sensors[1].label == "SSD (2)")
        // ids must differ too, or SwiftUI ForEach breaks
        #expect(sensors[0].id != sensors[1].id)
    }
}
