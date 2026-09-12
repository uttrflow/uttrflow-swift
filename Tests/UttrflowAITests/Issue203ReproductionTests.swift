import Testing
import UttrflowCore

@testable import UttrflowAI

/// Issue #203: the one table classifies every app the prompt's caption can name.
@Suite("Issue203")
struct Issue203ReproductionTests {
    /// One app per divergence the issue named, with the phrase and the destination its row gives it.
    static let apps: [(String, String, String, Destination)] = [
        ("Signal", "org.whispersystems.signal-desktop", "a chat app", .messaging),
        ("WhatsApp", "desktop.WhatsApp", "a chat app", .messaging),
        ("Microsoft Teams", "com.microsoft.teams", "a chat app", .messaging),
        ("Spark", "com.readdle.smartemail-Mac", "an email app", .email),
        ("Sublime Text", "com.sublimetext.4", "a code editor", .codeEditor),
        ("Nova", "com.panic.Nova", "a code editor", .codeEditor),
        ("Warp", "dev.warp.Warp-Stable", "a terminal", .codeEditor),
        ("kitty", "net.kovidgoyal.kitty", "a terminal", .codeEditor),
        ("Ghostty", "com.mitchellh.ghostty", "a terminal", .codeEditor),
        ("Alacritty", "org.alacritty", "a terminal", .codeEditor),
        ("Sequel Ace", "com.sequel-ace.sequel-ace", "a SQL editor", .sqlEditor),
        ("Sequel Pro", "com.sequelpro.SequelPro", "a SQL editor", .sqlEditor),
        ("Notion", "notion.id", "a note taking app", .document),
        ("Obsidian", "md.obsidian", "a note taking app", .document),
        ("Bear", "net.shinyfrog.bear", "a note taking app", .document),
    ]

    /// Every app the table names reaches a destination rather than falling through to `.plain`.
    @Test("every app AppKind knows is classified", arguments: apps)
    func classified(name: String, bundle: String, phrase: String, expected: Destination) {
        let app = AppContext(applicationName: name, bundleIdentifier: bundle)
        #expect(AppKind(applicationName: name, bundleIdentifier: bundle) != nil)
        #expect(DestinationClassifier.classify(app) == expected)
    }

    /// The prompt's "Typed into:" line and the style block it ships beside must name the same kind of place.
    @Test("the prompt does not give two answers", arguments: apps)
    func promptAgrees(name: String, bundle: String, phrase: String, expected: Destination) {
        let app = AppContext(applicationName: name, bundleIdentifier: bundle)
        let situation = SituationResolver.resolve(from: app)
        let described = AppContextDescriber.describe(situation) ?? ""
        #expect(described.contains(phrase))
        #expect(PromptBuilder.standard.block(for: situation.destination).id != "plain")
    }

    /// "on my way" into Signal must not gain the trailing stop a chat app drops.
    @Test("a short message into Signal keeps no trailing stop")
    func signalDropsTheStop() {
        let app = AppContext(applicationName: "Signal", bundleIdentifier: "org.whispersystems.signal-desktop")
        let situation = SituationResolver.resolve(from: app)
        let formatter = DestinationFormatter.standard(for: situation.destination)
        let pipeline = CleaningPipeline.standard(for: formatter, situation: situation)
        #expect(pipeline.run(Draft(text: "on my way")).text == "On my way")
    }

    /// The same words into Slack, for the side-by-side the issue reports.
    @Test("a short message into Slack keeps no trailing stop")
    func slackDropsTheStop() {
        let app = AppContext(applicationName: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap")
        let situation = SituationResolver.resolve(from: app)
        let formatter = DestinationFormatter.standard(for: situation.destination)
        let pipeline = CleaningPipeline.standard(for: formatter, situation: situation)
        #expect(pipeline.run(Draft(text: "on my way")).text == "On my way")
    }

    /// Dictated code into Sublime Text must keep its line breaks and gain no full stop, as it does in VS Code.
    @Test("dictated code into Sublime Text is not finished like prose")
    func sublimeKeepsCode() {
        let app = AppContext(applicationName: "Sublime Text", bundleIdentifier: "com.sublimetext.4")
        let situation = SituationResolver.resolve(from: app)
        let formatter = DestinationFormatter.standard(for: situation.destination)
        #expect(formatter.terminalStop == .never)
        #expect(formatter.grammar == .asSpoken)
        #expect(formatter.layout.contains(.preserveNewlines))
    }

    /// A spoken list dictated into Notion must be laid out as one, as it is in a document.
    @Test("Notion lays out a spoken list")
    func notionLaysOutLists() {
        let app = AppContext(applicationName: "Notion", bundleIdentifier: "notion.id")
        let situation = SituationResolver.resolve(from: app)
        #expect(DestinationFormatter.standard(for: situation.destination).layout.contains(.lists))
    }

    /// There is one table, so no app the caption can name is unknown to the style rules.
    @Test("no bundle identifier the caption names is unknown to DestinationRules")
    func tablesAgree() {
        let missing = Self.apps.filter {
            DestinationClassifier.classify(AppContext(bundleIdentifier: $0.1)) == .plain
        }
        #expect(missing.map(\.0) == [])
    }
}
