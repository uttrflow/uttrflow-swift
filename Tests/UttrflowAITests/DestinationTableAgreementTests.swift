import Testing
import UttrflowCore

@testable import UttrflowAI

/// Two tables answer "what sort of app is this", and the phrase the prompt writes must not outrun the style rules.
@Suite("Destination table agreement")
struct DestinationTableAgreementTests {
    /// An app the prompt already recognises, beside one the destination rules carry that it describes identically.
    struct Pair: Sendable, CustomStringConvertible {
        let name: String
        let bundle: String
        let referenceName: String
        let referenceBundle: String

        var subject: AppContext { AppContext(applicationName: name, bundleIdentifier: bundle) }
        var reference: AppContext {
            AppContext(applicationName: referenceName, bundleIdentifier: referenceBundle)
        }
        var description: String { "\(name) beside \(referenceName)" }
    }

    /// One pair per app the prompt describes and the rules do not, against the nearest app the rules do carry.
    static let pairs: [Pair] = [
        Pair(
            name: "Signal", bundle: "org.whispersystems.signal-desktop",
            referenceName: "Slack", referenceBundle: "com.tinyspeck.slackmacgap"),
        // The Electron build ships a different identifier from the native one the rules name.
        Pair(
            name: "WhatsApp", bundle: "desktop.WhatsApp",
            referenceName: "WhatsApp", referenceBundle: "net.whatsapp.WhatsApp"),
        Pair(
            name: "Microsoft Teams", bundle: "com.microsoft.teams",
            referenceName: "Microsoft Teams", referenceBundle: "com.microsoft.teams2"),
        Pair(
            name: "Spark", bundle: "com.readdle.smartemail-Mac",
            referenceName: "Mail", referenceBundle: "com.apple.mail"),
        Pair(
            name: "Sublime Text", bundle: "com.sublimetext.4",
            referenceName: "Visual Studio Code", referenceBundle: "com.microsoft.VSCode"),
        Pair(
            name: "Nova", bundle: "com.panic.Nova",
            referenceName: "Visual Studio Code", referenceBundle: "com.microsoft.VSCode"),
        Pair(
            name: "Warp", bundle: "dev.warp.Warp-Stable",
            referenceName: "Terminal", referenceBundle: "com.apple.Terminal"),
        Pair(
            name: "kitty", bundle: "net.kovidgoyal.kitty",
            referenceName: "Terminal", referenceBundle: "com.apple.Terminal"),
        Pair(
            name: "Ghostty", bundle: "com.mitchellh.ghostty",
            referenceName: "Terminal", referenceBundle: "com.apple.Terminal"),
        Pair(
            name: "Alacritty", bundle: "org.alacritty",
            referenceName: "Terminal", referenceBundle: "com.apple.Terminal"),
        Pair(
            name: "Sequel Ace", bundle: "com.sequel-ace.sequel-ace",
            referenceName: "TablePlus", referenceBundle: "com.tinyapp.TablePlus"),
        Pair(
            name: "Sequel Pro", bundle: "com.sequelpro.SequelPro",
            referenceName: "TablePlus", referenceBundle: "com.tinyapp.TablePlus"),
        Pair(
            name: "Notion", bundle: "notion.id",
            referenceName: "Notes", referenceBundle: "com.apple.Notes"),
        Pair(
            name: "Obsidian", bundle: "md.obsidian",
            referenceName: "Notes", referenceBundle: "com.apple.Notes"),
        Pair(
            name: "Bear", bundle: "net.shinyfrog.bear",
            referenceName: "Notes", referenceBundle: "com.apple.Notes"),
    ]

    /// The cleaned text `spoken` becomes when it is dictated into `app`, by the rules that app resolves to.
    private func cleaned(_ spoken: String, into app: AppContext) -> String {
        let situation = SituationResolver.resolve(from: app)
        let formatter = DestinationFormatter.standard(for: situation.destination)
        return CleaningPipeline.standard(for: formatter, situation: situation).run(Draft(text: spoken)).text
    }

    /// The formatter the app's resolved destination is cleaned and finished by.
    private func formatter(for app: AppContext) -> DestinationFormatter {
        DestinationFormatter.standard(for: SituationResolver.resolve(from: app).destination)
    }

    // MARK: The premise

    /// The precondition for everything below: the prompt genuinely calls both apps the same kind of place.
    @Test("the prompt describes both apps as the same kind of place", arguments: pairs)
    func describedAlike(pair: Pair) {
        let subject = AppKind(applicationName: pair.name, bundleIdentifier: pair.bundle)
        let reference = AppKind(applicationName: pair.referenceName, bundleIdentifier: pair.referenceBundle)
        #expect(subject != nil, "\(pair.name) is the app the prompt already recognises")
        #expect(subject == reference)
    }

    // MARK: The two tables must agree

    /// A row added to the prompt's table and not to the rules' leaves the app falling through to plain text.
    @Test("both apps reach the same destination", arguments: pairs)
    func sameDestination(pair: Pair) {
        #expect(
            DestinationClassifier.classify(pair.subject) == DestinationClassifier.classify(pair.reference))
    }

    /// Every decision the formatter makes, so a fix that adds a destination case is judged on behaviour.
    @Test("both apps are formatted by the same rules", arguments: pairs)
    func sameFormatter(pair: Pair) {
        let subject = formatter(for: pair.subject)
        let reference = formatter(for: pair.reference)
        #expect(subject.firstWord == reference.firstWord)
        #expect(subject.terminalStop == reference.terminalStop)
        #expect(subject.layout == reference.layout)
        #expect(subject.grammar == reference.grammar)
        #expect(subject.numbers == reference.numbers)
    }

    /// The "Typed into:" phrase and the style block below it are one message and must not contradict each other.
    @Test("both apps are given the same style block", arguments: pairs)
    func samePromptBlock(pair: Pair) {
        let subject = SituationResolver.resolve(from: pair.subject).destination
        let reference = SituationResolver.resolve(from: pair.reference).destination
        #expect(
            PromptBuilder.standard.block(for: subject).id == PromptBuilder.standard.block(for: reference).id)
    }

    // MARK: What the user sees

    /// The deterministic passes finish the same words differently in two places the prompt calls the same.
    @Test("the same words come out the same way in both apps", arguments: pairs)
    func sameCleanedText(pair: Pair) {
        #expect(cleaned("on my way", into: pair.subject) == cleaned("on my way", into: pair.reference))
    }

    /// The symptom the issue reports, pinned: a chat app drops the stop a short message never had.
    @Test("a short message into Signal keeps no full stop, as it does in Slack")
    func signalKeepsNoStop() {
        let signal = AppContext(
            applicationName: "Signal", bundleIdentifier: "org.whispersystems.signal-desktop")
        #expect(cleaned("on my way", into: signal) == "On my way")
    }

    /// Dictated code keeps its line breaks and gains no prose full stop, as it does in an editor the rules carry.
    @Test("dictated code into Sublime Text is not finished like prose")
    func sublimeTextIsNotProse() {
        let sublime = AppContext(applicationName: "Sublime Text", bundleIdentifier: "com.sublimetext.4")
        let vsCode = AppContext(
            applicationName: "Visual Studio Code", bundleIdentifier: "com.microsoft.VSCode")
        #expect(formatter(for: sublime).terminalStop == formatter(for: vsCode).terminalStop)
        #expect(formatter(for: sublime).layout.contains(.preserveNewlines))
    }

    // MARK: The invariant, swept

    /// Apps the prompt describes alike but the rules classify differently, browsers included to show plain text is allowed.
    static let corpus: [(String, String)] =
        pairs.map { ($0.name, $0.bundle) } + pairs.map { ($0.referenceName, $0.referenceBundle) } + [
            ("Safari", "com.apple.Safari"), ("Google Chrome", "com.google.Chrome"),
            ("Firefox", "org.mozilla.firefox"),
        ]

    /// One phrase, one destination — the invariant the two tables break, whatever vocabulary the fix chooses.
    @Test("no two apps the prompt describes alike reach different destinations")
    func onePhraseOneDestination() {
        var reached: [String: Set<Destination>] = [:]
        for (name, bundle) in Self.corpus {
            guard let kind = AppKind(applicationName: name, bundleIdentifier: bundle) else { continue }
            let app = AppContext(applicationName: name, bundleIdentifier: bundle)
            reached[kind.phrase, default: []].insert(DestinationClassifier.classify(app))
        }
        for (phrase, destinations) in reached.sorted(by: { $0.key < $1.key }) {
            #expect(
                destinations.count == 1,
                "\(phrase) reaches \(destinations.map(\.rawValue).sorted().joined(separator: " and "))")
        }
    }
}
