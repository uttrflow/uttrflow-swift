import UttrflowAI
import UttrflowCore

/// What the rules pass sees in a dictation that might need the model: the cues a tidy gate can read for free.
enum TidyCue: String, CaseIterable, Sendable {
    case filler
    case repeated
    case repair
    case list
    case runOn

    /// Present words after which a dictation the rules left without an inner stop counts as a run-on.
    static let runOnWords = 25

    /// The cues the shipped rules pipeline finds in `spoken`, read from which passes edited a word.
    static func cues(in spoken: String) -> Set<TidyCue> {
        let draft = CleaningPipeline.standard.run(Draft(text: spoken))
        let actors = Set(draft.words.flatMap { $0.edits.map(\.by) })
        var found: Set<TidyCue> = []
        if actors.contains(.fillers) { found.insert(.filler) }
        if actors.contains(.stammers) || actors.contains(.repeatedPhrase) { found.insert(.repeated) }
        if actors.contains(.selfCorrection) { found.insert(.repair) }
        let present = draft.presentIndices.map { draft.words[$0] }
        if present.contains(where: \.isListMark) { found.insert(.list) }
        if isRunOn(present.map(\.text)) { found.insert(.runOn) }
        return found
    }

    /// Long, with no sentence stop the rules could place before its last word.
    static func isRunOn(_ words: [String]) -> Bool {
        guard words.count >= runOnWords else { return false }
        return !words.dropLast().contains { word in
            word.last.map { ".?!".contains($0) } ?? false
        }
    }
}
