/// A place in markup or a style sheet where a spoken word has one meaning, so a notation row can name it.
package enum MarkupSlot: String, Decodable, Sendable, Equatable {
    /// Text content of an HTML document, where a tag may begin.
    case text
    /// Inside a start or end tag, after its opening angle bracket.
    case tag
    /// Where a style rule's selector is written.
    case selector
    /// Inside a declaration block, where a property name is written.
    case property
    /// After a property's colon, where its value is written.
    case value
}

/// Where the caret stands in HTML or CSS, read from the text before it.
package enum MarkupPosition: Sendable, Equatable {
    case slot(MarkupSlot)
    /// Inside a comment or a quoted value, where the words are the writer's own.
    case quoted

    /// The slot spoken notation may be written in, or `nil` inside a comment or a quoted value.
    package var slot: MarkupSlot? {
        if case .slot(let slot) = self { return slot }
        return nil
    }

    /// Reads the position at the end of `precedingText` for a document of `language`; `nil` when it is not markup or not known.
    package static func at(_ precedingText: String?, language: CodeLanguage?) -> MarkupPosition? {
        guard let precedingText, let language else { return nil }
        let text = Array(InsertionPoint.visibleText(precedingText))
        switch language {
        case .css: return Style.position(of: text[...])
        case .html: return Markup.position(of: text)
        default: return nil
        }
    }

    // MARK: HTML

    private enum Markup {
        enum State {
            case text, tag, comment
            case value(quote: Character)
            case raw(element: String)
        }

        static func position(of text: [Character]) -> MarkupPosition? {
            var state = State.text
            var name = ""
            var isClosing = false
            var readingName = false
            var rawStart = 0
            var index = 0
            while index < text.count {
                let character = text[index]
                switch state {
                case .text:
                    if matches("<!--", in: text, at: index) {
                        state = .comment
                        index += 4
                        continue
                    }
                    if character == "<", index + 1 < text.count,
                        text[index + 1].isLetter || text[index + 1] == "/" || text[index + 1] == "!"
                    {
                        state = .tag
                        name = ""
                        isClosing = text[index + 1] == "/"
                        readingName = true
                        index += isClosing ? 2 : 1
                        continue
                    }
                case .tag:
                    if readingName, character.isLetter || character.isNumber {
                        name.append(character.lowercased())
                    } else {
                        readingName = false
                    }
                    if character == "\"" || character == "'" {
                        state = .value(quote: character)
                    } else if character == ">" {
                        let rawElement = !isClosing && (name == "style" || name == "script")
                        state = rawElement ? .raw(element: name) : .text
                        rawStart = index + 1
                    }
                case .comment:
                    if matches("-->", in: text, at: index) {
                        state = .text
                        index += 3
                        continue
                    }
                case .value(let quote):
                    if character == quote { state = .tag }
                case .raw(let element):
                    if matches("</" + element, in: text, at: index) {
                        state = .tag
                        name = element
                        isClosing = true
                        readingName = false
                        index += 2 + element.count
                        continue
                    }
                }
                index += 1
            }
            switch state {
            case .text: return .slot(.text)
            case .tag: return .slot(.tag)
            case .comment, .value: return .quoted
            case .raw(let element):
                return element == "style" ? Style.position(of: text[rawStart...]) : nil
            }
        }

        /// Whether `marker` stands in `text` at `index`, letters compared without regard to case.
        static func matches(_ marker: String, in text: [Character], at index: Int) -> Bool {
            let characters = Array(marker)
            guard index + characters.count <= text.count else { return false }
            return zip(characters, text[index...]).allSatisfy { $0.lowercased() == $1.lowercased() }
        }
    }

    // MARK: CSS

    private enum Style {
        /// At-rules whose block holds more rules, where a selector is written, rather than declarations.
        static let ruleListAtRules = [
            "@media", "@supports", "@container", "@layer", "@document", "@scope", "@starting-style",
            "@keyframes", "@-webkit-keyframes",
        ]

        static func position(of text: ArraySlice<Character>) -> MarkupPosition {
            var blocks: [Bool] = []  // true for a block of declarations
            var prelude = ""
            var afterColon = false
            var parentheses = 0
            var index = text.startIndex
            while index < text.endIndex {
                let character = text[index]
                if character == "/", index + 1 < text.endIndex, text[index + 1] == "*" {
                    guard let end = closing(of: text, from: index + 2) else { return .quoted }
                    index = end
                    continue
                }
                if character == "\"" || character == "'" {
                    guard let end = closing(quote: character, in: text, from: index + 1) else {
                        return .quoted
                    }
                    prelude.append(character)
                    index = end
                    continue
                }
                switch character {
                case "(": parentheses += 1
                case ")": parentheses = max(0, parentheses - 1)
                case "{" where parentheses == 0:
                    let head = prelude.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let nestsRules = ruleListAtRules.contains { head.hasPrefix($0) }
                    blocks.append(!nestsRules)
                    prelude = ""
                    afterColon = false
                    index += 1
                    continue
                case "}" where parentheses == 0:
                    if !blocks.isEmpty { blocks.removeLast() }
                    prelude = ""
                    afterColon = false
                    index += 1
                    continue
                case ";" where parentheses == 0:
                    prelude = ""
                    afterColon = false
                    index += 1
                    continue
                case ":" where parentheses == 0 && blocks.last == true:
                    afterColon = true
                default: break
                }
                prelude.append(character)
                index += 1
            }
            guard blocks.last == true else { return .slot(.selector) }
            return .slot(afterColon ? .value : .property)
        }

        /// The index after the `*/` that ends a comment, or `nil` when it stays open.
        static func closing(of text: ArraySlice<Character>, from start: Int) -> Int? {
            var index = start
            while index + 1 < text.endIndex {
                if text[index] == "*", text[index + 1] == "/" { return index + 2 }
                index += 1
            }
            return nil
        }

        /// The index after the quote that ends a string, or `nil` when it stays open.
        static func closing(quote: Character, in text: ArraySlice<Character>, from start: Int) -> Int? {
            var index = start
            while index < text.endIndex {
                if text[index] == "\\" {
                    index += 2
                    continue
                }
                if text[index] == quote { return index + 1 }
                if text[index].isNewline { return nil }
                index += 1
            }
            return nil
        }
    }
}
