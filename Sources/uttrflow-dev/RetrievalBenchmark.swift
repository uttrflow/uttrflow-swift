private import Foundation
private import SQLite3

/// Times the retrieval the prediction engine will do, on a synthetic corpus of this Mac's making.
enum RetrievalBenchmark {
    /// Answers a prefix query the way phase 2 will, so the plan's numbers are checked and not assumed.
    struct Index {
        private let handle: OpaquePointer

        /// Builds the table, the index and the rows, in one transaction, in a temporary file.
        init?(_ corpus: [Entry]) {
            let path = NSTemporaryDirectory() + "uttrflow-probe-\(getpid()).sqlite"
            try? FileManager.default.removeItem(atPath: path)
            var handle: OpaquePointer?
            guard sqlite3_open(path, &handle) == SQLITE_OK, let handle else { return nil }
            self.handle = handle
            exec("PRAGMA journal_mode=WAL")
            exec("CREATE TABLE entry (surface_id INTEGER NOT NULL, text TEXT NOT NULL)")
            exec("BEGIN")
            var insert: OpaquePointer?
            sqlite3_prepare_v2(handle, "INSERT INTO entry VALUES (?, ?)", -1, &insert, nil)
            for (row, entry) in corpus.enumerated() {
                sqlite3_bind_int(insert, 1, Int32(row % 12))
                sqlite3_bind_text(insert, 2, String(decoding: entry.bytes, as: UTF8.self), -1, transient)
                sqlite3_step(insert)
                sqlite3_reset(insert)
            }
            sqlite3_finalize(insert)
            exec("COMMIT")
            exec("CREATE INDEX entry_prefix ON entry (surface_id, text)")
        }

        /// Counts the rows a range scan returns, which is the query the store will run.
        func rangeScan(_ prefix: String, surface: Int32) -> Int {
            count(
                "SELECT text FROM entry WHERE surface_id = ? AND text >= ? AND text < ? LIMIT 8",
                surface, prefix, upperBound(prefix))
        }

        /// Counts the same rows through `LIKE`, which cannot use the index.
        func likeScan(_ prefix: String, surface: Int32) -> Int {
            count(
                "SELECT text FROM entry WHERE surface_id = ? AND text LIKE ? LIMIT 8",
                surface, prefix + "%", nil)
        }

        func close() { sqlite3_close(handle) }

        private func count(_ sql: String, _ surface: Int32, _ first: String, _ second: String?) -> Int {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { return 0 }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int(statement, 1, surface)
            sqlite3_bind_text(statement, 2, first, -1, transient)
            if let second { sqlite3_bind_text(statement, 3, second, -1, transient) }
            var rows = 0
            while sqlite3_step(statement) == SQLITE_ROW { rows += 1 }
            return rows
        }

        /// The end of the prefix range, so `git c` scans up to but not including `git d`.
        private func upperBound(_ prefix: String) -> String {
            guard let last = prefix.unicodeScalars.last,
                let next = Unicode.Scalar(last.value + 1)
            else { return prefix }
            return String(prefix.unicodeScalars.dropLast()) + String(next)
        }

        private func exec(_ sql: String) { sqlite3_exec(handle, sql, nil, nil, nil) }

        /// Tells SQLite to copy a bound string, since Swift may free it before the step.
        private var transient: @convention(c) (UnsafeMutableRawPointer?) -> Void {
            unsafeBitCast(-1, to: (@convention(c) (UnsafeMutableRawPointer?) -> Void).self)
        }
    }

    /// One stored entry, held as bytes with the character set of its head precomputed.
    struct Entry {
        let bytes: [UInt8]
        let head: UInt64
    }

    /// Builds commands, URLs and phrases in roughly the mix a real corpus holds.
    static func corpus(_ count: Int, maskWidth: Int = 12) -> [Entry] {
        let verbs = ["git", "npm", "make", "swift", "docker", "kubectl", "aws", "brew", "curl"]
        let subs = ["commit", "checkout", "rebase", "push", "pull", "status", "run", "build", "verify"]
        let words = ["uttrflow", "swift", "main", "release", "corpus", "predict", "engine", "surface"]
        return (0..<count).map { index in
            let text: String
            switch index % 10 {
            case 0...4:
                text =
                    "\(verbs[index % verbs.count]) \(subs[(index / 3) % subs.count]) "
                    + "--\(words[index % words.count])=\(index)"
            case 5...7:
                text = "https://\(words[index % words.count]).example.com/\(index)"
            default:
                text = (0..<5).map { words[(index + $0 * 3) % words.count] }.joined(separator: " ")
            }
            let bytes = Array(text.utf8)
            return Entry(bytes: bytes, head: mask(bytes.prefix(maskWidth)))
        }
    }

    /// Counts the entries a plain prefix scan would return.
    static func exactPrefix(_ query: String, in corpus: [Entry]) -> Int {
        let needle = Array(query.utf8)
        return corpus.count { $0.bytes.count >= needle.count && $0.bytes.starts(with: needle) }
    }

    /// Counts the entries within an edit distance, optionally behind the character-mask prefilter.
    static func fuzzy(
        _ query: String, in corpus: [Entry], within distance: Int, prefiltered: Bool
    ) -> Int {
        let needle = Array(query.utf8)
        let needleMask = mask(needle[...])
        var found = 0
        for entry in corpus {
            if prefiltered, (needleMask & ~entry.head).nonzeroBitCount > distance { continue }
            if prefixDistance(needle, entry.bytes, distance) <= distance { found += 1 }
        }
        return found
    }

    /// The median of a hundred runs, in microseconds, after twenty warm-up runs.
    static func time(_ work: () -> Int) -> Double {
        var samples: [Double] = []
        for run in 0..<120 {
            let started = DispatchTime.now().uptimeNanoseconds
            _ = work()
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1000
            if run >= 20 { samples.append(elapsed) }
        }
        samples.sort()
        return samples[samples.count / 2]
    }

    /// A 64-bit set of the characters present, so a popcount can reject a candidate.
    private static func mask(_ bytes: ArraySlice<UInt8>) -> UInt64 {
        var set: UInt64 = 0
        for byte in bytes {
            let lowered = (byte >= 65 && byte <= 90) ? byte + 32 : byte
            set |= 1 << UInt64(lowered % 63)
        }
        return set
    }

    /// Damerau distance from the query to the nearest prefix of a candidate, capped at `limit`.
    private static func prefixDistance(_ query: [UInt8], _ candidate: [UInt8], _ limit: Int) -> Int {
        let rows = query.count
        guard rows > 0 else { return 0 }
        let columns = min(candidate.count, rows + limit)
        guard columns > 0 else { return rows }

        var beforeLast = [Int](repeating: 0, count: columns + 1)
        var last = (0...columns).map { $0 }
        var current = [Int](repeating: 0, count: columns + 1)

        for row in 1...rows {
            current[0] = row
            var best = row
            for column in 1...columns {
                let substitution = query[row - 1] == candidate[column - 1] ? 0 : 1
                var cell = min(
                    last[column] + 1, current[column - 1] + 1, last[column - 1] + substitution)
                if row > 1, column > 1, query[row - 1] == candidate[column - 2],
                    query[row - 2] == candidate[column - 1]
                {
                    cell = min(cell, beforeLast[column - 2] + 1)
                }
                current[column] = cell
                best = min(best, cell)
            }
            if best > limit { return limit + 1 }
            swap(&beforeLast, &last)
            swap(&last, &current)
        }
        return last.min() ?? limit + 1
    }
}
