import UttrflowCore

extension LayoutWordsPass {
    /// The words before "the following" that let it announce a series; a preposition before it makes it a time span.
    private static let announcers: Set<String> = [
        "are", "is", "include", "includes", "need", "needs", "bring", "buy", "get", "list", "note", "cover",
        "covers",
        "have", "has", "want", "add", "pack", "order",
    ]

    /// Nouns that make "the following three" a span of time or a count, not a series.
    private static let measures: Set<String> = [
        "day", "days", "week", "weeks", "month", "months", "year", "years", "hour", "hours", "minute",
        "minutes",
        "night", "nights", "morning", "mornings", "second", "seconds", "time", "times",
    ]

    /// The most words an item of a spoken series may take; a longer stretch is a clause.
    private static let longestItem = 6

    /// Lays out "the following three items: milk, eggs and bread" as a list, only when the cue's count matches the series.
    func layOutEnumeratedSeries(_ draft: inout Draft) {
        guard layout.contains(.lists) || layout.contains(.singleLine) else { return }
        var live = draft.presentIndices
        var position = 1
        while position < live.count {
            defer { position += 1 }
            guard let series = enumeratedSeries(at: position, in: live, of: draft) else { continue }
            apply(series, to: &draft)
            live = draft.presentIndices
        }
    }

    private struct Series {
        let noun: Int
        let items: [[Int]]
        let conjunction: Int?
    }

    /// The series the cue "the following N things" at `position` announces, nil when anything about it is doubtful.
    private func enumeratedSeries(at position: Int, in live: [Int], of draft: Draft) -> Series? {
        guard draft.shape(at: live[position]).key == "following",
            draft.shape(at: live[position - 1]).key == "the",
            position == 1 || draft.shape(at: live[position - 2]).endsSentence
                || Self.announcers.contains(draft.shape(at: live[position - 2]).key),
            let count = Self.itemNumber(at: position + 1, in: live, of: draft),
            (2...9).contains(count.value)
        else { return nil }
        let noun = position + 1 + count.count
        guard noun + 1 < live.count else { return nil }
        let nounShape = draft.shape(at: live[noun])
        guard nounShape.key.count > 3, nounShape.key.hasSuffix("s"), !Self.measures.contains(nounShape.key),
            nounShape.suffix.isEmpty || nounShape.suffix == ":" || nounShape.suffix == ","
        else { return nil }
        let end = draft.sentenceEnd(from: noun + 1, in: live)
        var items: [[Int]] = [[]]
        for index in noun + 1..<end {
            let word = draft.words[live[index]]
            let shape = draft.shape(at: live[index])
            guard !word.isLayoutMark, !draft.isHindi(at: live[index]),
                !shape.suffix.contains(where: { ";:".contains($0) })
            else { return nil }
            items[items.count - 1].append(index)
            if shape.suffix.contains(","), index + 1 < end { items.append([]) }
        }
        // A series with no comma before its last item splits at its one "and" when the count is one short.
        if items.count + 1 == count.value, let last = items.last {
            let conjunctionPositions = last.indices.filter {
                $0 > 0 && draft.shape(at: live[last[$0]]).key == "and"
            }
            if conjunctionPositions.count == 1, let split = conjunctionPositions.first {
                items[items.count - 1] = Array(last[..<split])
                items.append(Array(last[split...]))
            }
        }
        var conjunction: Int?
        if let first = items.last?.first, draft.shape(at: live[first]).key == "and" {
            conjunction = first
            items[items.count - 1].removeFirst()
        }
        guard items.count == count.value,
            items.allSatisfy({ !$0.isEmpty && $0.count <= Self.longestItem })
        else { return nil }
        return Series(
            noun: live[noun], items: items.map { $0.map { live[$0] } },
            conjunction: conjunction.map { live[$0] })
    }

    /// Writes the series: a colon on the lead-in, a bullet before each item, no comma after one, and no "and" between them.
    private func apply(_ series: Series, to draft: inout Draft) {
        let mark = "\n" + Draft.bullet
        for (offset, item) in series.items.enumerated().reversed() {
            if offset < series.items.count - 1, let last = item.last {
                let shape = draft.shape(at: last)
                draft.replace(
                    at: last, with: shape.prefix + shape.core + shape.suffix.filter { $0 != "," }, by: Self.id
                )
            }
            var anchor = item[0]
            if offset == series.items.count - 1, let conjunction = series.conjunction {
                draft.remove(at: conjunction, by: Self.id)
                anchor = conjunction
            }
            draft.insert(mark, at: anchor, by: Self.id)
        }
        let shape = draft.shape(at: series.noun)
        draft.replace(at: series.noun, with: shape.prefix + shape.core + ":", by: Self.id)
    }
}
