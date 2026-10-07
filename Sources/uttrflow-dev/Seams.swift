// The `seams` command: proves cleaning pieces then joining them writes what cleaning the whole does.
import ArgumentParser
import Foundation
import UttrflowAI
import UttrflowCore
import UttrflowDictionary
import UttrflowEval
import UttrflowPipeline

/// Cuts every corpus case at its word boundaries and compares the joined pieces with the whole. See `Docs/piece-seams.md`.
struct Seams: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract:
            "Count the corpus cuts where cleaning the pieces and joining differs from cleaning the whole."
    )

    @Flag(name: .long, help: "Also cut every case at every pair of word boundaries, into three pieces.")
    var three = false

    @Option(name: .long, help: "Compare with this baseline, failing when a cut differs that did not before.")
    var check: String?

    @Option(name: .long, help: "Write the differing cuts to this baseline.")
    var update: String?

    @Option(
        name: .long, parsing: .singleValue,
        help: "Switch this cleaning step off for the run, to see which cuts it makes differ. Repeatable.")
    var without: [String] = []

    @Flag(name: .long, help: "Name each cut on standard error before it is cleaned.")
    var trace = false

    @Flag(name: .long, help: "Print every differing cut.")
    var list = false

    func run() async throws {
        let steps = try Self.steps(without: without)
        let pipeline = DictationPipeline(
            capture: PlaybackCaptureEngine(audio: .empty, sharesEarly: false), speech: NoRecogniser(),
            cleaner: TransformerRouter(engines: [RuleBasedTransformer(steps: steps)], preference: [.rules]),
            context: FixedScreen(context: AppContext()), inserter: PrintingInserter(),
            corrector: DictionaryCorrections { PhoneticIndex(entries: []) })
        var differing: [SeamDifference] = []
        var cuts = 0
        for testCase in EvaluationCorpus.all {
            let words = testCase.spoken.split(whereSeparator: \.isWhitespace).map(String.init)
            let whole = await pipeline.clean([Transcription(text: testCase.spoken)], seeing: testCase.context)
                .text
            for boundaries in Self.cuts(of: words.count, three: three) {
                cuts += 1
                // A crash in a pass ends the run, so the cut under way is named first.
                if trace { FileHandle.standardError.write(Data("\(testCase.id)@\(boundaries)\n".utf8)) }
                let pieces = Self.pieces(of: words, at: boundaries).map { Transcription(text: $0) }
                let joined = await pipeline.clean(pieces, seeing: testCase.context).text
                guard joined != whole else { continue }
                differing.append(
                    SeamDifference(
                        id: testCase.id, boundaries: boundaries, whole: whole ?? "", joined: joined ?? ""))
            }
        }
        report(differing, of: cuts)
        let keys = differing.map(\.key).sorted()
        if let update { try SeamBaseline(cuts: keys).write(to: URL(fileURLWithPath: update)) }
        if let check { try compare(keys, with: URL(fileURLWithPath: check)) }
    }

    /// The default steps with each named one switched off, refusing a name the user cannot switch off.
    static func steps(without names: [String]) throws -> CleaningSteps {
        try names.reduce(CleaningSteps.default) { steps, name in
            let step = PassID(rawValue: name)
            guard CleaningSteps.isOffered(step) else {
                let offered = CleaningSteps.offered.map(\.id.rawValue).joined(separator: ", ")
                throw ValidationError("\(name) cannot be switched off; one of: \(offered)")
            }
            return steps.setting(step, isOn: false)
        }
    }

    /// Every way to cut a transcript of this many words into two pieces, and into three when asked.
    static func cuts(of count: Int, three: Bool) -> [[Int]] {
        guard count > 1 else { return [] }
        let twos = (1..<count).map { [$0] }
        guard three, count > 2 else { return twos }
        let threes = (1..<(count - 1)).flatMap { first in ((first + 1)..<count).map { [first, $0] } }
        return twos + threes
    }

    /// The words between each pair of cuts, each piece written as the recogniser writes one.
    static func pieces(of words: [String], at boundaries: [Int]) -> [String] {
        let edges = [0] + boundaries + [words.count]
        return zip(edges, edges.dropFirst()).map { words[$0..<$1].joined(separator: " ") }
    }

    private func report(_ differing: [SeamDifference], of cuts: Int) {
        print("  cuts       \(cuts)")
        print("  differing  \(differing.count) in \(Set(differing.map(\.id)).count) cases")
        let groups = Dictionary(grouping: differing, by: \.kind)
        for kind in SeamDifference.Kind.allCases {
            print(
                "  \(kind.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0))\(groups[kind]?.count ?? 0)"
            )
        }
        guard list else { return }
        for difference in differing {
            print("\(difference.key) [\(difference.kind.rawValue)]")
            print("    whole   \(difference.whole)")
            print("    pieces  \(difference.joined)")
        }
    }

    private func compare(_ keys: [String], with url: URL) throws {
        let recorded = Set(try SeamBaseline.read(from: url).cuts)
        let risen = keys.filter { !recorded.contains($0) }
        let fallen = recorded.subtracting(keys).count
        if fallen > 0 {
            print("  \(fallen) recorded cuts now match; rerun with --update to lower the baseline")
        }
        guard risen.isEmpty else {
            throw ValidationError(
                "\(risen.count) cuts now differ that did not:\n" + risen.joined(separator: "\n"))
        }
    }
}

/// One cut of one case whose joined pieces differ from the whole.
struct SeamDifference {
    /// Whether the words differ, or only the marks between them, or only the letters' case.
    enum Kind: String, CaseIterable {
        case words, letterCase = "case", punctuation
    }

    let id: String
    let boundaries: [Int]
    let whole: String
    let joined: String

    var key: String { "\(id)@\(boundaries.map(String.init).joined(separator: ","))" }

    var kind: Kind {
        let bare = { (text: String) in text.filter { $0.isLetter || $0.isNumber || $0.isWhitespace } }
        guard bare(whole).lowercased() == bare(joined).lowercased() else { return .words }
        return whole.lowercased() == joined.lowercased() ? .letterCase : .punctuation
    }
}

/// The cuts recorded as differing, which may fall and never rise.
struct SeamBaseline: Codable {
    let cuts: [String]
    var total: Int { cuts.count }

    enum CodingKeys: String, CodingKey { case cuts, total }

    init(cuts: [String]) { self.cuts = cuts }

    init(from decoder: any Decoder) throws {
        cuts = try decoder.container(keyedBy: CodingKeys.self).decode([String].self, forKey: .cuts)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(total, forKey: .total)
        try container.encode(cuts, forKey: .cuts)
    }

    static func read(from url: URL) throws -> SeamBaseline {
        try JSONDecoder().decode(SeamBaseline.self, from: Data(contentsOf: url))
    }

    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try (encoder.encode(self) + Data("\n".utf8)).write(to: url)
    }
}
