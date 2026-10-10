// Tests the short-utterance class and the four rates it is scored by.
import Testing
import UttrflowCore

@testable import UttrflowEval

@Suite("Short utterances")
struct ShortUtteranceTests {
    private let all = ShortUtterances.all

    @Test("holds at least 60 Latin replies of one to three words with unique ids")
    func shape() {
        #expect(all.count >= 60)
        #expect(Set(all.map(\.id)).count == all.count)
        for utterance in all {
            #expect(
                (1...3).contains(utterance.words.count), "\(utterance.id) has \(utterance.words.count) words")
            #expect(LatinScript.isLatin(utterance.text), "\(utterance.id) is not Latin")
        }
    }

    @Test("covers every kind in English and in Hindi, and the numbers one to ten")
    func coverage() {
        for language in [LanguageCode.english, .hindi] {
            for kind in ShortUtterance.Kind.allCases {
                #expect(
                    all.contains { $0.language == language && $0.kind == kind }, "\(language) lacks \(kind)")
            }
        }
        let numbers = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        #expect(numbers.allSatisfy { word in all.contains { $0.text == word } })
    }

    @Test("buckets clip lengths at the class boundaries")
    func buckets() {
        #expect(ShortUtteranceBucket(seconds: 0.29) == .under300ms)
        #expect(ShortUtteranceBucket(seconds: 0.3) == .to600ms)
        #expect(ShortUtteranceBucket(seconds: 0.6) == .to1s)
        #expect(ShortUtteranceBucket(seconds: 1.0) == .to2s)
        #expect(ShortUtteranceBucket(seconds: 2.0) == .over2s)
        #expect(ShortUtteranceBucket.to600ms < .to1s)
    }

    @Test("scores an exact answer, an invented word, an empty answer and a wrong language apart")
    func scoring() {
        let yes = ShortUtterance("theek hai", .hindi, .affirmative)
        let exact = ShortUtteranceScore(
            said: yes, heard: "Theek hai.", written: "Theek hai.", detected: .hindi)
        #expect(exact.exact && !exact.invented && !exact.empty && !exact.wrongScriptOrLanguage)

        let invented = ShortUtteranceScore(said: yes, heard: "Huh.", written: "Huh.", detected: nil)
        #expect(!invented.exact && invented.invented && !invented.empty)

        let empty = ShortUtteranceScore(said: yes, heard: "", written: "", detected: nil)
        #expect(empty.empty && !empty.invented && !empty.exact)

        let english = ShortUtteranceScore(said: yes, heard: "Okay.", written: "Okay.", detected: .english)
        #expect(english.wrongScriptOrLanguage)

        let devanagari = ShortUtteranceScore(said: yes, heard: "ठीक है", written: "theek hai", detected: nil)
        #expect(devanagari.wrongScriptOrLanguage && devanagari.exact)
    }

    @Test("turns scores into shares of the clips")
    func rates() {
        let said = ShortUtterance("yes", .english, .affirmative)
        let rates = ShortUtteranceRates([
            .init(said: said, heard: "Yes.", written: "Yes.", detected: .english),
            .init(said: said, heard: "", written: "", detected: nil),
        ])
        #expect(rates.clips == 2 && rates.exact == 1 && rates.empty == 1)
        #expect(rates.percent(rates.exact) == 50)
        #expect(ShortUtteranceRates([]).percent(0) == 0)
    }
}
