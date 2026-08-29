import Foundation
import Testing

@testable import UttrflowCore

@Suite("EngineConfiguration")
struct EngineConfigurationTests {
    @Test("ships defaulting to Whisper with Apple's model preferred for clean-up")
    func defaultConfiguration() {
        let configuration = EngineConfiguration.default

        #expect(configuration.speech == .whisperKit)
        #expect(configuration.transformerPreference == [.foundationModels, .localModel, .rules])
    }

    @Test("ends its default preference list in a transformer that can never decline")
    func defaultPreferenceHasAGuaranteedFloor() {
        #expect(EngineConfiguration.default.transformerPreference.last == .rules)
    }

    @Test("switching engine is a change to this value alone")
    func switchingEngines() {
        var configuration = EngineConfiguration.default
        configuration.speech = .appleSpeech
        configuration.transformerPreference = [.foundationModels, .rules]

        #expect(configuration.speech == .appleSpeech)
        #expect(configuration.resolvedTransformerPreference == [.foundationModels, .rules])
    }

    @Test("drops transformers this build does not contain, preserving order")
    func resolvedPreferenceFiltersUnselectableKinds() {
        let configuration = EngineConfiguration(
            speech: .whisperKit,
            transformerPreference: [.cloud, .foundationModels, .rules]
        )
        let selectable = Set(TransformerKind.selectable)

        #expect(configuration.resolvedTransformerPreference.allSatisfy(selectable.contains))
        #expect(configuration.resolvedTransformerPreference.last == .rules)
    }

    @Test("resolves to nothing when every preferred transformer is unavailable")
    func resolvedPreferenceCanBeEmpty() {
        let configuration = EngineConfiguration(speech: .whisperKit, transformerPreference: [])
        #expect(configuration.resolvedTransformerPreference.isEmpty)
    }

    @Test("round-trips through Codable so a saved preference survives relaunch")
    func codableRoundTrip() throws {
        let original = EngineConfiguration.default
        let decoded = try JSONDecoder().decode(
            EngineConfiguration.self,
            from: JSONEncoder().encode(original)
        )
        #expect(decoded == original)
    }
}

@Suite("Engine kinds")
struct EngineKindsTests {
    @Test("excludes the cloud transformer from a build without cloud support")
    func cloudIsNotSelectableByDefault() {
        #if UTTRFLOW_CLOUD
            #expect(TransformerKind.selectable.contains(.cloud))
        #else
            #expect(!TransformerKind.selectable.contains(.cloud))
        #endif
    }

    /// The local model links MLX, which the app deliberately does not build against, so
    /// a build that does not contain it must not offer it. It was being offered: it sat
    /// in the shipping preference and in the diagnostics list, and the router dropped it
    /// silently at routing time — the configuration said one thing, the product did
    /// another.
    @Test("excludes the local model from a build that does not link it")
    func localModelIsNotSelectableByDefault() {
        #if UTTRFLOW_LOCAL_MODEL
            #expect(TransformerKind.selectable.contains(.localModel))
        #else
            #expect(!TransformerKind.selectable.contains(.localModel))
        #endif
    }

    /// Whatever a build does or does not contain, the floor has to be there — it is what
    /// stops the pipeline dead-ending.
    @Test("always keeps the engines every build contains")
    func alwaysSelectableKinds() {
        let selectable = Set(TransformerKind.selectable)
        #expect(selectable.contains(.rules))
        #expect(selectable.contains(.foundationModels))
    }

    @Test("round-trips every engine kind through Codable")
    func kindsAreCodable() throws {
        for kind in TransformerKind.allCases {
            let decoded = try JSONDecoder().decode(
                TransformerKind.self,
                from: JSONEncoder().encode(kind)
            )
            #expect(decoded == kind)
        }
        for kind in SpeechEngineKind.allCases {
            let decoded = try JSONDecoder().decode(
                SpeechEngineKind.self,
                from: JSONEncoder().encode(kind)
            )
            #expect(decoded == kind)
        }
    }
}
