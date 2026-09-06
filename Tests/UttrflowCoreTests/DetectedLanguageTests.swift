// Tests for DetectedLanguage.

import Foundation
import Testing

@testable import UttrflowCore

@Suite("DetectedLanguage")
struct DetectedLanguageTests {
    @Test(
        "clamps engine-reported confidence into 0...1",
        arguments: [
            (1.5, 1.0),
            (-0.2, 0.0),
            (0.42, 0.42),
            (0.0, 0.0),
            (1.0, 1.0),
        ]
    )
    func clampsConfidence(input: Double, expected: Double) {
        #expect(DetectedLanguage(code: .english, confidence: input).confidence == expected)
    }

    @Test(
        "treats a non-finite confidence as no confidence",
        arguments: [Double.nan, .infinity, -.infinity]
    )
    func rejectsNonFiniteConfidence(input: Double) {
        #expect(DetectedLanguage(code: .english, confidence: input).confidence == 0)
    }

    @Test("reports no confidence when the engine gives none, rather than zero")
    func absentConfidence() {
        #expect(DetectedLanguage(code: .english).confidence == nil)
        #expect(DetectedLanguage(code: .english, confidence: nil).confidence == nil)
        #expect(DetectedLanguage(code: .english, confidence: 0).confidence == 0)
    }

    @Test("round-trips through Codable")
    func codableRoundTrip() throws {
        let original = DetectedLanguage(code: .hindi, confidence: 0.8)
        let decoded = try JSONDecoder().decode(
            DetectedLanguage.self,
            from: JSONEncoder().encode(original)
        )
        #expect(decoded == original)
    }
}
