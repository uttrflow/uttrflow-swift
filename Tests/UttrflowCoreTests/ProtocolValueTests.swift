import Foundation
import Testing

@testable import UttrflowCore

@Suite("TranscriptionOptions")
struct TranscriptionOptionsTests {
    @Test("defaults to detecting the language, which is what mixed speech needs")
    func automaticDetectsLanguage() {
        #expect(TranscriptionOptions.automatic.languageHint == nil)
        #expect(TranscriptionOptions() == .automatic)
    }

    @Test("carries a language hint when the caller wants to bias the engine")
    func carriesLanguageHint() {
        let options = TranscriptionOptions(languageHint: .hindi)
        #expect(options.languageHint == .hindi)
        #expect(options != .automatic)
        #expect(options == TranscriptionOptions(languageHint: .hindi))
    }
}

@Suite("Protocol value types")
struct ProtocolValueTypeTests {
    @Test("distinguishes recording from idle")
    func captureStates() {
        #expect(AudioCaptureState.idle != AudioCaptureState.recording)
    }

    @Test("names every insertion outcome and round-trips them")
    func insertionMethods() throws {
        #expect(TextInsertionMethod.allCases.count == 4)
        for method in TextInsertionMethod.allCases {
            let decoded = try JSONDecoder().decode(
                TextInsertionMethod.self,
                from: JSONEncoder().encode(method)
            )
            #expect(decoded == method)
        }
    }

    @Test("names every pipeline stage and round-trips them")
    func pipelineStages() throws {
        // In the order the journey runs, which is the order every report draws them in.
        #expect(
            PipelineStage.allCases == [
                .capture, .transcription, .correction, .transformation, .expansion, .insertion,
            ])
        for stage in PipelineStage.allCases {
            let decoded = try JSONDecoder().decode(
                PipelineStage.self,
                from: JSONEncoder().encode(stage)
            )
            #expect(decoded == stage)
        }
    }
}

@Suite("PCM sample conversion")
struct PCMConversionTests {
    @Test(
        "scales a normalised sample across the full 16-bit range",
        arguments: [(0, 0), (1.0, Int16.max), (-1.0, -Int16.max), (0.5, 16_384), (-0.5, -16_384)]
            as [(Float, Int16)]
    )
    func scales(input: Float, expected: Int16) {
        #expect(Int16(clampingAudioSample: input) == expected)
    }

    /// Resampling routinely nudges a sample just past the limit; wrapping would turn
    /// a loud moment into a loud click.
    @Test("clamps rather than wrapping", arguments: [Float(1.4), -1.4, 40, -40])
    func clamps(input: Float) {
        #expect(Int16(clampingAudioSample: input) == (input > 0 ? Int16.max : Int16.min))
    }

    @Test("reads a non-finite sample as silence", arguments: [Float.nan, .infinity, -.infinity])
    func nonFinite(input: Float) {
        #expect(Int16(clampingAudioSample: input) == 0)
    }
}
