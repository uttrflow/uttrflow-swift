import Foundation
import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowDictionary

/// A brand or app name the recogniser writes in Devanagari inside a Hindi sentence comes back in its English spelling when the lexicon or the person's dictionary holds it. See `Docs/latin-output.md`.
@Suite("Brand restoration")
struct BrandRestorationTests {
    /// Invented brand names in the person's dictionary, each as a recogniser writes it in Devanagari.
    static let personalBrands: [(String, String)] = [
        ("ओरवांटा", "Orvanta"), ("ज़ेलकोरा", "Zelkora"), ("मिरोवा", "Mirova"), ("ब्रिक्सन", "Brixon"),
        ("टैलोरा", "Talora"), ("क्विनटेक", "Quintek"), ("वेलमार्क", "Velmark"), ("डोरानो", "Dorano"),
        ("फ्लिंटो", "Flinto"), ("कैस्पेरो", "Caspero"),
    ]

    /// Tool names the shipped lexicon holds, as a recogniser writes them in Devanagari.
    static let lexiconBrands: [(String, String)] = [
        ("पाइथन", "Python"), ("कोटलिन", "Kotlin"), ("कुबरनेटीस", "Kubernetes"), ("जुपिटर", "Jupyter"),
        ("ग्रेडल", "Gradle"), ("मेवन", "Maven"), ("होमब्रू", "Homebrew"), ("लिनक्स", "Linux"),
        ("डेबियन", "Debian"), ("एलिक्सिर", "Elixir"),
    ]

    /// Invented names in neither source, which stay as the romaniser spells them.
    static let unknownBrands: [String] = [
        "नोवेरिक", "ज़ार्मिन", "पेलोक्स", "ट्रेविना", "कोरबिट", "लुमेन्ज़ा", "वाक्स्टर", "सिल्वोरा", "बेंट्रिक", "हेलिमो",
    ]

    /// A Hindi sentence around a name, as the recogniser writes it.
    static func sentence(_ name: String) -> String { "ये फ़ोटो \(name) पर भेज दो" }

    /// The rules engine's output for one sentence, with `personal` as the person's dictionary.
    static func cleaned(_ spoken: String, personal: [String]) async throws -> String {
        let request = TransformationRequest(transcription: Transcription(text: spoken), vocabulary: personal)
        return try await RuleBasedTransformer().transform(request).text
    }

    /// The words of a text, lowercased, punctuation dropped.
    static func words(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
    }

    /// Every name written in English is the right one, and at least the measured share of names is restored.
    @Test func restoresNamesFromTheDictionaryAndTheLexicon() async throws {
        let personal = Self.personalBrands.map(\.1)
        var restored = 0
        var wrong: [String] = []
        for (devanagari, english) in Self.personalBrands + Self.lexiconBrands {
            let text = try await Self.cleaned(Self.sentence(devanagari), personal: personal)
            let sources = Set((personal + TechnicalLexicon.terms.map(\.id)).map { $0.lowercased() })
            let names = Self.words(text).filter { sources.contains($0) }
            if text.contains(english) { restored += 1 } else if !names.isEmpty { wrong.append(text) }
            #expect(!text.unicodeScalars.contains { (0x0900...0x097F).contains($0.value) })
        }
        print("BRANDS restored \(restored) of 20, wrong \(wrong)")
        #expect(wrong.isEmpty)
        #expect(restored >= 15)
    }

    @Test func leavesNamesInNeitherSourceAsSpoken() async throws {
        let personal = Self.personalBrands.map(\.1)
        for devanagari in Self.unknownBrands {
            let spoken = Romaniser.romanised(devanagari).lowercased()
            let text = try await Self.cleaned(Self.sentence(devanagari), personal: personal)
            #expect(Self.words(text).contains(spoken), "\(devanagari): \(text)")
        }
    }

    @Test func restoresNoHindiWordWithBrandsInTheDictionary() {
        let restoration = LoanwordRestoration(personal: Self.personalBrands.map(\.1))
        let wrong = LoanwordRestorationProbeTests.hindiWords.compactMap { devanagari -> String? in
            let romanised = Romaniser.romanised(devanagari).lowercased()
            return restoration.restored(romanised).map { "\(romanised)->\($0)" }
        }
        #expect(wrong.isEmpty, "\(wrong)")
    }
}
