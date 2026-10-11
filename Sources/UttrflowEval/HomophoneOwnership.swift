// AC.21's decision: which one stage may change each homophone class, read from what decides the class's carriers.

/// The one stage that may change a homophone class; the guard judges every swap and owns none.
enum HomophoneOwner: String, Sendable, CaseIterable {
    /// The on-device model chooses from the offered reading, because grammar or meaning around the slot decides it.
    case model
    /// The personal dictionary or the screen offers the reading, because only the app or field decides it.
    case place
    /// Nothing in a sentence decides, so the word stays as heard.
    case none
}

/// Assigns every class in the carriers exactly one owner, from the carriers' decider tags.
enum HomophoneOwnership {
    /// The owner of the class holding `spelling`: the model for role or sense, the place for domain only, else none.
    static func owner(of spelling: String) -> HomophoneOwner? {
        guard let members = classOf(spelling) else { return nil }
        let deciders = Set(
            (HomophoneCarriers.all + HomophoneCarriers.lexicon)
                .filter { members.contains($0.spelling) }.map(\.decider))
        if deciders.contains(.role) || deciders.contains(.sense) { return .model }
        return deciders.contains(.domain) ? .place : HomophoneOwner.none
    }

    /// Every class with carriers, in order, with its owner.
    static var table: [(members: [String], owner: HomophoneOwner)] {
        (HomophoneCarriers.classes + HomophoneLexiconClasses.all).compactMap { members in
            owner(of: members[0]).map { (members, $0) }
        }
    }

    private static func classOf(_ spelling: String) -> [String]? {
        HomophoneCarriers.group(containing: spelling)
            ?? HomophoneLexiconClasses.all.first { $0.contains(spelling.lowercased()) }
    }
}
