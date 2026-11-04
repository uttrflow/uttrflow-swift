// Tests that word boundaries take the pause the audio holds, not the one the word times show.
import Foundation
import Testing

@testable import UttrflowCore
@testable import UttrflowSpeech

@Suite("PauseSnapping")
struct PauseSnappingTests {
    private let rate = AudioSamples.canonicalSampleRate

    /// Speech-like tone for `seconds`, or digital silence when `loud` is false.
    private func stretch(_ seconds: Double, loud: Bool) -> [Float] {
        let count = Int(Double(rate) * seconds)
        guard loud else { return [Float](repeating: 0, count: count) }
        return (0..<count).map { (index: Int) -> Float in 0.1 * Float(sin(Double(index) * 0.07)) }
    }

    private func audio(_ stretches: [(Double, Bool)]) -> AudioSamples {
        .canonical(stretches.flatMap { stretch($0.0, loud: $0.1) })
    }

    private func word(_ text: String, _ start: Double, _ end: Double) -> TranscribedWord {
        TranscribedWord(text: text, confidence: 1, start: .seconds(start), end: .seconds(end))
    }

    private func transcription(_ words: [TranscribedWord]) -> Transcription {
        Transcription(
            text: words.map(\.text).joined(separator: " "),
            segments: [TranscriptionSegment(text: "", start: .zero, end: .seconds(10), words: words)])
    }

    private func gap(_ result: Transcription, after index: Int) -> Duration? {
        let words = result.segments[0].words
        guard let end = words[index].end, let start = words[index + 1].start else { return nil }
        return start - end
    }

    @Test("a pause the word times swallowed is the length the audio holds")
    func swallowedPauseIsMeasured() {
        let heard = transcription([word("one", 0, 1.0), word("two", 1.0, 2.4)])
        let sound = audio([(1.0, true), (0.6, false), (0.8, true)])

        let result = PauseSnapping.snapped(heard, to: sound, startingAt: .zero)

        let measured = gap(result, after: 0) ?? .zero
        #expect(measured >= .milliseconds(560) && measured <= .milliseconds(640))
    }

    @Test("a pause is placed after the offset the audio started at")
    func offsetShiftsPause() {
        let heard = transcription([word("one", 2.0, 3.0), word("two", 3.0, 4.4)])
        let sound = audio([(1.0, true), (0.6, false), (0.8, true)])

        let result = PauseSnapping.snapped(heard, to: sound, startingAt: .seconds(2))

        #expect((gap(result, after: 0) ?? .zero) >= .milliseconds(560))
    }

    @Test("a pause the word times invented is taken away when the audio is loud under it")
    func inventedPauseIsRemoved() {
        let heard = transcription([word("one", 0, 1.0), word("two", 1.5, 2.0), word("three", 3.1, 3.5)])
        let sound = audio([(2.0, true), (0.6, false), (1.0, true)])

        let result = PauseSnapping.snapped(heard, to: sound, startingAt: .zero)

        #expect(gap(result, after: 0) == .zero)
        #expect((gap(result, after: 1) ?? .zero) >= .milliseconds(500))
    }

    @Test("audio with no quiet run leaves the word times as heard")
    func noQuietLeavesTimesAlone() {
        let heard = transcription([word("one", 0, 1.0), word("two", 1.5, 2.0)])

        let result = PauseSnapping.snapped(heard, to: audio([(2.0, true)]), startingAt: .zero)

        #expect(result == heard)
    }

    @Test("untimed words are left alone")
    func untimedWordsAreLeftAlone() {
        let heard = transcription([TranscribedWord(text: "one", confidence: 1), word("two", 1.0, 2.0)])

        let result = PauseSnapping.snapped(
            heard, to: audio([(1.0, true), (0.5, false), (1.0, true)]), startingAt: .zero)

        #expect(result == heard)
    }

    @Test("the engine hands on the pause the audio holds")
    func engineSnapsPauses() async throws {
        let words = [
            RawWord(text: " one", start: 0, end: 1.0, probability: 0.9),
            RawWord(text: " two", start: 1.0, end: 2.6, probability: 0.9),
        ]
        let raw = RawTranscript(
            text: "one two",
            segments: [RawSegment(text: " one two", start: 0, end: 2.6, words: words)])
        let engine = BackedSpeechEngine(kind: .whisperKit, backend: FakeTranscriptionBackend(result: raw))

        let heard = try await engine.transcribe(
            audio([(1.0, true), (0.6, false), (1.0, true)]), options: .automatic)

        #expect((gap(heard, after: 0) ?? .zero) >= .milliseconds(500))
    }
}
