import Foundation

/// Replaces every text a recorded snapshot holds with invented text of the same shape, so a fixture never carries what was on screen.
enum SnapshotRedaction {
    /// The attributes that name what an element is rather than what it holds, kept as the application answered them.
    static let structuralAttributes: Set<String> = ["AXRole", "AXSubrole", "AXRoleDescription"]

    /// What a window title or a document keeps besides its extension.
    static let placeholderName = "Untitled"

    /// The longest extension a title keeps, so a sentence ending in a full stop is not read as a file name.
    static let longestExtension = 5

    /// The snapshot with each text answer invented, window titles and documents cut to their extension.
    static func redacted(_ snapshot: AccessibilitySnapshot) -> AccessibilitySnapshot {
        var synthesiser = Synthesiser()
        return AccessibilitySnapshot(
            schema: snapshot.schema, family: snapshot.family, windowTitle: title(snapshot.windowTitle),
            document: document(snapshot.document), focused: synthesiser.element(snapshot.focused),
            window: snapshot.window.map { synthesiser.element($0) })
    }

    /// Invented text with the same UTF-16 length, line breaks, script and per-character class as `text`.
    static func synthesise(_ text: String) -> String {
        var synthesiser = Synthesiser()
        return synthesiser.text(text)
    }

    /// A window title cut to its file extension, the name before it replaced.
    static func title(_ title: String?) -> String? {
        guard let title, !title.isEmpty else { return title }
        let extensions = title.split(whereSeparator: \.isWhitespace).lazy.compactMap {
            fileExtension(of: String($0))
        }
        return extensions.first.map { "\(placeholderName).\($0)" } ?? placeholderName
    }

    /// A document address kept to its scheme and extension, so neither a path nor a host survives.
    static func document(_ document: String?) -> String? {
        guard let document else { return nil }
        guard let url = URL(string: document), let scheme = url.scheme else { return title(document) }
        let name = title(url.lastPathComponent) ?? placeholderName
        return scheme == "file" ? "file:///\(name)" : "\(scheme)://example.com/\(name)"
    }

    /// The extension of one word of a title, when it is short, alphanumeric and in one case.
    static func fileExtension(of word: String) -> String? {
        let candidate = (word as NSString).pathExtension
        guard (1...longestExtension).contains(candidate.count),
            !(word as NSString).deletingPathExtension.isEmpty,
            candidate.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
            candidate.contains(where: \.isLetter),
            candidate == candidate.lowercased() || candidate == candidate.uppercased()
        else { return nil }
        return candidate
    }

    /// The class a replacement keeps when no character of the same Unicode category is near the original.
    enum Group: Equatable {
        case letter, mark, number, punctuation, symbol, other

        init(_ category: Unicode.GeneralCategory) {
            switch category {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
                self = .letter
            case .nonspacingMark, .spacingMark, .enclosingMark: self = .mark
            case .decimalNumber, .letterNumber, .otherNumber: self = .number
            case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
                .initialPunctuation, .finalPunctuation, .otherPunctuation:
                self = .punctuation
            case .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol: self = .symbol
            default: self = .other
            }
        }
    }

    /// Picks each replacement from the same 128-character block, which keeps its script and its UTF-16 width.
    struct Synthesiser {
        /// The characters that would let invented text form an address, a host or a link.
        static let neverWritten: Set<Unicode.Scalar> = ["@", ".", ":", "/"]

        private var candidates: [CandidateKey: [Unicode.Scalar]] = [:]

        private struct CandidateKey: Hashable {
            let block: UInt32
            let category: String
            let emoji: Bool
        }

        mutating func element(_ element: AccessibilitySnapshot.Element) -> AccessibilitySnapshot.Element {
            let isWindow = element.attributes["AXRole"]?.text == "AXWindow"
            var attributes: [String: AccessibilitySnapshot.Answer] = [:]
            for (name, answer) in element.attributes {
                attributes[name] = self.answer(answer, named: name, inWindow: isWindow)
            }
            return AccessibilitySnapshot.Element(
                attributes: attributes,
                rangedText: element.rangedText.map { answer($0, named: "", inWindow: false) },
                children: element.children.map { self.element($0) })
        }

        private mutating func answer(
            _ answer: AccessibilitySnapshot.Answer, named name: String, inWindow: Bool
        ) -> AccessibilitySnapshot.Answer {
            guard let text = answer.text, !SnapshotRedaction.structuralAttributes.contains(name) else {
                return answer
            }
            let replaced: String? =
                switch name {
                case "AXDocument": SnapshotRedaction.document(text)
                case "AXTitle" where inWindow: SnapshotRedaction.title(text)
                default: self.text(text)
                }
            return AccessibilitySnapshot.Answer(
                kind: answer.kind, text: replaced, number: answer.number, milliseconds: answer.milliseconds)
        }

        /// The same text always becomes the same invented text, so the field and its place in the window stay equal.
        mutating func text(_ text: String) -> String {
            var scalars = String.UnicodeScalarView()
            for (position, scalar) in text.unicodeScalars.enumerated() {
                scalars.append(replacement(for: scalar, at: position))
            }
            return String(scalars)
        }

        /// Another character of the same category from the same block, or of the same class where the category stands alone.
        private mutating func replacement(for scalar: Unicode.Scalar, at position: Int) -> Unicode.Scalar {
            let properties = scalar.properties
            guard !Self.isLayout(scalar) else { return scalar }
            let block = scalar.value & ~0x7F
            let emoji = properties.isEmojiPresentation
            let category = properties.generalCategory
            let exact = pool(block: block, emoji: emoji, key: "\(category)") { $0 == category }
            if let pick = pick(from: exact, avoiding: scalar, at: position) { return pick }
            let group = Group(category)
            let near = pool(block: block, emoji: emoji, key: "\(group)") { Group($0) == group }
            return pick(from: near, avoiding: scalar, at: position) ?? Self.fallback(for: scalar)
        }

        /// Spaces, line breaks, tabs and invisible joiners, which shape the text without saying anything.
        static func isLayout(_ scalar: Unicode.Scalar) -> Bool {
            switch scalar.properties.generalCategory {
            case .spaceSeparator, .lineSeparator, .paragraphSeparator, .control, .format: true
            default: scalar.properties.isVariationSelector
            }
        }

        private mutating func pool(
            block: UInt32, emoji: Bool, key: String, matching: (Unicode.GeneralCategory) -> Bool
        ) -> [Unicode.Scalar] {
            let candidateKey = CandidateKey(block: block, category: key, emoji: emoji)
            if let known = candidates[candidateKey] { return known }
            let found = (block..<block + 0x80).compactMap(Unicode.Scalar.init).filter {
                matching($0.properties.generalCategory) && $0.properties.isEmojiPresentation == emoji
                    && !Self.isLayout($0) && !Self.neverWritten.contains($0)
            }
            candidates[candidateKey] = found
            return found
        }

        /// A character chosen by position alone, so the replacement says nothing about the original but that it differs.
        private func pick(
            from pool: [Unicode.Scalar], avoiding original: Unicode.Scalar, at position: Int
        ) -> Unicode.Scalar? {
            guard pool.count > 1 || pool.first.map({ $0 != original }) == true else { return nil }
            let index = (position &* 7 &+ 3) % pool.count
            return pool[index] != original ? pool[index] : pool[(index + 1) % pool.count]
        }

        /// A fixed character of the same UTF-16 width, for a block with nothing else in its class.
        static func fallback(for scalar: Unicode.Scalar) -> Unicode.Scalar {
            let wide = scalar.utf16.count > 1
            let first: Unicode.Scalar = wide ? "\u{1D400}" : "x"
            let second: Unicode.Scalar = wide ? "\u{1D401}" : "y"
            return scalar == first ? second : first
        }
    }
}
