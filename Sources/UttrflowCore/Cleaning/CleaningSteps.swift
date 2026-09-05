/// One clean-up step the user can see and switch off, in the words a screen shows it in.
public struct CleaningStep: Sendable, Equatable, Identifiable {
    public let id: PassID
    /// What the step is called, in plain English and never after what implements it.
    public let name: String
    /// One line saying what switching it off would leave in the text.
    public let detail: String

    public init(id: PassID, name: String, detail: String) {
        self.id = id
        self.name = name
        self.detail = detail
    }
}

/// Which clean-up steps run, stored as the set that is off so a later build's step is on. See `Docs/cleanup.md`.
public struct CleaningSteps: Sendable, Equatable, Codable {
    /// The steps the user has switched off; every step not named here runs.
    public let switchedOff: Set<PassID>

    public init(switchedOff: Set<PassID> = []) {
        self.switchedOff = switchedOff.intersection(Self.offeredIDs)
    }

    /// Everything on, which is what a user gets before they touch this.
    public static let `default` = CleaningSteps()

    /// Whether a step runs; a step nobody may switch off always does.
    public func runs(_ step: PassID) -> Bool { !switchedOff.contains(step) }

    /// The same choices with one step switched on or off.
    public func setting(_ step: PassID, isOn: Bool) -> CleaningSteps {
        isOn
            ? CleaningSteps(switchedOff: switchedOff.subtracting([step]))
            : CleaningSteps(switchedOff: switchedOff.union([step]))
    }

    /// Whether a step is the user's to switch off at all.
    public static func isOffered(_ step: PassID) -> Bool { offeredIDs.contains(step) }

    /// The steps the user may switch off, in the order they run.
    public static let offered: [CleaningStep] = [
        CleaningStep(
            id: .fillers, name: "Filler words",
            detail: "Takes out um, uh, hmm and the rest of what was never meant as words."),
        CleaningStep(
            id: .stammers, name: "Stammers",
            detail: "Takes out a short word said twice in a row."),
        CleaningStep(
            id: .repeatedPhrase, name: "Repeated phrases",
            detail: "Takes out a few words said twice in a row."),
        CleaningStep(
            id: .selfCorrection, name: "Self-corrections",
            detail: "Takes out the half you took back before \"no, sorry\" or \"I mean\"."),
        CleaningStep(
            id: .spokenPunctuation, name: "Spoken punctuation",
            detail: "Turns \"comma\" and \"full stop\" into the marks themselves."),
        CleaningStep(
            id: .layoutWords, name: "Layout words",
            detail: "Turns \"new line\" and \"bullet point\" into layout."),
        CleaningStep(
            id: .numberForms, name: "Numbers",
            detail: "Writes spoken numbers, times and ports as numerals."),
        CleaningStep(
            id: .spacing, name: "Spacing",
            detail: "Puts one space after a mark and none before it."),
    ]

    /// The step a page shows under this name, or nothing when nothing offers it.
    public static func step(_ id: PassID) -> CleaningStep? { offered.first { $0.id == id } }

    /// What a page calls a step, falling back to the identifier for one it does not offer.
    public static func name(of id: PassID) -> String { step(id)?.name ?? id.rawValue }

    static let offeredIDs = Set(offered.map(\.id))
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
                ?? [])
    }
}
