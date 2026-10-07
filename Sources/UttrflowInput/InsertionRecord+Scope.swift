public import UttrflowCore

extension CommandScope {
    /// The part of `records` (newest last) that the scope covers, as one record an `EditTarget` takes; nil refuses.
    public func span(in records: [InsertionRecord]) -> InsertionRecord? {
        guard let newest = records.last else { return nil }
        if self == .dictation {
            let run = Array(records.reversed().adjacentRun().reversed())
            guard let oldest = run.first else { return nil }
            return InsertionRecord(
                field: newest.field, range: oldest.range.lowerBound..<newest.range.upperBound,
                text: run.map(\.text).joined())
        }
        guard let span = range(in: newest.text) else { return nil }
        let skipped = newest.text[..<span.lowerBound].utf16.count
        return InsertionRecord(
            field: newest.field, range: (newest.range.lowerBound + skipped)..<newest.range.upperBound,
            text: String(newest.text[span]))
    }
}

extension Sequence where Element == InsertionRecord {
    /// The leading records, newest first, each of which ends exactly where the one before it in the list begins.
    fileprivate func adjacentRun() -> [InsertionRecord] {
        var run: [InsertionRecord] = []
        for record in self {
            if let later = run.last, record.range.upperBound != later.range.lowerBound { break }
            run.append(record)
        }
        return run
    }
}
