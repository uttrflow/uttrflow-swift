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

/// The one calibration map: a score over a fitted temperature, squashed to a probability (see Docs/dictation-quality.md).
public struct TemperatureScaling: Sendable, Equatable {
    /// Searched range of the natural log of the temperature; wide enough for any score spread a fit sees.
    static let logTemperatureRange = -4.0...4.0
    /// Golden-section steps; fixed, so the same rows always give the same temperature.
    static let searchSteps = 80

    /// The positive divisor of the score; above 1 flattens an over-confident score, below 1 sharpens it.
    public let temperature: Double

    public init(temperature: Double) {
        self.temperature = temperature.isFinite && temperature > 0 ? temperature : 1
    }

    /// The calibrated probability of one score; never decreasing in the score and always in [0, 1].
    public func probability(_ score: Double) -> Double {
        LinearScorer.sigmoid(score / temperature)
    }

    /// The digest of this calibration's stored form.
    public var digest: String {
        FitArtifact.digest([("temperature", [temperature])])
    }

    /// Fits by minimising log-loss over the temperature; scores are read in the caller's order.
    public static func fit(scores: [Double], labels: [Bool]) -> TemperatureScaling {
        let pairs = Array(zip(scores, labels))
        guard !pairs.isEmpty else { return TemperatureScaling(temperature: 1) }
        func loss(_ logTemperature: Double) -> Double {
            let temperature = exp(logTemperature)
            var total = 0.0
            for (score, label) in pairs {
                let value = max(1e-12, min(1 - 1e-12, LinearScorer.sigmoid(score / temperature)))
                total -= log(label ? value : 1 - value)
            }
            return total
        }
        let ratio = (5.0.squareRoot() - 1) / 2
        var low = logTemperatureRange.lowerBound
        var high = logTemperatureRange.upperBound
        for _ in 0..<searchSteps {
            let first = high - ratio * (high - low)
            let second = low + ratio * (high - low)
            if loss(first) <= loss(second) { high = second } else { low = first }
        }
        return TemperatureScaling(temperature: exp((low + high) / 2))
    }
}
