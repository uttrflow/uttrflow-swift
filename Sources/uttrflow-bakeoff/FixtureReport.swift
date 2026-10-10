import Foundation
import UttrflowPredict

/// One fixture's outcome, as the table prints it and the JSON records it.
struct FixtureResult: Encodable {
    let name: String
    let category: String
    let typed: String
    /// Whether the fixture was hit and the model did not error, so a thrown error always reads as a miss.
    let hit: Bool
    /// Whether the hit was checked against a named answer, rather than any continuation counting.
    let judged: Bool
    let conforms: Bool
    let elapsedMs: Int
    /// The first completion the model offered, or nothing when it offered none.
    let first: String?
    /// The lines the arbitration actually drew, empty when no candidate or no confident candidate was selected.
    let drawn: [String]
    /// Which production candidate source supplied the line shown to the person.
    let source: String?
    /// How the pass ended and every word the model wrote, recorded only when the run asked for it.
    let raw: String?
    /// Whether the model named a program, path, branch or verb the fixture's machine does not have, before the sieve dropped it.
    let invented: Bool
    /// Whether the hit came from the second, wider pass rather than the first.
    let rescued: Bool
    /// What the second pass cost, recorded only when one was spent.
    let secondOpinionMs: Int?
    /// Whether the first generation pass ended because it reached its token budget.
    let lengthStopped: Bool
    /// Whether the alternatives pass ended because it reached its token budget.
    let alternativesLengthStopped: Bool
    /// The error the generator threw for this fixture, when one was thrown rather than offered nothing; a generator that throws is not one that named silence.
    let error: String?
    /// What the confidence floor made of the first line.
    let gate: Gate

    /// The first line's score from its own pass, whether the floor held it back, and the scorer's second opinion when asked for.
    struct Gate: Encodable {
        let confidence: Double?
        let held: Bool
        /// Whether the line would have been a hit had it been drawn, which is what a lower floor would change.
        let hitIfDrawn: Bool
        let judgeScore: Double?
        let judgeMs: Int?

        static let open = Gate(confidence: nil, held: false, hitIfDrawn: false, judgeScore: nil, judgeMs: nil)
    }

    init(
        name: String, category: String, typed: String, hit: Bool, judged: Bool, conforms: Bool,
        elapsedMs: Int, first: String?, drawn: [String], source: String? = nil,
        raw: String?, invented: Bool, rescued: Bool = false, secondOpinionMs: Int? = nil,
        lengthStopped: Bool = false, alternativesLengthStopped: Bool = false, error: String? = nil,
        gate: Gate = .open
    ) {
        self.name = name
        self.category = category
        self.typed = typed
        // An errored pass is not a hit and not in register, even when silence would have been the right answer.
        self.hit = hit && error == nil
        self.judged = judged
        self.conforms = conforms && error == nil
        self.elapsedMs = elapsedMs
        self.first = first
        self.drawn = drawn
        self.source = source
        self.raw = raw
        self.invented = invented
        self.rescued = rescued
        self.secondOpinionMs = secondOpinionMs
        self.lengthStopped = lengthStopped
        self.alternativesLengthStopped = alternativesLengthStopped
        self.error = error
        self.gate = gate
    }

    /// Whether any line was put in front of the person, rather than only offered by the model.
    var shown: Bool { !drawn.isEmpty }

    /// Whether the model offered a line, drawn or held back by the floor.
    var offered: Bool { error == nil && (first?.isEmpty == false) && first?.hasPrefix("error:") != true }

    /// Whether this row belongs in the failures section.
    var failed: Bool { !hit || !conforms }

    /// The row as the table prints it while the run is under way.
    var row: String {
        let mark = error != nil ? "E" : (hit ? "✓" : "✗")
        return "\(mark)\(conforms ? "✓" : "✗") \(String(elapsedMs).leftPadded(to: 5))ms  "
            + "\(name.padded(to: 44)) \((first ?? "-").debugDescription)"
    }
}

/// The rates and latency percentiles a run is judged by, overall and per category.
struct FixtureSummary: Encodable {
    struct Category: Encodable {
        let name: String
        let total: Int
        let hits: Int
        let conforming: Int
        let shown: Int
        let right: Int
    }

    let total: Int
    let hits: Int
    let conforming: Int
    /// How many fixtures the generator threw on, which is what fails the run and was not counted as silence.
    let errors: Int
    /// How many answers the model wrote that named what the machine does not have, which the sieve kept off the screen.
    let invented: Int
    /// First passes that reached their token budget, whether or not the completion was withheld.
    let lengthStopped: Int
    /// Alternatives passes that reached their token budget.
    let alternativesLengthStopped: Int
    /// Shown candidates that came from a length-stopped pass. This must stay zero.
    let shownFromLengthStop: Int
    /// Hits checked against a named answer, and hits taken on any continuation, which say nothing about being right.
    let judgedHits: Int
    let unjudgedHits: Int
    /// How many judged turns drew something, and of those how many were right: the trust the feature is judged by.
    let shown: Int
    let right: Int
    /// How many unjudged turns drew something, which precision leaves out because nothing says whether they were right.
    let unjudgedShown: Int
    /// How many second passes were spent, how many hit, and what the median one cost.
    let secondOpinions: Int
    let rescued: Int
    let secondOpinionP50Ms: Int
    let p50Ms: Int
    let p95Ms: Int
    let categories: [Category]
    let sources: [Category]
    /// How many shown lines had no judgment corpus, which keeps their precision denominator honest.
    let unjudgedSources: [Category]

    init(_ results: [FixtureResult]) {
        total = results.count
        hits = results.filter(\.hit).count
        conforming = results.filter(\.conforms).count
        errors = results.filter { $0.error != nil }.count
        invented = results.filter(\.invented).count
        lengthStopped = results.filter(\.lengthStopped).count
        alternativesLengthStopped = results.filter(\.alternativesLengthStopped).count
        shownFromLengthStop = results.filter { $0.lengthStopped && $0.shown }.count
        judgedHits = results.filter { $0.hit && $0.judged }.count
        unjudgedHits = results.filter { $0.hit && !$0.judged }.count
        shown = results.filter { $0.shown && $0.judged }.count
        right = results.filter { $0.shown && $0.judged && $0.hit }.count
        unjudgedShown = results.filter { $0.shown && !$0.judged }.count
        let seconds = results.compactMap(\.secondOpinionMs).sorted()
        secondOpinions = seconds.count
        rescued = results.filter(\.rescued).count
        secondOpinionP50Ms = seconds.isEmpty ? 0 : seconds[seconds.count / 2]
        let times = results.map(\.elapsedMs).sorted()
        p50Ms = times.isEmpty ? 0 : times[times.count / 2]
        p95Ms = times.isEmpty ? 0 : times[min(times.count - 1, Int(Double(times.count) * 0.95))]
        categories = Set(results.map(\.category)).sorted().map { category in
            let inCategory = results.filter { $0.category == category }
            return Category(
                name: category, total: inCategory.count, hits: inCategory.filter(\.hit).count,
                conforming: inCategory.filter(\.conforms).count,
                shown: inCategory.filter { $0.shown && $0.judged }.count,
                right: inCategory.filter { $0.shown && $0.judged && $0.hit }.count)
        }
        sources = Set(results.compactMap(\.source)).sorted().map { source in
            let inSource = results.filter { $0.source == source }
            return Category(
                name: source, total: inSource.count, hits: inSource.filter(\.hit).count,
                conforming: inSource.filter(\.conforms).count,
                shown: inSource.filter { $0.shown && $0.judged }.count,
                right: inSource.filter { $0.shown && $0.judged && $0.hit }.count)
        }
        unjudgedSources = Set(results.compactMap(\.source)).sorted().map { source in
            let inSource = results.filter { $0.source == source }
            let shown = inSource.filter(\.shown)
            return Category(
                name: source, total: inSource.count, hits: inSource.filter(\.hit).count,
                conforming: inSource.filter(\.conforms).count,
                shown: shown.filter { !$0.judged }.count,
                right: shown.filter { !$0.judged && $0.hit }.count)
        }
    }
}

/// What a fixture run found, printed for the operator and written for whoever categorises the failures.
struct FixtureReport: Encodable {
    let results: [FixtureResult]
    let summary: FixtureSummary
    /// The unfiltered fixture count used by this command, when written from a catalogue run.
    let fixtureCatalogueCount: Int?
    /// True only when the default full generation catalogue ran without a selection filter.
    let fullFixtureCatalogue: Bool

    init(
        results: [FixtureResult], fixtureCatalogueCount: Int? = nil,
        fullFixtureCatalogue: Bool = false
    ) {
        self.results = results
        summary = FixtureSummary(results)
        self.fixtureCatalogueCount = fixtureCatalogueCount
        self.fullFixtureCatalogue = fullFixtureCatalogue
    }

    /// A rate as a percentage to two figures, since the last of them is what a trustworthy feature is judged on.
    private static func rate(_ part: Int, of whole: Int) -> String {
        guard whole > 0 else { return "-" }
        return String(format: "%.2f %%", 100 * Double(part) / Double(whole))
    }

    /// The per-category rates and the overall rates with latency percentiles.
    func printSummary() {
        print("")
        for category in summary.categories {
            print(
                "\(category.name.leftPadded(to: 10))  hit \(category.hits)/\(category.total)  "
                    + "in register \(category.conforming)/\(category.total)  precision "
                    + "\(Self.rate(category.right, of: category.shown)) (\(category.right)/\(category.shown) judged shown, "
                    + "\(category.shown - category.right) wrong)")
        }
        if !summary.sources.isEmpty {
            print("\nby shown source:")
            for source in summary.sources {
                print(
                    "\(source.name.leftPadded(to: 12)) precision "
                        + "\(Self.rate(source.right, of: source.shown)) (\(source.right)/\(source.shown) judged shown, "
                        + "\(source.shown - source.right) wrong)")
            }
            let unjudged = summary.unjudgedSources.filter { $0.shown > 0 }
            if !unjudged.isEmpty {
                print("unjudged shown lines by source:")
                for source in unjudged {
                    print("\(source.name.leftPadded(to: 12)) \(source.shown)")
                }
            }
        }
        guard summary.total > 0 else { return }
        print(
            "\nall  hit \(summary.hits)/\(summary.total)  in register \(summary.conforming)/\(summary.total)"
                + "  invented \(summary.invented)  length-stopped \(summary.lengthStopped)"
                + "  alternatives length-stopped \(summary.alternativesLengthStopped)"
                + "  shown from length stop \(summary.shownFromLengthStop)"
                + "  errors \(summary.errors)"
                + "  p50 \(summary.p50Ms)ms  p95 \(summary.p95Ms)ms")
        print("hits judged \(summary.judgedHits)  unjudged \(summary.unjudgedHits)")
        // Precision is what a person feels: of the judged times it spoke, how often it was right. Coverage is how often it spoke at all.
        let wrong = summary.shown - summary.right
        let spoke = summary.shown + summary.unjudgedShown
        print(
            "precision \(Self.rate(summary.right, of: summary.shown)) (\(summary.right)/\(summary.shown) judged shown,"
                + " \(wrong) wrong, \(summary.unjudgedShown) unjudged shown)"
                + "  coverage \(Self.rate(spoke, of: summary.total))")
        guard summary.secondOpinions > 0 else { return }
        print(
            "second opinion  spent \(summary.secondOpinions)  rescued \(summary.rescued)"
                + "  p50 \(summary.secondOpinionP50Ms)ms")
    }

    /// Precision and coverage had every first line been held to each floor, from the model's own score and from the scorer's when it was asked for.
    func printFloors() {
        let offered = results.filter(\.offered)
        guard offered.contains(where: { $0.gate.confidence != nil }) else { return }
        let held = offered.filter(\.gate.held)
        let heldWrong = held.filter { $0.judged && !$0.gate.hitIfDrawn }.count
        print(
            "\nheld under the floor \(held.count) (judged: \(heldWrong) wrong,"
                + " \(held.filter { $0.judged && $0.gate.hitIfDrawn }.count) right)")
        print(
            "floors on the pass's own score (the app holds a lone line under \(Verification.certainFloor)):")
        for floor in [-0.5, -0.6, -0.75, -0.9, -1.0, -1.5] {
            printFloor(floor, kept: offered.filter { Verification.clears($0.gate.confidence, floor: floor) })
        }
        guard offered.contains(where: { $0.gate.judgeScore != nil }) else { return }
        print("floors on the scorer's second pass:")
        for floor in [-3.0, -4.0, -5.0, -6.0, -8.0] {
            printFloor(floor, kept: offered.filter { Verification.clears($0.gate.judgeScore, floor: floor) })
        }
        let times = offered.compactMap(\.gate.judgeMs).sorted()
        guard !times.isEmpty else { return }
        print(
            "second pass p50 \(times[times.count / 2])ms  p95 \(times[min(times.count - 1, times.count * 95 / 100)])ms"
        )
    }

    /// One floor's row: of the judged lines kept, how many were right, and how many lines were kept at all.
    private func printFloor(_ floor: Double, kept: [FixtureResult]) {
        let judged = kept.filter(\.judged)
        let right = judged.filter(\.gate.hitIfDrawn).count
        print(
            "  \(String(format: "%5.2f", floor))  precision \(Self.rate(right, of: judged.count)) (\(right)/\(judged.count),"
                + " \(judged.count - right) wrong)  coverage \(Self.rate(kept.count, of: results.count))")
    }

    /// Every miss and every line out of register, each with what was typed and what came back first.
    func printFailures() {
        let failures = results.filter(\.failed)
        guard !failures.isEmpty else { return }
        print("\nfailures (\(failures.count)):")
        for result in failures {
            print(
                "\(result.hit ? "✓" : "✗")\(result.conforms ? "✓" : "✗") \(result.name.padded(to: 44)) "
                    + "typed \(result.typed.debugDescription)  first \((result.first ?? "-").debugDescription)"
            )
        }
    }

    /// The whole report as JSON at this path, directories made as needed.
    func write(to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url)
    }
}
