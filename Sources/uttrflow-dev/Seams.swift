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

    @Option(
        name: .long,
        help: "Cut only every Nth corpus case, for a shorter run; a baseline check then ignores the rest.")
    var sample = 1

    @Flag(name: .long, help: "Name each cut on standard error before it is cleaned.")
    var trace = false

    @Flag(name: .long, help: "Print every differing cut.")
    var list = false

    @Flag(
        name: .long,
        help: "Name, for each differing cut, the first step in run order whose removal makes it match.")
    var attribute = false

    func run() async throws {
        let steps = try Self.steps(without: without)
        // The pipeline is an actor, so each case gets its own and the cases run side by side.
        let three = three
        let trace = trace
        guard sample >= 1 else { throw ValidationError("--sample must be 1 or more") }
        let cases = Self.sampled(EvaluationCorpus.all, every: sample)
        var differing: [SeamDifference] = []
        var cuts = 0
        await withTaskGroup(of: (Int, [SeamDifference]).self) { group in
            var pending = cases.makeIterator()
            func next() -> Bool {
                guard let testCase = pending.next() else { return false }
                group.addTask {
                    await Self.differences(in: testCase, under: steps, three: three, trace: trace)
                }
                return true
            }
            for _ in 0..<ProcessInfo.processInfo.activeProcessorCount where next() {}
            while let (count, found) = await group.next() {
                cuts += count
                differing += found
                _ = next()
            }
        }
        differing.sort { $0.key < $1.key }
        report(differing, of: cuts)
        if attribute { await attribute(differing, under: steps) }
        let keys = differing.map(\.key).sorted()
        if let update { try SeamBaseline(cuts: keys).write(to: URL(fileURLWithPath: update)) }
        if let check { try compare(keys, with: URL(fileURLWithPath: check), among: Set(cases.map(\.id))) }
    }

    /// Every cut of one case, and those whose joined pieces differ from the whole.
    static func differences(
        in testCase: EvaluationCase, under steps: CleaningSteps, three: Bool, trace: Bool
    ) async -> (Int, [SeamDifference]) {
        let pipeline = pipeline(steps)
        let words = testCase.spoken.split(whereSeparator: \.isWhitespace).map(String.init)
        let whole = await pipeline.clean([Transcription(text: testCase.spoken)], seeing: testCase.context)
            .text
        let cuts = cuts(of: words.count, three: three)
        var differing: [SeamDifference] = []
        for boundaries in cuts {
            // A crash in a pass ends the run, so the cut under way is named first.
            if trace { FileHandle.standardError.write(Data("\(testCase.id)@\(boundaries)\n".utf8)) }
            let pieces = pieces(of: words, at: boundaries).map { Transcription(text: $0) }
            let joined = await pipeline.clean(pieces, seeing: testCase.context).text
            guard joined != whole else { continue }
            differing.append(
                SeamDifference(
                    id: testCase.id, boundaries: boundaries, whole: whole ?? "", joined: joined ?? ""))
        }
        return (cuts.count, differing)
    }

    /// A rules-only pipeline cleaning with these steps, seeing nothing and inserting nowhere.
    static func pipeline(_ steps: CleaningSteps) -> DictationPipeline {
        pipeline(
            cleaning: TransformerRouter(engines: [RuleBasedTransformer(steps: steps)], preference: [.rules]))
    }

    /// A pipeline handed recognised words, cleaning with `cleaner`, with no dictionary, seeing nothing and inserting nowhere.
    static func pipeline(cleaning cleaner: any TranscriptCleaning) -> DictationPipeline {
        DictationPipeline(
            capture: PlaybackCaptureEngine(audio: .empty, sharesEarly: false), speech: NoRecogniser(),
            cleaner: cleaner, context: FixedScreen(context: AppContext()), inserter: PrintingInserter(),
            corrector: DictionaryCorrections { PhoneticIndex(entries: []) })
    }

    /// Counts the differing cuts by the first running step whose removal makes them match, else `join`.
    private func attribute(_ differing: [SeamDifference], under steps: CleaningSteps) async {
        let candidates = CleaningSteps.offered.map(\.id).filter { steps.runs($0) }
        let cases = Dictionary(uniqueKeysWithValues: EvaluationCorpus.all.map { ($0.id, $0) })
        var counts: [String: Int] = [:]
        await withTaskGroup(of: String.self) { group in
            var pending = differing.makeIterator()
            func next() -> Bool {
                guard let difference = pending.next() else { return false }
                guard let testCase = cases[difference.id] else { return true }
                group.addTask {
                    await Self.owner(of: difference, in: testCase, among: candidates, under: steps)
                }
                return true
            }
            for _ in 0..<ProcessInfo.processInfo.activeProcessorCount where next() {}
            while let owner = await group.next() {
                counts[owner, default: 0] += 1
                _ = next()
            }
        }
        print("  first pass whose removal makes the cut match:")
        for (owner, count) in counts.sorted(by: { ($0.value, $1.key) > ($1.value, $0.key) }) {
            print("    \(owner.padding(toLength: 20, withPad: " ", startingAt: 0))\(count)")
        }
    }

    /// The first step, in run order, whose removal makes this cut's pieces and whole agree, or `join`.
    static func owner(
        of difference: SeamDifference, in testCase: EvaluationCase, among candidates: [PassID],
        under steps: CleaningSteps
    ) async -> String {
        let words = testCase.spoken.split(whereSeparator: \.isWhitespace).map(String.init)
        let pieces = pieces(of: words, at: difference.boundaries).map { Transcription(text: $0) }
        for step in candidates {
            let without = pipeline(steps.setting(step, isOn: false))
            let whole = await without.clean([Transcription(text: testCase.spoken)], seeing: testCase.context)
                .text
            let joined = await without.clean(pieces, seeing: testCase.context).text
            if whole == joined { return step.rawValue }
        }
        return "join"
    }

    /// Every `stride`th element, starting with the first, so the same sample comes back on every run.
    static func sampled<Element>(_ all: [Element], every stride: Int) -> [Element] {
        all.enumerated().filter { $0.offset % stride == 0 }.map(\.element)
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

    private func compare(_ keys: [String], with url: URL, among ids: Set<String>) throws {
        // A cut's key is its case id, "@", then its boundaries; a sampled run checks only its own cases.
        let recorded = Set(
            try SeamBaseline.read(from: url).cuts.filter { key in
                key.lastIndex(of: "@").map { ids.contains(String(key[..<$0])) } ?? false
            })
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
struct SeamDifference: Sendable {
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
