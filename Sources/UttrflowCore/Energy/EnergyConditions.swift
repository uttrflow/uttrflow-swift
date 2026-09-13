// What the Mac is asking of discretionary work: Low Power Mode and thermal pressure.

public import Foundation

/// How hot the Mac says it is running, in the system's four steps.
public enum ThermalPressure: Int, Sendable, Comparable, CaseIterable {
    case nominal
    case fair
    case serious
    case critical

    /// The system's reading in this type's terms, with anything newer treated as the worst.
    public init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .critical
        }
    }

    public static func < (lhs: ThermalPressure, rhs: ThermalPressure) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Whether the Mac wants less work done now, which work nobody is waiting for should honour. See `Docs/performance.md`.
public struct EnergyConditions: Sendable, Equatable {
    public var isLowPowerMode: Bool
    public var thermal: ThermalPressure

    public init(isLowPowerMode: Bool = false, thermal: ThermalPressure = .nominal) {
        self.isLowPowerMode = isLowPowerMode
        self.thermal = thermal
    }

    /// Whether work nobody asked for yet may start: not in Low Power Mode, and not at serious thermal pressure or worse.
    public var allowsDiscretionaryWork: Bool {
        !isLowPowerMode && thermal < .serious
    }

    /// What this process reads from the system right now; cheap enough to ask before each piece of work.
    public static func current(_ info: ProcessInfo = .processInfo) -> EnergyConditions {
        EnergyConditions(
            isLowPowerMode: info.isLowPowerModeEnabled, thermal: ThermalPressure(info.thermalState))
    }
}
