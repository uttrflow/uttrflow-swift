/// Invents a continuation when the corpus has none, which is the one thing memory cannot do.
public protocol CandidateGenerating: Sendable {
    /// Whether the model can answer at once, since a keystroke may never wait on one still loading.
    var isReady: Bool { get async }

    /// Likely continuations of the typed text, most likely first, or none when it cannot say.
    func completions(for typed: String, in surface: Surface, isProse: Bool) async -> [String]
}
