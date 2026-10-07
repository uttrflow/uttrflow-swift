// Tests that a word opening a chat app's own mention, emoji or command picker draws nothing and claims no key.

import Testing

@testable import UttrflowPredict

/// A chat composer, which has its own pickers.
private let composer = Surface(bundleIdentifier: "com.tinyspeck.slackmacgap", role: "AXTextArea")

@Suite("A word that opens the application's own picker")
struct AppPickerTests {
    @Test(
        "a mention, a shortcode, a channel or a slash command still being typed is a picker",
        arguments: [
            "@", "@jo", "hey @jo", ":", ":smi", "nice :thumbs_up", "#gen", "see #", "/", "/rem", "  /remind",
        ])
    func pickerOpen(line: String) {
        #expect(AppPicker.isOpen(after: line))
    }

    @Test(
        "a finished word, an address, a time, an emoticon or a slash inside a line is not",
        arguments: [
            "@jo ", "me@example.com", "at 12:30", "ok :)", "/remind me", "and/or", "see /usr/bin", "",
            "Note: ",
        ])
    func pickerClosed(line: String) {
        #expect(!AppPicker.isOpen(after: line))
    }

    @Test("with the picker open, the turn settles quiet and navigation and acceptance go to the app")
    func pickerLeavesTabAndEscape() {
        for line in ["@jo", ":smi", "/rem"] {
            var session = SuggestionSession()
            let turn = session.turn(in: composer, at: PredictionContext(typed: line, isProse: true))
            guard case .settled(let update) = turn.step else {
                Issue.record("\(line) asked for candidates while the app's picker is open")
                continue
            }
            #expect(update.silence == .applicationPicker)
            #expect(update.armed.isEmpty)
            #expect(
                KeyRouting.decision(for: KeyStroke(.tab), showing: update.suggestion) == .passThrough)
            #expect(
                KeyRouting.decision(for: KeyStroke(.escape), showing: update.suggestion) == .passThrough)
            for key in [Key.downArrow, .upArrow, .return] {
                #expect(
                    KeyRouting.decision(for: KeyStroke(key), showing: update.suggestion) == .passThrough)
            }
        }
    }

    @Test("a field that says its own list is open settles quiet, on any line and in a terminal too")
    func ownListLeavesTabAndEscape() {
        for (line, isCommandLine) in [("Thanks for the", false), ("git che", true)] {
            var session = SuggestionSession()
            let context = PredictionContext(typed: line, isCommandLine: isCommandLine, showsOwnList: true)
            guard case .settled(let update) = session.turn(in: composer, at: context).step else {
                Issue.record("\(line) asked for candidates while the field's own list is open")
                continue
            }
            #expect(update.silence == .applicationPicker)
            #expect(update.armed.isEmpty)
            #expect(
                KeyRouting.decision(for: KeyStroke(.tab), showing: update.suggestion) == .passThrough)
            #expect(
                KeyRouting.decision(for: KeyStroke(.escape), showing: update.suggestion) == .passThrough)
        }
        #expect(Quieting.reason(PredictionContext(typed: "Thanks for the")) == nil)
    }

    @Test("a terminal's command line opens no picker, so a path or a flag still asks")
    func commandLineIsNotAPicker() {
        var terminal = SuggestionSession()
        let terminalTurn = terminal.turn(
            in: Surface(bundleIdentifier: "com.apple.Terminal", role: "AXTextArea"),
            at: PredictionContext(typed: "/usr", isCommandLine: true))
        guard case .query = terminalTurn.step else {
            Issue.record("a terminal command was treated as a picker")
            return
        }

        var chat = SuggestionSession()
        let chatTurn = chat.turn(in: composer, at: PredictionContext(typed: "/usr"))
        guard case .settled(let update) = chatTurn.step else {
            Issue.record("a chat slash command was not treated as a picker")
            return
        }
        #expect(update.silence == .applicationPicker)
    }

    @Test("ordinary prose and terminated trigger tokens remain eligible for suggestions")
    func ordinaryTextIsNotPicker() {
        for line in ["Thanks for the update", "me@example.com", "at 12:30", "we use /usr/bin"] {
            #expect(Quieting.reason(PredictionContext(typed: line, isProse: true)) == nil)
        }
        for line in ["@jo ", ":smile ", "/remind me"] {
            #expect(Quieting.reason(PredictionContext(typed: line, isProse: true)) == nil)
        }
    }

    @Test("trigger text quiets suggestions only in applications with pickers")
    func pickerTriggersAreScopedToPickerApplications() {
        let ordinaryApplications = [
            Surface(bundleIdentifier: "com.apple.Notes", role: "AXTextArea"),
            Surface(bundleIdentifier: "com.apple.mail", role: "AXTextField"),
            Surface(bundleIdentifier: "com.google.Chrome", role: "AXTextField"),
        ]
        let pickerApplications = [
            composer,
            Surface(bundleIdentifier: "notion.id", role: "AXTextArea"),
        ]
        let pickerTriggers = ["@name", "#launch", ":smile", "/Users/you"]
        let ordinaryInputs = pickerTriggers + ["name@"]

        for surface in ordinaryApplications {
            for trigger in ordinaryInputs {
                var session = SuggestionSession()
                let turn = session.turn(in: surface, at: PredictionContext(typed: trigger, isProse: true))
                guard case .query = turn.step else {
                    Issue.record("\(surface.bundleIdentifier) suppressed \(trigger) without a picker")
                    continue
                }
            }
        }

        for surface in pickerApplications {
            for trigger in pickerTriggers {
                var session = SuggestionSession()
                let turn = session.turn(in: surface, at: PredictionContext(typed: trigger, isProse: true))
                guard case .settled(let update) = turn.step else {
                    Issue.record("\(surface.bundleIdentifier) did not suppress its picker for \(trigger)")
                    continue
                }
                #expect(update.silence == .applicationPicker)
                #expect(update.armed.isEmpty)
            }
        }
    }
}
