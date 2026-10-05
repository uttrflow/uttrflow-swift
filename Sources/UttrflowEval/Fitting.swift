// Fits the parameters dictation layers ship: one implementation, in Swift, beside the scoring it is judged by.

import CryptoKit
import Foundation

/// How a fit's artifact is stored and digested; the reproducibility rules are in Docs/dictation-quality.md.
public enum FitArtifact {
    /// Significant digits a stored float keeps, so a last-bit difference cannot change the digest.
    public static let significantDigits = 12

    /// One float in its stored form.
    public static func stored(_ value: Double) -> String {
        guard value.isFinite else { return value.isNaN ? "nan" : (value > 0 ? "inf" : "-inf") }
        return String(format: "%.\(significantDigits - 1)e", value == 0 ? 0.0 : value)
    }

    /// The SHA-256 of a named list of floats in stored form, hex encoded.
    public static func digest(_ fields: [(name: String, values: [Double])]) -> String {
        let text = fields.map { "\($0.name)=" + $0.values.map(stored).joined(separator: ",") }
            .joined(separator: "\n")
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// One labelled row for a fit: the layer's features for a candidate and whether that candidate was right.
public struct FitRow: Sendable, Equatable {
    public let features: [Double]
    public let label: Bool

    public init(features: [Double], label: Bool) {
        self.features = features
        self.label = label
    }
}

/// A linear scorer over a handful of features, fitted by L2-regularised logistic regression.
public struct LinearScorer: Sendable, Equatable {
    public let weights: [Double]
    public let bias: Double

    public init(weights: [Double], bias: Double) {
        self.weights = weights
        self.bias = bias
    }

    /// The raw score of one feature vector; higher means more likely right.
    public func score(_ features: [Double]) -> Double {
        var total = bias
        for (weight, value) in zip(weights, features) { total += weight * value }
        return total
    }

    /// The probability the scorer gives one feature vector.
    public func probability(_ features: [Double]) -> Double {
        LinearScorer.sigmoid(score(features))
    }

    /// The digest of this scorer's stored form.
    public var digest: String {
        FitArtifact.digest([("weights", weights), ("bias", [bias])])
    }

    static func sigmoid(_ value: Double) -> Double {
        1 / (1 + exp(-value))
    }

    /// Fits by full-batch gradient descent; deterministic for the same rows, so two fits never differ.
    public static func fit(
        _ rows: [FitRow], iterations: Int = 200, learningRate: Double = 0.5, l2: Double = 1e-4
    ) -> LinearScorer {
        let width = rows.first?.features.count ?? 0
        var weights = [Double](repeating: 0, count: width)
        var bias = 0.0
        guard !rows.isEmpty else { return LinearScorer(weights: weights, bias: bias) }
        let count = Double(rows.count)
        var gradient = [Double](repeating: 0, count: width)
        for _ in 0..<iterations {
            for index in gradient.indices { gradient[index] = 0 }
            var biasGradient = 0.0
            for row in rows {
                var total = bias
                for index in 0..<width { total += weights[index] * row.features[index] }
                let error = sigmoid(total) - (row.label ? 1 : 0)
                biasGradient += error
                for index in 0..<width { gradient[index] += error * row.features[index] }
            }
            for index in 0..<width {
                weights[index] -= learningRate * (gradient[index] / count + l2 * weights[index])
            }
            bias -= learningRate * biasGradient / count
        }
        return LinearScorer(weights: weights, bias: bias)
    }
}

/// A monotone map from a raw score to a calibrated probability, fitted by pool-adjacent-violators.
public struct MonotoneCalibration: Sendable, Equatable {
    /// The upper score of each step, ascending.
    public let thresholds: [Double]
    /// The probability for scores up to the matching threshold; never decreasing.
    public let probabilities: [Double]

    /// The calibrated probability of one score; scores above the last step take the last value.
    public func probability(_ score: Double) -> Double {
        guard let last = probabilities.last else { return 0 }
        var low = 0
        var high = thresholds.count
        while low < high {
            let middle = (low + high) / 2
            if thresholds[middle] < score { low = middle + 1 } else { high = middle }
        }
        return low < probabilities.count ? probabilities[low] : last
    }

    /// The digest of this calibration's stored form.
    public var digest: String {
        FitArtifact.digest([("thresholds", thresholds), ("probabilities", probabilities)])
    }

    /// Fits from scores and whether each was right; equal scores sort wrong before right, whatever the input order.
    public static func fit(scores: [Double], labels: [Bool]) -> MonotoneCalibration {
        let pairs = zip(scores, labels).sorted { $0.0 != $1.0 ? $0.0 < $1.0 : (!$0.1 && $1.1) }
        var blocks: [(upper: Double, sum: Double, weight: Double)] = []
        for (score, label) in pairs {
            blocks.append((score, label ? 1 : 0, 1))
            while blocks.count > 1,
                let last = blocks.last, let previous = blocks.dropLast().last,
                previous.sum / previous.weight >= last.sum / last.weight
            {
                blocks.removeLast(2)
                blocks.append((last.upper, previous.sum + last.sum, previous.weight + last.weight))
            }
        }
        return MonotoneCalibration(
            thresholds: blocks.map(\.upper), probabilities: blocks.map { $0.sum / $0.weight })
    }
}
