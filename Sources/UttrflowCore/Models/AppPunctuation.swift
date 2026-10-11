/// Whether the last sentence of a dictation ends in a full stop in one app.
enum FinalStopChoice: String, Sendable, Equatable, Codable, CaseIterable {
    /// The destination's own policy decides.
    case auto
    case never
    case always
}

/// Whether the first word of a dictation is capitalised in one app.
enum FirstLetterChoice: String, Sendable, Equatable, Codable, CaseIterable {
    /// The destination's own policy decides.
    case auto
    /// The first word keeps its spoken case.
    case never
}

/// The layout the user fixed for one app, independent of the kind of place the app is; it never alters a word.
struct AppPunctuation: Sendable, Equatable, Codable {
    let finalStop: FinalStopChoice
    let firstLetter: FirstLetterChoice

    init(finalStop: FinalStopChoice = .auto, firstLetter: FirstLetterChoice = .auto) {
        self.finalStop = finalStop
        self.firstLetter = firstLetter
    }

    /// Nothing is fixed, which is what every app starts with.
    static let automatic = AppPunctuation()

    var isAutomatic: Bool { self == .automatic }

    /// Reads a choice this build has no word for as `auto`, so one bad entry costs only itself.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        finalStop =
            ((try? container.decodeIfPresent(FinalStopChoice.self, forKey: .finalStop)) ?? nil) ?? .auto
        firstLetter =
            ((try? container.decodeIfPresent(FirstLetterChoice.self, forKey: .firstLetter)) ?? nil) ?? .auto
    }

    private enum CodingKeys: String, CodingKey { case finalStop, firstLetter }

    /// The formatter with the final stop and first letter this app fixed, every other field untouched.
    func applied(to formatter: DestinationFormatter) -> DestinationFormatter {
        guard !isAutomatic else { return formatter }
        let stop: TerminalStopPolicy
        switch finalStop {
        case .auto: stop = formatter.terminalStop
        case .never: stop = .never
        case .always: stop = .always
        }
        return DestinationFormatter(
            destination: formatter.destination,
            firstWord: firstLetter == .never ? .asSpoken : formatter.firstWord, terminalStop: stop,
            layout: formatter.layout, grammar: formatter.grammar, numbers: formatter.numbers,
            digits: formatter.digits, promptBlock: formatter.promptBlock,
            consequence: formatter.consequence)
    }
}
