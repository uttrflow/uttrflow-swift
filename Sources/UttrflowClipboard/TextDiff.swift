/// What a formatter changed, line by line.
///
/// D6 — the diff is shown before the change is kept, and this is the part that can be
/// tested. A formatter is a program the user did not write running over code they did, so
/// "here is what it wants to do" is the difference between a tool and a surprise.
public enum TextDiff {
    public enum Kind: Sendable, Equatable {
        case same
        case added
        case removed
    }

    public struct Line: Sendable, Equatable {
        public let kind: Kind
        public let text: String

        public init(kind: Kind, text: String) {
            self.kind = kind
            self.text = text
        }
    }

    /// The whole comparison, line by line.
    ///
    /// A longest-common-subsequence diff, which is what makes the output read as "these
    /// three lines changed" rather than "everything after line four changed" — the latter
    /// being what a naïve positional comparison produces the moment a line is inserted,
    /// and useless for judging whether to accept.
    public static func lines(from before: String, to after: String) -> [Line] {
        let old = before.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let new = after.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // Lengths of the common subsequence for every pair of suffixes.
        var common = Array(
            repeating: Array(repeating: 0, count: new.count + 1), count: old.count + 1)
        for i in stride(from: old.count - 1, through: 0, by: -1) {
            for j in stride(from: new.count - 1, through: 0, by: -1) {
                common[i][j] =
                    old[i] == new[j]
                    ? common[i + 1][j + 1] + 1
                    : max(common[i + 1][j], common[i][j + 1])
            }
        }

        var result: [Line] = []
        var i = 0
        var j = 0
        while i < old.count && j < new.count {
            if old[i] == new[j] {
                result.append(Line(kind: .same, text: old[i]))
                i += 1
                j += 1
            } else if common[i + 1][j] >= common[i][j + 1] {
                result.append(Line(kind: .removed, text: old[i]))
                i += 1
            } else {
                result.append(Line(kind: .added, text: new[j]))
                j += 1
            }
        }
        while i < old.count {
            result.append(Line(kind: .removed, text: old[i]))
            i += 1
        }
        while j < new.count {
            result.append(Line(kind: .added, text: new[j]))
            j += 1
        }
        return result
    }

    /// How many lines the change touches.
    ///
    /// The number a user actually decides on. A 420-point panel cannot show a diff of any
    /// size honestly, so it leads with this and shows what fits.
    public static func changedLines(from before: String, to after: String) -> Int {
        lines(from: before, to: after).count { $0.kind != .same }
    }

    /// Only the parts that changed, with a line of context on each side.
    ///
    /// Long runs of untouched code are exactly what makes a diff unreadable in a narrow
    /// panel, and they are also the part nobody is deciding about.
    public static func interesting(
        from before: String, to after: String, context: Int = 1
    )
        -> [Line]
    {
        let all = lines(from: before, to: after)
        let changed = all.indices.filter { all[$0].kind != .same }
        guard !changed.isEmpty else { return [] }

        var wanted = Set<Int>()
        for index in changed {
            for nearby in (index - context)...(index + context) where all.indices.contains(nearby) {
                wanted.insert(nearby)
            }
        }
        return wanted.sorted().map { all[$0] }
    }
}
