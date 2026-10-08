import CoreGraphics
import Testing

@testable import UttrflowCore
@testable import UttrflowInput
@testable import UttrflowPredict

@Suite("Key presses said under the command key")
struct KeyCommandTests {
    /// Records each stroke instead of posting it.
    final class RecordingPoster: KeyStrokePosting, @unchecked Sendable {
        var posted: [KeyStroke] = []
        func post(_ stroke: KeyStroke) throws(TextInsertionError) { posted.append(stroke) }
    }

    private func plan(_ heard: String, in destination: Destination, isSecure: Bool = false) -> KeyCommandPlan?
    {
        KeyCommand.row(heard: heard).map { KeyCommand.plan($0, in: destination, isSecure: isSecure) }
    }

    @Test(
        "each command posts exactly its stroke in a chat field",
        arguments: [
            ("press enter", KeyStroke(.return)), ("Press return.", KeyStroke(.return)),
            ("press tab", KeyStroke(.tab)), ("press escape", KeyStroke(.escape)),
            ("Go to the end.", KeyStroke(.downArrow, modifiers: .command)),
            ("go to the start", KeyStroke(.upArrow, modifiers: .command)),
        ])
    func postsItsStroke(heard: String, stroke: KeyStroke) throws {
        guard case .post(let planned) = plan(heard, in: .messaging) else {
            Issue.record("\(heard) did not plan a stroke")
            return
        }
        let poster = RecordingPoster()
        try poster.post(planned)
        #expect(poster.posted == [stroke])
    }

    @Test("running a command posts its stroke where it is on, and posts nothing where it is off")
    func runsThroughThePoster() throws {
        let poster = RecordingPoster()
        try KeyCommand.run("Press enter.", in: .email, isSecure: false, through: poster)
        #expect(poster.posted == [KeyStroke(.return)])
        #expect(throws: TextInsertionError.self) {
            try KeyCommand.run("press enter", in: .terminal, isSecure: false, through: poster)
        }
        #expect(throws: TextInsertionError.self) {
            try KeyCommand.run("press tab", in: .email, isSecure: true, through: poster)
        }
        #expect(throws: TextInsertionError.self) {
            try KeyCommand.run("please press enter", in: .email, isSecure: false, through: poster)
        }
        #expect(poster.posted == [KeyStroke(.return)])
    }

    @Test(
        "a terminal and a SQL editor refuse every key command",
        arguments: ["press enter", "press tab", "press escape", "go to the end"])
    func refusesRunningSurfaces(heard: String) {
        for destination in [Destination.terminal, .sqlEditor] {
            guard case .refused = plan(heard, in: destination) else {
                Issue.record("\(heard) posted in \(destination)")
                continue
            }
        }
    }

    @Test("a code editor takes navigation but never enter or tab")
    func codeEditorNavigationOnly() {
        #expect(plan("go to the end", in: .codeEditor) == .post(KeyStroke(.downArrow, modifiers: .command)))
        #expect(plan("press escape", in: .codeEditor) == .post(KeyStroke(.escape)))
        for heard in ["press enter", "press tab"] {
            guard case .refused = plan(heard, in: .codeEditor) else {
                Issue.record("\(heard) posted in a code editor")
                continue
            }
        }
    }

    @Test("a secure field refuses everything", arguments: ["press enter", "go to the end"])
    func refusesSecureFields(heard: String) {
        #expect(
            plan(heard, in: .plain, isSecure: true)
                == .refused(reason: "Key commands never reach a password field."))
    }

    @Test(
        "the phrase inside a longer utterance names no key",
        arguments: [
            "press enter to send", "please press enter now", "enter", "go to the end of the line", "",
        ])
    func refusesOtherWords(heard: String) {
        #expect(KeyCommand.row(heard: heard) == nil)
    }

    @Test("modifiers become the window server's flags and back unchanged")
    func flagsRoundTrip() {
        let modifiers: KeyModifiers = [.command, .shift]
        #expect(modifiers.eventFlags == [.maskCommand, .maskShift])
        #expect(KeyModifiers(modifiers.eventFlags) == modifiers)
    }

    @Test("every key row names a stroke")
    func everyRowHasAStroke() {
        #expect(!SpokenCommands.keys.isEmpty)
        for row in SpokenCommands.keys { #expect(KeyStroke(named: row.text) != nil, "\(row.id)") }
    }
}
