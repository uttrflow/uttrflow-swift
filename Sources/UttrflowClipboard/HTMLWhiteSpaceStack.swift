import UttrflowCore

/// Whether text sits inside elements that keep its whitespace: `<pre>`, `<code>`, or an inline `white-space` style.
struct HTMLWhiteSpaceStack {
    private var frames: [(name: String, preservesWhitespace: Bool)] = []
    /// How many frames each element name holds, so a stray end tag is refused without walking the stack.
    private var open: [String: Int] = [:]

    /// Whether the innermost open element keeps runs of spaces and line breaks as written.
    var preservesWhitespace: Bool { frames.last?.preservesWhitespace ?? false }

    /// Opens or closes the element `tag` names; an element without its own style inherits its parent's mode.
    mutating func consume(_ tag: HTMLTag) {
        if tag.isClosing {
            guard open[tag.name, default: 0] > 0,
                let index = frames.lastIndex(where: { $0.name == tag.name })
            else { return }
            for frame in frames[index...] { open[frame.name, default: 1] -= 1 }
            frames.removeSubrange(index...)
            return
        }
        guard !HTMLElements.void.contains(tag.name) else { return }
        let preserves = Self.styled(tag) ?? (Self.verbatim.contains(tag.name) || preservesWhitespace)
        frames.append((tag.name, preserves))
        open[tag.name, default: 0] += 1
    }

    /// Elements whose whitespace is kept exactly as written without any style.
    private static let verbatim: Set<String> = ["pre", "code", "kbd", "samp", "tt"]

    /// The mode the inline style sets, the last `white-space` declaration winning; `nil` when it sets none.
    private static func styled(_ tag: HTMLTag) -> Bool? {
        var preserves: Bool?
        for declaration in tag.styleDeclarations where declaration.property == "white-space" {
            switch declaration.value {
            case "pre", "pre-wrap", "break-spaces": preserves = true
            case "normal", "nowrap", "pre-line": preserves = false
            default: break
            }
        }
        return preserves
    }
}
