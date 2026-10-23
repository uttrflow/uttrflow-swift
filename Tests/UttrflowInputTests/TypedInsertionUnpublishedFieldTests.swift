import Synchronization
import Testing
import UttrflowCore

@testable import UttrflowInput

/// A focus that publishes the chosen kind of element in one chosen application.
private struct KindFocus: AccessibilityFocus {
    let application: InsertionDestination
    let kind: FocusedElementKind

    func focusedTextField() -> (any FocusedTextField)? { nil }
    func hasFocusedElement() -> Bool { kind != .unpublished }
    func isSelfFrontmost() -> Bool { false }
    func focusedApplication() -> InsertionDestination? { application }
    func focusedElementKind() -> FocusedElementKind { kind }
}

/// Records every key event posted.
private final class RecordingTypist: KeystrokeTyping, @unchecked Sendable {
    private let posted = Mutex<[String]>([])
    var typed: [String] { posted.withLock { $0 } }
    func type(_ text: String) throws(TextInsertionError) { posted.withLock { $0.append(text) } }
    func deleteBackwards(_ count: Int) throws(TextInsertionError) {
        posted.withLock { $0.append("⌫\(count)") }
    }
}

@Suite("A field that cannot be read is refused for the classes the table lists")
struct TypedInsertionUnpublishedFieldTests {
    static let listed: [InsertionDestination] = [
        InsertionDestination(applicationName: "Terminal", bundleIdentifier: "com.apple.Terminal"),
        InsertionDestination(applicationName: "iTerm2", bundleIdentifier: "com.googlecode.iterm2"),
        InsertionDestination(applicationName: "Screen Sharing", bundleIdentifier: "com.apple.ScreenSharing"),
        InsertionDestination(
            applicationName: "Remote Desktop", bundleIdentifier: "com.microsoft.rdc.macos"),
    ]

    private static let composer = InsertionDestination(
        applicationName: "Composer", bundleIdentifier: "com.example.composer")

    @Test("A terminal or remote desktop that publishes no field gets zero key events.", arguments: listed)
    func unpublishedListedClassIsRefused(application: InsertionDestination) async {
        let typist = RecordingTypist()
        let focus = KindFocus(application: application, kind: .unpublished)
        let engine = TypedTextInsertionEngine(focus: focus, typist: typist)

        #expect(await engine.canInsert() == false)
        await #expect(throws: TextInsertionError.noFocusedTextField) {
            _ = try await engine.insert("remove the old directory")
        }
        #expect(typist.typed.isEmpty)
    }

    @Test("The same classes take typing while a text field is published.", arguments: listed)
    func publishedFieldIsTyped(application: InsertionDestination) async throws {
        let typist = RecordingTypist()
        let focus = KindFocus(application: application, kind: .textEntry)
        let engine = TypedTextInsertionEngine(focus: focus, typist: typist)

        #expect(await engine.canInsert())
        _ = try await engine.insert("hello")
        #expect(typist.typed == ["hello"])
    }

    @Test("An unlisted app that publishes nothing, such as a bundled-browser composer, still takes typing.")
    func unlistedUnpublishedIsTyped() async throws {
        let typist = RecordingTypist()
        let focus = KindFocus(application: Self.composer, kind: .unpublished)
        let engine = TypedTextInsertionEngine(focus: focus, typist: typist)

        #expect(await engine.canInsert())
        _ = try await engine.insert("hello")
        #expect(typist.typed == ["hello"])
    }

    @Test("Dictation refused for an unreadable field keeps the words for explicit copy.")
    func refusalMessage() async {
        let typist = RecordingTypist()
        let focus = KindFocus(application: Self.listed[0], kind: .unpublished)
        let coordinator = TextInsertion.dictation(focus: focus, typist: typist)

        let expected = TextInsertionError.insertionNeedsCopy(
            description: TextInsertionError.noFocusedTextField.userMessage)
        await #expect(throws: expected) { _ = try await coordinator.insert("remove the old directory") }
        #expect(typist.typed.isEmpty)
    }

    @Test("The table, not an app name in code, lists the classes.")
    func tableCarriesTheFlag() {
        for application in Self.listed {
            let app = AppContext(
                applicationName: application.applicationName, bundleIdentifier: application.bundleIdentifier)
            #expect(DestinationClassifier.refusesUnreadField(in: app), "\(application.applicationName ?? "")")
        }
        let unlisted = AppContext(bundleIdentifier: "com.example.composer")
        #expect(!DestinationClassifier.refusesUnreadField(in: unlisted))
        #expect(!DestinationClassifier.refusesUnreadField(in: AppContext(bundleIdentifier: "dev.zed.Zed")))
    }
}
