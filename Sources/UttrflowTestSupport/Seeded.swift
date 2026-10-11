// The one seeded generator every randomised test draws from, and the seed policy that replays a failure.
import Foundation
import UttrflowCore

/// A fixed-seed generator, so every generated case is the same on every run and a failure names its seed.
public struct Seeded: RandomNumberGenerator, CustomStringConvertible {
    /// The environment variable that replaces a test's fixed seeds with the one seed to replay.
    public static let seedVariable = "UTTRFLOW_SEED"

    /// The seed this generator started from, so a failure message can name it.
    public let seed: Int

    /// The sequence itself, which the seed alone sets.
    private var generator: SeededGenerator

    /// A generator that always produces the same sequence for the same seed.
    public init(seed: Int) {
        self.seed = seed
        generator = SeededGenerator(seed: UInt64(truncatingIfNeeded: seed))
    }

    /// `seed=<n>`, the form a failure message prints and `UTTRFLOW_SEED` takes back.
    public var description: String { "seed=\(seed)" }

    /// The next value in the sequence.
    public mutating func next() -> UInt64 {
        generator.next()
    }

    /// One of the values, chosen uniformly.
    public mutating func pick<Value>(_ values: [Value]) -> Value {
        values[Int.random(in: 0..<values.count, using: &self)]
    }

    /// Whether an event with this probability happens this time.
    public mutating func chance(_ probability: Double) -> Bool {
        Double.random(in: 0..<1, using: &self) < probability
    }

    /// The seeds a property test runs: its fixed ones, or only the seed `UTTRFLOW_SEED` names.
    public static func seeds(
        _ fixed: some Sequence<Int>, environment: [String: String]? = nil
    ) -> [Int] {
        let environment = environment ?? ProcessInfo.processInfo.environment
        guard let replay = environment[seedVariable].flatMap({ Int($0) }) else { return Array(fixed) }
        return [replay]
    }
}
