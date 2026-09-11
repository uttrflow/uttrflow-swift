public import UttrflowCore
private import UttrflowDictionary

/// What a doubtful run could have been, taken from the words the screen is already showing.
public struct ScreenCandidates: CandidateSource {
    /// The most words read off the screen, so a selected page cannot turn a lookup into a scan.
    public static let maximumWordsOnScreen = CorrectionEvidence.maximumWordsOnScreen
    /// The shortest screen word worth offering; below this a stray initial matches everything.
    public static let shortestWorthOffering = 3
    /// Fewer than a span's whole budget, so a crowded screen cannot crowd the other sources off the line.
    public static let maximumOffered = 2

    public init() {}

    /// The screen words that spell the run with its spaces closed up, then those that sound and open like it.
    public func candidates(for word: Draft.Word, in situation: Situation) async -> [String] {
        let heard = word.text
        let closed = DoubtfulSpan.closedUp(heard)
        var spelled: [String] = []
        var sounded: [String] = []
        for shown in Self.words(on: situation) {
            if DoubtfulSpan.closedUp(shown) == closed {
                spelled.append(shown)
            } else if ReadingRestraint.isWorthOffering(shown, for: heard) {
                sounded.append(shown)
            }
        }
        return Array((spelled + sounded).prefix(Self.maximumOffered))
    }

    /// The window title, the selection and the text either side of the caret, split into words that carry a spelling.
    static func words(on situation: Situation) -> [String] {
        var seen: Set<String> = []
        return [
            situation.app.documentName, situation.app.selectedText,
            situation.insertion.precedingText, situation.insertion.followingText,
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .split { !$0.isLetter && !$0.isNumber }
        .prefix(maximumWordsOnScreen)
        .map(String.init)
        .filter { $0.count >= shortestWorthOffering && seen.insert($0.lowercased()).inserted }
    }
}
