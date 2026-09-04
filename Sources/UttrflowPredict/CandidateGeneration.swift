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

    public init(
        application: String, field: String? = nil, document: String? = nil, preceding: String? = nil,
        windowTitle: String? = nil, surroundings: String? = nil, recentLines: [String] = []
    ) {
        self.application = application
        self.field = field
        self.document = document
        self.preceding = preceding
        self.windowTitle = windowTitle
        self.surroundings = surroundings
        self.recentLines = recentLines
    }
}

/// Invents a continuation when the corpus has none, which is the one thing memory cannot do.
public protocol CandidateGenerating: Sendable {
    /// Whether the model can answer at once, since a keystroke may never wait on one still loading.
    var isReady: Bool { get async }

    /// Likely continuations of the typed text, most likely first, or none when it cannot say.
    func completions(for typed: String, in situation: GenerationSituation) async -> [String]
}
