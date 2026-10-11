import UttrflowUX

struct MainContentSnapshot: Sendable {
    let notice: MainNotice?
    let home: HomeSnapshot
    let sidebar: SidebarSnapshot
    let history: HistorySnapshot
    let dictionary: DictionarySnapshot
    let corrections: CorrectionsSnapshot
    let insights: InsightsSnapshot
    let snippets: SnippetsSnapshot
    let diagnostics: DiagnosticsSnapshot
    let suggestionModelBytesOnDisk: Int64?
    let account: AccountPagePresentation
    let shortcutKeycaps: [String]

    func presented() -> MainContent {
        MainContent(
            notice: notice,
            home: HomePresenter.page(for: home),
            sidebar: SidebarPresenter.sidebar(for: sidebar),
            history: HistoryPresenter.page(for: history),
            dictionary: DictionaryPresenter.page(for: dictionary),
            corrections: CorrectionsPresenter.page(for: corrections),
            insights: InsightsPresenter.page(for: insights),
            snippets: SnippetsPresenter.page(for: snippets),
            diagnostics: DiagnosticsPresenter.page(
                for: diagnostics, suggestionModelBytesOnDisk: suggestionModelBytesOnDisk),
            account: account,
            shortcutKeycaps: shortcutKeycaps)
    }
}
