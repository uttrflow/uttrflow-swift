// Repair and harm rates of one clean-up engine over the generated homophone cases, per decider tag.
import Foundation

/// What one engine wrote for one case: once given the wrong spelling, once given the meant one.
public struct HomophoneOutcome: Sendable, Equatable {
    /// The case the engine was run on.
    public let homophoneCase: HomophoneCase
    /// The engine's output for `homophoneCase.input`.
    public let fromInput: String
    /// The engine's output for `homophoneCase.expected`.
    public let fromExpected: String

    /// One case's two outputs.
    public init(_ homophoneCase: HomophoneCase, fromInput: String, fromExpected: String) {
        self.homophoneCase = homophoneCase
        self.fromInput = fromInput
        self.fromExpected = fromExpected
    }

    /// The engine wrote the meant spelling at the slot when given the wrong one.
    public var repaired: Bool { HomophoneRepairRates.holdsMeant(fromInput, homophoneCase) }

    /// The engine moved the meant spelling away from the slot when it was already right.
    public var harmed: Bool { !HomophoneRepairRates.holdsMeant(fromExpected, homophoneCase) }
}

/// One decider tag's rates for one engine.
public struct HomophoneRepairRow: Sendable, Equatable {
    /// The tag.
    public let decider: HomophoneDecider
    /// Cases carrying the tag.
    public let cases: Int
    /// Cases whose wrong spelling the engine replaced with the meant one.
    public let repaired: Int
    /// Cases whose meant spelling the engine changed.
    public let harmed: Int

    /// `repaired` over `cases`; zero when there are none.
    public var repairRate: Double { cases == 0 ? 0 : Double(repaired) / Double(cases) }
    /// `harmed` over `cases`; zero when there are none.
    public var harmRate: Double { cases == 0 ? 0 : Double(harmed) / Double(cases) }
}

/// Scores engine outputs against `HomophoneCaseSet` cases by the word at the slot.
public enum HomophoneRepairRates {
    /// One row per decider tag, in `HomophoneDecider.allCases` order, tags without cases included.
    public static func rows(_ outcomes: [HomophoneOutcome]) -> [HomophoneRepairRow] {
        HomophoneDecider.allCases.map { decider in
            let tagged = outcomes.filter { $0.homophoneCase.decider == decider }
            return HomophoneRepairRow(
                decider: decider, cases: tagged.count, repaired: tagged.filter(\.repaired).count,
                harmed: tagged.filter(\.harmed).count)
        }
    }

    /// Whether `output` holds the meant spelling where the case's slot is.
    ///
    /// Words are compared without case or edge punctuation, so a capital or a full stop added by the engine
    /// is not counted against it. When the engine changed the word count the slot cannot be located, and the
    /// whole sentence must then equal the expected one.
    public static func holdsMeant(_ output: String, _ homophoneCase: HomophoneCase) -> Bool {
        let written = words(output)
        let expected = words(homophoneCase.expected)
        guard written.count == expected.count else { return written == expected }
        let heard = words(homophoneCase.input)
        guard let slot = expected.indices.first(where: { expected[$0] != heard[$0] }) else { return false }
        return written[slot] == expected[slot]
    }

    /// Lowercased words with punctuation trimmed from each edge; an inner apostrophe is kept.
    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map { token in
            String(token.lowercased().replacingOccurrences(of: "\u{2019}", with: "'"))
                .trimmingCharacters(in: .punctuationCharacters)
        }.filter { !$0.isEmpty }
    }
}
