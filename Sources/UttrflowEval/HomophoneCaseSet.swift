// Homophone repair cases generated from carrier sentences, each tagged by what in the sentence decides the spelling.

/// What in a carrier sentence tells the meant spelling from the one that sounds the same.
public enum HomophoneDecider: String, Sendable, CaseIterable {
    /// The grammar around the slot: "their car", "going to go".
    case role
    /// The meaning of the other words: "meet at noon", "a cup of flour".
    case sense
    /// The app or field the text is written in: "clear the cache" in a terminal.
    case domain
    /// Nothing in the sentence decides; a repair here can only be a guess, so these cases count harm.
    case none
}

/// One invented sentence that means `spelling` at the slot `_`.
public struct HomophoneCarrier: Sendable, Equatable {
    /// The spelling the sentence means.
    public let spelling: String
    /// What decides it.
    public let decider: HomophoneDecider
    /// The sentence, holding `_` once where the spelling goes.
    public let template: String

    /// A carrier for one spelling.
    public init(_ spelling: String, _ decider: HomophoneDecider, _ template: String) {
        self.spelling = spelling
        self.decider = decider
        self.template = template
    }

    /// The template with `word` at the slot.
    public func filled(with word: String) -> String {
        template.replacingOccurrences(of: "_", with: word)
    }
}

/// One repair case: the recogniser wrote `input`, and `expected` is what was meant.
public struct HomophoneCase: Sendable, Equatable {
    /// The sentence with the wrong member of the class at the slot.
    public let input: String
    /// The sentence with the meant member.
    public let expected: String
    /// The meant spelling.
    public let meant: String
    /// The spelling the recogniser wrote instead.
    public let heard: String
    /// What in the sentence decides between them.
    public let decider: HomophoneDecider
}

/// Builds every repair case from the classes and carriers, so a new class or carrier needs no case written by hand.
public enum HomophoneCaseSet {
    /// Every case: for each carrier, one per other member of its spelling's class.
    public static func cases(
        classes: [[String]], carriers: [HomophoneCarrier] = HomophoneCarriers.all
    ) -> [HomophoneCase] {
        carriers.flatMap { carrier -> [HomophoneCase] in
            guard let members = classes.first(where: { $0.contains(carrier.spelling) }) else { return [] }
            return members.filter { $0 != carrier.spelling }.map { heard in
                HomophoneCase(
                    input: carrier.filled(with: heard), expected: carrier.filled(with: carrier.spelling),
                    meant: carrier.spelling, heard: heard, decider: carrier.decider)
            }
        }
    }
}
