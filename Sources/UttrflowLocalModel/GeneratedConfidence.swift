import Foundation
private import UttrflowPredict

/// The confidence of the lines recent passes wrote, so the gate reads a line's score without a second pass.
struct ConfidenceMemory {
    /// How many lines are remembered, enough for a turn's leader, its alternatives and a line kept across keystrokes.
    static let capacity = 64

    private var scores: [String: Double] = [:]
    private var order: [String] = []

    /// The mean log-probability per token the latest pass to write `line` gave it.
    func confidence(of line: String) -> Double? { scores[line] }

    /// Remembers what a pass measured, the newest pass winning and the oldest lines let go past the capacity.
    mutating func remember(_ measured: [String: Double]) {
        for (line, confidence) in measured {
            if scores.updateValue(confidence, forKey: line) == nil { order.append(line) }
        }
        while order.count > Self.capacity { scores[order.removeFirst()] = nil }
    }

    /// Forgets every line, as a release of the weights does.
    mutating func forgetEverything() {
        scores = [:]
        order = []
    }
}

/// Finds the tokens that wrote each line past what was typed, and scores the line from them.
enum GeneratedConfidence {
    /// Each line's mean log-probability per token, read from the pass that wrote `text` after `written`; a line the pass never spelt out is left unscored.
    static func confidences(
        of lines: [String], typed: String, written: String, text: String, tokens: [Int],
        logProbabilities: [Double], bytes: [[UInt8]]
    ) -> [String: Double] {
        let ends = byteEnds(of: tokens, bytes: bytes)
        let whole = Array((written + text).utf8)
        let offset = written.utf8.count
        var cursor = 0
        var scored: [String: Double] = [:]
        for line in lines {
            guard let (start, end) = span(of: line, typed: typed, in: whole, from: cursor) else { continue }
            cursor = end
            let range = (start - offset)..<(end - offset)
            guard
                let confidence = confidence(
                    over: range, ends: ends, logProbabilities: logProbabilities)
            else { continue }
            scored[line] = confidence
        }
        return scored
    }

    /// Where the line's words past the typing sit in the pass, as bytes of `whole`, searched from `cursor` so each line is found after the last.
    static func span(of line: String, typed: String, in whole: [UInt8], from cursor: Int) -> (Int, Int)? {
        let lineBytes = Array(line.utf8)
        let typedBytes = CompletionText.typedPart(of: line, following: typed).utf8.count
        // The whole line pins the tail to its own occurrence; a line the parser reshaped is found by its tail alone.
        if let start = firstIndex(of: lineBytes, in: whole, from: cursor) {
            guard lineBytes.count > typedBytes else { return nil }
            return (start + typedBytes, start + lineBytes.count)
        }
        let tail = Array(lineBytes[typedBytes...])
        guard !tail.isEmpty, let start = firstIndex(of: tail, in: whole, from: cursor) else { return nil }
        return (start, start + tail.count)
    }

    /// The mean log-probability of the tokens overlapping `range`, or the weakest when it is under the plausibility floor; nothing when none does.
    static func confidence(over range: Range<Int>, ends: [Int], logProbabilities: [Double]) -> Double? {
        var picked: [Double] = []
        var start = 0
        for (index, end) in ends.enumerated() where index < logProbabilities.count {
            defer { start = end }
            // A token wholly before the tail was typed or prefilled, and one past it was never drawn.
            guard end > start, end > range.lowerBound, start < range.upperBound else { continue }
            picked.append(logProbabilities[index])
        }
        guard let weakest = picked.min() else { return nil }
        // One token the model finds implausible is an invention a mean of many likely tokens would hide.
        guard weakest >= Verification.plausibilityFloor else { return weakest }
        return picked.reduce(0, +) / Double(picked.count)
    }

    /// Where each sampled token's bytes end in the pass's text.
    static func byteEnds(of tokens: [Int], bytes: [[UInt8]]) -> [Int] {
        var total = 0
        return tokens.map { id in
            total += id < bytes.count ? bytes[id].count : 0
            return total
        }
    }

    /// The first place `needle` occurs in `haystack` at or after `from`.
    private static func firstIndex(of needle: [UInt8], in haystack: [UInt8], from: Int) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count, from <= haystack.count - needle.count else {
            return nil
        }
        for start in from...(haystack.count - needle.count)
        where haystack[start] == needle[0] && Array(haystack[start..<(start + needle.count)]) == needle {
            return start
        }
        return nil
    }
}
