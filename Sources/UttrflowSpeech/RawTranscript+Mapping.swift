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
            audioDuration: audioDuration
        )
    }

    private var detectedLanguage: DetectedLanguage? {
        guard let languageIdentifier, let code = LanguageCode(languageIdentifier) else { return nil }
        return DetectedLanguage(code: code, confidence: languageProbability)
    }

    /// Removes bracketed non-speech markers such as `[BLANK_AUDIO]`. See `Docs/silence.md`.
    static func cleaned(_ text: String) -> String {
        var result: [Substring] = []
        var remainder = Substring(text)

        while let open = remainder.firstIndex(where: { $0 == "[" || $0 == "(" }) {
            let closer: Character = remainder[open] == "[" ? "]" : ")"
            guard let close = remainder[open...].firstIndex(of: closer) else { break }

            let before = remainder[..<open].last
            let after =
                remainder.index(after: close) < remainder.endIndex
                ? remainder[remainder.index(after: close)] : nil
            let standsAlone =
                (before == nil || before?.isWhitespace == true)
                && (after == nil || after?.isWhitespace == true || after?.isPunctuation == true)

            let inside = remainder[remainder.index(after: open)..<close]
            let looksLikeAMarker =
                standsAlone
                && !inside.isEmpty
                && inside.allSatisfy { $0.isLetter || $0.isWhitespace || $0 == "_" || $0 == "-" }
                && inside.split(whereSeparator: \.isWhitespace).count <= 3

            result.append(remainder[..<open])
            if !looksLikeAMarker {
                result.append(remainder[open...close])
            }
            remainder = remainder[remainder.index(after: close)...]
        }
        result.append(remainder)

        return result.joined()
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
            .trimmingWhitespace()
    }
}

extension RawSegment {
    fileprivate func transcriptionSegment(shiftedBy offset: Duration) -> TranscriptionSegment {
        TranscriptionSegment(
            text: RawTranscript.cleaned(text),
            start: .seconds(start) + offset,
            end: .seconds(end) + offset,
            words: (words ?? []).map {
                // Whisper emits a leading space on each word, which no correction indexes.
                TranscribedWord(
                    text: $0.text.trimmingCharacters(in: .whitespaces),
                    confidence: $0.probability)
            }
        )
    }
}

extension String {
    /// Foundation-free whitespace trim, so this module stays as testable as the core.
    fileprivate func trimmingWhitespace() -> String {
        String(drop(while: \.isWhitespace).reversed().drop(while: \.isWhitespace).reversed())
    }
}
