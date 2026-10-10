// The guided read: one fixed passage, and what a single reading of it measures about the speaker. See `Docs/eval-methodology.md`.
package import UttrflowCore

/// What one reading of the guided passage says about the speaker, measured from the recogniser's timed words alone.
package struct GuidedRead: Sendable, Equatable {
    /// The invented passage read aloud, holding everyday words and terms from the technical lexicon.
    package static let passage = """
        Before lunch I opened the terminal and ran grep over the logs, then piped the result through sed \
        and awk to keep only the slow requests. The API answered in time, but the DNS lookup behind it took \
        far longer than the week before. I wrote the numbers into a CSV file, checked them twice, and sent \
        the summary to the team as a PDF. After that I logged in over SSH, read the config, and found a cron \
        job that had been running every minute instead of every hour. Fixing it was one line. I moved the old \
        file with mv, made a new folder with mkdir, and pushed the change with git. Then I wrote a short regex \
        to catch the same mistake in the other repo, and a test with pytest so it would not come back. By the \
        evening the CPU was quiet again, the queue was empty, and the page loaded before I could finish \
        reading this sentence aloud.
        """

    /// Words spoken per minute, from the first timed word's start to the last one's end; nil without two timed words.
    package let wordsPerMinute: Double?
    /// The median gap between two words of one sentence, in seconds; nil when no gap was timed.
    package let medianPause: Double?
    /// The 90th-percentile gap between two words of one sentence, in seconds; nil when no gap was timed.
    package let longPause: Double?
    /// The median recogniser confidence over every word heard; nil when nothing was heard.
    package let medianConfidence: Double?
    /// The passage's words written as one technical-lexicon term, normalised, in the order read.
    package let targets: [String]
    /// The targets that did not come out as read, in the order read.
    package let missedTargets: [String]

    /// The pause setting whose sentence pause the speaker's long mid-sentence gap stays under; nil when no gap was timed.
    package var pauses: PauseLength? {
        guard let longPause else { return nil }
        return PauseLength.allCases.first {
            longPause < SpeechWindowing.standard.adjusted(for: $0).sentencePause
        }
            ?? .veryLong
    }

    /// Measures one reading of `reference` from the words the recogniser heard, in order.
    package static func measure(
        _ heard: [TranscribedWord], reading reference: String = passage
    ) -> GuidedRead {
        let read = TextNormaliser.standard.words(reference)
        let scored = heard.flatMap { word in
            TextNormaliser.standard.words(word.text).map { (word: $0, score: word.confidence) }
        }
        // A term whose written form normalises into several words (`I/O`, `and/or`) is no single word to look for.
        let lexicon = Set(
            TechnicalLexicon.terms.map { $0.id.lowercased() }.filter {
                TextNormaliser.standard.words($0) == [$0]
            })
        let positions = read.indices.filter { lexicon.contains(read[$0]) }
        let missed = positions.filter {
            HomophoneConfidence.outcome(reference: read, index: $0, heard: scored).isError
        }
        let gaps = sentenceGaps(heard)
        return GuidedRead(
            wordsPerMinute: rate(heard), medianPause: HomophoneConfidence.median(gaps),
            longPause: FinalPiece.percentile(gaps, 0.9),
            medianConfidence: HomophoneConfidence.median(heard.map(\.confidence)),
            targets: positions.map { read[$0] }, missedTargets: missed.map { read[$0] })
    }

    /// Silence between consecutive timed words, leaving out the gap after a word that closes a sentence.
    private static func sentenceGaps(_ heard: [TranscribedWord]) -> [Double] {
        zip(heard, heard.dropFirst()).compactMap { before, after in
            guard let end = before.end, let start = after.start,
                !before.text.hasSuffix("."), !before.text.hasSuffix("?"), !before.text.hasSuffix("!")
            else { return nil }
            return Swift.max(0, (start - end).inSeconds)
        }
    }

    private static func rate(_ heard: [TranscribedWord]) -> Double? {
        guard let start = heard.first(where: { $0.start != nil })?.start,
            let end = heard.last(where: { $0.end != nil })?.end, heard.count >= 2
        else { return nil }
        let minutes = (end - start).inSeconds / 60
        return minutes > 0 ? Double(heard.count) / minutes : nil
    }
}
