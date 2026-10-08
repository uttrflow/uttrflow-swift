import CoreGraphics
import CoreText
import Foundation
import Testing
import UttrflowPredict

@testable import UttrflowContext

/// The whole focused-field read driven through `ElementTree`, so each refusal's fallback is asserted without another app.
struct FocusedFieldSnapshotReadTests {
    static let refusals: [FieldAnswer] = [.noValue, .unsupported, .cannotComplete, .timedOut]
    static let value = "Dear team"
    static let screenTop: CGFloat = 1_000
    static let fieldFrame = CGRect(x: 10, y: 20, width: 300, height: 24)

    /// The answers a read keeps between turns, held where a test can see whether a second read used them.
    final class Kept {
        var answers: FocusedFieldReader.StableAnswers?
        var stores = 0
    }

    private static func sources(
        kept: Kept? = nil, inputSource: InputSourceKind = .layout
    ) -> FocusedFieldReader.SnapshotSources<Node> {
        FocusedFieldReader.SnapshotSources(
            app: FrontmostApp(processIdentifier: 42, bundleIdentifier: "com.example.editor", name: "Editor"),
            decode: FieldAnswerDecoder(element: { $0 as? Node }, range: { $0 as? CFRange }),
            cached: { _ in kept?.answers },
            keep: { answers, _ in
                kept?.answers = answers
                kept?.stores += 1
            },
            elementHash: { UInt($0.id) }, windowNumber: { _ in 7 }, primaryScreenMaxY: { screenTop },
            inputSourceKind: { inputSource }, elapsedMicroseconds: { 0 })
    }

    private static func field(_ overrides: [String: FieldAnswer] = [:]) -> Node {
        let answers: [String: FieldAnswer] = [
            "AXRole": .value("AXTextField"), "AXNumberOfCharacters": .value(value.utf16.count),
            "AXValue": .value(value), "AXSelectedTextRange": .value(CFRange(location: 9, length: 0)),
            "AXPosition": .value(fieldFrame.origin), "AXSize": .value(fieldFrame.size),
        ]
        return Node(id: 2, role: "AXTextField", answers: answers.merging(overrides) { $1 })
    }

    private static func read(
        _ field: Node, log: MessageLog? = nil, kept: Kept? = nil, inputSource: InputSourceKind = .layout,
        while goOn: () -> Bool = { true }
    ) -> FocusedFieldSnapshot? {
        FocusedFieldReader.snapshot(
            of: field, in: FakeTree(root: field, messages: log),
            from: sources(kept: kept, inputSource: inputSource), while: goOn)
    }

    private static func flipped(_ rect: CGRect) -> CGRect {
        SuggestionGeometry.fromAccessibility(rect, primaryScreenMaxY: screenTop)
    }

    private static func helvetica(_ size: CGFloat) throws -> CFAttributedString {
        let string = try #require(CFAttributedStringCreateMutable(nil, 0))
        CFAttributedStringReplaceString(string, CFRange(location: 0, length: 0), "m" as CFString)
        CFAttributedStringSetAttribute(
            string, CFRange(location: 0, length: 1), kCTFontAttributeName,
            CTFontCreateWithName("Helvetica" as CFString, size, nil))
        return string
    }

    @Test func answeringFieldGivesItsTextIdentityAndFrame() throws {
        let snapshot = try #require(Self.read(Self.field()))
        #expect(snapshot.value == Self.value)
        #expect(snapshot.selection == NSRange(location: 9, length: 0))
        #expect(snapshot.field == Self.flipped(Self.fieldFrame))
        #expect(snapshot.focusedFieldIdentity == FocusedFieldIdentity(processIdentifier: 42, elementHash: 2))
        #expect(snapshot.windowNumber == 7)
        #expect(!snapshot.isSecure)
    }

    @Test(arguments: refusals)
    func refusedNamesGiveNoSnapshotAndAskNothingMore(refusal: FieldAnswer) {
        let log = MessageLog()
        #expect(Self.read(Self.field(["AXRole": refusal]), log: log) == nil)
        #expect(log.asked == ["AXWindow", FocusedFieldRead.nameAttributes.joined(separator: "+")])
    }

    @Test func severalSelectionsGiveNoSnapshot() {
        let ranges = [CFRange(location: 0, length: 1), CFRange(location: 3, length: 1)]
        #expect(Self.read(Self.field(["AXSelectedTextRanges": .value(ranges)])) == nil)
    }

    @Test(arguments: refusals)
    func refusedSelectionFallsToTheTextMarkerRung(refusal: FieldAnswer) throws {
        let log = MessageLog()
        let marker = MarkerSelection(range: NSRange(location: 4, length: 0), count: Self.value.utf16.count)
        let field = Self.field(["AXSelectedTextRange": refusal, "AXSelectedTextMarkerRange": .value(marker)])
        let snapshot = try #require(Self.read(field, log: log))
        #expect(snapshot.selection == NSRange(location: 4, length: 0))
        #expect(snapshot.value == Self.value)
        #expect(log.asked.contains("AXSelectedTextMarkerRange"))
    }

    @Test(arguments: refusals)
    func secureFieldIsNeverAskedForItsMarkerTextOrStyle(refusal: FieldAnswer) throws {
        let log = MessageLog()
        let field = Self.field([
            "AXRole": .value("AXSecureTextField"), "AXSelectedTextRange": refusal,
            "AXSelectedTextMarkerRange": .value(
                MarkerSelection(range: NSRange(location: 1, length: 0), count: 2)),
        ])
        let snapshot = try #require(Self.read(field, log: log))
        #expect(snapshot.isSecure)
        #expect(snapshot.value == nil)
        let forbidden = [
            "AXSelectedTextMarkerRange", "AXValue", "AXStringForRange", "AXAttributedStringForRange",
        ]
        #expect(log.asked.allSatisfy { !forbidden.contains($0) })
    }

    @Test(arguments: refusals)
    func refusedStyleLeavesTheGhostWithoutTheFieldsType(refusal: FieldAnswer) throws {
        let snapshot = try #require(Self.read(Self.field(["AXAttributedStringForRange": refusal])))
        #expect(snapshot.pointSize == nil)
        #expect(snapshot.fontFamily == nil)
    }

    @Test func answeredStyleSetsTheGhostInTheFieldsType() throws {
        let style = try Self.helvetica(15)
        let snapshot = try #require(Self.read(Self.field(["AXAttributedStringForRange": .value(style)])))
        #expect(snapshot.pointSize == 15)
        #expect(snapshot.fontFamily == "Helvetica")
    }

    @Test(arguments: refusals)
    func refusedGlyphBoundsFallToTheTextMarkerRectangle(refusal: FieldAnswer) throws {
        let log = MessageLog()
        let marker = CGRect(x: 100, y: 200, width: 2, height: 18)
        let field = Self.field(["AXBoundsForRange": refusal, "AXBoundsForTextMarkerRange": .value(marker)])
        let snapshot = try #require(Self.read(field, log: log))
        #expect(snapshot.caret == Self.flipped(CGRect(x: 100, y: 200, width: 0, height: 18)))
        #expect(log.asked.contains("AXBoundsForTextMarkerRange"))
    }

    @Test func answeredGlyphBoundsNeverAskTheTextMarker() throws {
        let log = MessageLog()
        let field = Self.field([
            "AXBoundsForRange": .value(CGRect(x: 60, y: 22, width: 8, height: 18)),
            "AXBoundsForTextMarkerRange": .value(CGRect(x: 100, y: 200, width: 2, height: 18)),
        ])
        let snapshot = try #require(Self.read(field, log: log))
        #expect(snapshot.caret != nil)
        #expect(!log.asked.contains("AXBoundsForTextMarkerRange"))
    }

    @Test(arguments: refusals)
    func refusedMarkedRangeLeavesComposingToTheInputSource(refusal: FieldAnswer) throws {
        let field = Self.field([FocusedFieldRead.markedRangeAttribute: refusal])
        let onLayout = try #require(Self.read(field, inputSource: .layout))
        let onInputMethod = try #require(Self.read(field, inputSource: .inputMethod))
        #expect(onLayout.markedText == .unanswered)
        #expect(!onLayout.isComposing)
        #expect(onInputMethod.isComposing)
    }

    @Test func answeredMarkedRangeSettlesComposingWhateverTheInputSource() throws {
        let present = Self.field([
            FocusedFieldRead.markedRangeAttribute: .value(CFRange(location: 2, length: 3))
        ])
        let absent = Self.field([
            FocusedFieldRead.markedRangeAttribute: .value(CFRange(location: 2, length: 0))
        ])
        #expect(try #require(Self.read(present, inputSource: .layout)).isComposing)
        #expect(try !#require(Self.read(absent, inputSource: .inputMethod)).isComposing)
    }

    @Test func answeredFlagsAreKeptAndRefusedOnesAreUnknown() throws {
        let answered = try #require(
            Self.read(
                Self.field([
                    "AXEnabled": .value(false), "AXIsEditable": .value(true), "AXExpanded": .value(1),
                ])))
        #expect(answered.isEnabled == false)
        #expect(answered.isEditable == true)
        #expect(answered.showsOwnList)
        let refused = try #require(
            Self.read(
                Self.field([
                    "AXEnabled": .cannotComplete, "AXIsEditable": .timedOut, "AXExpanded": .unsupported,
                ])))
        #expect(refused.isEnabled == nil)
        #expect(refused.isEditable == nil)
        #expect(!refused.showsOwnList)
    }

    @Test func windowAnswersFillWhatTheFieldLeavesOut() throws {
        let window = Node(
            id: 3, role: "AXWindow", frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            answers: ["AXTitle": .value("Draft"), "AXDocument": .value("file:///draft.txt")])
        let snapshot = try #require(Self.read(Self.field(["AXWindow": .value(window)])))
        #expect(snapshot.windowTitle == "Draft")
        #expect(snapshot.document == "file:///draft.txt")
        #expect(snapshot.window == Self.flipped(CGRect(x: 0, y: 0, width: 800, height: 600)))
    }

    @Test func secondReadOfTheSameFieldSkipsTheKeptAnswers() throws {
        let kept = Kept()
        let first = MessageLog()
        let second = MessageLog()
        let one = try #require(Self.read(Self.field(), log: first, kept: kept))
        let two = try #require(Self.read(Self.field(), log: second, kept: kept))
        #expect(one == two)
        #expect(kept.stores == 1)
        for stable in ["AXDocument", "AXPosition", "AXSize"] {
            #expect(first.asked.contains(stable))
            #expect(!second.asked.contains(stable))
        }
    }

    @Test(arguments: 0..<30)
    func noQuestionIsAskedOnceTheReadIsToldToStop(allowed: Int) {
        let log = MessageLog()
        var checks = 0
        var askedWhenStopped: Int?
        let snapshot = Self.read(Self.field(), log: log) {
            checks += 1
            guard checks > allowed else { return true }
            if askedWhenStopped == nil { askedWhenStopped = log.asked.count }
            return false
        }
        guard let askedWhenStopped else { return }
        #expect(snapshot == nil)
        #expect(log.asked.count == askedWhenStopped)
    }
}
