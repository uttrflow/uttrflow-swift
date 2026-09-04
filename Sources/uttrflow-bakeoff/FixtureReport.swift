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
    let p50Ms: Int
    let p95Ms: Int
    let categories: [Category]

    init(_ results: [FixtureResult]) {
        total = results.count
        hits = results.filter(\.hit).count
        conforming = results.filter(\.conforms).count
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
                + "  p50 \(summary.p50Ms)ms  p95 \(summary.p95Ms)ms")
    }

    /// Every miss and every line out of register, each with what was typed and what came back first.
    func printFailures() {
        let failures = results.filter(\.failed)
        guard !failures.isEmpty else { return }
        print("\nfailures (\(failures.count)):")
        for result in failures {
            print(
                "\(result.hit ? "✓" : "✗")\(result.conforms ? "✓" : "✗") \(result.name.padded(to: 44)) "
                    + "typed \(result.typed.debugDescription)  first \((result.first ?? "-").debugDescription)")
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
