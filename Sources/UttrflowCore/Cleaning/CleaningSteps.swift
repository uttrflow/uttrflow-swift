/// One clean-up step the user can see and switch off, in the words a screen shows it in.
public struct CleaningStep: Sendable, Equatable, Identifiable {
    public let id: PassID
    /// What the step is called, in plain English and never after what implements it.
    public let name: String
    /// One line saying what switching it off would leave in the text.
    public let detail: String
    /// An invented spoken sentence that this step changes, which a settings preview cleans with it on and off.
    public let example: String
    /// Whether the step runs before the user touches it; one that does not waits to be switched on.
    public let isOnByDefault: Bool

    public init(id: PassID, name: String, detail: String, example: String, isOnByDefault: Bool = true) {
        self.id = id
        self.name = name
        self.detail = detail
        self.example = example
        self.isOnByDefault = isOnByDefault
    }
}

/// Which clean-up steps run, stored as the set that is off so a later build's step is on. See `Docs/cleanup.md`.
public struct CleaningSteps: Sendable, Equatable, Codable {
    /// The steps on by default that the user has switched off; every other such step runs.
    public let switchedOff: Set<PassID>
    /// The steps off by default that the user has switched on; every other such step stays off.
    public let switchedOn: Set<PassID>

    public init(switchedOff: Set<PassID> = [], switchedOn: Set<PassID> = []) {
        self.switchedOff = switchedOff.intersection(Self.offeredIDs).subtracting(Self.optInIDs)
        self.switchedOn = switchedOn.intersection(Self.optInIDs)
    }

    /// Every step at its default, which is what a user gets before they touch this.
    public static let `default` = CleaningSteps()

    /// Whether a step runs; a step nobody may switch off always does.
    public func runs(_ step: PassID) -> Bool {
        Self.optInIDs.contains(step) ? switchedOn.contains(step) : !switchedOff.contains(step)
    }

    /// The same choices with one step switched on or off.
    public func setting(_ step: PassID, isOn: Bool) -> CleaningSteps {
        isOn
            ? CleaningSteps(
                switchedOff: switchedOff.subtracting([step]), switchedOn: switchedOn.union([step]))
            : CleaningSteps(
                switchedOff: switchedOff.union([step]), switchedOn: switchedOn.subtracting([step]))
    }

    /// Whether a step is the user's to switch off at all.
    public static func isOffered(_ step: PassID) -> Bool { offeredIDs.contains(step) }

    /// The steps the user may switch off, in the order they run.
    public static let offered: [CleaningStep] = [
        CleaningStep(
            id: .fillers, name: "Filler words",
            detail: "Takes out um, uh, hmm and the rest of what was never meant as words.",
            example: "um we ship on friday"),
        CleaningStep(
            id: .repeatedPhrase, name: "Repeated phrases",
            detail: "Takes out repeated words and a few incomplete starts the speaker restarts.",
            example: "we should we should leave at noon"),
        CleaningStep(
            id: .stammers, name: "Stammers",
            detail: "Takes out a short word said twice in a row.",
            example: "I I think it works"),
        CleaningStep(
            id: .selfCorrection, name: "Self-corrections",
            detail: "Takes out the half you took back before \"no, sorry\" or \"I mean\".",
            example: "send it on monday no sorry tuesday"),
        CleaningStep(
            id: .spokenPunctuation, name: "Spoken punctuation",
            detail: "Turns \"comma\" and \"full stop\" into the marks themselves.",
            example: "yes comma that works full stop"),
        CleaningStep(
            id: .spokenEmoji, name: "Emoji by name",
            detail: "Turns \"thumbs up emoji\" into the emoji, except in code and terminals.",
            example: "great work thumbs up emoji", isOnByDefault: false),
        CleaningStep(
            id: .layoutWords, name: "Layout words",
            detail: "Turns \"new line\" and \"bullet point\" into layout.",
            example: "buy milk new line buy bread"),
        CleaningStep(
            id: .numberForms, name: "Numbers",
            detail: "Writes spoken numbers, times and ports as numerals.",
            example: "the meeting has twenty five people"),
        CleaningStep(
            id: .contractions, name: "Contractions",
            detail: "Puts the apostrophe back into dont, cant and their kind.",
            example: "I dont think so"),
        CleaningStep(
            id: .spacing, name: "Spacing",
            detail: "Puts one space after a mark and none before it.",
            example: "yes , that works"),
    ]

    /// The step a page shows under this name, or nothing when nothing offers it.
    public static func step(_ id: PassID) -> CleaningStep? { offered.first { $0.id == id } }

    /// What a page calls a step, falling back to the identifier for one it does not offer.
    public static func name(of id: PassID) -> String { step(id)?.name ?? id.rawValue }

    static let offeredIDs = Set(offered.map(\.id))
    /// The steps that stay off until the user switches them on.
    static let optInIDs = Set(offered.filter { !$0.isOnByDefault }.map(\.id))
    /// The steps that run until the user switches them off, which are the ones a record calls off.
    static let optOut = offered.filter(\.isOnByDefault)
}

extension CleaningSteps {
    /// Normalises what it reads, so a stored step this build does not offer cannot arrive switched off.
    public init(from decoder: any Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            self.init()
            return
        }
        self.init(
            switchedOff: (try? container.decodeIfPresent(Set<PassID>.self, forKey: .switchedOff))
                ?? [],
            switchedOn: (try? container.decodeIfPresent(Set<PassID>.self, forKey: .switchedOn)) ?? [])
    }
}
