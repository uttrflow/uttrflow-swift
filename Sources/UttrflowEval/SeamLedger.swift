// The reviewed list of seam cuts a new corpus case is allowed to make differ, each with its reason.

/// Cuts a pull request named as differing, one line each, `<case id>@<boundaries> <reason>`; a cut in no list still fails.
package struct SeamLedger: Equatable, Sendable {
    package struct Entry: Equatable, Sendable {
        package let cut: String
        package let reason: String
    }

    package enum Failure: Error, Equatable {
        case noReason(line: Int)
        case notACut(line: Int)
        case listedTwice(cut: String)
    }

    package let entries: [Entry]
    package var cuts: Set<String> { Set(entries.map(\.cut)) }

    package init(entries: [Entry]) { self.entries = entries }

    /// Reads the ledger text, refusing a line with no reason, a key that is not a cut, or a cut named twice.
    package init(parsing text: String) throws {
        var entries: [Entry] = []
        var seen: Set<String> = []
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
        where !line.hasPrefix("#") && !line.allSatisfy(\.isWhitespace) {
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            guard let cut = parts.first, cut.contains("@"), !cut.hasSuffix("@"), !cut.hasPrefix("@") else {
                throw Failure.notACut(line: index + 1)
            }
            guard parts.count == 2, !parts[1].allSatisfy(\.isWhitespace) else {
                throw Failure.noReason(line: index + 1)
            }
            guard seen.insert(cut).inserted else { throw Failure.listedTwice(cut: cut) }
            entries.append(Entry(cut: cut, reason: parts[1]))
        }
        self.entries = entries
    }

    /// The keys that neither the baseline nor this ledger names.
    package func unnamed(among keys: [String], baseline: SeamBaseline) -> [String] {
        let named = cuts
        return baseline.risen(among: keys).filter { !named.contains($0) }
    }

    /// The ledger lines for `keys`, each with `reason`, to append.
    package static func lines(for keys: [String], reason: String) -> String {
        keys.map { "\($0) \(reason)\n" }.joined()
    }
}
