import Foundation
import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowDictionary
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

/// Words said across a pause, and the message the same words make said as one piece.
struct SeamCut: Sendable, CustomTestStringConvertible {
    let pieces: [String]
    let whole: String

    var testDescription: String { pieces.joined(separator: " | ") }
}

@Suite("A unit said across a pause is read as the one unit it is")
struct SeamRecleaningTests {
    private let pipeline: DictationPipeline = {
        let router = TransformerRouter(engines: [RuleBasedTransformer()], preference: [.rules])
        return DictationPipeline(
            capture: FakeAudioCaptureEngine(), speech: FakeSpeechEngine(), cleaner: router,
            context: FakeContextEngine(), inserter: FakeTextInserter(),
            corrector: DictionaryCorrections { _ in PhoneticIndex(entries: []) })
    }()

    static let markCuts: [SeamCut] = [
        SeamCut(
            pieces: ["send me the file", "question mark and then call me"],
            whole: "send me the file question mark and then call me"),
        SeamCut(
            pieces: ["is it ready question", "mark tell me soon"],
            whole: "is it ready question mark tell me soon"),
        SeamCut(
            pieces: ["she said she would come", "comma but she did not"],
            whole: "she said she would come comma but she did not"),
        SeamCut(
            pieces: ["the report covers january", "comma through march"],
            whole: "the report covers january comma through march"),
    ]

    @Test(
        "a mark name at the head of a piece, or split by the pause, writes what one piece does",
        arguments: markCuts)
    func markAcrossSeam(_ cut: SeamCut) async {
        #expect(await written(cut.pieces) == written([cut.whole]))
    }

    static let unitCuts: [SeamCut] = [
        SeamCut(
            pieces: ["the meeting is at three", "thirty tomorrow"],
            whole: "the meeting is at three thirty tomorrow"),
        SeamCut(
            pieces: ["we sold two thousand", "five hundred units last year"],
            whole: "we sold two thousand five hundred units last year"),
        SeamCut(
            pieces: ["we raised twenty", "five thousand dollars"],
            whole: "we raised twenty five thousand dollars"),
        SeamCut(
            pieces: ["we have one hundred", "twenty people coming"],
            whole: "we have one hundred twenty people coming"),
        SeamCut(pieces: ["the flight is at six", "forty five"], whole: "the flight is at six forty five"),
        SeamCut(
            pieces: ["we met at nine", "a m and left at five"], whole: "we met at nine a m and left at five"),
        SeamCut(
            pieces: ["the plan costs nine", "ninety nine a month"],
            whole: "the plan costs nine ninety nine a month"),
        SeamCut(
            pieces: ["send it to sam at example", "dot com and copy the team"],
            whole: "send it to sam at example dot com and copy the team"),
        SeamCut(
            pieces: ["the site is example dot com", "slash pricing"],
            whole: "the site is example dot com slash pricing"),
        SeamCut(
            pieces: ["the meeting is on march", "third at ten"],
            whole: "the meeting is on march third at ten"),
    ]

    @Test("a number, time or address said across a pause writes what one piece does", arguments: unitCuts)
    func unitAcrossSeam(_ cut: SeamCut) async {
        #expect(await written(cut.pieces) == written([cut.whole]))
    }

    @Test("a number, time or address is read whole at every cut inside it")
    func everyUnitCut() async {
        for (sentence, unit) in [
            ("the meeting is at three thirty tomorrow", "3:30"),
            ("send it to sam at example dot com", "sam@example.com"),
            ("we met at nine a m and left at five", "9 am"),
            ("the meeting is on march third at ten", "March third"),
        ] {
            let words = sentence.split(separator: " ").map(String.init)
            for cut in 1..<words.count {
                let pieces = [words[..<cut].joined(separator: " "), words[cut...].joined(separator: " ")]
                let text = await written(pieces) ?? ""
                #expect(text.contains(unit), "cut at \(cut): \(text)")
            }
        }
    }

    @Test("a mark name is read across a cut at every word boundary")
    func everyCut() async {
        let words = "send me the file question mark and then call me".split(separator: " ").map(String.init)
        for cut in 1..<words.count {
            let pieces = [words[..<cut].joined(separator: " "), words[cut...].joined(separator: " ")]
            let text = await written(pieces) ?? ""
            #expect(
                text.contains("file?") && !text.lowercased().contains("question"), "cut at \(cut): \(text)")
        }
    }

    @Test("a notation command in code is read whole at every cut inside it")
    func everyNotationCut() async {
        let code = AppContext(
            applicationName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode", documentName: "Example.swift",
            precedingText: "let x = ")
        for (sentence, written) in [
            ("camel case user id", "userId"), ("snake case max retries", "max_retries"),
        ] {
            let words = sentence.split(separator: " ").map(String.init)
            let whole = await self.written([sentence], seeing: code)
            #expect(whole == written)
            for cut in 1..<words.count {
                let pieces = [words[..<cut].joined(separator: " "), words[cut...].joined(separator: " ")]
                let text = await self.written(pieces, seeing: code)
                #expect(text == written, "cut at \(cut) of \(sentence)")
            }
        }
    }

    @Test("a symbol pair or a number in code is read whole at every cut inside it")
    func everyCodeSymbolCut() async {
        let code = AppContext(
            applicationName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode", documentName: "Example.swift",
            precedingText: "let x = ")
        for sentence in [
            "fetch user open paren close paren", "items open bracket index close bracket",
            "let count equals forty two",
        ] {
            let words = sentence.split(separator: " ").map(String.init)
            let whole = await self.written([sentence], seeing: code)
            for cut in 1..<words.count {
                let pieces = [words[..<cut].joined(separator: " "), words[cut...].joined(separator: " ")]
                let text = await self.written(pieces, seeing: code)
                #expect(text == whole, "cut at \(cut) of \(sentence)")
            }
        }
    }

    @Test("a quotation is read whole at every cut inside it")
    func everyQuotationCut() async {
        let sentence = "the brief says open quote ship on friday close quote"
        let words = sentence.split(separator: " ").map(String.init)
        let whole = await written([sentence])
        // From "open | quote" to "friday | close quote": every cut that leaves the quotation open.
        for cut in 4..<words.count {
            let pieces = [words[..<cut].joined(separator: " "), words[cut...].joined(separator: " ")]
            let text = await written(pieces)
            #expect(text == whole, "cut at \(cut): \(text ?? "")")
        }
    }

    @Test("a named mark kept as a word stays a word across the cut")
    func mentionedMarkStays() async {
        let text = await written(["it lasted a long", "period of time"]) ?? ""
        #expect(text.lowercased().contains("period of time"))
    }

    private func written(_ pieces: [String], seeing context: AppContext = AppContext()) async -> String? {
        await pipeline.clean(pieces.map { Transcription(text: $0) }, seeing: context).text
    }
}
