import UttrflowCore
internal import UttrflowDictionary

extension PassID {
    /// A doubted run of spoken words written as the one identifier on screen it names.
    static let screenIdentifier: PassID = "screenIdentifier"
}

/// Writes a run the recogniser scored low as the one identifier on screen it names: "order totals" → `orderTotals`. See `Docs/cleanup.md`.
struct ScreenIdentifierPass: PieceCleaningPass {
    static let id: PassID = .screenIdentifier
    /// Joining a run into one identifier writes a word the draft did not hold, so `addsNoWords` is not kept.
    static let laws: Set<PassLaw> = [.idempotent, .keepsDigits, .latinOnly]

    /// Which runs may be bound.
    enum Reading: Sendable, Equatable {
        /// A run the recogniser scored low, to an identifier spelt or sounding like it.
        case doubted
        /// Any run of a statement, only to an identifier it spells, never past a word the recogniser ended with a pause mark.
        case statement(pausedAfter: Set<Int>)
    }

    /// The identifiers the screen shows; empty, the pass changes nothing.
    let vocabulary: ScreenVocabulary

    /// Which runs may be bound.
    let reading: Reading

    init(vocabulary: ScreenVocabulary = .empty, reading: Reading = .doubted) {
        self.vocabulary = vocabulary
        self.reading = reading
    }

    func apply(_ draft: Draft) -> Draft {
        guard !vocabulary.identifiers.isEmpty else { return draft }
        var draft = draft
        let said = draft.words.indices.filter {
            draft.words[$0].isPresent && !draft.words[$0].isLayoutMark && !draft.words[$0].heard.isEmpty
        }
        var start = 0
        while start < said.count {
            guard let (length, identifier) = longestBinding(from: start, in: said, of: draft) else {
                start += 1
                continue
            }
            let run = Array(said[start..<(start + length)])
            let (opening, closing) = (draft.shape(at: run[0]).prefix, draft.shape(at: run[length - 1]).suffix)
            let written = opening + identifier + closing
            for index in run.dropFirst() { draft.remove(at: index, by: Self.id) }
            draft.replace(at: run[0], with: written, by: Self.id)
            start += length
        }
        return draft
    }

    /// The longest admitted run from `start`, unbroken by a mark, that binds to one identifier, and that identifier.
    private func longestBinding(from start: Int, in said: [Int], of draft: Draft) -> (Int, String)? {
        var admitted = 0
        while admitted < PhoneticIndex.maximumWordsPerEntry, start + admitted < said.count,
            admits(draft.words[said[start + admitted]])
        {
            admitted += 1
            if case .statement(let paused) = reading, paused.contains(said[start + admitted - 1]) { break }
        }
        for length in stride(from: admitted, through: 1, by: -1) {
            let shapes = said[start..<(start + length)].map { draft.shape(at: $0) }
            guard shapes.dropLast().allSatisfy({ $0.suffix.isEmpty }),
                shapes.dropFirst().allSatisfy({ $0.prefix.isEmpty }),
                case .bound(let identifier) = IdentifierResolver.bind(
                    spokenWords: shapes.map(\.core), vocabulary: vocabulary, soundsAlike: reading == .doubted)
            else { continue }
            return (length, identifier)
        }
        return nil
    }

    /// Any word of a statement; in prose only a word the recogniser scored low, so a surely heard homophone is never bound.
    private func admits(_ word: Draft.Word) -> Bool {
        reading != .doubted || Self.isDoubted(word)
    }

    /// A word the recogniser scored low.
    private static func isDoubted(_ word: Draft.Word) -> Bool {
        DoubtPolicy.reason(text: word.text, confidence: word.confidence, settled: word.settled) == .lowScore
    }
}
