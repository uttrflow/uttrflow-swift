private import Synchronization

/// How many steps a diff took while this was bound to `TextDiff.tally`.
package final class DiffTally: Sendable {
    private let steps = Mutex(0)

    package init() {}

    /// The steps taken so far.
    package var count: Int { steps.withLock { $0 } }

    func record(_ taken: Int) { steps.withLock { $0 += taken } }
}

/// What a formatter changed, line by line, shown before the change is kept.
public enum TextDiff {
    public enum Kind: Sendable, Equatable {
        case same
        case added
        case removed
    }

    public struct Line: Sendable, Equatable {
        public let kind: Kind
        public let text: String

        public init(kind: Kind, text: String) {
            self.kind = kind
            self.text = text
        }
    }

    /// Two texts compared: every line, or only how long each is when comparing them would cost too much.
    public enum Comparison: Sendable, Equatable {
        /// Every line of both texts, in order.
        case lines([Line])
        /// The line counts before and after, for a pair too large or too changed to compare line by line.
        case tooLarge(before: Int, after: Int)
    }

    /// The most lines either text may have and still be compared line by line.
    public static let lineLimit = 20_000

    /// The most UTF-8 bytes either text may have and still be compared line by line.
    public static let byteLimit = 1_000_000

    /// The most changed lines a comparison looks for before it gives up, which bounds its time and memory.
    public static let changeLimit = 4_000

    /// Counts the steps taken while bound, so a test can bound the work without a clock.
    @TaskLocal package static var tally: DiffTally?

    /// The lines of both texts, or their sizes when they pass the line, byte or change limit.
    public static func compare(from before: String, to after: String) -> Comparison {
        guard before.utf8.count <= byteLimit, after.utf8.count <= byteLimit else {
            return .tooLarge(before: lineCount(before), after: lineCount(after))
        }
        let old = split(before)
        let new = split(after)
        guard old.count <= lineLimit, new.count <= lineLimit,
            let lines = lines(from: old, to: new, changeLimit: changeLimit)
        else { return .tooLarge(before: old.count, after: new.count) }
        return .lines(lines)
    }

    /// A shortest diff with no limits, walked so an inserted line reads as one change and a removal comes before its addition.
    static func lines(from before: String, to after: String) -> [Line] {
        let old = split(before)
        let new = split(after)
        return lines(from: old, to: new, changeLimit: old.count + new.count) ?? []
    }

    /// How many lines the change touches, which is the number a user decides on.
    static func changedLines(from before: String, to after: String) -> Int {
        changedLines(in: lines(from: before, to: after))
    }

    /// How many of these lines were added or removed.
    public static func changedLines(in lines: [Line]) -> Int {
        lines.count { $0.kind != .same }
    }

    /// Only the changed parts with `context` lines each side; untouched runs make a narrow diff unreadable.
    static func interesting(
        from before: String, to after: String, context: Int = 1
    )
        -> [Line]
    {
        interesting(in: lines(from: before, to: after), context: context)
    }

    /// Only the changed lines of a diff with `context` lines each side, in order.
    public static func interesting(in all: [Line], context: Int = 1) -> [Line] {
        let radius = max(0, context)
        var wanted = [Bool](repeating: false, count: all.count)
        for index in all.indices where all[index].kind != .same {
            for nearby in max(0, index - radius)...min(all.count - 1, index + radius) {
                wanted[nearby] = true
            }
        }
        return all.indices.filter { wanted[$0] }.map { all[$0] }
    }

    /// One line: the text shown, and the key it is compared by, which keeps the CR ending before it.
    private struct Piece {
        let text: Substring
        let key: Substring
    }

    /// The lines of a text split at LF, CRLF or CR, a trailing ending making an empty last line.
    private static func split(_ text: String) -> [Piece] {
        var pieces: [Piece] = []
        var start = text.startIndex
        // Where the next line's key begins: its own start after LF, the ending itself after CR or CRLF.
        var keyStart = start
        var index = start
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if character == "\n" || character == "\r\n" || character == "\r" {
                pieces.append(Piece(text: text[start..<index], key: text[keyStart..<index]))
                start = next
                keyStart = character == "\n" ? next : index
            }
            index = next
        }
        pieces.append(Piece(text: text[start...], key: text[keyStart...]))
        return pieces
    }

    /// How many lines a text has, counted as `split` counts them but without splitting it.
    private static func lineCount(_ text: String) -> Int {
        var count = 1
        var previous: UInt8 = 0
        for byte in text.utf8 {
            if byte == UInt8(ascii: "\n") {
                if previous != UInt8(ascii: "\r") { count += 1 }
            } else if byte == UInt8(ascii: "\r") {
                count += 1
            }
            previous = byte
        }
        return count
    }

    /// The diff of two runs of lines, or nothing when more than `changeLimit` lines changed.
    private static func lines(from old: [Piece], to new: [Piece], changeLimit: Int) -> [Line]? {
        var numbers: [Substring: Int] = [:]
        func number(_ line: Piece) -> Int {
            if let known = numbers[line.key] { return known }
            numbers[line.key] = numbers.count
            return numbers.count - 1
        }
        let oldNumbers = old.map(number)
        var walk = ShortestEdit(old: oldNumbers, new: new.map(number))
        defer { tally?.record(walk.steps) }
        guard let changes = walk.distance(limit: changeLimit) else { return nil }
        let script = walk.script(changes: changes)
        var result: [Line] = []
        result.reserveCapacity(script.count)
        for step in script {
            switch step {
            case .same(let index): result.append(Line(kind: .same, text: String(old[index].text)))
            case .removed(let index): result.append(Line(kind: .removed, text: String(old[index].text)))
            case .added(let index): result.append(Line(kind: .added, text: String(new[index].text)))
            }
        }
        return result
    }
}

/// One step of a diff, naming the line it keeps, removes or adds by its index in its own text.
private enum EditStep {
    case same(Int)
    case removed(Int)
    case added(Int)
}

/// A shortest edit script whose kept layers grow with the square of the changes, choosing at each change what a full table walked from the top would. See `Docs/performance.md`.
private struct ShortestEdit {
    /// The old lines, numbered so equal lines share a number.
    let old: [Int]
    /// The new lines, numbered from the same table.
    let new: [Int]
    /// The diagonal the end of both texts lies on.
    let end: Int
    /// The steps taken, which a test bounds.
    var steps = 0

    /// How many layers apart the kept layers are, and how many are rebuilt at once when replayed backwards.
    private static let stride = 32

    /// Every `stride`th layer the distance passed through, which the script is rebuilt from.
    private var checkpoints: [Layer] = []

    init(old: [Int], new: [Int]) {
        self.old = old
        self.new = new
        end = old.count - new.count
    }

    /// For each diagonal a layer covers, the least old index from which the end is that many changes away.
    private typealias Layer = [Int]

    /// The layer for no changes: the run of equal lines the two texts end on.
    private mutating func firstLayer() -> Layer {
        [slideBack(from: old.count, on: end)]
    }

    /// The layer one change further out than `previous`, whose number is `depth`.
    private mutating func layer(after previous: Layer, depth: Int) -> Layer {
        var next = Layer(repeating: .max, count: depth + 1)
        for slot in 0...depth {
            steps += 1
            let diagonal = end - depth + 2 * slot
            var x = Int.max
            // A removal from here lands on the diagonal above, one old line on.
            if slot < depth, previous[slot] != .max, previous[slot] >= 1 { x = previous[slot] - 1 }
            // An addition from here lands on the diagonal below, at the same old line.
            if slot > 0, previous[slot - 1] != .max, previous[slot - 1] >= diagonal {
                x = min(x, previous[slot - 1])
            }
            if x != .max { next[slot] = slideBack(from: x, on: diagonal) }
        }
        return next
    }

    /// The least old index reached by walking back along a diagonal through equal lines.
    private mutating func slideBack(from start: Int, on diagonal: Int) -> Int {
        var x = start
        while x > 0, x - diagonal > 0, old[x - 1] == new[x - diagonal - 1] {
            x -= 1
            steps += 1
        }
        return x
    }

    /// The fewest changed lines, or nothing when there are more than `limit`.
    mutating func distance(limit: Int) -> Int? {
        var current = firstLayer()
        var depth = 0
        while true {
            if depth % Self.stride == 0 { checkpoints.append(current) }
            if depth >= abs(end), (depth - end) % 2 == 0, current[(depth - end) / 2] == 0 { return depth }
            guard depth < limit else { return nil }
            depth += 1
            current = layer(after: current, depth: depth)
        }
    }

    /// The edit script for texts `changes` apart, taking equal lines first and a removal before an addition.
    mutating func script(changes: Int) -> [EditStep] {
        var walk = Walk(old: old, new: new, end: end)
        walk.advance()
        // The walk needs the layers from the deepest down, so each stretch is rebuilt from its checkpoint and replayed.
        for (index, checkpoint) in checkpoints.enumerated().reversed() {
            let low = index * Self.stride
            let high = min(low + Self.stride, changes) - 1
            guard low <= high else { continue }
            var kept = [checkpoint]
            for depth in Swift.stride(from: low + 1, through: high, by: 1) {
                kept.append(layer(after: kept[kept.count - 1], depth: depth))
            }
            for (offset, layer) in kept.enumerated().reversed() {
                walk.change(with: layer, depth: low + offset)
            }
        }
        steps += walk.steps
        return walk.script
    }
}

/// The walk from the top of both texts, one change per layer, in the order the layers are handed to it.
private struct Walk {
    let old: [Int]
    let new: [Int]
    let end: Int
    var x = 0
    var y = 0
    var steps = 0
    var script: [EditStep] = []

    /// Keeps every equal line from here on, since keeping one is never longer than changing it.
    mutating func advance() {
        while x < old.count, y < new.count, old[x] == new[y] {
            script.append(.same(x))
            x += 1
            y += 1
            steps += 1
        }
    }

    /// Makes one change, a removal whenever the end is still `depth` changes away after it.
    mutating func change(with layer: [Int], depth: Int) {
        let slot = (x - y + 1 - end + depth) / 2
        let removes =
            y == new.count || (x < old.count && (0...depth).contains(slot) && layer[slot] <= x + 1)
        if removes {
            script.append(.removed(x))
            x += 1
        } else {
            script.append(.added(y))
            y += 1
        }
        advance()
    }
}
