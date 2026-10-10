// What joining pieces did at each seam, measured against the same speech written in one pass.
internal import UttrflowCore

/// The artefacts one seam left: a stop the whole has not, a capital it has not, and words doubled or lost.
public struct SeamTally: Sendable, Equatable, Codable {
    /// The piece before the seam ends in `.`, `!` or `?` where the whole's matching word does not.
    public var strayStops = 0
    /// The first word after the seam differs from the whole's matching word only in its first letter's case.
    public var wrongCapitals = 0
    /// Words the pieces wrote that the whole has nothing behind, beside the seam.
    public var duplicated = 0
    /// Words of the whole the pieces never wrote, beside the seam.
    public var dropped = 0

    public init() {}

    /// Every artefact counted, the number a seam must hold at zero.
    public var total: Int { strayStops + wrongCapitals + duplicated + dropped }

    /// Each kind of artefact named, in a fixed order, for reports and baseline comparisons.
    var kinds: [(name: String, count: Int)] {
        [
            ("stray stops", strayStops), ("wrong capitals", wrongCapitals), ("duplicated", duplicated),
            ("dropped", dropped),
        ]
    }

    static func + (left: Self, right: Self) -> Self {
        var sum = left
        sum.strayStops += right.strayStops
        sum.wrongCapitals += right.wrongCapitals
        sum.duplicated += right.duplicated
        sum.dropped += right.dropped
        return sum
    }
}

/// One clip's seams scored against its one-pass text: one tally per seam, in order, aligned by word match.
public struct SeamScore: Sendable, Equatable {
    /// One tally for each boundary between consecutive pieces.
    public let seams: [SeamTally]

    /// All seams summed.
    public var total: SeamTally { seams.reduce(SeamTally(), +) }

    /// Scores `pieces`, the texts the clip's pieces were written as, against `whole`, the clip written at once.
    public init(whole: String, pieces: [String]) {
        let reference = Self.words(whole)
        let pieceWords = pieces.map(Self.words)
        let written = pieceWords.flatMap(\.self)
        // A seam sits before the first word of every piece after the first, as a position in `written`.
        var seamStarts: [Int] = []
        var start = 0
        for words in pieceWords.dropLast() {
            start += words.count
            seamStarts.append(start)
        }
        let alignment = WordErrorRate.measure(
            reference: reference.map(\.key), hypothesis: written.map(\.key)
        ).alignment
        seams = seamStarts.map {
            Self.tally(at: $0, alignment: alignment, reference: reference, written: written)
        }
    }

    /// A written word with its comparison key: lower case, letters and digits only.
    struct Word: Equatable {
        let surface: String
        let key: String
    }

    static func words(_ text: String) -> [Word] {
        WordTokens.words(text, .display).compactMap { piece in
            let surface = String(piece)
            let key = String(surface.lowercased().filter { $0.isLetter || $0.isNumber })
            return key.isEmpty ? nil : Word(surface: surface, key: key)
        }
    }

    /// The seam's artefacts, read from the alignment steps that touch the written words on either side of it.
    static func tally(
        at seam: Int, alignment: [WordErrorRate.Operation], reference: [Word], written: [Word]
    )
        -> SeamTally
    {
        var tally = SeamTally()
        var referenceIndex = 0
        var writtenIndex = 0
        // Steps are kept with the written position they sit at, so a run of edits at the seam is found whole.
        var steps: [(operation: WordErrorRate.Operation, reference: Int, written: Int)] = []
        for operation in alignment {
            steps.append((operation, referenceIndex, writtenIndex))
            switch operation.kind {
            case .match, .substitution:
                referenceIndex += 1
                writtenIndex += 1
            case .deletion: referenceIndex += 1
            case .insertion: writtenIndex += 1
            }
        }
        // The edits beside the seam: the unbroken run of non-matching steps that reaches it from either side.
        guard let first = steps.firstIndex(where: { $0.written >= seam }) else { return tally }
        var low = first
        while low > 0, steps[low - 1].operation.kind != .match { low -= 1 }
        var high = first
        while high < steps.count, steps[high].operation.kind != .match { high += 1 }
        for step in steps[low..<high] {
            switch step.operation.kind {
            case .insertion: tally.duplicated += 1
            case .deletion: tally.dropped += 1
            case .match, .substitution: break
            }
        }
        // The words either side of the seam, compared with the whole's word each lines up with.
        func referenceWord(forWritten index: Int) -> Word? {
            guard let step = steps.first(where: { $0.written == index && $0.operation.kind == .match }) else {
                return nil
            }
            return reference[step.reference]
        }
        if seam > 0, let before = referenceWord(forWritten: seam - 1),
            endsSentence(written[seam - 1].surface), !endsSentence(before.surface)
        {
            tally.strayStops += 1
        }
        if seam < written.count, let after = referenceWord(forWritten: seam),
            let writtenFirst = written[seam].surface.first(where: \.isLetter),
            let wholeFirst = after.surface.first(where: \.isLetter),
            writtenFirst.isUppercase != wholeFirst.isUppercase
        {
            tally.wrongCapitals += 1
        }
        return tally
    }

    static func endsSentence(_ surface: String) -> Bool {
        guard let last = surface.last(where: { !"\"')]}".contains($0) }) else { return false }
        return ".!?".contains(last)
    }
}
