// The class-by-class error table for homophone repair, read only from the generated cases.
private import Foundation

/// One stage a repair case passes through: a name and what it does to the text.
public struct HomophoneStage: Sendable {
    /// The column heading.
    public let name: String
    /// The text after this stage.
    public let apply: @Sendable (String) -> String

    /// A stage named `name` that rewrites text with `apply`.
    public init(_ name: String, apply: @escaping @Sendable (String) -> String) {
        self.name = name
        self.apply = apply
    }
}

/// One class's row: how many cases it has and how many each stage leaves wrong.
public struct HomophoneClassRow: Sendable, Equatable {
    /// The class's spellings, sorted and joined with "/".
    public let members: String
    /// The cases whose meant spelling is in this class.
    public let cases: Int
    /// For each stage, in the order given, the cases whose output still differs from the meant sentence.
    public let errors: [Int]
}

/// Builds AC.21's table from `HomophoneCaseSet`, so no sentence set is written by hand for it.
public enum HomophoneClassTable {
    /// One row per class, in the order classes first appear in `cases`.
    public static func rows(
        cases: [HomophoneCase], classOf: (String) -> [String]?, stages: [HomophoneStage]
    ) -> [HomophoneClassRow] {
        var order: [String] = []
        var grouped: [String: [HomophoneCase]] = [:]
        for item in cases {
            let key = (classOf(item.meant) ?? [item.meant]).sorted().joined(separator: "/")
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(item)
        }
        return order.map { key in
            let members = grouped[key] ?? []
            let errors = stages.map { stage in
                members.filter { words(stage.apply($0.input)) != words($0.expected) }.count
            }
            return HomophoneClassRow(members: key, cases: members.count, errors: errors)
        }
    }

    /// The table as Markdown: class, cases, then the error rate after each stage.
    public static func markdown(_ rows: [HomophoneClassRow], stages: [HomophoneStage]) -> String {
        let head = "| Class | Cases | " + stages.map(\.name).joined(separator: " | ") + " |"
        let rule = "|---|---|" + String(repeating: "---|", count: stages.count)
        let body = rows.map { row in
            let rates = row.errors.map { percent($0, of: row.cases) }
            return "| \(row.members) | \(row.cases) | " + rates.joined(separator: " | ") + " |"
        }
        return ([head, rule] + body).joined(separator: "\n")
    }

    /// The words compared: lower case, with every mark but an inner apostrophe dropped, so "its" and "it's" stay apart.
    static func words(_ text: String) -> [String] {
        text.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
            .split(whereSeparator: \.isWhitespace)
            .map { word in
                String(word.filter { $0.isLetter || $0.isNumber || $0 == "'" })
                    .trimmingCharacters(in: ["'"])
            }
            .filter { !$0.isEmpty }
    }

    private static func percent(_ count: Int, of total: Int) -> String {
        guard total > 0 else { return "-" }
        return "\((count * 100 + total / 2) / total)%"
    }
}
