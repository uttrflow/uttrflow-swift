public import UttrflowCore
private import UttrflowDictionary

/// What a doubtful run could have been, taken from the words the screen is already showing.
public struct ScreenCandidates: CandidateSource {
    /// The most words read off the screen, so a selected page cannot turn a lookup into a scan.
    public static let maximumWordsOnScreen = CorrectionEvidence.maximumWordsOnScreen
    /// The shortest screen word worth offering; below this a stray initial matches everything.
    static let shortestWorthOffering = 3
    /// Fewer than a span's whole budget, so a crowded screen cannot crowd the other sources off the line.
    public static let maximumOffered = 2

    public init() {}

    /// The screen words that spell the run with its spaces closed up, then those that sound and open like it.
    public func candidates(for word: Draft.Word, in situation: Situation) async -> [Reading] {
        await candidates(for: [word], in: situation).first ?? []
    }

    /// Every run against one reading of the screen, so a page of selected text is read and coded once a piece.
    public func candidates(for words: [Draft.Word], in situation: Situation) async -> [[Reading]] {
        let shown = Self.words(on: situation).map(ReadingKey.init)
        return words.map { word in
            let heard = ReadingKey(word.text)
            var spelled: [String] = []
            var sounded: [String] = []
            for screen in shown {
                if screen.closed == heard.closed {
                    spelled.append(screen.word)
                } else if ReadingRestraint.isWorthOffering(screen, for: heard) {
                    sounded.append(screen.word)
                }
            }
            return (spelled + sounded).prefix(Self.maximumOffered).map { Reading($0) }
        }
    }

    /// Whether the screen shows the word spelt as heard, so a word in front of the user is never doubted for its sentence.
    public func vouches(for heard: String, in situation: Situation) async -> Bool {
        let spelling = ReadingRestraint.closedUp(heard)
        return Self.words(on: situation).contains { ReadingRestraint.closedUp($0) == spelling }
    }

    /// The window title, the selection and the text either side of the caret, secrets dropped, split into words that carry a spelling.
    static func words(on situation: Situation) -> [String] {
        var seen: Set<String> = []
        let insertion = situation.insertion.vocabulary
        let shown = [
            situation.app.documentName.map(SecretShapes.vocabulary(of:)),
            situation.app.selectedText.map(SecretShapes.vocabulary(of:)),
            insertion.precedingText, insertion.followingText,
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        return WordTokens.words(shown, .comparison)
            .prefix(maximumWordsOnScreen)
            .filter { $0.count >= shortestWorthOffering && seen.insert($0.lowercased()).inserted }
    }
}
