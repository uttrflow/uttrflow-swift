public import UttrflowCore

extension RawTranscript {
    /// Turns a recogniser's raw output into the product's ``Transcription``.
    ///
    /// Pure, and shared by every backend, so the rules below hold no matter which
    /// recogniser produced the text.
    public func transcription(audioDuration: Duration) -> Transcription {
        Transcription(
            text: Self.cleaned(text),
            detectedLanguage: detectedLanguage,
            segments: segments.map(\.transcriptionSegment),
            audioDuration: audioDuration
        )
    }

    private var detectedLanguage: DetectedLanguage? {
        guard let languageIdentifier, let code = LanguageCode(languageIdentifier) else { return nil }
        return DetectedLanguage(code: code, confidence: languageProbability)
    }

    /// Removes the bracketed markers recognisers emit for things that are not speech
    /// — `[BLANK_AUDIO]`, `(music)`, `[ Silence ]`.
    ///
    /// Whisper produces these routinely on a quiet recording, and typing them into
    /// the user's document would be worse than typing nothing. Three conditions have
    /// to hold together, because each alone destroys real dictation:
    ///
    /// - the bracket stands alone, not attached to a word — otherwise `get_user(id)`
    ///   loses its argument, and dictating code is a headline use of this product;
    /// - the contents are only letters — otherwise `[1, 2, 3]` disappears;
    /// - there are at most three words — otherwise a spoken aside in parentheses goes
    ///   with them.
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
    fileprivate var transcriptionSegment: TranscriptionSegment {
        TranscriptionSegment(
            text: RawTranscript.cleaned(text),
            start: .seconds(start),
            end: .seconds(end),
            words: (words ?? []).map {
                // Trimmed because Whisper emits its words with the leading space that
                // joins them, and a token with a space in it is not the word a
                // correction indexes.
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
