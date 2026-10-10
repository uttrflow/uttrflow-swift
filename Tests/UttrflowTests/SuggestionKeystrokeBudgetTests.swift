// Holds the keystroke path to its budget in `Docs/performance.md` by counting what each key really costs.

import AppKit
import Foundation
import Testing
import UttrflowPredict
import UttrflowPredictStore
import UttrflowTestSupport

@testable import Uttrflow
@testable import UttrflowContext

/// One text field in another application, read through the same `ElementTree` seam the system read uses.
private final class TypedField: @unchecked Sendable {
    static let application = FrontmostApp(
        processIdentifier: 4_242, bundleIdentifier: "com.example.editor", name: "Editor")
    /// Every glyph is this wide, so the caret after the last one is known without laying text out.
    static let glyphWidth: CGFloat = 8

    private let lock = NSLock()
    private let frame: CGRect
    private let screenTop: CGFloat
    private var value = ""
    private var caretX: CGFloat
    private var readCount = 0

    /// A field at `frame`, in AppKit's measure, on a primary screen whose top edge is `screenTop`.
    init(frame: CGRect, screenTop: CGFloat) {
        self.frame = frame
        self.screenTop = screenTop
        caretX = frame.minX + 4
    }

    /// How many whole reads the field has been sent.
    var reads: Int { lock.withLock { readCount } }

    /// The person types `text`: the value grows and the caret moves past the new glyphs.
    func type(_ text: String) {
        lock.withLock {
            value += text
            caretX += CGFloat(text.count) * Self.glyphWidth
        }
    }

    /// Puts the caret where the ghost already follows it, as a field does once a typed-through key lands.
    func placeCaret(atX x: CGFloat) { lock.withLock { caretX = x } }

    /// The caret alone, as the armed offer's poll reads it.
    func selection() -> FocusedFieldSelectionRead {
        lock.withLock {
            .selection(
                FocusedFieldSelection(
                    processIdentifier: Self.application.processIdentifier, elementHash: 1,
                    range: NSRange(location: value.utf16.count, length: 0)))
        }
    }

    /// One whole read, as `FocusedFieldReader.read()` makes it, counted.
    func read() -> FocusedFieldSnapshot? {
        lock.withLock { readCount += 1 }
        let sources = FocusedFieldReader.SnapshotSources<Int>(
            app: Self.application,
            decode: FieldAnswerDecoder(element: { $0 as? Int }, range: { $0 as? CFRange }),
            cached: { _ in nil }, keep: { _, _ in }, elementHash: { UInt($0) }, windowNumber: { _ in nil },
            primaryScreenMaxY: { [screenTop] in screenTop }, inputSourceKind: { .layout },
            elapsedMicroseconds: { 0 })
        return FocusedFieldReader.snapshot(of: 1, in: Tree(field: self), from: sources, while: { true })
    }

    /// What the field answers to one attribute.
    fileprivate func answer(_ name: String) -> FieldAnswer {
        lock.withLock {
            let top = screenTop - frame.maxY
            switch name {
            case "AXRole": return .value("AXTextField")
            case "AXValue": return .value(value)
            case "AXNumberOfCharacters": return .value(value.utf16.count)
            case "AXSelectedTextRange": return .value(CFRange(location: value.utf16.count, length: 0))
            case "AXPosition": return .value(CGPoint(x: frame.minX, y: top))
            case "AXSize": return .value(frame.size)
            default: return .unsupported
            }
        }
    }

    /// The glyphs over `range`, laid out one glyph width apart and ending at the caret.
    fileprivate func answer(_ name: String, range: NSRange) -> FieldAnswer {
        guard name == "AXBoundsForRange" else { return .unsupported }
        return lock.withLock {
            let offset = CGFloat(range.location - value.utf16.count) * Self.glyphWidth
            return .value(
                CGRect(
                    x: caretX + offset, y: screenTop - frame.maxY + 3,
                    width: CGFloat(range.length) * Self.glyphWidth, height: 18))
        }
    }

    /// The field as an `ElementTree` of one element, so the read decides everything the system read decides.
    private struct Tree: ElementTree {
        let field: TypedField

        func role(of element: Int) -> String? { "AXTextField" }
        func isSecure(_ element: Int) -> Bool { false }
        func text(of element: Int) -> String? { nil }
        func children(of element: Int) -> [Int] { [] }
        func parent(of element: Int) -> Int? { nil }
        func frame(of element: Int) -> CGRect? { nil }
        func attribute(_ name: String, of element: Int) -> FieldAnswer { field.answer(name) }
        func attribute(_ name: String, of element: Int, range: NSRange) -> FieldAnswer {
            field.answer(name, range: range)
        }
    }
}

@MainActor
@Suite("A key costs one field read a turn and no redraw of a ghost it types", .timeLimit(.minutes(1)))
struct SuggestionKeystrokeBudgetTests {
    /// The numeric limit `Docs/performance.md` states for the key path, so the document and this test cannot drift.
    private static func documentedLimit(_ name: String) throws -> Int {
        let page = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Docs/performance.md")
        let text = try String(contentsOf: page, encoding: .utf8)
        let line = try #require(text.split(separator: "\n").first { $0.hasPrefix("- `\(name)`: ") })
        let number = line.dropFirst("- `\(name)`: ".count).prefix { $0.isNumber }
        return try #require(Int(number))
    }

    /// Sends one key with the text it types, as the key monitor hands it over.
    private static func press(_ text: String, in field: TypedField, to coordinator: SuggestionCoordinator) {
        field.type(text)
        coordinator.keyPressed(.other, typing: text)
    }

    @Test("a burst of keys and keys typed through the ghost read once a turn and never hide or redraw it")
    func keystrokesKeepToTheBudget() async throws {
        let readsPerTurn = try Self.documentedLimit("keystrokeReadsPerTurn")
        let duplicateDraws = try Self.documentedLimit("sameSuggestionDrawsPerKey")
        let screen = try #require(NSScreen.screens.first)
        let visible = screen.visibleFrame
        let frame = CGRect(x: visible.minX + 100, y: visible.midY - 12, width: 500, height: 24)
        let container = FileManager.default.temporaryDirectory
            .appending(path: "suggestion-keystroke-budget-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        // What the person wrote in this field before, so the corpus has a line to offer.
        let earlier = TypedField(frame: frame, screenTop: screen.frame.maxY)
        earlier.type("meet")
        let before = try #require(earlier.read())
        let surface = try #require(SuggestionMoment.reading(of: before).surface)
        let store = try PredictStore(
            path: PredictStore.defaultFile(in: container).path(percentEncoded: false))
        for _ in 0..<3 { try await store.record("meet later", in: surface, at: Date()) }

        let field = TypedField(frame: frame, screenTop: screen.frame.maxY)
        let panel = SuggestionPanelController()
        let coordinator = try await SuggestionCoordinator(
            container: container, preferences: SuggestionPreferences(isEnabled: true),
            focusedSelectionReader: { field.selection() }, focusedFieldReader: { field.read() },
            frontmostBundleIdentifier: { TypedField.application.bundleIdentifier }, panel: panel)
        defer {
            coordinator.stop()
            panel.hide()
        }
        // The pause clock reads the field every second; an hour-long one leaves every turn here to a key.
        coordinator.noteActivity()
        coordinator.scheduleTicker(every: 3_600)

        // Faster than the debounce, so the burst is coalesced to one turn running and one waiting.
        for letter in ["m", "e", "e", "t"] { Self.press(letter, in: field, to: coordinator) }
        try await eventually { coordinator.isSettled }
        #expect(panel.drawn.inline?.ghost == " later")
        #expect(coordinator.turnsAdmitted <= 2)
        #expect(field.reads <= coordinator.turnsAdmitted * readsPerTurn)

        let (reads, turns) = (field.reads, coordinator.turnsAdmitted)
        let (renders, withdrawals) = (panel.renders, panel.withdrawals)
        let typedThrough = [" ", "l", "a"]
        for letter in typedThrough {
            Self.press(letter, in: field, to: coordinator)
            // The field's caret lands where the ghost's advance put it, so the read that follows agrees with the drawing.
            field.placeCaret(atX: try #require(panel.caret).minX)
            try await eventually { coordinator.isSettled }
        }
        #expect(panel.drawn.inline?.ghost == "ter")
        #expect(panel.withdrawals == withdrawals)
        #expect(panel.renders - renders - typedThrough.count == duplicateDraws)
        #expect(coordinator.turnsAdmitted > turns)
        #expect(field.reads - reads <= (coordinator.turnsAdmitted - turns) * readsPerTurn)
    }
}
