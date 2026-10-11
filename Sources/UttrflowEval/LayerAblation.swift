// Each default-on layer switched off over the stored decodes of the test side, paired against the full chain.
package import Foundation
package import UttrflowCore
import UttrflowPipeline

/// The per-layer ablation on recorded decode dumps. See `Docs/dictation-quality.md`.
package struct LayerAblation: Sendable, Equatable {
    /// Why the ablation could not run.
    package enum Refusal: Error, Equatable, CustomStringConvertible {
        case unreadable(String)
        case nothingToMeasure

        package var description: String {
            switch self {
            case .unreadable(let reason): reason
            case .nothingToMeasure:
                "No English test-side recording has a kept decode here. Run: uttrflow-eval transcribe"
            }
        }
    }

    /// The recordings measured, one per audio, each with its first kept decode.
    package let recordings: Int
    /// Each default-on layer off alone against the full chain, in declaration order.
    package let contributions: [LayerContribution]

    /// The layers switched off, one run each.
    package static var paths: [[QualityLayer]] {
        QualityLayers.degradedPaths.filter { $0.count == 1 }
    }

    /// The English test-side recordings with a kept decode, each as its decode and the passage it read.
    package static func subjects(
        of recorded: [RecordedPassage], decoded dumps: [DecodeDump]
    ) -> [DegradedPathMatrix.Subject] {
        var first: [String: DecodeDump] = [:]
        for dump in dumps where first[dump.recordingIdentity] == nil { first[dump.recordingIdentity] = dump }
        return recorded.compactMap { recording in
            let passage = recording.passage
            guard passage.language == .english, passage.split == .test,
                let identity = recording.recordingIdentity, let dump = first[identity]
            else { return nil }
            let heard = dump.transcription
            return DegradedPathMatrix.Subject(
                testCase: EvaluationCase(
                    id: recording.id, category: .everyday, spoken: heard.text, expected: passage.romanised),
                heard: heard)
        }
    }

    /// Runs `subjects` through the full chain and then with each default-on layer off.
    package static func measure(
        _ subjects: [DegradedPathMatrix.Subject], cleaner: any TranscriptCleaning,
        building: @escaping DegradedPathMatrix.Building
    ) async -> LayerAblation {
        let matrix = await DegradedPathMatrix.measure(
            subjects, on: paths, cleaner: cleaner, building: building)
        return LayerAblation(recordings: subjects.count, contributions: matrix.contributions)
    }

    /// The report: how many recordings it rests on, then the table `Docs/degraded-path-matrix.md` holds.
    package var report: String {
        [
            "Per-layer ablation on \(recordings) English test-side recordings, from their kept decodes.", "",
            DegradedPathMatrix.contributionSection(contributions, latency: false),
        ].joined(separator: "\n") + "\n"
    }

    /// Reads the corpus at `directory` and its kept decodes, and reports each layer's contribution.
    package static func report(
        corpus directory: URL, engineVersion: String?, cleaner: any TranscriptCleaning
    ) async throws(Refusal) -> String {
        let recorded: [RecordedPassage]
        let dumps: [DecodeDump]
        do {
            recorded = try TranscriptionCorpusStore(directory: directory).all()
            dumps = try DecodeDumpStore(corpusDirectory: directory).dumps(engineVersion: engineVersion)
        } catch let error as DecodeDumpError {
            throw .unreadable(error.description)
        } catch {
            throw .unreadable("\(error)")
        }
        let subjects = subjects(of: recorded, decoded: dumps)
        guard !subjects.isEmpty else { throw .nothingToMeasure }
        return await measure(subjects, cleaner: cleaner, building: recordedChain).report
    }

    /// A pipeline with no microphone, recogniser, screen or field behind it, so only the layers under test act.
    package static let recordedChain: DegradedPathMatrix.Building = {
        layers, corrector, speechWords, cleaner in
        DictationPipeline(
            capture: NoMicrophone(), speech: NoRecogniser(), cleaner: cleaner, context: NoScreen(),
            inserter: NoField(), speechWords: speechWords, corrector: corrector, layers: layers)
    }
}

private struct NoMicrophone: AudioCaptureEngine {
    var state: AudioCaptureState { .idle }
    func start() async throws(AudioCaptureError) { throw .notRecording }
    func stop() async throws(AudioCaptureError) -> AudioSamples { throw .notRecording }
    func cancel() async {}
    func cancelKeepingRecording() async {}
    func capturedSoFar() async -> AudioSamples { .empty }
}

private struct NoRecogniser: SpeechEngine {
    let kind = SpeechEngineKind.whisperKit
    func prepare() async throws(SpeechEngineError) {}
    func transcribe(
        _ audio: AudioSamples, options: TranscriptionOptions
    ) async throws(SpeechEngineError)
        -> Transcription
    { Transcription(text: "") }
}

private struct NoScreen: ContextEngine {
    func currentContext() async -> AppContext { .unknown }
}

private struct NoField: TextInserting {
    func insert(_ text: String) async throws(TextInsertionError) -> InsertionAttempt {
        InsertionAttempt(.accessibility)
    }
}
