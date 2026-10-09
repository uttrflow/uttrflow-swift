import CoreFoundation
import Foundation
import Testing
import UttrflowCore

@testable import UttrflowContext

/// Replays the remote-screen and canvas snapshots of `Docs/context-accessibility.md` through the dictation's window read.
@Suite("Remote and canvas surface replay")
struct SurfaceFixtureReplayTests {
    private static let directory = URL(filePath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "Fixtures/AccessibilitySnapshots")

    private static let viewer = FrontmostApplication(
        name: "Viewer", bundleIdentifier: "com.example.viewer", processIdentifier: 4_343)

    /// The snapshot's focused element as an application's focus, under a window carrying its title.
    private static func app(replaying file: String) throws -> Node {
        let snapshot = try AccessibilitySnapshot.decode(Data(contentsOf: directory.appending(path: file)))
        let answers = snapshot.focused.attributes.mapValues(\.fieldAnswer)
        let field = Node(id: 2, role: answers["AXRole"]?.string, answers: answers)
        let window = Node(
            id: 9, role: "AXWindow", answers: ["AXTitle": snapshot.windowTitle.map { .value($0) } ?? .noValue]
        )
        return Node(
            id: 1, role: "AXApplication",
            answers: ["AXFocusedWindow": .value(window), "AXFocusedUIElement": .value(field)])
    }

    /// The context the dictation reads from `app`, through the engine and the fake tree.
    private static func context(reading app: Node) async -> AppContext {
        let engine = MacContextEngine(
            readFrontmostApplication: { viewer },
            readFocusedWindow: { _, sink in
                let source = TreeWindowSource(
                    tree: FakeTree(root: app), app: app,
                    decode: FieldAnswerDecoder(element: { $0 as? Node }, range: { $0 as? CFRange }),
                    cap: { _ in }, identify: { _ in nil })
                MacContextEngine.read(source, isTerminal: false, into: sink, while: { true })
            },
            ownBundleIdentifier: "com.example.uttrflow", ownProcessIdentifier: 1)
        return await engine.currentContext()
    }

    @Test(
        "an element that publishes no text is named as no text surface, not as a refusal",
        arguments: ["remote-screen-window.json", "canvas-editor-drawn-text.json"])
    func replay(_ file: String) async throws {
        let context = await Self.context(reading: try Self.app(replaying: file))

        #expect(context.unavailable == .notTextSurface)
        #expect(context.precedingText == nil)
        #expect(context.followingText == nil)
        #expect(context.applicationName == "Viewer")
        #expect(context.insertionPoint.sentenceState == .unknown)
    }

    @Test("a text field that publishes no text still counts as refusing it")
    func aTextRoleIsNeverATextlessSurface() async {
        let field = Node(id: 2, role: "AXTextArea", answers: ["AXRole": .value("AXTextArea")])
        let app = Node(
            id: 1, role: "AXApplication", answers: ["AXFocusedUIElement": .value(field)])

        let context = await Self.context(reading: app)

        #expect(context.unavailable == .refused)
    }

    @Test("a group that gives a selection is a text surface the read could not finish, not a textless one")
    func aGroupWithASelectionRefuses() async {
        let answers: [String: FieldAnswer] = [
            "AXRole": .value("AXGroup"), "AXSelectedTextRange": .value(CFRange(location: 0, length: 0)),
        ]
        let field = Node(id: 2, answers: answers)
        let app = Node(
            id: 1, role: "AXApplication", answers: ["AXFocusedUIElement": .value(field)])

        let context = await Self.context(reading: app)

        #expect(context.unavailable == .refused)
    }
}
