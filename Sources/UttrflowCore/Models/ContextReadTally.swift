// How often each rung of the read ladder answered, per application, counted without a word of the field.

/// Reads per application and rung since launch; the key is a bundle identifier and nothing here holds field text.
public struct ContextReadTally: Sendable, Equatable {
    /// Each application's reads, by the rung that answered them.
    public private(set) var counts: [String: [ContextReadRung: Int]] = [:]

    public init() {}

    /// Counts one read in `bundleIdentifier` that `rung` answered.
    public mutating func add(_ rung: ContextReadRung, in bundleIdentifier: String) {
        counts[bundleIdentifier, default: [:]][rung, default: 0] += 1
    }

    /// Every application's reads added together, by rung.
    public var totals: [ContextReadRung: Int] {
        counts.values.reduce(into: [:]) { totals, rungs in
            totals.merge(rungs, uniquingKeysWith: +)
        }
    }

    /// Each application with its counts, applications in name order.
    public var entries: [(bundleIdentifier: String, counts: String)] {
        counts.keys.sorted().map { ($0, Self.line(counts[$0] ?? [:])) }
    }

    /// `rungs` in ladder order, as `rangedValue 2, none 1`, leaving out rungs that never answered.
    public static func line(_ rungs: [ContextReadRung: Int]) -> String {
        ContextReadRung.allCases.compactMap { rung in
            rungs[rung].map { "\(rung.rawValue) \($0)" }
        }.joined(separator: ", ")
    }
}
