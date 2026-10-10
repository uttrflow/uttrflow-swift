// The prompt's version, computed from the text the model reads rather than kept by hand.
import CryptoKit
import Foundation
import FoundationModels
import UttrflowCore

extension PromptBuilder {
    /// A fingerprint of everything the shipping prompt shows the model, so a measured result names the exact prompt.
    public static let version = standard.version(answeringIn: answerSchema)

    /// Every fixed label a situation line can carry, each of which the model reads in a user prompt.
    static let labels = [
        AppContextDescriber.label, AppContextDescriber.selectionLabel, caretLabel, doubtfulLabel,
        preservedLabel,
    ]

    /// The structured answer's schema, guide description included, as the model is given it.
    static var answerSchema: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(CleanedDictation.generationSchema) else {
            return CleanedDictation.generationSchema.debugDescription
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// The fingerprint of the instructions for every place, the situation labels and the answer's schema.
    func version(answeringIn schema: String) -> String {
        Self.fingerprint(Destination.allCases.map { instructions(for: $0) } + Self.labels + [schema])
    }

    /// Twelve hex digits of a SHA-256 over the parts, each length-prefixed so no two splits of one text collide.
    public static func fingerprint(_ parts: [String]) -> String {
        var hash = SHA256()
        for part in parts { hash.update(data: Data("\(part.utf8.count):\(part)".utf8)) }
        return hash.finalize().prefix(6).map { byte in
            let digits = String(byte, radix: 16)
            return digits.count == 1 ? "0\(digits)" : digits
        }.joined()
    }
}
