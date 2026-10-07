// Scores the two ways of committing the open tail while the key is held: agreement between passes, or pauses.
public import UttrflowCore

/// What the joins between pieces did to the transcript, counted against the reference. See `Docs/tail-commit.md`.
public struct SeamArtefacts: Sendable, Equatable {
    /// A sentence stop at the end of a piece where the reference has none.
    public let strayStops: Int
    /// A capital at the start of a piece where the reference word is lower case.
    public let strayCapitals: Int
    /// A piece that repeats the word the piece before it ended on.
    public let duplicatedWords: Int
    /// Reference words missing next to a seam.
    public let droppedWords: Int
    /// How many joins there were.
    public let seams: Int

    public init(strayStops: Int, strayCapitals: Int, duplicatedWords: Int, droppedWords: Int, seams: Int) {
        self.strayStops = strayStops
        self.strayCapitals = strayCapitals
        self.duplicatedWords = duplicatedWords
        self.droppedWords = droppedWords
        self.seams = seams
    }

    /// Every artefact together.
    public var total: Int { strayStops + strayCapitals + duplicatedWords + droppedWords }
}

/// The agreement rule and the scoring both commit policies are judged by.
public enum TailCommit {
    /// A word as compared between passes and against the reference: lower case, letters and digits only.
    public static func normalized(_ word: String) -> String {
        String(word.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// How many leading words two passes over the same open audio agree on.
    public static func agreedPrefix(_ previous: [AlignedWord], _ current: [AlignedWord]) -> Int {
        zip(previous, current).prefix { normalized($0.word) == normalized($1.word) }.count
    }

    /// The words of `text` that score, empty words dropped.
    public static func scoredWords(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map { normalized(String($0)) }.filter { !$0.isEmpty }
    }

    /// The word error rate of `hypothesis` against `reference`, both normalized.
    public static func wordErrorRate(hypothesis: String, reference: String) -> WordErrorRate {
        WordErrorRate.measure(reference: scoredWords(reference), hypothesis: scoredWords(hypothesis))
    }

    /// The artefacts at each join of `pieces`, read against `reference` through the word alignment.
    public static func seamArtefacts(pieces: [String], reference: String) -> SeamArtefacts {
        let raw = pieces.map { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
            .map { $0.filter { !normalized($0).isEmpty } }
        let referenceWords = reference.split(whereSeparator: \.isWhitespace).map(String.init)
            .filter { !normalized($0).isEmpty }
        let alignment = WordErrorRate.measure(
            reference: referenceWords.map(normalized), hypothesis: raw.flatMap { $0 }.map(normalized)
        ).alignment
        let mapping = referenceIndex(of: alignment)
        var stops = 0
        var capitals = 0
        var duplicated = 0
        var dropped = 0
        var seams = 0
        var offset = 0
        for (index, piece) in raw.enumerated() {
            defer { offset += piece.count }
            guard index + 1 < raw.count, let last = piece.last, let next = raw[index + 1].first else {
                continue
            }
            seams += 1
            let lastIndex = offset + piece.count - 1
            let lastReference = mapping.hypothesis[lastIndex]
            let nextReference = mapping.hypothesis[lastIndex + 1]
            if isSentenceStop(last), lastReference.map({ !isSentenceStop(referenceWords[$0]) }) ?? true {
                stops += 1
            }
            if isCapitalised(next), nextReference.map({ !isCapitalised(referenceWords[$0]) }) ?? false {
                capitals += 1
            }
            if normalized(last) == normalized(next) {
                let repeated = lastReference.map {
                    $0 + 1 < referenceWords.count && normalized(referenceWords[$0 + 1]) == normalized(next)
                }
                if repeated != true { duplicated += 1 }
            }
            dropped += mapping.deletions(before: lastIndex + 1)
        }
        return SeamArtefacts(
            strayStops: stops, strayCapitals: capitals, duplicatedWords: duplicated, droppedWords: dropped,
            seams: seams)
    }

    private static func isSentenceStop(_ word: String) -> Bool {
        word.last.map { ".?!".contains($0) } ?? false
    }

    /// Upper case first letter, the pronoun "I" aside, which is capitalised wherever it falls.
    private static func isCapitalised(_ word: String) -> Bool {
        guard let first = word.first(where: \.isLetter), normalized(word) != "i" else { return false }
        return first.isUppercase
    }

    /// The alignment read as positions: each hypothesis word's reference index and the deletions between.
    struct Mapping {
        var hypothesis: [Int?] = []
        /// Deletions counted before hypothesis word `i`, at index `i`; the last entry counts those after the end.
        var deletionsBefore: [Int] = []

        /// Reference words deleted just before hypothesis word `index`.
        func deletions(before index: Int) -> Int {
            index < deletionsBefore.count ? deletionsBefore[index] : 0
        }
    }

    /// Walks the alignment once, so every seam reads its reference word without searching.
    static func referenceIndex(of alignment: [WordErrorRate.Operation]) -> Mapping {
        var mapping = Mapping()
        var reference = 0
        var pending = 0
        for operation in alignment {
            switch operation.kind {
            case .match, .substitution:
                mapping.hypothesis.append(reference)
                mapping.deletionsBefore.append(pending)
                pending = 0
                reference += 1
            case .insertion:
                mapping.hypothesis.append(nil)
                mapping.deletionsBefore.append(pending)
                pending = 0
            case .deletion:
                pending += 1
                reference += 1
            }
        }
        mapping.deletionsBefore.append(pending)
        return mapping
    }
}
