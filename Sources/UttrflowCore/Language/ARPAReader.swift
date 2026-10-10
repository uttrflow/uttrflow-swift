// Reads an ARPA back-off language model into an NGramModel, refusing any file outside its stated limits.

/// Why an ARPA file could not be read.
public enum ARPAError: Error, Equatable, Sendable {
    /// The text is longer than the reader's byte limit.
    case tooLarge(bytes: Int)
    /// The file declares more n-grams than the reader's limit.
    case tooManyNGrams(count: Int)
    /// The file declares an order this reader does not hold.
    case unsupportedOrder(Int)
    /// The file declares more distinct words than a packed key can name.
    case tooManyWords(count: Int)
    /// The line at this 1-based number is not the shape its section needs.
    case malformed(line: Int)
    /// A section holds a different number of n-grams than the header declares.
    case countMismatch(order: Int, declared: Int, found: Int)
    /// The same n-gram appears twice.
    case duplicate(line: Int)
}

/// The size limits an ARPA file is checked against before any n-gram is kept.
public struct ARPALimits: Sendable, Equatable {
    /// The largest text accepted, in UTF-8 bytes.
    public let maxBytes: Int
    /// The largest total number of n-grams accepted.
    public let maxNGrams: Int

    public init(maxBytes: Int, maxNGrams: Int) {
        self.maxBytes = maxBytes
        self.maxNGrams = maxNGrams
    }

    /// Room for a pruned 3-gram model of a few million n-grams.
    public static let standard = ARPALimits(maxBytes: 256 << 20, maxNGrams: 8_000_000)
}

/// Parses the ARPA text format: a `\data\` header of counts, one section per order, and `\end\`.
public enum ARPAReader {
    /// The model in `text`, or the first reason it cannot be used.
    public static func model(
        from text: String, limits: ARPALimits = .standard
    ) throws(ARPAError) -> NGramModel {
        let bytes = text.utf8.count
        guard bytes <= limits.maxBytes else { throw .tooLarge(bytes: bytes) }
        var parser = Parser(limits: limits)
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            try parser.read(line, number: index + 1)
        }
        return try parser.finish()
    }
}

private struct Parser {
    let limits: ARPALimits
    var declared: [Int: Int] = [:]
    var found: [Int: Int] = [:]
    var section = 0
    var ended = false
    var ids: [String: UInt32] = [:]
    var entries: [UInt64: NGramEntry] = [:]

    init(limits: ARPALimits) {
        self.limits = limits
    }

    mutating func read(_ raw: Substring, number: Int) throws(ARPAError) {
        let line = raw.trimmingWhitespace()
        guard !line.isEmpty, !ended else { return }
        if line == "\\data\\" { return }
        if line == "\\end\\" { ended = true; return }
        if line.hasPrefix("ngram ") { return try declare(line, number: number) }
        if line.hasPrefix("\\"), line.hasSuffix("-grams:") {
            guard let order = Int(line.dropFirst().dropLast(7)), declared[order] != nil else {
                throw .malformed(line: number)
            }
            section = order
            return
        }
        guard section > 0 else { throw .malformed(line: number) }
        try add(line, number: number)
    }

    mutating func declare(_ line: Substring, number: Int) throws(ARPAError) {
        let parts = line.dropFirst(6).split(separator: "=")
        guard parts.count == 2, let order = Int(parts[0]), let count = Int(parts[1]), count >= 0 else {
            throw .malformed(line: number)
        }
        guard (1...NGramModel.maxOrder).contains(order) else { throw .unsupportedOrder(order) }
        declared[order] = count
        let total = declared.values.reduce(0, +)
        guard total <= limits.maxNGrams else { throw .tooManyNGrams(count: total) }
    }

    mutating func add(_ line: Substring, number: Int) throws(ARPAError) {
        let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard fields.count == section + 1 || fields.count == section + 2,
            let probability = Float(fields[0]), probability.isFinite
        else { throw .malformed(line: number) }
        var backoff: Float = 0
        if fields.count == section + 2 {
            guard let value = Float(fields[section + 1]), value.isFinite else {
                throw .malformed(line: number)
            }
            backoff = value
        }
        let wordIDs = try fields[1...section].map { word throws(ARPAError) in try id(for: String(word)) }
        let key = NGramModel.key(wordIDs)
        guard
            entries.updateValue(NGramEntry(log10Probability: probability, log10Backoff: backoff), forKey: key)
                == nil
        else {
            throw .duplicate(line: number)
        }
        found[section, default: 0] += 1
    }

    mutating func id(for word: String) throws(ARPAError) -> UInt32 {
        if let known = ids[word] { return known }
        guard ids.count < NGramModel.maxVocabulary else { throw .tooManyWords(count: ids.count + 1) }
        let next = UInt32(ids.count + 1)
        ids[word] = next
        return next
    }

    func finish() throws(ARPAError) -> NGramModel {
        guard ended, let order = declared.keys.max(), declared.keys.sorted() == Array(1...order) else {
            throw .malformed(line: 0)
        }
        for (level, count) in declared where found[level, default: 0] != count {
            throw .countMismatch(order: level, declared: count, found: found[level, default: 0])
        }
        return NGramModel(order: order, ids: ids, entries: entries)
    }
}

private extension Substring {
    func trimmingWhitespace() -> Substring {
        let isSpace: (Character) -> Bool = { $0 == " " || $0 == "\t" || $0 == "\r" }
        guard let first = firstIndex(where: { !isSpace($0) }), let last = lastIndex(where: { !isSpace($0) })
        else {
            return self[endIndex...]
        }
        return self[first...last]
    }
}
