import Foundation
import Testing
import UttrflowAccount
import UttrflowCore
import UttrflowDictionary
import UttrflowHistory
import UttrflowUX

@testable import Uttrflow

@Suite("Main content snapshot presentation")
struct MainContentSnapshotTests {
    private let now = Date(timeIntervalSince1970: 1_750_000_800)
    private let secret = "Cobalt meadow"

    private enum Fixture: CaseIterable { case empty, concealed, revealed }

    private func records(for fixture: Fixture) -> [DictationRecord] {
        guard fixture != .empty else { return [] }
        let correction = RecordedCorrection(
            heard: "sail", wrote: "safe", wordRange: 3..<4, entryID: UUID(),
            reason: .seenOnScreen, heardConfidence: 0.5)
        return [
            DictationRecord(
                text: "Keep \(secret) safe.", when: now,
                changes: RecordedChanges(corrections: [correction], spokenWords: 4))
        ]
    }

    private func snapshot(_ fixture: Fixture) -> MainContentSnapshot {
        let populated = fixture != .empty
        let account = Account(
            identifier: "synthetic-account", displayName: "Example Reader", emailAddress: nil,
            provider: .google)
        let snippet = Snippet(trigger: "my passphrase", expansion: secret, created: now, isSecret: true)
        let entries = records(for: fixture)
        let words = populated ? [DictionaryEntry(word: "Cobalt", origin: .added, firstSeen: now)] : []
        let correction = CorrectionHistory(of: entries).corrections
        let accountPage = AccountPagePresenter.page(
            for: AccountPageSnapshot(
                entitlement: populated
                    ? Entitlement(
                        account: account, plan: .free, expiresAt: now.addingTimeInterval(86_400),
                        signature: "synthetic")
                    : nil,
                access: .allowed, now: now, picture: populated ? Data("synthetic-picture".utf8) : nil))
        return MainContentSnapshot(
            notice: populated ? .clipboardCopyFailed : nil,
            home: HomeSnapshot(
                entries: entries, account: populated ? account : nil, shortcut: "⌃Space", now: now,
                secretPhrases: populated ? [secret] : []),
            sidebar: SidebarSnapshot(
                selection: .page(.history), entries: entries, shortcutKeys: ["⌃", "Space"], now: now),
            history: HistorySnapshot(
                entries: entries, keepsRecordings: populated, now: now,
                secretPhrases: populated ? [secret] : []),
            dictionary: DictionarySnapshot(entries: words, now: now),
            corrections: CorrectionsSnapshot(corrections: correction, dictations: entries, now: now),
            insights: InsightsSnapshot(entries: entries, now: now),
            snippets: SnippetsSnapshot(
                snippets: populated ? [snippet] : [], now: now, dictionary: words,
                revealed: fixture == .revealed ? [snippet.id] : []),
            diagnostics: DiagnosticsSnapshot(machine: populated ? "Synthetic Mac" : nil),
            suggestionModelBytesOnDisk: populated ? 1024 : nil,
            account: accountPage, shortcutKeycaps: ["⌃", "Space"])
    }

    @Test(arguments: Fixture.allCases)
    private func allNineFieldsMatchExistingPresentation(fixture: Fixture) {
        let input = snapshot(fixture)
        let expected = MainContent(
            notice: input.notice,
            home: HomePresenter.page(for: input.home),
            sidebar: SidebarPresenter.sidebar(for: input.sidebar),
            history: HistoryPresenter.page(for: input.history),
            dictionary: DictionaryPresenter.page(for: input.dictionary),
            corrections: CorrectionsPresenter.page(for: input.corrections),
            insights: InsightsPresenter.page(for: input.insights),
            snippets: SnippetsPresenter.page(for: input.snippets),
            diagnostics: DiagnosticsPresenter.page(
                for: input.diagnostics, suggestionModelBytesOnDisk: input.suggestionModelBytesOnDisk),
            account: input.account, shortcutKeycaps: input.shortcutKeycaps)
        #expect(input.presented() == expected)
    }

    @Test(arguments: [Fixture.concealed, .revealed])
    private func forwardsPrivacyHeaderNoticeAndStorage(fixture: Fixture) throws {
        let content = snapshot(fixture).presented()
        #expect(content.notice == .clipboardCopyFailed)
        #expect(content.shortcutKeycaps == ["⌃", "Space"])
        #expect(content.account.identity?.name == "Example Reader")
        #expect(content.account.identity?.picture == Data("synthetic-picture".utf8))
        let recent = try #require(content.home.recent.first)
        #expect(!recent.text.contains(secret))
        let history = try #require(content.history.days.first?.rows.first)
        #expect(!history.text.contains(secret))
        let row = try #require(content.snippets.rows.first)
        #expect(row.text.contains(secret) == (fixture == .revealed))
        #expect(content.diagnostics.storage.contains { $0.title == "Suggestion model" && $0.action != nil })
    }
}
