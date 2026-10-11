import Foundation
import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowDictionary
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

@Suite("A notation command cut by a pause reads as it does said whole")
struct SeamNotationSweepTests {
    private let pipeline: DictationPipeline = {
        let router = TransformerRouter(engines: [RuleBasedTransformer()], preference: [.rules])
        return DictationPipeline(
            capture: FakeAudioCaptureEngine(), speech: FakeSpeechEngine(), cleaner: router,
            context: FakeContextEngine(), inserter: FakeTextInserter(),
            corrector: DictionaryCorrections { _ in PhoneticIndex(entries: []) })
    }()

    private let code = AppContext(
        applicationName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode", documentName: "Example.swift",
        precedingText: "")

    /// One invented sentence per command family: casing, symbol pair, quoted value, number.
    static let sentences = [
        "let camel case retry count equals forty two",
        "pascal case order total open paren close paren",
        "snake case greeting equals open quote hello there close quote",
        "kebab case item list open bracket zero close bracket",
        "return screaming snake case max size plus one hundred twenty eight",
    ]

    @Test("every single cut of a command sentence in code matches the whole", arguments: sentences)
    func everyCut(sentence: String) async {
        let words = sentence.split(separator: " ").map(String.init)
        let whole = await written([sentence])
        #expect(whole != sentence, "the whole sentence is read as a command: \(whole ?? "")")
        for cut in 1..<words.count {
            let pieces = [words[..<cut].joined(separator: " "), words[cut...].joined(separator: " ")]
            let text = await written(pieces)
            let cutAt = pieces.joined(separator: " | ")
            #expect(text == whole, "cut \(cutAt) wrote \(text ?? "") not \(whole ?? "")")
        }
    }

    @Test("a 300-word dictation in pieces is joined within a stated cost")
    func threeHundredWordsCost() async {
        let sentence = "let camel case retry count equals forty two and then snake case max size plus one"
        let piece = Array(repeating: sentence, count: 2).joined(separator: " and ")
        let pieces = Array(repeating: piece, count: 10).map { Transcription(text: $0) }
        #expect(pieces.reduce(0) { $0 + $1.text.split(separator: " ").count } >= 300)
        var seconds: [Double] = []
        for _ in 0..<20 {
            let start = ContinuousClock.now
            _ = await pipeline.clean(pieces, seeing: code)
            seconds.append((ContinuousClock.now - start) / .seconds(1))
        }
        seconds.sort()
        let p95 = seconds[Int(Double(seconds.count - 1) * 0.95)]
        #expect(p95 < 5)
    }

    private func written(_ pieces: [String]) async -> String? {
        await pipeline.clean(pieces.map { Transcription(text: $0) }, seeing: code).text
    }
}
