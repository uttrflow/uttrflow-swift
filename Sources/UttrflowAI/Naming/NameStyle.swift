internal import UttrflowCore

/// How the words of one name are joined and cased, the single writer of every identifier style.
enum NameStyle: Sendable, Equatable, CaseIterable {
    case camel, pascal, snake, screamingSnake, kebab

    /// The style an identifier already written is in, or `nil` for one that joins no words or mixes styles.
    init?(identifier: String) {
        let name = identifier.drop { $0 == "_" }
        let letters = name.filter(\.isLetter)
        guard let first = name.first, first.isLetter else { return nil }
        if name.contains("_") {
            if letters.allSatisfy(\.isUppercase) {
                self = .screamingSnake
            } else if letters.allSatisfy(\.isLowercase) {
                self = .snake
            } else {
                return nil
            }
        } else if letters.allSatisfy(\.isUppercase) || letters.allSatisfy(\.isLowercase) {
            return nil
        } else {
            self = first.isUppercase ? .pascal : .camel
        }
    }

    /// The words written as one name in this style; each word is lower-cased first, so the speaker's casing never leaks in.
    func write(_ words: [String]) -> String {
        let lower = words.map { $0.lowercased() }
        switch self {
        case .camel:
            return lower.enumerated().map { $0 == 0 ? $1 : WordShape.capitalised($1) }.joined()
        case .pascal: return lower.map(WordShape.capitalised).joined()
        case .snake: return lower.joined(separator: "_")
        case .screamingSnake: return lower.joined(separator: "_").uppercased()
        case .kebab: return lower.joined(separator: "-")
        }
    }
}
