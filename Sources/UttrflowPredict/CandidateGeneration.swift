/// Where the caret is, read live from the field so the model, not a hardcoded list, infers the dialect.
public struct GenerationSituation: Sendable, Equatable {
    /// The application as the user knows it, e.g. "Terminal", "DBeaver", "Safari".
    public let application: String
    /// What the field calls itself, when it says anything: a role, a placeholder, a description.
    public let field: String?
    /// The page or directory the field belongs to: a web host, a working directory.
    public let document: String?
    /// The text before the caret's line, which is what the line continues from: the command before, the sentence before.
    public let preceding: String?
    /// The window's title, which names the recipient, the page or the directory more often than not.
    public let windowTitle: String?
    /// The visible text around the field, nearest the field last: the thread being answered, the form being filled.
    public let surroundings: String?
    /// The lines this person most recently entered in this field, newest first, which is how they write here.
    public let recentLines: [String]
    /// Whether the field holds many lines, which is where paragraphs are written rather than commands or searches.
    public let isMultiline: Bool
    /// The whole words the next word must be one of, as the machine lists them; empty when the word may be anything.
    public let choices: [String]

    public init(
        application: String, field: String? = nil, document: String? = nil, preceding: String? = nil,
        windowTitle: String? = nil, surroundings: String? = nil, recentLines: [String] = [],
        isMultiline: Bool = false, choices: [String] = []
    ) {
        self.application = application
        self.field = field
        self.document = document
        self.preceding = preceding
        self.windowTitle = windowTitle
        self.surroundings = surroundings
        self.recentLines = recentLines
        self.isMultiline = isMultiline
        self.choices = choices
    }

    /// The same moment with the next word held to these choices.
    public func choosing(_ choices: [String]) -> GenerationSituation {
        GenerationSituation(
            application: application, field: field, document: document, preceding: preceding,
            windowTitle: windowTitle, surroundings: surroundings, recentLines: recentLines,
            isMultiline: isMultiline, choices: choices)
    }
}

/// Invents a continuation when the corpus has none, which is the one thing memory cannot do.
public protocol CandidateGenerating: Sendable {
    /// Whether the model can answer at once, since a keystroke may never wait on one still loading.
    var isReady: Bool { get async }

    /// The most likely continuation of the typed text, alone, since one line is what the person waits for; throws when the pass itself failed, which is not the same as having nothing to offer.
    func completions(for typed: String, in situation: GenerationSituation) async throws -> [String]

    /// Other ways to finish the line, different from the one already offered, fetched once that one is on screen.
    func alternatives(
        for typed: String, in situation: GenerationSituation, excluding leader: String
    ) async throws
        -> [String]
}

extension CandidateGenerating {
    /// A generator that offers one line only has no alternatives, which the list then simply never opens on.
    public func alternatives(
        for typed: String, in situation: GenerationSituation, excluding leader: String
    ) async throws
        -> [String]
    {
        []
    }
}

/// One pass as a generator wrote it, beside what the parser made of it, so a bake-off can read why a miss was a miss.
public struct GenerationPass: Sendable {
    /// Every word the generator produced, unparsed.
    public let text: String
    /// Why the pass ended, in the generator's own terms.
    public let stopReason: String
    /// What `completions(for:in:)` would have answered from the same pass.
    public let completions: [String]

    public init(text: String, stopReason: String, completions: [String]) {
        self.text = text
        self.stopReason = stopReason
        self.completions = completions
    }
}

/// A generator that can show one pass raw, which is how a measurement reads a miss.
public protocol PassShowing: CandidateGenerating {
    /// The one-line pass for `typed`, raw and parsed together; nothing when the line is too short to ask about.
    func pass(for typed: String, in situation: GenerationSituation) async throws -> GenerationPass?
}
