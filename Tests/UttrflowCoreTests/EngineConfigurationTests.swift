// Tests for EngineConfiguration and for which engine kinds a build can select.

import Foundation
import Testing

@testable import UttrflowCore

@Suite("EngineConfiguration")
struct EngineConfigurationTests {
    @Test("ships defaulting to Whisper with Apple's model preferred for clean-up")
    func defaultConfiguration() {
        let configuration = EngineConfiguration.default

        #expect(configuration.speech == .whisperKit)
        #expect(configuration.transformerPreference == [.localModel, .foundationModels, .rules])
    }

    @Test("ends its default preference list in a transformer that can never decline")
    func defaultPreferenceHasAGuaranteedFloor() {
        #expect(EngineConfiguration.default.transformerPreference.last == .rules)
    }

    @Test("switching clean-up engines is a change to this value alone")
    func switchingEngines() {
        var configuration = EngineConfiguration.default
        configuration.transformerPreference = [.foundationModels, .rules]

        #expect(configuration.speech == .whisperKit)
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
    @Test("never offers the retired hosted engine")
    func cloudIsNeverSelectable() {
        #expect(!TransformerKind.selectable.contains(.cloud))
    }

    /// No build ever wrote it, but a record or preference naming it by hand must still load.
    @Test("a stored record naming the retired hosted engine still decodes")
    func cloudStillDecodes() throws {
        let json = Data(#"{"speech":"whisperKit","transformerPreference":["cloud","rules"]}"#.utf8)
        let decoded = try JSONDecoder().decode(EngineConfiguration.self, from: json)
        #expect(decoded.transformerPreference == [.cloud, .rules])
        #expect(decoded.resolvedTransformerPreference == [.rules])
    }

    /// The app hands the loaded model in as a `CleanupModel`, so the local model leads, then Apple's, then rules.
    @Test("offers the local model first, then Apple's model, then the rules")
    func localModelLeadsSelectable() {
        #expect(TransformerKind.selectable == [.localModel, .foundationModels, .rules])
    }

    /// The floor has to be there whatever a build contains; it is what stops the pipeline dead-ending.
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
