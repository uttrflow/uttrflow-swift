// The supported-hardware floor, decided in one place from values the caller reads or a test injects.
import Foundation

/// Whether this Mac meets the hardware the speech and suggestion paths are built for.
package enum HardwareFloor {
    /// What a Mac's hardware makes of the app.
    package enum Support: Sendable, Equatable {
        case supported
        /// Dictation works; the Mac is below the memory the budgets are written for.
        case slow(Reason)
        /// The app cannot run its models on this Mac.
        case unsupported(Reason)
    }

    /// The requirement a Mac misses.
    package enum Reason: Sendable, Equatable {
        case notAppleSilicon
        case memoryBelowMinimum
    }

    /// The memory of the smallest Mac the budgets are written for.
    package static let minimumMemoryBytes: Int64 = 8 * 1_073_741_824

    /// The floor for a Mac with these values; the chip is checked before the memory.
    package static func classify(isAppleSilicon: Bool, physicalMemory: Int64) -> Support {
        guard isAppleSilicon else { return .unsupported(.notAppleSilicon) }
        return physicalMemory < minimumMemoryBytes ? .slow(.memoryBelowMinimum) : .supported
    }

    /// The floor for this Mac, read from `hw.optional.arm64` and the physical memory.
    package static func current() -> Support {
        var arm64: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let read = sysctlbyname("hw.optional.arm64", &arm64, &size, nil, 0) == 0
        return classify(
            isAppleSilicon: read && arm64 == 1,
            physicalMemory: Int64(ProcessInfo.processInfo.physicalMemory))
    }
}
