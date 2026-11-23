import Foundation
import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowDictionary
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

/// The adapter is chosen once per dictation from every corrected word, so where a pause cuts the speech never changes the choice.
@Suite("One adapter decision per dictation, whichever way the speech is cut")
struct AdapterDecisionOnceTests {
    private let pipeline: DictationPipeline = {
        let router = TransformerRouter(
            engines: [RuleBasedTransformer()], preference: [.rules], clock: ManualClock())
        return DictationPipeline(
            capture: FakeAudioCaptureEngine(), speech: FakeSpeechEngine(), cleaner: router,
            context: FakeContextEngine(), inserter: FakeTextInserter(),
            corrector: DictionaryCorrections { _ in PhoneticIndex(entries: []) })
    }()

    private static let query = AppContext(
        applicationName: "TablePlus", bundleIdentifier: DestinationRules.tablePlus, precedingText: "")
    private static let shell = AppContext(
        applicationName: "Terminal", bundleIdentifier: DestinationRules.terminal, precedingText: "")
    private static let source = AppContext(
        applicationName: "Xcode", bundleIdentifier: DestinationRules.xcode, documentName: "Example.swift",
        precedingText: "")
    private static let json = AppContext(
        applicationName: "Visual Studio Code", bundleIdentifier: DestinationRules.vsCode,
        documentName: "data.json", precedingText: "{\n  ")

    /// A dictation and the screen it is said at.
    struct Dictation: CustomStringConvertible, Sendable {
        let spoken: String
        let screen: AppContext
        var description: String { spoken }
    }

    /// Twelve invented dictations of notation: SQL, shell, source and JSON.
    static let structured: [Dictation] = [
        Dictation(
            spoken:
                "select id from orders where status equals quote paid unquote and total greater than twelve",
            screen: query),
        Dictation(
            spoken: "select name from users where age greater than thirty and city equals quote lyon unquote",
            screen: query),
        Dictation(
            spoken: "insert into items values open paren one comma quote pen unquote close paren",
            screen: query),
        Dictation(
            spoken: "update orders set status equals quote shipped unquote where id equals seven",
            screen: query),
        Dictation(spoken: "git log dash dash since equals yesterday pipe grep fix", screen: shell),
        Dictation(spoken: "export NODE underscore ENV equals production", screen: shell),
        Dictation(spoken: "make build ampersand ampersand make test", screen: shell),
        Dictation(spoken: "let camel case retry count equals forty two", screen: source),
        Dictation(spoken: "pascal case order total open paren close paren", screen: source),
        Dictation(
            spoken: "snake case greeting equals open quote hello there close quote", screen: source),
        Dictation(
            spoken:
                "open brace quote name quote colon quote pen quote comma quote count quote colon five close brace",
            screen: json),
        Dictation(spoken: "open bracket one comma two comma three close bracket", screen: json),
    ]

    /// Six invented sentences that hold a notation word and say prose.
    static let prose: [Dictation] = [
        Dictation(spoken: "select statement is slow because the join equals a full scan", screen: query),
        Dictation(spoken: "the update statement ran twice so the delete went missing", screen: query),
        Dictation(spoken: "the dot product of the two vectors is slow", screen: source),
        Dictation(spoken: "we compare the equals method with the hash method in the file", screen: source),
        Dictation(spoken: "the pipe is greater than the hose", screen: shell),
        Dictation(spoken: "our budget equals the sum of the two quarters", screen: query),
    ]

    @Test("a dictation of notation is written the same for 200 random cuts", arguments: structured)
    func structuredCuts(dictation: Dictation) async {
        let whole = await written([dictation.spoken], dictation.screen)
        #expect(whole != dictation.spoken, "the uncut dictation is written as notation: \(whole ?? "")")
        await expectEveryCut(of: dictation, equals: whole)
    }

    @Test("a sentence with a notation word is written as no notation for 200 random cuts", arguments: prose)
    func proseCuts(dictation: Dictation) async {
        let whole = await written([dictation.spoken], dictation.screen) ?? ""
        #expect(!whole.contains { "=|()<>*".contains($0) }, "uncut wrote \(whole)")
        await expectEveryCut(of: dictation) { Self.words(of: $0 ?? "") == Self.words(of: whole) }
    }

    @Test("a keyword said only in the first, the middle or the last piece still decides the whole")
    func keywordInOnePiece() async {
        let statement =
            "select id from orders where status equals quote paid unquote and total greater than twelve"
        let uncut = await written([statement], Self.query)
        let threeWays = [
            [
                "select id", "from orders where status equals",
                "quote paid unquote and total greater than twelve",
            ],
            [
                "select", "id from orders where status",
                "equals quote paid unquote and total greater than twelve",
            ],
            [
                "select id from orders where status equals quote paid unquote and total",
                "greater than", "twelve",
            ],
        ]
        for pieces in threeWays {
            let text = await written(pieces, Self.query)
            #expect(text == uncut, "\(pieces.joined(separator: " | ")) wrote \(text ?? "")")
        }
        // The notation word "equals" is in no piece but the last, and the statement keyword in no piece but the first.
        let shellWhole = await written(["export NODE underscore ENV equals production"], Self.shell)
        let shellCut = await written(["export", "NODE underscore ENV", "equals production"], Self.shell)
        #expect(shellCut == shellWhole)
    }

    @Test("the choice reads a 300-word dictation within 5 ms of processor time at the 95th percentile")
    func choiceCost() {
        let sentence =
            "select id from orders where status equals quote paid unquote and total greater than twelve"
        let text = Array(repeating: sentence, count: 21).joined(separator: " and ")
        #expect(text.split(separator: " ").count >= 300)
        let situation = SituationResolver.resolve(from: Self.query)
        var milliseconds: [Double] = []
        for _ in 0..<200 {
            // Processor time on this thread, so a busy machine's scheduling is not counted against the choice.
            let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
            _ = NotationEvidence.writesNotation(in: text, situation: situation)
            milliseconds.append(Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start) / 1_000_000)
        }
        milliseconds.sort()
        #expect(milliseconds[Int(Double(milliseconds.count - 1) * 0.95)] < 5)
    }

    /// The words a text says with its marks kept, without the stops and capitals a pause adds, which are prose's own.
    private static func words(of text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber && !"=|()<>*'\"".contains($0) }.map(
            String.init)
    }

    private func expectEveryCut(of dictation: Dictation, equals expected: String?) async {
        await expectEveryCut(of: dictation) { $0 == expected }
    }

    /// Cuts `dictation` at 200 random sets of one to four word boundaries and expects each written text to satisfy `holds`.
    private func expectEveryCut(of dictation: Dictation, holds: (String?) -> Bool) async {
        let words = dictation.spoken.split(separator: " ").map(String.init)
        var random = SeededGenerator(seed: UInt64(truncatingIfNeeded: dictation.spoken.hashValueStable))
        var seen: Set<[Int]> = []
        for _ in 0..<200 {
            let count = Int.random(in: 1...min(4, words.count - 1), using: &random)
            var cuts = Set<Int>()
            while cuts.count < count { cuts.insert(Int.random(in: 1..<words.count, using: &random)) }
            let ordered = cuts.sorted()
            guard seen.insert(ordered).inserted else { continue }
            let bounds = [0] + ordered + [words.count]
            let pieces = zip(bounds, bounds.dropFirst()).map { words[$0..<$1].joined(separator: " ") }
            let text = await written(pieces, dictation.screen)
            #expect(holds(text), "cut \(pieces.joined(separator: " | ")) wrote \(String(reflecting: text))")
        }
    }

    private func written(_ pieces: [String], _ screen: AppContext) async -> String? {
        let text = await pipeline.clean(pieces.map { Transcription(text: $0) }, seeing: screen).text
        #expect(text != nil, "no text written for \(pieces.joined(separator: " | "))")
        return text
    }
}

/// A small deterministic generator, so a failing cut can be named and run again.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}

extension String {
    /// A hash that is the same on every run, unlike `hashValue`, which is seeded per process.
    fileprivate var hashValueStable: UInt64 {
        unicodeScalars.reduce(14_695_981_039_346_656_037) { ($0 ^ UInt64($1.value)) &* 1_099_511_628_211 }
    }
}
