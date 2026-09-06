import Foundation

/// One fixture's outcome, as the table prints it and the JSON records it.
struct FixtureResult: Encodable {
    let name: String
    let category: String
    let typed: String
    let hit: Bool
    let conforms: Bool
    let elapsedMs: Int
    /// The first completion the model offered, or nothing when it offered none.
    let first: String?
    /// How the pass ended and every word the model wrote, recorded only when the run asked for it.
    let raw: String?
    /// Whether the model named a program, path, branch or verb the fixture's machine does not have, before the sieve dropped it.
    let invented: Bool
    /// Whether the hit came from the second, wider pass rather than the first.
    let rescued: Bool
    /// What the second pass cost, recorded only when one was spent.
    let secondOpinionMs: Int?

    init(
        name: String, category: String, typed: String, hit: Bool, conforms: Bool, elapsedMs: Int,
        first: String?,
        raw: String?, invented: Bool, rescued: Bool = false, secondOpinionMs: Int? = nil
    ) {
        self.name = name
        self.category = category
        self.typed = typed
        self.hit = hit
        self.conforms = conforms
        self.elapsedMs = elapsedMs
        self.first = first
        self.raw = raw
        self.invented = invented
        self.rescued = rescued
        self.secondOpinionMs = secondOpinionMs
    }

    /// Whether anything at all was put in front of the person, which is what a wrong answer needs to be wrong.
    var shown: Bool { (first?.isEmpty == false) && first?.hasPrefix("error:") != true }

    /// Whether this row belongs in the failures section.
    var failed: Bool { !hit || !conforms }

    /// The row as the table prints it while the run is under way.
    var row: String {
        "\(hit ? "✓" : "✗")\(conforms ? "✓" : "✗") \(String(elapsedMs).leftPadded(to: 5))ms  "
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
    }

    let total: Int
    let hits: Int
    let conforming: Int
    /// How many answers the model wrote that named what the machine does not have, which the sieve kept off the screen.
    let invented: Int
    /// How many turns drew something, and of those how many were right: the trust the feature is judged by.
    let shown: Int
    let right: Int
    /// How many second passes were spent, how many hit, and what the median one cost.
    let secondOpinions: Int
    let rescued: Int
    let secondOpinionP50Ms: Int
    let p50Ms: Int
    let p95Ms: Int
    let categories: [Category]

    init(_ results: [FixtureResult]) {
        total = results.count
        hits = results.filter(\.hit).count
        conforming = results.filter(\.conforms).count
        invented = results.filter(\.invented).count
        shown = results.filter(\.shown).count
        right = results.filter { $0.shown && $0.hit }.count
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
                conforming: inCategory.filter(\.conforms).count)
        }
    }
}

/// What a fixture run found, printed for the operator and written for whoever categorises the failures.
struct FixtureReport: Encodable {
    let results: [FixtureResult]
    let summary: FixtureSummary

    init(results: [FixtureResult]) {
        self.results = results
        summary = FixtureSummary(results)
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
                    + "in register \(category.conforming)/\(category.total)")
        }
        guard summary.total > 0 else { return }
        print(
            "\nall  hit \(summary.hits)/\(summary.total)  in register \(summary.conforming)/\(summary.total)"
                + "  invented \(summary.invented)  p50 \(summary.p50Ms)ms  p95 \(summary.p95Ms)ms")
        // Precision is what a person feels: of the times it spoke, how often it was right. Coverage is how often it spoke at all.
        let wrong = summary.shown - summary.right
        print(
            "precision \(Self.rate(summary.right, of: summary.shown)) (\(summary.right)/\(summary.shown) shown,"
                + " \(wrong) wrong)  coverage \(Self.rate(summary.shown, of: summary.total))")
        guard summary.secondOpinions > 0 else { return }
        print(
            "second opinion  spent \(summary.secondOpinions)  rescued \(summary.rescued)"
                + "  p50 \(summary.secondOpinionP50Ms)ms")
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
