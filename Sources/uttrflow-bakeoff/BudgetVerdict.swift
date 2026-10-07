import ArgumentParser
import Foundation
import UttrflowEval

/// Prints how a run's memory and disk readings sit against the budget, and fails the command when any is over. See `Docs/performance.md`.
enum BudgetVerdict {
    static func enforce(_ readings: [BudgetReading], disk: [DiskReading] = []) throws {
        let breaches = ResourceBudget.breaches(in: readings)
        let diskBreaches = ResourceBudget.breaches(in: disk)
        let highest = Dictionary(grouping: readings, by: \.state).compactMapValues {
            $0.max { $0.footprintBytes < $1.footprintBytes }
        }
        print("\nMemory budget")
        for state in BudgetedState.allCases {
            guard let reading = highest[state] else { continue }
            let mark = reading.isOverBudget ? "✗" : "✓"
            print(
                "  \(mark) \(state.rawValue): highest \(reading.footprintBytes / 1_048_576) MB of \(state.limitInMegabytes) MB"
            )
        }
        if !disk.isEmpty { print("\nDisk budget") }
        for reading in disk {
            let mark = reading.isOverBudget ? "✗" : "✓"
            print(
                "  \(mark) \(reading.part.rawValue): \(reading.bytes / 1_048_576) MB of \(reading.part.limitInMegabytes) MB"
            )
        }
        guard !breaches.isEmpty || !diskBreaches.isEmpty else { return }
        for breach in breaches.map(\.description) + diskBreaches.map(\.description) {
            FileHandle.standardError.write(Data("  ✗ \(breach)\n".utf8))
        }
        throw ExitCode.failure
    }
}
