// A replay gate: a week of invented dictations through the learner, scored for real terms against junk.

import Foundation
import Testing
import UttrflowCore

@testable import UttrflowDictionary

/// One invented dictation: the window title, the raw transcript, the selection it was spoken over and what landed.
private struct ReplayDictation {
    let application: String
    let title: String?
    let heard: String
    let selection: String?
    let wrote: String
}

/// An application family and the dictations a week in it produces, in order.
private struct ReplayFamily {
    let application: String
    let dictations: [(title: String?, heard: String, selection: String?, wrote: String?)]
}

/// What the replay learnt, scored against the labels.
private struct ReplayScore: CustomStringConvertible {
    let learned: [String]
    let real: [String]
    let junk: [String]
    let missed: [String]

    /// The share of learned words that were real terms, as a whole percentage; 100 when nothing was learnt.
    var realSharePercent: Int { learned.isEmpty ? 100 : real.count * 100 / learned.count }

    var description: String {
        "learned \(learned.count), real \(real.count) (\(realSharePercent)%), junk \(junk.count) \(junk.sorted()), "
            + "missed \(missed.count) \(missed.sorted())"
    }
}

/// The invented terms that are real vocabulary the learner should keep, lower cased.
private let realTerms: Set<String> = [
    "quorbit", "zentrafy", "kelparo", "vandrel", "pixora", "drumlet", "tesravo", "ombrix",
    "fennick", "larvio", "sorrento", "brixel", "talmora", "corvane", "nuvelo", "jastrel",
]

/// Words that must never be learned: chrome, file names, numbered drafts and plain homophones.
private let junkTerms: Set<String> = [
    "inbox", "screenshot", "untitled", "draft", "weather", "their", "right", "sent", "downloads",
    "new", "tab", "copy", "final", "notes", "whole", "meet", "for", "buy", "knew", "piece",
]

/// The families, each dictation in the order it was spoken; titles and names are invented.
private let families: [ReplayFamily] = [
    ReplayFamily(
        application: "Code Editor",
        dictations: [
            ("Quorbit — Package.swift", "add quorbit to the package", nil, nil),
            ("Untitled 4", "untitled scratch file for now", nil, nil),
            ("Quorbit — Sources", "the quorbit client needs a retry", nil, nil),
            ("Zentrafy.swift", "rename zentrafy model", nil, nil),
            ("Draft2.swift", "draft two of the parser", nil, nil),
            ("Quorbit — Tests", "quorbit tests are flaky", nil, nil),
            ("Zentrafy.swift", "zentrafy should cache this", nil, nil),
            ("Untitled 5", "untitled again", nil, nil),
            ("Zentrafy.swift", "move zentrafy into core", nil, nil),
            ("Main.swift", "call the core bit here", "core bit", "Quorbit"),
            ("Draft3.swift", "draft three of the parser", nil, nil),
            ("Notes.txt", "notes for the review", nil, nil),
            ("Main.swift", "fix the whole loop", nil, nil),
            ("Main.swift", "set it right", "write", "right"),
            ("Final copy.swift", "final copy of the build", nil, nil),
            ("Quorbit — README", "document quorbit setup", nil, nil),
            ("Zentrafy.swift", "zentrafy needs a test", nil, nil),
            ("Draft4.swift", "draft four", nil, nil),
            ("Untitled 6", "scratch", nil, nil),
            ("New Tab", "new tab for docs", nil, nil),
            ("Main.swift", "their code works", "there", "their"),
            ("Quorbit — Sources", "ship quorbit", nil, nil),
            ("Zentrafy.swift", "zentrafy is done", nil, nil),
            ("Notes.txt", "notes again", nil, nil),
            ("Main.swift", "a piece of it", "peace", "piece"),
            ("Final copy.swift", "final copy", nil, nil),
        ]),
    ReplayFamily(
        application: "Browser",
        dictations: [
            ("New Tab", "search for kelparo pricing", nil, nil),
            ("Kelparo — Dashboard", "open the kelparo dashboard", nil, nil),
            ("Weather — Today", "whether it rains today", nil, nil),
            ("Kelparo — Billing", "kelparo billing looks wrong", nil, nil),
            ("Downloads", "downloads folder is full", nil, nil),
            ("Kelparo — Settings", "change kelparo settings", nil, nil),
            ("Vandrel Docs", "vandrel docs say otherwise", nil, nil),
            ("New Tab", "new tab", nil, nil),
            ("Vandrel Docs", "check vandrel limits", nil, nil),
            ("Weather — Week", "weather for the week", nil, nil),
            ("Vandrel Docs", "vandrel quotas", nil, nil),
            ("Search results", "buy more storage", "by", "buy"),
            ("Search results", "the van drill api", "van drill", "Vandrel"),
            ("Downloads", "downloads again", nil, nil),
            ("Kelparo — Status", "kelparo is down", nil, nil),
            ("Screenshot 2031-04-02", "screenshot of the error", nil, nil),
            ("Screenshot 2031-04-03", "screenshot again", nil, nil),
            ("New Tab", "open a new tab", nil, nil),
            ("Vandrel Docs", "vandrel retries", nil, nil),
            ("Weather — Today", "weather today", nil, nil),
            ("Kelparo — Logs", "kelparo logs", nil, nil),
            ("Search results", "i knew it", "new", "knew"),
            ("Screenshot 2031-04-04", "screen shot", nil, nil),
            ("Vandrel Docs", "vandrel again", nil, nil),
            ("Downloads", "clean downloads", nil, nil),
            ("New Tab", "tab", nil, nil),
        ]),
    ReplayFamily(
        application: "Mail",
        dictations: [
            ("Inbox (12)", "reply to pixora about the invoice", nil, nil),
            ("Re: Pixora renewal", "pixora renewal is fine", nil, nil),
            ("Inbox (11)", "in box is full", nil, nil),
            ("Re: Pixora renewal", "tell pixora yes", nil, nil),
            ("Sent", "sent the deck", nil, nil),
            ("Re: Pixora renewal", "pixora wants a call", nil, nil),
            ("Drumlet onboarding", "welcome to drumlet", nil, nil),
            ("Inbox (10)", "inbox zero soon", nil, nil),
            ("Drumlet onboarding", "drumlet setup steps", nil, nil),
            ("Draft", "draft a reply", nil, nil),
            ("Drumlet onboarding", "drumlet account", nil, nil),
            ("Re: Meet next week", "lets meet monday", nil, nil),
            ("Re: Meet next week", "meat on monday", "meat", "meet"),
            ("Inbox (9)", "inbox", nil, nil),
            ("Sent", "sent", nil, nil),
            ("Re: Pixora invoice", "pixora invoice attached", nil, nil),
            ("Draft", "draft two", nil, nil),
            ("Re: Drumlet access", "drumlet access granted", nil, nil),
            ("Inbox (8)", "check inbox", nil, nil),
            ("Re: For review", "four items for review", "four", "for"),
            ("Re: Pixora invoice", "pixora paid", nil, nil),
            ("Sent", "sent it", nil, nil),
            ("Re: Drumlet access", "drumlet admin", nil, nil),
            ("Draft", "draft", nil, nil),
            ("Inbox (7)", "inbox", nil, nil),
            ("Re: Pixora", "the pick sora contract", "pick sora", "Pixora"),
        ]),
    ReplayFamily(
        application: "Chat",
        dictations: [
            ("#tesravo-dev", "tesravo build is green", nil, nil),
            ("#general", "morning all", nil, nil),
            ("#tesravo-dev", "who owns tesravo alerts", nil, nil),
            ("#tesravo-dev", "tesravo deploy at noon", nil, nil),
            ("#ombrix", "ombrix needs a review", nil, nil),
            ("#general", "right on", nil, nil),
            ("#ombrix", "ombrix migration plan", nil, nil),
            ("#ombrix", "ombrix is live", nil, nil),
            ("#general", "their call", nil, nil),
            ("#random", "whole team lunch", nil, nil),
            ("#tesravo-dev", "tesravo again", nil, nil),
            ("#general", "new joiner today", nil, nil),
            ("#ombrix", "ombrix rollback", nil, nil),
            ("#random", "a piece of cake", nil, nil),
            ("#general", "i knew that", nil, nil),
            ("#tesravo-dev", "tess rah vo is flaky", "tess rah vo", "Tesravo"),
            ("#random", "weather is nice", nil, nil),
            ("#ombrix", "ombrix logs", nil, nil),
            ("#general", "for sure", nil, nil),
            ("#tesravo-dev", "tesravo tests", nil, nil),
            ("#random", "buy snacks", nil, nil),
            ("#general", "meet at three", nil, nil),
            ("#ombrix", "ombrix done", nil, nil),
            ("#general", "sent", nil, nil),
            ("#random", "right", nil, nil),
            ("#tesravo-dev", "tesravo shipped", nil, nil),
        ]),
    ReplayFamily(
        application: "Documents",
        dictations: [
            ("Fennick proposal", "the fennick proposal draft", nil, nil),
            ("Untitled document", "untitled document", nil, nil),
            ("Fennick proposal", "fennick budget section", nil, nil),
            ("Fennick proposal", "fennick timeline", nil, nil),
            ("Larvio spec", "larvio spec overview", nil, nil),
            ("Notes", "notes from the call", nil, nil),
            ("Larvio spec", "larvio data model", nil, nil),
            ("Final copy", "final copy for print", nil, nil),
            ("Larvio spec", "larvio open questions", nil, nil),
            ("Draft 3", "draft three", nil, nil),
            ("Fennick proposal", "fennick risks", nil, nil),
            ("Untitled document 2", "untitled again", nil, nil),
            ("Larvio spec", "the lar vio api", "lar vio", "Larvio"),
            ("Notes", "notes", nil, nil),
            ("Weather report", "weather report summary", nil, nil),
            ("Final copy", "final copy", nil, nil),
            ("Fennick proposal", "fennick summary", nil, nil),
            ("Draft 4", "draft four", nil, nil),
            ("Larvio spec", "larvio appendix", nil, nil),
            ("Copy of Notes", "copy of notes", nil, nil),
            ("Notes", "the whole page", "hole", "whole"),
            ("Fennick proposal", "fennick sign off", nil, nil),
            ("Untitled document 3", "untitled", nil, nil),
            ("Larvio spec", "larvio final", nil, nil),
            ("Draft 5", "draft", nil, nil),
            ("Notes", "notes end", nil, nil),
        ]),
    ReplayFamily(
        application: "Design",
        dictations: [
            ("Sorrento — Home", "sorrento home screen", nil, nil),
            ("Sorrento — Home", "sorrento hero image", nil, nil),
            ("Screenshot 2031-05-01", "screenshot import", nil, nil),
            ("Sorrento — Checkout", "sorrento checkout flow", nil, nil),
            ("Brixel icons", "brixel icon set", nil, nil),
            ("Untitled", "untitled frame", nil, nil),
            ("Brixel icons", "brixel grid", nil, nil),
            ("Copy of Brixel icons", "copy of brixel", nil, nil),
            ("Brixel icons", "brixel export", nil, nil),
            ("Sorrento — Checkout", "sorrento colours", nil, nil),
            ("Screenshot 2031-05-02", "screenshot", nil, nil),
            ("Final", "final version", nil, nil),
            ("Sorrento — Home", "so rento header", "so rento", "Sorrento"),
            ("Untitled 2", "untitled", nil, nil),
            ("Brixel icons", "brick sell icons", "brick sell", "Brixel"),
            ("Draft", "draft layout", nil, nil),
            ("Sorrento — Home", "sorrento footer", nil, nil),
            ("Screenshot 2031-05-03", "screen shot", nil, nil),
            ("Brixel icons", "brixel review", nil, nil),
            ("New page", "new page", nil, nil),
            ("Final", "final", nil, nil),
            ("Sorrento — Checkout", "sorrento done", nil, nil),
            ("Copy of Final", "copy", nil, nil),
            ("Brixel icons", "brixel done", nil, nil),
            ("Untitled 3", "untitled", nil, nil),
            ("Draft", "draft", nil, nil),
        ]),
    ReplayFamily(
        application: "Terminal",
        dictations: [
            ("talmora — ssh", "restart talmora worker", nil, nil),
            ("talmora — logs", "talmora logs show errors", nil, nil),
            ("~/Downloads", "list downloads", nil, nil),
            ("talmora — ssh", "talmora disk is full", nil, nil),
            ("corvane — build", "corvane build failed", nil, nil),
            ("corvane — build", "corvane cache", nil, nil),
            ("~/Downloads", "downloads", nil, nil),
            ("corvane — build", "corvane retry", nil, nil),
            ("talmora — ssh", "talmora again", nil, nil),
            ("New window", "new window", nil, nil),
            ("corvane — test", "corvane tests", nil, nil),
            ("talmora — logs", "tall mora errors", "tall mora", "talmora"),
            ("~/Notes", "notes", nil, nil),
            ("corvane — build", "core vane is green", "core vane", "corvane"),
            ("talmora — ssh", "talmora ok", nil, nil),
            ("New tab", "new tab", nil, nil),
            ("~/Downloads", "clear downloads", nil, nil),
            ("corvane — build", "corvane ok", nil, nil),
            ("talmora — ssh", "talmora done", nil, nil),
            ("~/Notes", "notes", nil, nil),
            ("corvane — test", "corvane done", nil, nil),
            ("New tab", "tab", nil, nil),
            ("talmora — logs", "talmora clean", nil, nil),
            ("~/Downloads", "downloads", nil, nil),
            ("corvane — build", "corvane final", nil, nil),
            ("talmora — ssh", "exit", nil, nil),
        ]),
    ReplayFamily(
        application: "Files",
        dictations: [
            ("Nuvelo invoices", "move nuvelo invoices", nil, nil),
            ("Downloads", "downloads", nil, nil),
            ("Nuvelo invoices", "nuvelo march", nil, nil),
            ("Nuvelo invoices", "nuvelo april", nil, nil),
            ("Jastrel assets", "jastrel logos", nil, nil),
            ("Screenshot 2031-06-01.png", "screenshot", nil, nil),
            ("Jastrel assets", "jastrel fonts", nil, nil),
            ("Jastrel assets", "jastrel archive", nil, nil),
            ("Untitled folder", "untitled folder", nil, nil),
            ("Copy of report", "copy of report", nil, nil),
            ("Nuvelo invoices", "new vello receipts", "new vello", "Nuvelo"),
            ("Draft1.pdf", "draft one", nil, nil),
            ("Draft2.pdf", "draft two", nil, nil),
            ("Jastrel assets", "jazz trel icons", "jazz trel", "Jastrel"),
            ("Final.pdf", "final", nil, nil),
            ("Screenshot 2031-06-02.png", "screen shot", nil, nil),
            ("Nuvelo invoices", "nuvelo may", nil, nil),
            ("Downloads", "downloads", nil, nil),
            ("Jastrel assets", "jastrel done", nil, nil),
            ("Untitled folder 2", "untitled", nil, nil),
            ("Notes", "notes", nil, nil),
            ("Nuvelo invoices", "nuvelo june", nil, nil),
            ("Final copy.pdf", "final copy", nil, nil),
            ("Jastrel assets", "jastrel export", nil, nil),
            ("Draft3.pdf", "draft three", nil, nil),
            ("Downloads", "downloads", nil, nil),
        ]),
]

/// The replay in spoken order, family after family, half an hour apart.
private var replay: [ReplayDictation] {
    families.flatMap { family in
        family.dictations.map {
            ReplayDictation(
                application: family.application, title: $0.title, heard: $0.heard,
                selection: $0.selection, wrote: $0.wrote ?? $0.heard)
        }
    }
}

/// The ratchet: lower these when the learner improves; a rule change that raises junk or lowers the share fails.
private enum ReplayBaseline {
    static let junkLearned = 2
    static let realSharePercent = 81
    static let termsMissed = 7
}

@Suite("A replayed week of invented dictations, scored for real terms against junk")
struct LearnedWordQualityReplayTests {
    @Test("The replay holds at least 200 dictations across 8 application families")
    func replayIsLargeEnough() {
        #expect(replay.count >= 200)
        #expect(Set(replay.map(\.application)).count == 8)
    }

    @Test("Junk learned and terms missed never rise, and the real share never falls")
    func learnedWordQualityHoldsTheBaseline() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        let start = Date(timeIntervalSinceReferenceDate: 0)

        var learned: [String] = []
        for (index, dictation) in replay.enumerated() {
            learned += try await store.learn(
                heard: dictation.heard, wrote: dictation.wrote,
                seeing: AppContext(
                    applicationName: dictation.application, documentName: dictation.title,
                    selectedText: dictation.selection),
                at: start.addingTimeInterval(Double(index) * 1_800)
            ).map(\.word)
        }

        let lowered = Set(learned.map { $0.lowercased() })
        let score = ReplayScore(
            learned: learned,
            real: learned.filter { realTerms.contains($0.lowercased()) },
            junk: learned.filter { !realTerms.contains($0.lowercased()) },
            missed: realTerms.subtracting(lowered).sorted())
        print("Learned-word replay: \(score)")

        #expect(score.junk.count <= ReplayBaseline.junkLearned, "\(score)")
        #expect(score.realSharePercent >= ReplayBaseline.realSharePercent, "\(score)")
        #expect(score.missed.count <= ReplayBaseline.termsMissed, "\(score)")
        #expect(junkTerms.isDisjoint(with: realTerms))
    }
}
