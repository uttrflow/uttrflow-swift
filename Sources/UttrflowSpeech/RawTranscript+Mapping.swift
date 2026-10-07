// Turns a recogniser's raw output into the product's Transcription.
public import UttrflowCore

extension RawTranscript {
    /// Turns any recogniser's raw output into the product's ``Transcription``, shifted by `offset`.
    public func transcription(
        audioDuration: Duration, startingAt offset: Duration = .zero
    ) -> Transcription {
        Transcription(
            text: Self.cleaned(text),
            detectedLanguage: detectedLanguage,
            segments: segments.map { $0.transcriptionSegment(shiftedBy: offset) },
            audioDuration: audioDuration,
            effort: effort,
            vocabularyPrompt: vocabularyPrompt,
            conditioning: conditioning
        )
    }

    /// Seconds between the recogniser's last segment and the audio end that suggests a decode stopped at the cap.
    public static let cappedDecodeGap: Duration = .milliseconds(2_500)

    /// Whether the last segment ends well before the audio did, which is what a capped decode looks like from outside.
    public func appearsCapped(audioDuration: Duration) -> Bool {
        guard let lastEnd = segments.last?.end else { return false }
        return audioDuration.inSeconds - lastEnd > Self.cappedDecodeGap.inSeconds
    }

    private var detectedLanguage: DetectedLanguage? {
        guard let languageIdentifier, let code = LanguageCode(languageIdentifier) else { return nil }
        return DetectedLanguage(code: code, confidence: languageProbability)
    }

    /// Words recognisers use for non-speech markers; unknown bracketed or starred words stay as dictated. See `Docs/silence.md`.
    static let markerWords: Set<String> = [
        "pain", "painful", "thud", "thunk", "puff", "crack", "gunshot",
        "blank", "audio", "silence", "silent", "quiet", "pause", "no", "speech", "sound", "sounds",
        "noise", "noises", "static", "background", "inaudible", "unintelligible", "indistinct",
        "muffled", "crosstalk", "chatter", "music", "musical", "song", "singing", "humming",
        "laughter", "laughs", "laughing", "chuckles", "applause", "clapping", "cheering",
        "coughs", "coughing", "sighs", "sighing", "sniffs", "breathing", "breath", "beep",
        "beeping", "chime", "ringing", "buzzing", "clicking", "typing", "footsteps", "wind",
        "rain", "thunder", "foreign", "language", "speaking", "upbeat", "soft", "gentle",
        "dramatic", "tense", "loud", "faint", "distant", "continues", "continued", "playing",
        "plays", "ends",
    ]

    /// Exact caption phrases reported by issue #2372 that need words outside `markerWords`.
    static let markerPhrases: Set<String> = [
        "door slams", "phone ringing", "clears throat", "sneezes", "speaking in foreign language",
        "background conversations",
    ]

    /// Whether a bounded bracket or star phrase is a known non-speech description.
    static func isMarker(_ inside: Substring) -> Bool {
        let words = inside.split(whereSeparator: { $0.isWhitespace || $0 == "_" || $0 == "-" })
        guard !words.isEmpty else { return false }
        let phrase = words.map { $0.lowercased() }.joined(separator: " ")
        if markerPhrases.contains(phrase) || isInaudibleTimestamp(phrase) { return true }
        guard words.count <= 3 else { return false }
        return words.allSatisfy { markerWords.contains($0.lowercased()) }
    }

    /// Recognises the timestamped inaudible caption reported by issue #2372.
    private static func isInaudibleTimestamp(_ phrase: String) -> Bool {
        let parts = phrase.split(separator: " ")
        guard parts.count == 2, parts[0] == "inaudible" else { return false }
        let timestamp = parts[1].split(separator: ":", omittingEmptySubsequences: false)
        return timestamp.count == 2 && timestamp.allSatisfy { $0.count == 2 && $0.allSatisfy(\.isNumber) }
    }

    /// Removes a leading music-caption run bounded by notes and containing only words or whitespace.
    private static func removingMusicRuns(_ text: String) -> String {
        let characters = Array(text)
        var kept: [Character] = []
        var index = 0

        while index < characters.count {
            guard characters[index] == "♪", isBoundary(characters, before: index) else {
                kept.append(characters[index])
                index += 1
                continue
            }

            var cursor = index + 1
            var lastNote = index
            while cursor < characters.count {
                while cursor < characters.count,
                    characters[cursor].isWhitespace || characters[cursor].isLetter
                {
                    cursor += 1
                }
                guard cursor < characters.count, characters[cursor] == "♪" else { break }
                lastNote = cursor
                cursor += 1
            }

            guard lastNote > index, isBoundary(characters, after: lastNote) else {
                kept.append(characters[index])
                index += 1
                continue
            }
            index = lastNote + 1
        }
        return String(kept)
    }

    /// A note run begins and ends at transcript boundaries, so inline musical symbols stay literal.
    private static func isBoundary(_ characters: [Character], before index: Int) -> Bool {
        index == 0 || characters[index - 1].isWhitespace || characters[index - 1].isPunctuation
    }

    /// A note run ends at transcript boundaries, so inline musical symbols stay literal.
    private static func isBoundary(_ characters: [Character], after index: Int) -> Bool {
        index + 1 == characters.count || characters[index + 1].isWhitespace
            || characters[index + 1].isPunctuation
    }

    /// Removes a musical caption only when its bracket contains two or more notes and no punctuation.
    private static func isMusicMarker(_ inside: Substring) -> Bool {
        var notes = 0
        for character in inside {
            if character == "♪" {
                notes += 1
            } else if !character.isWhitespace && !character.isLetter {
                return false
            }
        }
        return notes >= 2 && inside.first(where: { !$0.isWhitespace }) == "♪"
            && inside.reversed().first(where: { !$0.isWhitespace }) == "♪"
    }

    /// Removes a leading recogniser speaker marker while preserving the first spoken word's confidence.
    private static func removingSpeakerPrefix(_ words: [TranscribedWord]) -> [TranscribedWord] {
        guard let first = words.first else { return words }
        let leadingTrimmed = first.text.drop(while: \.isWhitespace)
        guard leadingTrimmed.hasPrefix(">>"),
            leadingTrimmed.dropFirst(2).first.map({ $0.isWhitespace }) ?? true
        else { return words }

        let spoken = leadingTrimmed.dropFirst(2).drop(while: \.isWhitespace)
        if spoken.isEmpty { return Array(words.dropFirst()) }
        return [
            TranscribedWord(
                text: String(spoken), confidence: first.confidence, start: first.start, end: first.end)
        ] + words.dropFirst()
    }

    /// The same removal over the recogniser's words, so the text and the word list cannot fall out of step.
    static func cleaned(_ words: [TranscribedWord]) -> [TranscribedWord] {
        var kept: [TranscribedWord] = []
        let withoutSpeaker = removingSpeakerPrefix(words)
        var index = withoutSpeaker.startIndex

        while index < withoutSpeaker.endIndex {
            let token = withoutSpeaker[index].text
            if token.allSatisfy({ $0 == "*" }), token.count >= 3 {
                index += 1
                continue
            }
            let opener = token.first
            guard opener == "[" || opener == "(" || opener == "*" else {
                kept.append(withoutSpeaker[index])
                index += 1
                continue
            }
            let closer: Character = opener == "[" ? "]" : opener == "(" ? ")" : "*"
            guard
                let close = withoutSpeaker[index...].indices.first(where: { candidate in
                    let text = withoutSpeaker[candidate].text
                    guard let closing = text.lastIndex(of: closer) else { return false }
                    if candidate == index && opener == closer && closing == text.startIndex { return false }
                    return text[text.index(after: closing)...].allSatisfy(\.isPunctuation)
                })
            else {
                kept.append(withoutSpeaker[index])
                index += 1
                continue
            }
            let closeText = withoutSpeaker[close].text
            guard let closingMarker = closeText.lastIndex(of: closer) else {
                kept.append(contentsOf: withoutSpeaker[index...close])
                index = withoutSpeaker.index(after: close)
                continue
            }
            let markerWords = withoutSpeaker[index...close].map(\.text)
            let inside = markerWords.enumerated().map { offset, word in
                if offset == 0 && close == index {
                    return String(word.dropFirst().prefix(upTo: closingMarker))
                }
                if offset == 0 { return String(word.dropFirst()) }
                if offset == markerWords.count - 1 { return String(word[..<closingMarker]) }
                return word
            }.joined(separator: " ")
            let openingToken = token.drop(while: \.isWhitespace)
            let punctuation = closeText[closeText.index(after: closingMarker)...]
            let standsAlone = openingToken.first == opener && punctuation.allSatisfy(\.isPunctuation)
            if !standsAlone || (!isMarker(inside[...]) && !isMusicMarker(inside[...])) {
                kept.append(contentsOf: withoutSpeaker[index...close])
            } else if !punctuation.isEmpty {
                kept.append(
                    TranscribedWord(
                        text: String(punctuation), confidence: withoutSpeaker[close].confidence,
                        start: withoutSpeaker[close].start, end: withoutSpeaker[close].end))
            }
            index = withoutSpeaker.index(after: close)
        }
        return removingMusicRuns(from: kept)
    }

    /// Removes note-delimited lyric runs from recognised words without disturbing retained confidences.
    private static func removingMusicRuns(from words: [TranscribedWord]) -> [TranscribedWord] {
        var kept: [TranscribedWord] = []
        var index = 0
        while index < words.count {
            // Each word stands apart, so a note that is a whole word is a run's boundary by itself.
            guard words[index].text.trimmingCharacters(in: .whitespaces) == "♪" else {
                kept.append(words[index])
                index += 1
                continue
            }

            var cursor = index + 1
            var lastNote = index
            while cursor < words.count {
                let token = words[cursor].text.trimmingCharacters(in: .whitespaces)
                if token == "♪" {
                    lastNote = cursor
                    cursor += 1
                } else if !token.isEmpty && token.allSatisfy(\.isLetter) {
                    cursor += 1
                } else {
                    break
                }
            }
            if lastNote > index {
                index = lastNote + 1
            } else {
                kept.append(words[index])
                index += 1
            }
        }
        return kept
    }

    /// Removes standalone non-speech markers. See `Docs/silence.md`.
    static func cleaned(_ text: String) -> String {
        let withoutSpeaker = removingSpeakerPrefix(from: text)
        var result: [Substring] = []
        var remainder = Substring(withoutSpeaker)

        while let open = remainder.firstIndex(where: { $0 == "[" || $0 == "(" || $0 == "*" }) {
            if remainder[open] == "*" {
                let runEnd = remainder[open...].prefix(while: { $0 == "*" }).endIndex
                let runLength = remainder.distance(from: open, to: runEnd)
                if runLength >= 3 {
                    let before = remainder[..<open].last
                    let after = runEnd < remainder.endIndex ? remainder[runEnd] : nil
                    let standsAlone =
                        (before == nil || before?.isWhitespace == true)
                        && (after == nil || after?.isWhitespace == true || after?.isPunctuation == true)
                    result.append(remainder[..<open])
                    if !standsAlone { result.append(remainder[open..<runEnd]) }
                    remainder = remainder[runEnd...]
                    continue
                }
            }
            let closer: Character = remainder[open] == "[" ? "]" : remainder[open] == "(" ? ")" : "*"
            guard let close = remainder[remainder.index(after: open)...].firstIndex(of: closer) else { break }

            let before = remainder[..<open].last
            let after =
                remainder.index(after: close) < remainder.endIndex
                ? remainder[remainder.index(after: close)] : nil
            let standsAlone =
                (before == nil || before?.isWhitespace == true)
                && (after == nil || after?.isWhitespace == true || after?.isPunctuation == true)

            let inside = remainder[remainder.index(after: open)..<close]
            let looksLikeAMarker = standsAlone && (isMarker(inside) || isMusicMarker(inside))

            result.append(remainder[..<open])
            if !looksLikeAMarker {
                result.append(remainder[open...close])
            }
            remainder = remainder[remainder.index(after: close)...]
        }
        result.append(remainder)

        return removingMusicRuns(result.joined())
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
            .trimmingWhitespace()
    }

    /// Removes a leading `>>` speaker caption and its separating whitespace.
    private static func removingSpeakerPrefix(from text: String) -> String {
        let leadingTrimmed = text.drop(while: \.isWhitespace)
        guard leadingTrimmed.hasPrefix(">>") else { return text }
        let spoken = leadingTrimmed.dropFirst(2)
        guard spoken.first.map({ $0.isWhitespace }) ?? true else { return text }
        return String(spoken.drop(while: \.isWhitespace))
    }
}

extension RawSegment {
    fileprivate func transcriptionSegment(shiftedBy offset: Duration) -> TranscriptionSegment {
        // An empty list falls back to the segment's text; Whisper's leading space on each word is trimmed.
        let spoken = words.flatMap { $0.isEmpty ? nil : $0 }?.map {
            TranscribedWord(
                text: $0.text.trimmingCharacters(in: .whitespaces),
                confidence: $0.probability, start: .seconds($0.start) + offset,
                end: .seconds($0.end) + offset)
        }
        let kept = spoken.map(RawTranscript.cleaned)
        return TranscriptionSegment(
            // Derived from the words wherever the recogniser reported them, so a removal reaches both.
            text: kept.map { $0.map(\.text).joined(separator: " ") } ?? RawTranscript.cleaned(text),
            start: .seconds(start) + offset,
            end: .seconds(end) + offset,
            words: kept ?? []
        )
    }
}

extension String {
    /// Foundation-free whitespace trim, so this module stays as testable as the core.
    fileprivate func trimmingWhitespace() -> String {
        String(drop(while: \.isWhitespace).reversed().drop(while: \.isWhitespace).reversed())
    }
}
