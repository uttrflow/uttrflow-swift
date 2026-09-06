// Tests for the Dictation page: rows, the changes badge, flags, the rail figures, and empty states.
import Foundation
import UttrflowCore
import UttrflowHistory
import UttrflowSettings
import Testing

@testable import UttrflowUX

extension HistoryFixture {
    /// A dictation that was timed, so the pace figures have something to work from.
    static func timed(
        _ text: String, seconds: Int, minutesAgo: Int = 0, daysAgo: Int = 0,
        application: String? = "Slack", changes: RecordedChanges? = RecordedChanges()
    ) -> HistoryEntry {
        HistoryEntry(
            id: UUID(), text: text,
            when: now.addingTimeInterval(Double(-minutesAgo) * 60 + Double(-daysAgo) * 86_400),
            applicationName: application, spokenFor: .seconds(seconds), changes: changes)
    }

    /// One change, in the terms the accuracy figure counts: which of the words the user said it covered.
    static func change(
        _ heard: String, _ wrote: String, over spoken: Range<Int>
    ) -> RecordedCorrection {
        RecordedCorrection(
            heard: heard, wrote: wrote, wordRange: spoken, entryID: UUID(),
            reason: .heardAsStrayLetters, heardConfidence: 0.3)
    }

    /// A dictation whose utterance was counted; `text` and `spokenWords` differ on purpose.
    static func measured(
        _ text: String, spokenWords: Int, changes: [RecordedCorrection] = [],
        daysAgo: Int = 0
    ) -> HistoryEntry {
        entry(
            text, daysAgo: daysAgo,
            changes: RecordedChanges(corrections: changes, spokenWords: spokenWords))
    }

    /// The Dictation page over these inputs, with the fixed clock and region.
    static func dictation(
        permissions: [PermissionKind: PermissionStatus] = [
            .microphone: .granted, .accessibility: .granted,
        ],
        entries: [HistoryEntry] = [],
        corrections: [Correction] = [],
        query: String = "",
        settings: Settings = .default
    ) -> DictationPresentation {
        DictationPresenter.page(
            for: DictationSnapshot(
                permissions: permissions, entries: entries, corrections: corrections,
                query: query, shortcut: "⌥Space",
                settings: settings, now: now),
            calendar: calendar, locale: locale)
    }
}

@Suite("Dictation, the landing page")
struct DictationPageTests {
    @Test("today's dictations are listed newest first")
    func listsToday() {
        let page = HistoryFixture.dictation(entries: [
            HistoryFixture.entry("Newest", minutesAgo: 2),
            HistoryFixture.entry("Older", minutesAgo: 40),
        ])

        #expect(page.rows.map(\.text) == ["Newest", "Older"])
        #expect(page.emptyState == nil)
        #expect(page.blocked == nil)
        #expect(page.chrome.title == "Dictation")
    }

    /// The one rule that keeps this a page about what just happened rather than a second history.
    @Test("anything older than today belongs to History")
    func todayOnly() {
        let page = HistoryFixture.dictation(entries: [
            HistoryFixture.entry("Today"),
            HistoryFixture.entry("Yesterday", daysAgo: 1),
        ])
        #expect(page.rows.map(\.text) == ["Today"])
    }

    @Test("the caption names the day the page is about")
    func caption() {
        #expect(HistoryFixture.dictation().caption.hasPrefix("Today · "))
    }

    @Test("a row says how long it took and how much was said")
    func detail() {
        let page = HistoryFixture.dictation(entries: [
            HistoryFixture.timed("one two three four five", seconds: 11)
        ])
        #expect(page.rows.first?.detail == "11s · 5 words")
    }

    /// A duration invented for an untimed dictation would make the pace figure a fiction.
    @Test("an untimed dictation reports only its words")
    func detailWithoutTiming() {
        let page = HistoryFixture.dictation(entries: [HistoryFixture.entry("two words")])
        #expect(page.rows.first?.detail == "2 words")
    }

    @Test("every row offers copy, insert again and flag, in that order")
    func rowActions() {
        let entry = HistoryFixture.entry("Say it again")
        let row = HistoryFixture.dictation(entries: [entry]).rows[0]

        #expect(row.actions.map(\.title) == ["Copy", "Insert Again", "Flag"])
        #expect(row.actions[0].intent == .copy("Say it again"))
        #expect(row.actions[1].intent == .insert("Say it again"))
        #expect(row.actions[2].intent == .flagDictation(entry.id))
        #expect(row.more.map(\.intent) == [.forgetDictation(entry.id)])
        #expect(row.more[0].isDestructive)
        #expect(row.id == entry.id)
    }

    @Test("the app a dictation went into is drawn as a tile")
    func application() {
        let page = HistoryFixture.dictation(entries: [
            HistoryFixture.entry(application: "Slack")
        ])
        #expect(page.rows.first?.application?.initial == "S")
    }

    @Test("the search field appears only when there is something to search")
    func search() {
        #expect(HistoryFixture.dictation().chrome.search == nil)
        #expect(HistoryFixture.dictation(entries: [HistoryFixture.entry()]).chrome.search != nil)
    }

    @Test("searching narrows the list")
    func searching() {
        let page = HistoryFixture.dictation(
            entries: [HistoryFixture.entry("deployment"), HistoryFixture.entry("standup")],
            query: "deploy")
        #expect(page.rows.map(\.text) == ["deployment"])
    }

    @Test("the footnote appears under a list and nowhere else")
    func footnote() {
        #expect(HistoryFixture.dictation(entries: [HistoryFixture.entry()]).footnote != nil)
        #expect(HistoryFixture.dictation().footnote == nil)
    }
}

@Suite("The badge that leads to Corrections")
struct DictationChangesTests {
    @Test("a dictation Uttrflow changed says how many words it changed")
    func badge() {
        let entry = HistoryFixture.entry("utter flow is late")
        let page = HistoryFixture.dictation(
            entries: [entry],
            corrections: [
                HistoryFixture.correction(in: entry.id, heard: "utter flow", wrote: "Uttrflow"),
                HistoryFixture.correction(in: entry.id, heard: "is", wrote: "is,"),
            ])

        #expect(page.rows[0].changes?.title == "2 changes")
        #expect(page.rows[0].changes?.intent == .show(.corrections))
    }

    @Test("one change is one change")
    func singular() {
        let entry = HistoryFixture.entry()
        let page = HistoryFixture.dictation(
            entries: [entry],
            corrections: [HistoryFixture.correction(in: entry.id)])
        #expect(page.rows[0].changes?.title == "1 change")
    }

    @Test("an undone change is no longer counted against the dictation")
    func undoneIsNotCounted() {
        let entry = HistoryFixture.entry()
        let page = HistoryFixture.dictation(
            entries: [entry],
            corrections: [HistoryFixture.correction(in: entry.id, isUndone: true)])
        #expect(page.rows[0].changes == nil)
    }

    /// A dictation that kept no record shows no badge, even where a correction elsewhere claims it.
    @Test("a dictation that kept no record shows no badge")
    func withoutARecord() {
        let entry = HistoryFixture.entry(changes: nil)
        let page = HistoryFixture.dictation(
            entries: [entry], corrections: [HistoryFixture.correction(in: entry.id)])
        #expect(page.rows[0].changes == nil)
    }
}

@Suite("Saying a dictation came out wrong")
struct DictationFlagTests {
    /// A button whose label never changes gives no way to tell a recorded flag from one that was not.
    @Test("the button says what it will do and shows what it has done")
    func flagReadsItsState() {
        let plain = HistoryFixture.dictation(entries: [HistoryFixture.entry()])
        #expect(plain.rows[0].actions.map(\.title) == ["Copy", "Insert Again", "Flag"])

        let flagged = HistoryFixture.dictation(
            entries: [HistoryFixture.entry(isFlagged: true)])
        #expect(flagged.rows[0].actions.map(\.title) == ["Copy", "Insert Again", "Unflag"])
        #expect(flagged.rows[0].actions.last?.symbolName == "flag.fill")
    }

    /// Always three, in that order, so pointing at a row never reflows it.
    @Test("flagging does not change how many controls a row has")
    func flagKeepsTheRowStill() {
        let flagged = HistoryFixture.dictation(
            entries: [HistoryFixture.entry(isFlagged: true)])
        #expect(flagged.rows[0].actions.count == 3)
    }
}

@Suite("The figures beside today's dictations")
struct DictationFiguresTests {
    /// No "time saved" tile: words and streak are counts, pace and accuracy need something measured.
    @Test("nothing is reported that has not been measured")
    func noInventedFigures() {
        let page = HistoryFixture.dictation(
            entries: [HistoryFixture.entry("two words", changes: nil)])
        #expect(page.figures.map(\.caption) == ["Words dictated", "Day dictating"])
        #expect(!page.figures.contains { $0.caption.localizedCaseInsensitiveContains("saved") })
    }

    @Test("words dictated counts everything kept, and says how much is today's")
    func words() {
        let page = HistoryFixture.dictation(entries: [
            HistoryFixture.entry("one two three"), HistoryFixture.entry("four five"),
            HistoryFixture.entry("six seven eight nine", daysAgo: 3),
        ])
        let figure = page.figures.first { $0.caption == "Words dictated" }
        #expect(figure?.value == "9")
        #expect(figure?.comment == "5 of them today")
    }

    /// The history keeps a retention window and no more, so this can never be called a lifetime total.
    @Test("the headline figure never claims to be a lifetime total")
    func neverClaimsALifetime() {
        let page = HistoryFixture.dictation(entries: [HistoryFixture.entry("one two")])
        let figure = page.figures.first { $0.caption == "Words dictated" }
        #expect(figure?.caption.localizedCaseInsensitiveContains("total") == false)
        #expect(figure?.caption.localizedCaseInsensitiveContains("all time") == false)
    }

    @Test("nothing dictated today is said plainly rather than left blank")
    func nothingToday() {
        let page = HistoryFixture.dictation(
            entries: [HistoryFixture.entry("one two", daysAgo: 2)])
        #expect(page.figures.first { $0.caption == "Words dictated" }?.comment == "none yet today")
    }

    // MARK: The streak

    @Test("counts the days in a row that were dictated in")
    func streak() {
        let page = HistoryFixture.dictation(entries: [
            HistoryFixture.entry("today"), HistoryFixture.entry("yesterday", daysAgo: 1),
            HistoryFixture.entry("the day before", daysAgo: 2),
            // A gap so the run stops here; five days, not seven, since seven is the retention window.
            HistoryFixture.entry("before that", daysAgo: 5),
        ])
        let figure = page.figures.first { $0.caption == "Day streak" }
        #expect(figure?.value == "3")
        #expect(figure?.comment == "days in a row")
    }

    /// Counted from the most recent day, not today, so a quiet morning does not break the streak.
    @Test("a morning with nothing in it yet does not break the streak")
    func streakSurvivesAQuietMorning() {
        let page = HistoryFixture.dictation(entries: [
            HistoryFixture.entry("yesterday", daysAgo: 1),
            HistoryFixture.entry("the day before", daysAgo: 2),
        ])
        #expect(page.figures.first { $0.caption == "Day streak" }?.value == "2")
    }

    /// A run reaching the oldest thing kept is a floor, since older days may have been deleted.
    @Test("a streak that reaches the edge of what is kept says so")
    func streakAtTheEdge() {
        let page = HistoryFixture.dictation(entries: [
            HistoryFixture.entry("today"), HistoryFixture.entry("yesterday", daysAgo: 1),
        ])
        let figure = page.figures.first { $0.caption == "Day streak" }
        #expect(figure?.value == "2")
        #expect(figure?.comment == "at least — anything older has been deleted")
    }

    /// One day is not a streak, and calling it one makes every other number less believable.
    @Test("a single day is not called a streak")
    func oneDayIsNotAStreak() {
        let page = HistoryFixture.dictation(entries: [HistoryFixture.entry("today")])
        #expect(page.figures.contains { $0.caption == "Day dictating" })
        #expect(!page.figures.contains { $0.caption == "Day streak" })
    }

    @Test("pace is pooled across everything that was timed")
    func pace() {
        // Sixty words in sixty seconds across two unequal dictations: pooling gives 60, averaging would not.
        let page = HistoryFixture.dictation(entries: [
            HistoryFixture.timed(String(repeating: "word ", count: 50), seconds: 30),
            HistoryFixture.timed(String(repeating: "word ", count: 10), seconds: 30),
        ])
        #expect(page.figures.first { $0.caption == "Words per minute" }?.value == "60")
    }

    @Test("nothing timed means no pace at all")
    func paceWithoutTimings() {
        let page = HistoryFixture.dictation(entries: [HistoryFixture.entry()])
        #expect(!page.figures.contains { $0.caption == "Words per minute" })
        #expect(DictationPresenter.pace(of: []) == nil)
    }

    @Test("today's pace is set beside the usual one")
    func usualPace() {
        let page = HistoryFixture.dictation(entries: [
            HistoryFixture.timed(String(repeating: "word ", count: 10), seconds: 10),
            HistoryFixture.timed(String(repeating: "word ", count: 10), seconds: 20, daysAgo: 1),
        ])
        #expect(
            page.figures.first { $0.caption == "Words per minute" }?.comment
                == "your usual pace is 30")
    }

    /// A comparison against nothing is not a comparison, so it is left off rather than filled in.
    @Test("a first day has nothing to compare against and says nothing")
    func noComparisonOnTheFirstDay() {
        let page = HistoryFixture.dictation(entries: [
            HistoryFixture.timed("one two three", seconds: 6)
        ])
        #expect(page.figures.first { $0.caption == "Words per minute" }?.comment == nil)
    }

    /// Five words said, one written over three of them correctly: two survive untouched, so 40%.
    @Test("a change that writes one word over three does not make the dictation 0% accurate")
    func accuracy() {
        let page = HistoryFixture.dictation(entries: [
            HistoryFixture.measured(
                "the SQL query", spokenWords: 5,
                changes: [HistoryFixture.change("s q l", "SQL", over: 1..<4)])
        ])

        let figure = page.figures.first { $0.caption == "Accuracy" }
        #expect(figure?.value == "40.0%")
        #expect(figure?.meters.map(\.label) == ["Today"])
        #expect(figure?.comment == "Words that came out exactly as you said them.")
    }

    /// Two changes whose ranges sum past the text length must still count the word between them.
    @Test("two such changes leave the word between them counted")
    func accuracyWithSeveralChanges() {
        let page = HistoryFixture.dictation(entries: [
            HistoryFixture.measured(
                "SQL and JSON", spokenWords: 6,
                changes: [
                    HistoryFixture.change("s q l", "SQL", over: 0..<3),
                    HistoryFixture.change("j son", "JSON", over: 4..<6),
                ])
        ])
        // One of the six words said — "and" — survives untouched.
        #expect(page.figures.first { $0.caption == "Accuracy" }?.value == "16.7%")
    }

    /// Snippets are not counted: the trigger words were heard correctly, so they cannot inflate the figure.
    @Test("a snippet expanding two words into nine does not inflate the figure")
    func accuracyIgnoresSnippets() {
        let entry = HistoryFixture.entry(
            // The snippet writes nine words over the first two, and "SQL" replaces the last three.
            "Flat 2, 14 Rowan Street, Hackney, London E8 3PQ then SQL",
            changes: RecordedChanges(
                corrections: [HistoryFixture.change("s q l", "SQL", over: 3..<6)],
                snippets: [
                    RecordedSnippet(
                        snippetID: UUID(), matched: "my address",
                        expansion: "Flat 2, 14 Rowan Street, Hackney, London E8 3PQ")
                ],
                spokenWords: 6))

        // Three of the six words said came out as said; dividing by the eleven written would give 72.7%.
        #expect(
            HistoryFixture.dictation(entries: [entry])
                .figures.first { $0.caption == "Accuracy" }?.value == "50.0%")
    }

    @Test("accuracy is drawn against the baseline once there is one")
    func accuracyBaseline() {
        let page = HistoryFixture.dictation(entries: [
            HistoryFixture.measured(
                "one two three four", spokenWords: 4,
                changes: [HistoryFixture.change("one", "One", over: 0..<1)]),
            HistoryFixture.measured(
                "Five six seven eight", spokenWords: 4,
                changes: [HistoryFixture.change("five six", "Five six", over: 0..<2)],
                daysAgo: 1),
        ])

        let figure = page.figures.first { $0.caption == "Accuracy" }
        #expect(figure?.meters.map(\.label) == ["Today", "Baseline"])
        #expect(figure?.meters.last?.isBaseline == true)
        #expect(
            figure?.comment
                == "Words that came out exactly as you said them. Your baseline is 50.0%.")
    }

    /// An accuracy of 100% computed from no evidence is a number, not a measurement.
    @Test("no record of changes means no accuracy figure")
    func accuracyNeedsARecord() {
        let page = HistoryFixture.dictation(
            entries: [HistoryFixture.entry("one two", changes: nil)])
        #expect(!page.figures.contains { $0.caption == "Accuracy" })
    }

    /// Changes kept without the utterance counted have no denominator, so they leave the sample.
    @Test("changes recorded without the utterance being counted give no accuracy figure")
    func accuracyNeedsTheUtterance() {
        let page = HistoryFixture.dictation(entries: [
            HistoryFixture.entry("one two", changes: RecordedChanges())
        ])
        #expect(!page.figures.contains { $0.caption == "Accuracy" })
    }

    /// An unmeasured dictation leaves the sample instead of hiding the figure for the measured ones.
    @Test("one unmeasured dictation does not hide the figure for the measured ones")
    func accuracyIgnoresTheUnmeasured() {
        let page = HistoryFixture.dictation(entries: [
            HistoryFixture.measured(
                "one two three four", spokenWords: 4,
                changes: [HistoryFixture.change("one", "One", over: 0..<1)]),
            HistoryFixture.entry("salvaged", changes: nil),
        ])
        // Three of the measured dictation's four spoken words survive; the salvaged one is in neither half.
        #expect(page.figures.first { $0.caption == "Accuracy" }?.value == "75.0%")
    }

    @Test("nothing said means no accuracy either")
    func accuracyNeedsWords() {
        #expect(DictationPresenter.accuracy(of: []) == nil)
        #expect(DictationPresenter.accuracy(of: [HistoryFixture.measured("", spokenWords: 0)]) == nil)
    }

    /// Changed words are counted as positions inside the utterance, so a wide range cannot take more.
    @Test("a stored change wider than the utterance cannot take more words than were said")
    func accuracyCannotGoBelowNothing() {
        let page = HistoryFixture.dictation(entries: [
            HistoryFixture.measured(
                "One", spokenWords: 1,
                changes: [HistoryFixture.change("one two three", "One", over: 0..<3)])
        ])
        #expect(page.figures.first { $0.caption == "Accuracy" }?.value == "0.0%")
    }

    @Test("a page nobody can use has no figures on it")
    func blockedHasNoFigures() {
        let page = HistoryFixture.dictation(
            permissions: [.microphone: .denied], entries: [HistoryFixture.entry()])
        #expect(page.figures.isEmpty)
        #expect(page.rows.isEmpty)
        #expect(page.chrome.search == nil)
    }
}

@Suite("Dictation with nothing to show")
struct DictationEmptyTests {
    @Test("a day that has not started yet invites the user to speak")
    func nothingToday() {
        let empty = HistoryFixture.dictation().emptyState
        #expect(empty?.title == "Nothing dictated today")
        #expect(empty?.message.hasPrefix("Hold ⌥Space anywhere") == true)
    }

    @Test("the invitation follows how the shortcut is set up")
    func verb() {
        var settings = Settings.default
        settings.hotkeyActivation = .pressToToggle
        #expect(
            HistoryFixture.dictation(settings: settings).emptyState?.message
                .hasPrefix("Press ⌥Space") == true)
    }

    /// The pane is never blank, and never blank with a number that could be read as today's.
    @Test("yesterday's figures stand in for today's")
    func yesterdaysChips() {
        let empty = HistoryFixture.dictation(entries: [
            HistoryFixture.timed(
                String(repeating: "word ", count: 20), seconds: 10, daysAgo: 1, changes: nil)
        ]).emptyState

        #expect(empty?.chips.map(\.caption) == ["words yesterday", "wpm yesterday"])
        #expect(empty?.chips.first?.value == "20")
        #expect(empty?.footnote?.hasPrefix("Yesterday’s figures") == true)
    }

    @Test("accuracy joins the chips once there is a record of changes")
    func accuracyChip() {
        let before = HistoryFixture.measured(
            "one two three four", spokenWords: 4,
            changes: [HistoryFixture.change("one", "One", over: 0..<1)], daysAgo: 1)
        let empty = HistoryFixture.dictation(entries: [before]).emptyState
        #expect(empty?.chips.map(\.caption).contains("accuracy yesterday") == true)
        #expect(empty?.chips.last?.value == "75.0%")
    }

    /// A total from further back under today's heading is read as today's and never corrected.
    @Test("only yesterday counts as yesterday")
    func onlyYesterday() {
        let empty = HistoryFixture.dictation(entries: [
            HistoryFixture.entry("Ancient", daysAgo: 4)
        ]).emptyState
        #expect(empty?.chips.isEmpty == true)
        #expect(empty?.footnote == nil)
    }

    @Test("a search that matched nothing says so rather than pretending the day is empty")
    func noMatches() {
        let empty = HistoryFixture.dictation(
            entries: [HistoryFixture.entry("deployment")], query: "invoice"
        ).emptyState
        #expect(empty?.title == "No matches")
        #expect(empty?.message.contains("“invoice”") == true)
    }

    @Test("a page in the way replaces the page rather than sitting above it")
    func blocked() {
        let page = HistoryFixture.dictation(permissions: [.microphone: .denied])
        #expect(page.blocked != nil)
        #expect(page.emptyState == nil)
    }
}
