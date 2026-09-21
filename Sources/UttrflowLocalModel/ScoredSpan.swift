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

    /// The span of a whole line past its typed opening, both as token ids, with each id's bytes read from `bytes`; nothing when no token is left to judge.
    init?(whole: [Int], typed: [Int], bytes: [[UInt8]]) {
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
        let start = max(index, 1)
        guard whole.count > start else { return nil }
        let first = Self.written(by: whole[start], in: bytes)
        // Only a token that begins with the typed remainder can be conditioned on it; any other join is judged as it stands.
        let holds = start == index && first.count > owed.count && first.starts(with: owed)
        self.init(start: start, owed: holds ? owed : [])
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

    /// The judged log-probabilities, the first read as P(token | typed remainder) by subtracting the log mass of every token that continues it.
    static func conditioned(_ taken: [Float], onMass mass: Float?) -> [Double] {
        guard let first = taken.first, let mass else { return taken.map(Double.init) }
        return [Double(min(first - mass, 0))] + taken.dropFirst().map(Double.init)
    }

    /// The log of the summed probabilities, computed from the largest so no term underflows.
    static func logSumExp(_ values: [Float]) -> Float? {
        guard let largest = values.max(), largest > -.infinity else { return nil }
        return largest + log(values.reduce(0) { $0 + exp($1 - largest) })
    }
}
