// The string and transcription helpers the pipeline's stages share.
import UttrflowAI
import UttrflowCore

extension String {
    /// Whether the string contains only whitespace.
    var isBlank: Bool { allSatisfy(\.isWhitespace) }

    /// Whether any letter or digit can be inserted in place of the user's selection.
    var hasRecognisableContent: Bool { contains { $0.isLetter || $0.isNumber } }
}

extension Transcription {
    /// The same recognised speech, with different words in it and the same timings.
    func saying(_ text: String) -> Transcription {
        guard text != self.text else { return self }
        return Transcription(
            text: text, detectedLanguage: detectedLanguage, segments: segments,
            audioDuration: audioDuration)
    }

    /// The same speech with the dictionary's spellings in it, every other word keeping the score it was heard with.
    func saying(_ corrected: CorrectedTranscript) -> Transcription {
        guard corrected.text != text else { return self }
        let heard = Draft(transcription: self)
        guard heard.confidencesAreReal else { return saying(corrected.text) }

        var scored: [TranscribedWord] = []
        var next = 0
        for correction in corrected.corrections.sorted(by: {
            $0.wordRange.lowerBound < $1.wordRange.lowerBound
        }) {
            let range = correction.wordRange
            guard range.lowerBound >= next, range.upperBound <= heard.words.count else {
                return saying(corrected.text)
            }
            scored += heard.words[next..<range.lowerBound].map(\.scored)
            // Settled by the dictionary, so never half-heard; heard over the replaced words' span.
            let replaced = heard.words[range]
            scored += correction.wrote.split(whereSeparator: \.isWhitespace).map {
                TranscribedWord(
                    text: String($0), confidence: 1, start: replaced.first?.start, end: replaced.last?.end)
            }
            next = range.upperBound
        }
        scored += heard.words[next...].map(\.scored)

        // The words have to spell the text, or the confidences would be read onto the wrong ones.
        let spelling = corrected.text.split(whereSeparator: \.isWhitespace).joined()
        guard scored.map(\.text).joined() == spelling else { return saying(corrected.text) }
        return Transcription(
            text: corrected.text, detectedLanguage: detectedLanguage,
            segments: [
                TranscriptionSegment(
                    text: corrected.text, start: .zero, end: audioDuration, words: scored)
            ],
            audioDuration: audioDuration)
    }
}

extension Draft.Word {
    /// The word as the recogniser reported it, so a rebuilt transcription can carry its score.
    fileprivate var scored: TranscribedWord {
        TranscribedWord(text: text, confidence: confidence, start: start, end: end)
    }
}
