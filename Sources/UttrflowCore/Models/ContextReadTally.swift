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

    /// Each application's counts as one line, in bundle identifier order.
    public var entries: [(bundleIdentifier: String, counts: String)] {
        counts.keys.sorted().map { ($0, Self.listed(counts[$0] ?? [:])) }
    }

    /// Every application's reads added together, so a report can carry the rungs without naming an app.
    public var allApplications: String {
        Self.listed(counts.values.reduce(into: [:]) { sum, rungs in sum.merge(rungs, uniquingKeysWith: +) })
    }

    private static func listed(_ rungs: [ContextReadRung: Int]) -> String {
        ContextReadRung.allCases.compactMap { rung in rungs[rung].map { "\(rung.rawValue) \($0)" } }
            .joined(separator: ", ")
    }
}
