/// What a completion is held to: which continuations count, how long the first may run, what it must never echo.
public struct CompletionExpectation: Sendable, Equatable {
    /// Continuations past the typed text that count as a hit; empty when any continuation counts.
    public let acceptable: [String]
    /// How long the first continuation may be, in characters, which is the register's verbosity made checkable.
    public let lengthBand: ClosedRange<Int>
    /// Text a completion must never contain, since what is on screen is never the line.
    public let forbidden: [String]

    /// The one acceptable entry that says no completion at all is the right answer.
    public static let nothing = "<none>"

    public init(acceptable: [String] = [], band: ClosedRange<Int>, forbidden: [String] = []) {
        self.acceptable = acceptable
        lengthBand = band
        self.forbidden = forbidden
    }

    /// Whether the right answer here is silence.
    public var expectsNothing: Bool { acceptable == [Self.nothing] }

    /// Whether any completion continues the typed text the way this expects.
    public func hits(_ completions: [String], typed: String) -> Bool {
        if expectsNothing { return completions.isEmpty }
        let continuations = completions.map { String($0.dropFirst(typed.count)).lowercased() }
        guard !acceptable.isEmpty else { return !continuations.isEmpty }
        return continuations.contains { got in acceptable.contains { got.hasPrefix($0.lowercased()) } }
    }

    /// Whether the first completion keeps to the register, or there is none where none is expected.
    public func conforms(_ completions: [String], typed: String) -> Bool {
        if expectsNothing { return completions.isEmpty }
        guard let first = completions.first else { return false }
        let continuation = String(first.dropFirst(typed.count))
        guard lengthBand.contains(continuation.count) else { return false }
        return !forbidden.contains { first.lowercased().contains($0.lowercased()) }
    }

    /// The continuations a cut of this line determines: its own rest and that of every sibling sharing the typed text.
    public static func acceptable(
        for line: String, typed: String, determinacy: Determinacy, among siblings: [String]
    ) -> [String] {
        switch determinacy {
        case .any:
            return []
        case .nothing:
            return [nothing]
        case .segment(let separators):
            // A cut ending on a separator has finished its piece, so the next one is nobody's to determine.
            guard let last = typed.last, !separators.contains(last) else { return [] }
            return rests(of: [line] + siblings, past: typed) { String($0.prefix { !separators.contains($0) }) }
        case .line:
            return rests(of: [line] + siblings, past: typed) { $0 }
        }
    }

    /// A band wide enough for lines like these: one character to twice the longest, never narrower than the floor.
    public static func band(fitting lines: [String], atLeast floor: Int = 20) -> ClosedRange<Int> {
        1...max(floor, 2 * (lines.map(\.count).max() ?? 0))
    }

    /// What each line sharing the typed text goes on with, cut down by the piece rule, once each and never empty.
    private static func rests(
        of lines: [String], past typed: String, piece: (String) -> String
    ) -> [String] {
        var seen: Set<String> = []
        return lines.compactMap { candidate in
            guard candidate.hasPrefix(typed) else { return nil }
            let rest = piece(String(candidate.dropFirst(typed.count)))
            guard !rest.isEmpty, seen.insert(rest.lowercased()).inserted else { return nil }
            return rest
        }
    }
}

/// What every line typed in one place shares: the band, the text never to echo, the other lines typed there.
public struct CutRegister: Sendable, Equatable {
    public let band: ClosedRange<Int>
    public let forbidden: [String]
    /// Other lines typed here, whose rests count too when they share a cut's typed text.
    public let siblings: [String]
    /// The fewest non-blank characters the generator answers, below which a cut is not a case.
    public let minimumTyped: Int

    public init(band: ClosedRange<Int>, forbidden: [String] = [], siblings: [String] = [], minimumTyped: Int = 2) {
        self.band = band
        self.forbidden = forbidden
        self.siblings = siblings
        self.minimumTyped = minimumTyped
    }
}

/// One cut of one line, named and held to an expectation, which a harness pairs with a situation.
public struct CompletionCase: Sendable, Equatable {
    /// The line's slug and the cut, as `slug/cutN` where N is how many characters are typed.
    public let name: String
    public let typed: String
    public let expectation: CompletionExpectation

    public init(name: String, typed: String, expectation: CompletionExpectation) {
        self.name = name
        self.typed = typed
        self.expectation = expectation
    }
}

/// One full line as the person means to type it, with where it is cut and how much each cut determines.
public struct CutLine: Sendable, Equatable {
    public let text: String
    public let slug: String
    public let cuts: [LineCut]
    public let determinacy: Determinacy

    public init(_ text: String, slug: String? = nil, cuts: [LineCut], determinacy: Determinacy) {
        self.text = text
        self.slug = slug ?? Self.slug(of: text)
        self.cuts = cuts
        self.determinacy = determinacy
    }

    /// The line's first few words as lowercase letters and digits joined by hyphens, or "line" when it has none.
    public static func slug(of text: String, words limit: Int = 3) -> String {
        let words = text.split(separator: " ").map { word in
            String(word.lowercased().filter { $0.isLetter || $0.isNumber })
        }
        let slug = words.filter { !$0.isEmpty }.prefix(limit).joined(separator: "-")
        return slug.isEmpty ? "line" : slug
    }

    /// Every distinct cut of the line that leaves enough typed to answer and something left to write.
    public func cases(in register: CutRegister) -> [CompletionCase] {
        var seen: Set<String> = []
        return cuts.compactMap { cut in
            guard let typed = cut.typed(of: text), seen.insert(typed).inserted else { return nil }
            if determinacy != .nothing {
                let core = typed.drop { $0 == " " }.reversed().drop { $0 == " " }
                guard core.count >= register.minimumTyped, typed.count < text.count else { return nil }
            }
            let acceptable = CompletionExpectation.acceptable(
                for: text, typed: typed, determinacy: determinacy, among: register.siblings)
            return CompletionCase(
                name: "\(slug)/cut\(typed.count)", typed: typed,
                expectation: CompletionExpectation(
                    acceptable: acceptable, band: register.band, forbidden: register.forbidden))
        }
    }
}

/// The "Name: message" lines a chat shows beside its field, read for what a reply must never repeat.
public enum ScreenThread {
    /// A speaker label runs no longer than this before its colon.
    public static let labelLength = 24

    /// The speaker labels, each as "Name:" and each once, in the order they first speak.
    public static func labels(in thread: String) -> [String] {
        var seen: Set<String> = []
        return messages(in: thread).compactMap { message in
            guard let label = message.label, seen.insert(label).inserted else { return nil }
            return label
        }
    }

    /// The opening of every message long enough that repeating it is recognisably an echo.
    public static func snippets(in thread: String, atLeast length: Int = 24) -> [String] {
        messages(in: thread).compactMap { message in
            message.body.count >= length ? String(message.body.prefix(length)) : nil
        }
    }

    /// Each non-blank line split at its first colon into who speaks and what they say.
    static func messages(in thread: String) -> [(label: String?, body: String)] {
        thread.split(whereSeparator: \.isNewline).compactMap { line in
            let text = String(line)
            guard text.contains(where: { !$0.isWhitespace }) else { return nil }
            guard let colon = text.firstIndex(of: ":"), text.distance(from: text.startIndex, to: colon) < labelLength
            else { return (nil, text) }
            let label = String(text[...colon])
            let body = text[text.index(after: colon)...].drop { $0 == " " }
            return (label, String(body))
        }
    }
}
