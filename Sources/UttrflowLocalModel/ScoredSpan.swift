import Foundation

/// Where the model's judgement of a candidate starts, and what of a word cut inside a token the first judged token must still write. See `Docs/predict.md`, the scorer.
struct ScoredSpan: Equatable {
    /// The index of the first token judged, never the first token of the line, since nothing predicts it.
    let start: Int
    /// The typed bytes the token at `start` writes first, empty when what was typed ends on a token boundary.
    let owed: [UInt8]

    init(start: Int, owed: [UInt8]) {
        self.start = start
        self.owed = owed
    }

    /// Where a whole line's tokens leave its typed opening: the first of them that writes what the line adds, and the typed bytes that token writes before it.
    struct Divergence: Equatable {
        let index: Int
        let owed: [UInt8]
    }

    /// The span of a whole line past its typed opening, both as token ids, with each id's bytes read from `bytes`; nothing when no token is left to judge.
    init?(whole: [Int], typed: [Int], bytes: [[UInt8]]) {
        self.init(whole: whole, past: Self.divergence(whole: whole, typed: typed, bytes: bytes), bytes: bytes)
    }

    /// The span a divergence leaves to judge, with each id's bytes read from `bytes`; nothing when no token is left.
    init?(whole: [Int], past divergence: Divergence, bytes: [[UInt8]]) {
        let start = max(divergence.index, 1)
        guard whole.count > start else { return nil }
        let first = Self.written(by: whole[start], in: bytes)
        // Only a token that begins with the typed remainder can be conditioned on it; any other join is judged as it stands.
        let holds =
            start == divergence.index && first.count > divergence.owed.count
            && first.starts(with: divergence.owed)
        self.init(start: start, owed: holds ? divergence.owed : [])
    }

    /// Where the whole line's tokens stop agreeing with the typed opening's own, which costs a second tokenising of the opening.
    static func divergence(whole: [Int], typed: [Int], bytes: [[UInt8]]) -> Divergence {
        var shared = 0
        while shared < typed.count, shared < whole.count, typed[shared] == whole[shared] {
            shared += 1
        }
        // The typed tokens past the divergence are what the line's own tokens still have to write.
        var owed = typed[shared...].flatMap { Self.written(by: $0, in: bytes) }
        var index = shared
        // A line token that writes only typed bytes was typed, so it is passed over rather than judged.
        while !owed.isEmpty, index < whole.count {
            let written = Self.written(by: whole[index], in: bytes)
            guard !written.isEmpty, written.count <= owed.count, owed.starts(with: written) else { break }
            owed.removeFirst(written.count)
            index += 1
        }
        return Divergence(index: index, owed: owed)
    }

    /// The same divergence from the whole line's tokens alone, walked back from its end until they have written `continuation`; nothing when their bytes do not spell it, which is the only case the opening is tokenised for.
    static func divergence(whole: [Int], continuation: [UInt8], bytes: [[UInt8]]) -> Divergence? {
        var tail: [UInt8] = []
        var index = whole.count
        while tail.count < continuation.count, index > 0 {
            index -= 1
            let written = Self.written(by: whole[index], in: bytes)
            guard !written.isEmpty else { return nil }
            tail = written + tail
        }
        // A tail that ends in anything but the continuation is a vocabulary that cannot be read back as text.
        guard tail.count >= continuation.count, tail.suffix(continuation.count).elementsEqual(continuation)
        else { return nil }
        return Divergence(index: index, owed: Array(tail.dropLast(continuation.count)))
    }

    /// The bytes a token writes, or none for an id the vocabulary does not hold.
    static func written(by id: Int, in bytes: [[UInt8]]) -> [UInt8] {
        bytes.indices.contains(id) ? bytes[id] : []
    }

    /// Every token the typed remainder could go on as: those that write it first, which the first judged token is among.
    static func continuing(_ owed: [UInt8], in bytes: [[UInt8]]) -> [Int] {
        guard !owed.isEmpty else { return [] }
        return bytes.indices.filter { bytes[$0].count >= owed.count && bytes[$0].starts(with: owed) }
    }

    /// Every token that writes the owed bytes first, read from the vocabulary's prebuilt prefix index.
    static func continuing(_ owed: [UInt8], in vocabulary: TokenHealing.Vocabulary) -> [Int] {
        guard !owed.isEmpty else { return [] }
        return vocabulary.continuing(owed)
    }

    /// The judged log-probabilities, the first read as P(token | typed remainder) by subtracting the log mass of every token that continues it.
    static func conditioned(_ taken: [Float], onMass mass: Float?) -> [Double] {
        guard let first = taken.first, let mass else { return taken.map(Double.init) }
        if mass == -.infinity { return taken.map(Double.init) }
        if mass.isNaN || mass == .infinity {
            return [-Double.infinity] + taken.dropFirst().map(Double.init)
        }
        return [Double(min(first - mass, 0))] + taken.dropFirst().map(Double.init)
    }

    /// The log of the summed probabilities, computed from the largest so no term underflows.
    static func logSumExp(_ values: [Float]) -> Float? {
        guard let largest = values.max(), largest > -.infinity else { return nil }
        return largest + log(values.reduce(0) { $0 + exp($1 - largest) })
    }
}
