/// A named bundle of the existing clean-up choices: data only, which can switch steps off or pick among existing policies.
public struct QualityPreset: Sendable, Equatable, Identifiable {
    /// Which preset this is, the only part of it that is ever stored.
    public enum ID: String, Sendable, Equatable, Codable, CaseIterable {
        case standard
        case verbatim
        case code
    }

    public let id: ID
    /// What a picker calls the preset.
    public let name: String
    /// One line saying what the preset leaves in the text.
    public let detail: String
    /// The steps this preset switches off, on top of whatever the user switched off.
    public let switchedOff: Set<PassID>
    public let firstWord: FirstWordPolicy?
    public let numbers: NumberPolicy?
    public let layout: LayoutPolicy?
    public let terminalStop: TerminalStopPolicy?

    init(
        id: ID, name: String, detail: String, switchedOff: Set<PassID> = [],
        firstWord: FirstWordPolicy? = nil, numbers: NumberPolicy? = nil, layout: LayoutPolicy? = nil,
        terminalStop: TerminalStopPolicy? = nil
    ) {
        self.id = id
        self.name = name
        self.detail = detail
        self.switchedOff = switchedOff.intersection(CleaningSteps.offeredIDs)
        self.firstWord = firstWord
        self.numbers = numbers
        self.layout = layout
        self.terminalStop = terminalStop
    }

    /// Everything as the place wants it, which is what a user gets before they choose.
    public static let standard = QualityPreset(
        id: .standard, name: "Standard",
        detail: "Tidies the text for the place it lands in.")

    /// Every spoken word kept, fillers and repeats included, for transcripts and speech differences.
    public static let verbatim = QualityPreset(
        id: .verbatim, name: "Verbatim",
        detail: "Keeps every word as spoken, fillers, repeats and restarts included.",
        switchedOff: [.fillers, .repeatedPhrase, .stammers, .selfCorrection])

    /// Numerals, the first word as spoken, no added stop and line breaks kept, as code wants.
    public static let code = QualityPreset(
        id: .code, name: "Code",
        detail: "Writes numerals, keeps line breaks and adds no capital or full stop.",
        firstWord: .asSpoken, numbers: .always, layout: .preserveNewlines, terminalStop: .never)

    /// Every preset, in the order a picker shows them.
    public static let offered: [QualityPreset] = [.standard, .verbatim, .code]

    /// The preset with this identifier.
    public static func preset(_ id: ID) -> QualityPreset {
        offered.first { $0.id == id } ?? .standard
    }

    /// The user's steps with this preset's steps also off; a preset never switches a step back on.
    public func applied(to steps: CleaningSteps) -> CleaningSteps {
        CleaningSteps(switchedOff: steps.switchedOff.union(switchedOff))
    }

    /// The place's formatter with this preset's policies chosen in its stead, every other field untouched.
    public func applied(to formatter: DestinationFormatter) -> DestinationFormatter {
        DestinationFormatter(
            destination: formatter.destination, firstWord: firstWord ?? formatter.firstWord,
            terminalStop: terminalStop ?? formatter.terminalStop, layout: layout ?? formatter.layout,
            grammar: formatter.grammar, numbers: numbers ?? formatter.numbers, digits: formatter.digits,
            promptBlock: formatter.promptBlock, consequence: formatter.consequence)
    }
}

extension QualityPreset.ID {
    /// Reads an identifier this build does not know as the standard preset rather than failing the settings around it.
    public init(from decoder: any Decoder) throws {
        let raw = try? decoder.singleValueContainer().decode(String.self)
        self = raw.flatMap(Self.init(rawValue:)) ?? .standard
    }
}
