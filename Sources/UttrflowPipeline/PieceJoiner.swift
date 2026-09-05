import UttrflowCore

/// One piece of the recording, through every stage that runs before the words are joined.
struct Piece: Sendable {
    let heard: Transcription
    let corrected: CorrectedTranscript
    let cleaned: TransformationResult
}

/// Joins the pieces of one dictation, laying out what only the seam between two of them can show. See `Docs/cleanup-design.md` §7.
enum PieceJoiner {
    static let id: PassID = "pieceJoiner"

    /// Every piece as one, with the corrections' word ranges moved to where their piece begins.
    static func join(_ pieces: [Piece], under formatter: DestinationFormatter) -> Piece {
        guard pieces.count > 1, let first = pieces.first else {
            return pieces.first
                ?? Piece(
                    heard: Transcription(text: ""), corrected: .unchanged(""),
                    cleaned: TransformationResult(text: "", producedBy: .rules))
        }
        var corrections: [DictationCorrection] = []
        var wordsBefore = 0
        var heardText: [String] = []
        var correctedText: [String] = []
        var producedBy = first.cleaned.producedBy
        for piece in pieces {
            corrections += piece.corrected.corrections.map { $0.shifted(by: wordsBefore) }
            wordsBefore += piece.heard.text.spokenWordCount
            heardText.append(piece.heard.text)
            correctedText.append(piece.corrected.text)
            // Any piece the model left to the rules makes the whole a rules result.
            if piece.cleaned.producedBy != producedBy { producedBy = .rules }
        }
        let heard = Transcription(
            text: heardText.joined(separator: " "),
            detectedLanguage: first.heard.detectedLanguage,
            segments: pieces.flatMap(\.heard.segments),
            audioDuration: pieces.reduce(.zero) { $0 + $1.heard.audioDuration })
        return Piece(
            heard: heard,
            corrected: CorrectedTranscript(
                text: correctedText.joined(separator: " "), corrections: corrections),
            cleaned: TransformationResult(
                text: laidOut(pieces.map(\.cleaned.text), under: formatter), producedBy: producedBy))
    }

    /// The cleaned pieces as one text: a spoken list, a paragraph at a topic, a restatement across the seam, else a space.
    static func laidOut(_ pieces: [String], under formatter: DestinationFormatter) -> String {
        var draft = Draft(words: [])
        var starts: [Int] = []
        for text in pieces {
            let piece = Draft(keepingLineBreaks: text)
            guard !piece.words.isEmpty else { continue }
            starts.append(draft.words.count)
            draft.words += piece.words
        }
        guard starts.count > 1 else { return draft.text }

        var marks: [Int: String] = [:]
        var absorbed: Set<Int> = []
        for opening in starts.indices.dropFirst() where restate(&draft, at: starts[opening]) {
            absorbed.insert(opening)
        }
        let items = formatter.layout.contains(.lists) ? listItems(in: draft, starts: starts) : []
        for opening in items {
            if let mark = itemise(&draft, opening, starts) { marks[starts[opening]] = mark }
        }
        for opening in starts.indices.dropFirst() {
            guard paragraphs(formatter), !absorbed.contains(opening), !items.contains(opening),
                opensTopic(draft, at: starts[opening])
            else { continue }
            marks[starts[opening]] = "\n\n"
        }
        for (index, mark) in marks.sorted(by: { $0.key > $1.key }) {
            draft.insert(mark, at: index, by: id)
        }
        return draft.text
    }

    /// Whether this place wants a blank line between topics at all.
    private static func paragraphs(_ formatter: DestinationFormatter) -> Bool {
        formatter.layout.contains(.paragraphs) && !formatter.layout.contains(.singleLine)
    }

    // MARK: Restatements across the seam

    /// Drops the tail the speaker replaced when a piece opens with a correction trigger, saying whether it did.
    private static func restate(_ draft: inout Draft, at word: Int) -> Bool {
        let live = draft.presentIndices
        guard let position = live.firstIndex(of: word), position > 0 else { return false }
        let trigger = Restatement.triggerRun(at: position, in: live, of: draft)
        guard trigger > 0, position + trigger < live.count else { return false }

        // The stop the piece before was given ends a sentence the speaker never did, so the match reaches through it.
        let last = live[position - 1]
        let stopped = draft.words[last].text
        draft.words[last].text = WordShape.withoutTrailingStop(stopped)
        guard
            let start = Restatement.discardedStart(
                before: position, after: position + trigger, in: live, of: draft)
        else {
            draft.words[last].text = stopped
            return false
        }
        for index in live[start..<position + trigger] { draft.remove(at: index, by: id) }
        return true
    }

    // MARK: Lists from spoken sequence words

    /// The openings that are the items of one spoken list, or nothing when the pieces do not spell one.
    private static func listItems(in draft: Draft, starts: [Int]) -> [Int] {
        let live = draft.presentIndices
        guard
            let head = starts.indices.first(where: {
                sequence(draft, live, at: starts[$0])?.value == 1
            }), starts.count - head >= 2
        else { return [] }
        let kind = sequence(draft, live, at: starts[head])?.kind
        for opening in head..<starts.count {
            guard let found = sequence(draft, live, at: starts[opening]), found.kind == kind,
                found.value == opening - head + 1,
                isClause(draft, live, opening, starts, after: found.length)
            else { return [] }
        }
        return Array(head..<starts.count)
    }

    /// Takes the sequence word off an item, capitalises what is left of it and drops its full stop, answering its mark.
    private static func itemise(_ draft: inout Draft, _ opening: Int, _ starts: [Int]) -> String? {
        let live = draft.presentIndices
        guard let position = live.firstIndex(of: starts[opening]),
            let found = sequence(draft, live, at: starts[opening])
        else { return nil }
        for index in live[position..<position + found.length] { draft.remove(at: index, by: id) }
        let body = words(of: opening, starts, in: draft)
        guard let head = body.first, let tail = body.last else { return nil }
        draft.replace(at: head, with: WordShape.capitalised(draft.words[head].text), by: id)
        draft.replace(at: tail, with: WordShape.withoutTrailingStop(draft.words[tail].text), by: id)
        return draft.presentIndices.first == head ? Draft.bullet : "\n" + Draft.bullet
    }

    /// The sequence word a piece opens with — "first", "two", "number three", "point four" — and how many words it took.
    private static func sequence(
        _ draft: Draft, _ live: [Int], at word: Int
    ) -> (value: Int, kind: SequenceKind, length: Int)? {
        guard let position = live.firstIndex(of: word) else { return nil }
        var length = 0
        if position + 1 < live.count, Self.prefixes.contains(draft.shape(at: live[position]).key) {
            length = 1
        }
        guard position + length < live.count else { return nil }
        let key = draft.shape(at: live[position + length]).key
        if let value = Self.ordinals[key] { return (value, .ordinal, length + 1) }
        if let value = Self.cardinals[key] { return (value, .cardinal, length + 1) }
        return nil
    }

    /// Whether what a piece says after its sequence word stands as a clause rather than naming a thing.
    private static func isClause(
        _ draft: Draft, _ live: [Int], _ opening: Int, _ starts: [Int], after head: Int
    ) -> Bool {
        let body = words(of: opening, starts, in: draft).dropFirst(head)
        guard body.count >= 2, let first = body.first else { return false }
        return !Self.determiners.contains(draft.shape(at: first).key)
    }

    /// The words of one piece that are still in the text, in order.
    private static func words(of opening: Int, _ starts: [Int], in draft: Draft) -> [Int] {
        let end = opening + 1 < starts.count ? starts[opening + 1] : draft.words.count
        return draft.presentIndices.filter { $0 >= starts[opening] && $0 < end }
    }

    // MARK: Paragraphs between topics

    /// Whether a piece opens on a new topic — a sequence word, or one of the phrases a speaker moves on with.
    private static func opensTopic(_ draft: Draft, at word: Int) -> Bool {
        let live = draft.presentIndices
        guard let position = live.firstIndex(of: word) else { return false }
        if Self.ordinals[draft.shape(at: live[position]).key] != nil { return true }
        return Self.topics.contains { phrase in
            position + phrase.count <= live.count
                && zip(phrase, live[position..<position + phrase.count]).allSatisfy {
                    $0 == draft.shape(at: $1).key
                }
        }
    }

    // MARK: The words this reads

    /// Whether a sequence is counted in ordinals or in cardinals; one dictation's list never mixes them.
    private enum SequenceKind { case ordinal, cardinal }

    /// Words that may stand before the number of an item, as in "number one" and "point two".
    private static let prefixes: Set<String> = ["number", "point", "item", "step"]

    private static let ordinals: [String: Int] = [
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7,
        "eighth": 8, "ninth": 9, "tenth": 10,
    ]

    private static let cardinals: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
        "nine": 9, "ten": 10, "1": 1, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7, "8": 8,
        "9": 9, "10": 10,
    ]

    /// Words an item may not open on, because what follows them names a thing rather than saying something about it.
    private static let determiners: Set<String> = [
        "a", "an", "the", "my", "your", "his", "her", "its", "their", "our", "this", "that",
        "these", "those", "some", "any",
    ]

    /// The phrases a speaker opens a new topic with after a pause.
    private static let topics: [[String]] = [
        ["okay", "so"], ["ok", "so"], ["another", "thing"], ["one", "more", "thing"],
        ["moving", "on"], ["also"], ["next"], ["finally"], ["anyway"], ["additionally"],
        ["furthermore"], ["lastly"],
    ]
}

extension DictationCorrection {
    /// The same correction, indexing words `offset` further into a longer sentence.
    fileprivate func shifted(by offset: Int) -> Self {
        Self(
            heard: heard, wrote: wrote,
            wordRange: (wordRange.lowerBound + offset)..<(wordRange.upperBound + offset),
            entryID: entryID, reason: reason, heardConfidence: heardConfidence)
    }
}

extension String {
    /// How many words were spoken, counted the way the corrections' ranges count them.
    var spokenWordCount: Int { split(whereSeparator: \.isWhitespace).count }
}
