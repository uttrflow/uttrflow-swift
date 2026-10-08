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

    /// The same speech with the dictionary's spellings in it, settled, and every word keeping the score it was heard with.
    func saying(_ corrected: CorrectedTranscript) -> Transcription {
        guard corrected.text != text || !corrected.held.isEmpty else { return self }
        let heard = Draft(transcription: self)
        guard EvidencePolicy.unscored(heard, in: .dictionarySpellings) == nil else {
            return saying(corrected.text)
        }
        // A run the corrector weighed and kept is settled as heard, so no later layer reads it as half-heard.
        let settled = Set(corrected.held.flatMap { $0 })
        func standing(_ index: Int) -> TranscribedWord {
            let word = heard.words[index]
            return settled.contains(index)
                ? TranscribedWord(text: word.text, confidence: 1, start: word.start, end: word.end)
                : word.scored
        }

        var scored: [TranscribedWord] = []
        var next = 0
        for correction in corrected.corrections.sorted(by: {
            $0.wordRange.lowerBound < $1.wordRange.lowerBound
        }) {
            let range = correction.wordRange
            guard range.lowerBound >= next, range.upperBound <= heard.words.count else {
                return saying(corrected.text)
            }
            scored += (next..<range.lowerBound).map(standing)
            // Keep the recogniser's score and audio span while marking the dictionary reading final.
            let replaced = heard.words[range]
            scored += correction.wrote.split(whereSeparator: \.isWhitespace).map {
                TranscribedWord(
                    text: String($0), confidence: correction.heardConfidence, settled: true,
                    start: replaced.first?.start, end: replaced.last?.end)
            }
            next = range.upperBound
        }
        scored += (next..<heard.words.count).map(standing)

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
