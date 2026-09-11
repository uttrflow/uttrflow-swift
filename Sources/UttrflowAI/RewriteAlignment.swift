/// Where each run of the kept draft stands in the rewrite, so a check reads one position rather than the whole text.
struct RewriteAlignment: Sendable {
    /// One run the rewrite did not leave alone, paired with the run of rewritten words standing in its place.
    struct Change: Sendable, Equatable {
        let kept: Range<Int>
        let rewritten: Range<Int>
    }

    private typealias Token = MeaningPreservationGuard.GrammarToken

    /// The kept draft as it was handed in, which the checks that read whole text still need.
    let keptText: String
    /// The rewrite as it was handed in.
    let rewrittenText: String
    /// The kept draft's words, in order.
    let kept: [MeaningPreservationGuard.GrammarToken]
    /// The rewrite's words, in order.
    let rewritten: [MeaningPreservationGuard.GrammarToken]
    /// Every run that changed, earliest first; every word outside one stands where it stood.
    let changes: [Change]

    /// Aligns the two texts on the words they share, which leaves each changed run paired with what replaced it.
    init(kept keptText: String, rewritten rewrittenText: String) {
        self.keptText = keptText
        self.rewrittenText = rewrittenText
        kept = MeaningPreservationGuard.grammarTokens(keptText)
        rewritten = MeaningPreservationGuard.grammarTokens(rewrittenText)
        changes = Self.changes(between: kept, and: rewritten)
    }

    /// The kept words of a run, closed up to letters and digits, which is how a reading is compared.
    func keptSpelling(of range: Range<Int>) -> String {
        DoubtfulSpan.closedUp(kept[range].map(\.text).joined())
    }

    /// The rewritten words standing in a run's place, closed up the same way.
    func rewrittenSpelling(of range: Range<Int>) -> String {
        DoubtfulSpan.closedUp(rewritten[range].map(\.text).joined())
    }

    /// The rewritten words standing in a run's place, as the form a survival check matches by.
    func rewrittenWords(of range: Range<Int>) -> Set<String> {
        Set(rewritten[range].filter(\.isPlain).map(\.matching))
    }

    // MARK: Aligning

    /// Trims the runs that match end to end, then splits what is left at the words standing once on each side.
    private static func changes(between kept: [Token], and rewritten: [Token]) -> [Change] {
        var found: [Change] = []
        var pending: [(Range<Int>, Range<Int>)] = [(0..<kept.count, 0..<rewritten.count)]
        while let (keptRange, rewrittenRange) = pending.popLast() {
            var left = keptRange
            var right = rewrittenRange
            while !left.isEmpty, !right.isEmpty,
                kept[left.lowerBound].matching == rewritten[right.lowerBound].matching
            {
                left = (left.lowerBound + 1)..<left.upperBound
                right = (right.lowerBound + 1)..<right.upperBound
            }
            while !left.isEmpty, !right.isEmpty,
                kept[left.upperBound - 1].matching == rewritten[right.upperBound - 1].matching
            {
                left = left.lowerBound..<(left.upperBound - 1)
                right = right.lowerBound..<(right.upperBound - 1)
            }
            if left.isEmpty, right.isEmpty { continue }
            let anchors = Self.anchors(in: kept, left, and: rewritten, right)
            guard !anchors.isEmpty else {
                found.append(Change(kept: left, rewritten: right))
                continue
            }
            var keptStart = left.lowerBound
            var rewrittenStart = right.lowerBound
            for anchor in anchors {
                pending.append((keptStart..<anchor.kept, rewrittenStart..<anchor.rewritten))
                keptStart = anchor.kept + 1
                rewrittenStart = anchor.rewritten + 1
            }
            pending.append((keptStart..<left.upperBound, rewrittenStart..<right.upperBound))
        }
        return found.sorted { $0.kept.lowerBound < $1.kept.lowerBound }
    }

    /// The words standing exactly once on each side, paired and left in order, which is what a run splits at.
    private static func anchors(
        in kept: [Token], _ left: Range<Int>, and rewritten: [Token], _ right: Range<Int>
    ) -> [(kept: Int, rewritten: Int)] {
        var keptCount: [String: Int] = [:]
        for index in left { keptCount[kept[index].matching, default: 0] += 1 }
        var place: [String: Int] = [:]
        var rewrittenCount: [String: Int] = [:]
        for index in right {
            rewrittenCount[rewritten[index].matching, default: 0] += 1
            place[rewritten[index].matching] = index
        }
        var paired: [(kept: Int, rewritten: Int)] = []
        for index in left where keptCount[kept[index].matching] == 1 {
            let word = kept[index].matching
            guard rewrittenCount[word] == 1, let found = place[word] else { continue }
            paired.append((index, found))
        }
        return inOrder(paired)
    }

    /// The longest run of pairs that keeps its order, so a word that moved does not drag the rest with it.
    private static func inOrder(_ pairs: [(kept: Int, rewritten: Int)]) -> [(kept: Int, rewritten: Int)] {
        var tails: [Int] = []
        var previous = [Int](repeating: -1, count: pairs.count)
        for (index, pair) in pairs.enumerated() {
            var low = 0
            var high = tails.count
            while low < high {
                let middle = (low + high) / 2
                if pairs[tails[middle]].rewritten < pair.rewritten { low = middle + 1 } else { high = middle }
            }
            previous[index] = low > 0 ? tails[low - 1] : -1
            if low == tails.count { tails.append(index) } else { tails[low] = index }
        }
        var chain: [(kept: Int, rewritten: Int)] = []
        var walk = tails.last ?? -1
        while walk >= 0 {
            chain.append(pairs[walk])
            walk = previous[walk]
        }
        return chain.reversed()
    }
}
