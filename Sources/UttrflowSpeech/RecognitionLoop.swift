// Undoes a recogniser that looped over one short piece, writing the sentence twice or in quotes.
public import UttrflowCore

/// Keeps one copy of a piece the recogniser repeated faster than speech allows. See `Docs/speech-engines.md`.
public enum RecognitionLoop {
    /// Words a second past which a piece cannot be what one person said; see `Docs/speech-engines.md`.
    public static let fastestSpeech = 4.5
    /// How far the two copies may differ, as a word error rate, and still be one loop.
    static let mostCopyDifference = 0.2
    /// The fewest words in a copy, since a word or two said twice is ordinary speech.
    static let fewestCopyWords = 3

    /// The transcription with a looped repeat kept once and quotes wrapped round the whole piece taken off.
    public static func undone(_ heard: Transcription, speechDuration: Duration) -> Transcription {
        let original = heard.text.split(whereSeparator: \.isWhitespace).map(String.init)
        var tokens = withoutWrappingQuotes(original)
        if let run = loopedCopies(tokens, speechDuration: speechDuration) {
            let trailing = tokens.dropFirst(run.repeatedEnd)
            tokens = Array(tokens.prefix(run.copyLength)) + trailing
        } else if let half = loopedHalf(tokens, speechDuration: speechDuration) {
            tokens = Array(tokens.prefix(half))
        }
        // Again once the loop is cut, since quotes round each copy only wrap the whole piece after it.
        let unquoted = withoutWrappingQuotes(tokens)
        guard unquoted != original else {
            return heard
        }
        return Transcription(
            text: unquoted.joined(separator: " "),
            detectedLanguage: heard.detectedLanguage,
            segments: segments(heard.segments, keeping: unquoted),
            audioDuration: heard.audioDuration,
            effort: heard.effort)
    }

    /// Whether a partial decode is already a loop `undone` would cut, so decoding can stop before spending more tokens.
    public static func isLooping(_ partial: String, within audio: Duration) -> Bool {
        let tokens = withoutWrappingQuotes(partial.split(whereSeparator: \.isWhitespace).map(String.init))
        return loopedCopies(tokens, speechDuration: audio) != nil
    }

    /// How many words the first copy holds, when the piece is one run of words said twice too fast to be real.
    static func loopedHalf(_ tokens: [String], speechDuration: Duration) -> Int? {
        let seconds = speechDuration / .seconds(1)
        guard tokens.count.isMultiple(of: 2), tokens.count / 2 >= fewestCopyWords, seconds > 0,
            Double(tokens.count) / seconds > fastestSpeech
        else { return nil }
        let half = tokens.count / 2
        let first = tokens.prefix(half).map(comparable)
        let second = tokens.suffix(half).map(comparable)
        guard !containsShorterLoop(first) else { return nil }
        let difference = WordErrorRate.measure(reference: first, hypothesis: second).rate ?? 1
        return difference <= mostCopyDifference ? half : nil
    }

    /// The repeated word range, when at least three copies match above the speech-rate threshold.
    private static func loopedCopies(
        _ tokens: [String], speechDuration: Duration
    ) -> (copyLength: Int, repeatedEnd: Int)? {
        let seconds = speechDuration / .seconds(1)
        guard seconds > 0, Double(tokens.count) / seconds > fastestSpeech,
            tokens.count / 3 >= fewestCopyWords
        else { return nil }

        for copyLength in fewestCopyWords...(tokens.count / 3) {
            let completeCopies = tokens.count / copyLength
            let completeEnd = completeCopies * copyLength
            let first = tokens.prefix(copyLength).map(comparable)
            guard !containsShorterLoop(first) else { continue }
            let copiesMatch = (1..<completeCopies).allSatisfy { copy in
                let start = copy * copyLength
                let candidate = tokens[start..<(start + copyLength)].map(comparable)
                let difference = WordErrorRate.measure(reference: first, hypothesis: candidate).rate ?? 1
                return difference <= mostCopyDifference
            }
            guard copiesMatch else { continue }

            let partialCount = tokens.count - completeEnd
            guard partialCount > 0 else { return (copyLength, completeEnd) }
            let partial = tokens[completeEnd...].map(comparable)
            let expected = Array(first.prefix(partialCount))
            let difference = WordErrorRate.measure(reference: expected, hypothesis: partial).rate ?? 1
            return (copyLength, difference <= mostCopyDifference ? tokens.count : completeEnd)
        }
        return nil
    }

    /// Refuses a candidate copy built only from repetitions shorter than an ordinary phrase.
    private static func containsShorterLoop(_ tokens: [String]) -> Bool {
        for copyLength in 1..<fewestCopyWords where tokens.count.isMultiple(of: copyLength) {
            let first = Array(tokens.prefix(copyLength))
            let copiesMatch = stride(from: copyLength, to: tokens.count, by: copyLength).allSatisfy { start in
                let candidate = Array(tokens[start..<(start + copyLength)])
                let difference = WordErrorRate.measure(reference: first, hypothesis: candidate).rate ?? 1
                return difference <= mostCopyDifference
            }
            if copiesMatch { return true }
        }
        return false
    }

    /// The words without a pair of double quotes that opens the first and closes the last, when no other quote is there.
    static func withoutWrappingQuotes(_ tokens: [String]) -> [String] {
        guard var first = tokens.first, var last = tokens.last else { return tokens }
        let quotes = tokens.joined().filter(isDoubleQuote)
        guard quotes.count == 2, let opener = first.first, isDoubleQuote(opener) else { return tokens }
        first.removeFirst()
        var result = tokens
        result[0] = first
        last = result[result.count - 1]
        guard let closer = last.lastIndex(where: isDoubleQuote),
            last[last.index(after: closer)...].allSatisfy({ $0.isPunctuation && !isDoubleQuote($0) })
        else { return tokens }
        last.remove(at: closer)
        result[result.count - 1] = last
        return result.filter { !$0.isEmpty }
    }

    /// The segments cut to the words kept, each segment's text rebuilt from the words it keeps.
    private static func segments(
        _ segments: [TranscriptionSegment], keeping kept: [String]
    ) -> [TranscriptionSegment] {
        var remaining = kept[...]
        var result: [TranscriptionSegment] = []
        for segment in segments {
            guard !remaining.isEmpty else { break }
            let count = segment.text.split(whereSeparator: \.isWhitespace).count
            guard count > 0 else { continue }
            let taken = Array(remaining.prefix(count))
            remaining = remaining.dropFirst(taken.count)
            let words =
                segment.words.count == count
                ? zip(segment.words, taken).map {
                    TranscribedWord(text: $1, confidence: $0.confidence, start: $0.start, end: $0.end)
                }
                : Array(segment.words.prefix(taken.count))
            result.append(
                TranscriptionSegment(
                    text: taken.joined(separator: " "), start: segment.start, end: segment.end,
                    words: words))
        }
        return result
    }

    /// A word folded to lower case with its punctuation dropped, so "rakhna." and "Rakhna" compare equal.
    private static func comparable(_ token: String) -> String {
        String(token.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    private static func isDoubleQuote(_ character: Character) -> Bool {
        character == "\"" || character == "\u{201C}" || character == "\u{201D}"
    }
}
