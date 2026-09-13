// Tests for when discretionary work may start.

import Foundation
import Testing

@testable import UttrflowCore

@Suite("What the Mac allows discretionary work")
struct EnergyConditionsTests {
    @Test("allows it on a cool Mac that is not in Low Power Mode")
    func coolAndPlugged() {
        #expect(EnergyConditions().allowsDiscretionaryWork)
        #expect(EnergyConditions(thermal: .fair).allowsDiscretionaryWork)
    }

    @Test("refuses it in Low Power Mode, however cool")
    func lowPowerMode() {
        #expect(!EnergyConditions(isLowPowerMode: true).allowsDiscretionaryWork)
    }

    @Test(
        "refuses it at serious thermal pressure and worse",
        arguments: [ThermalPressure.serious, .critical])
    func thermalPressure(_ pressure: ThermalPressure) {
        #expect(!EnergyConditions(thermal: pressure).allowsDiscretionaryWork)
    }

    @Test("reads the system's four thermal states in order")
    func mapsTheSystemStates() {
        #expect(ThermalPressure(.nominal) == .nominal)
        #expect(ThermalPressure(.fair) == .fair)
        #expect(ThermalPressure(.serious) == .serious)
        #expect(ThermalPressure(.critical) == .critical)
        #expect(ThermalPressure.allCases.sorted() == [.nominal, .fair, .serious, .critical])
    }

    @Test("reads this process's own conditions from the system")
    func readsTheSystem() {
        let info = ProcessInfo.processInfo
        let current = EnergyConditions.current(info)

        #expect(current.isLowPowerMode == info.isLowPowerModeEnabled)
        #expect(current.thermal == ThermalPressure(info.thermalState))
    }
}
