// Keeps a sign-off from being signed with a name the model only read on screen.

import Foundation

/// A closing such as "Kind regards," and the signature a completion may hang after it.
enum SignOff {
    /// Closings a signature follows, compared lowercased with the comma and outer spaces removed.
    static let closings: Set<String> = [
        "all the best", "best", "best regards", "best wishes", "cheers", "kind regards", "many thanks",
        "regards", "sincerely", "take care", "thank you", "thanks", "thanks again", "warm regards",
        "warmly", "with thanks", "yours", "yours sincerely", "yours truly",
    ]

    /// The line cut back to its closing when what follows it is a name found only on screen, or nothing when that leaves no continuation.
    static func unsigned(_ line: String, typed: String, screen: [String], ownLines: [String]) -> String? {
        guard let comma = line.firstIndex(of: ","),
            closings.contains(line[..<comma].trimmingCharacters(in: .whitespaces).lowercased())
        else { return line }
        let signature = words(of: String(line[line.index(after: comma)...]))
        // A signature is a name: a capitalised word or three, never a sentence.
        guard (1...longestSignature).contains(signature.count),
            signature.allSatisfy({ $0.first?.isUppercase == true })
        else { return line }
        let onScreen = Set(screen.flatMap(words(of:)).map { $0.lowercased() })
        let own = Set(ownLines.flatMap(words(of:)).map { $0.lowercased() })
        // A name the person has written themselves is theirs to sign with; one only the screen holds is somebody else's.
        guard signature.map({ $0.lowercased() }).allSatisfy({ onScreen.contains($0) && !own.contains($0) })
        else { return line }
        let closing = String(line[...comma])
        return closing.count > typed.count ? closing : nil
    }

    /// The most words a signature after a closing runs to.
    static let longestSignature = 3

    /// The words of a text, with the punctuation around them dropped.
    private static func words(of text: String) -> [String] {
        text.split { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "-" }.map(String.init)
    }
}
